const SESSION_DAYS = 30;
const PASSWORD_ITERATIONS = 120000;

const headers = { "content-type": "application/json; charset=utf-8" };

function response(payload, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(payload), { status, headers: { ...headers, ...extraHeaders } });
}

function cookieValue(request, name) {
  const cookies = request.headers.get("cookie") || "";
  const match = cookies.split(";").map((part) => part.trim()).find((part) => part.startsWith(`${name}=`));
  return match ? decodeURIComponent(match.slice(name.length + 1)) : "";
}

function bytesToBase64(bytes) {
  let binary = "";
  bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
  return btoa(binary);
}

function base64ToBytes(value) {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}

function randomBytes(size) {
  const bytes = new Uint8Array(size);
  crypto.getRandomValues(bytes);
  return bytes;
}

async function sha256(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return bytesToBase64(new Uint8Array(digest));
}

async function passwordHash(password, salt = randomBytes(16)) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations: PASSWORD_ITERATIONS, hash: "SHA-256" }, key, 256);
  return `pbkdf2$${PASSWORD_ITERATIONS}$${bytesToBase64(salt)}$${bytesToBase64(new Uint8Array(bits))}`;
}

async function passwordMatches(password, stored) {
  const [, iterations, salt, expected] = String(stored).split("$");
  if (!iterations || !salt || !expected) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt: base64ToBytes(salt), iterations: Number(iterations), hash: "SHA-256" }, key, 256);
  return bytesToBase64(new Uint8Array(bits)) === expected;
}

async function ensureSchema(db) {
  await db.batch([
    db.prepare("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL, password_hash TEXT NOT NULL, created_at TEXT NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS sessions (token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires_at TEXT NOT NULL, created_at TEXT NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS spaces (id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS members (space_id TEXT NOT NULL, user_id TEXT NOT NULL UNIQUE, joined_at TEXT NOT NULL, PRIMARY KEY (space_id, user_id))"),
    db.prepare("CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, space_id TEXT NOT NULL, author_id TEXT NOT NULL, body TEXT NOT NULL, vessel TEXT NOT NULL, created_at TEXT NOT NULL, opened_at TEXT, opened_by TEXT, deleted_at TEXT)"),
    db.prepare("CREATE INDEX IF NOT EXISTS notes_by_space ON notes (space_id, created_at)"),
  ]);
}

function dbFor(env) {
  if (!env.DB) throw new Error("D1 binding DB is not configured");
  return env.DB;
}

async function currentUser(request, db) {
  const token = cookieValue(request, "between_us_session");
  if (!token) return null;
  const tokenHash = await sha256(token);
  const row = await db.prepare("SELECT u.id, u.username, u.display_name AS displayName FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > ?").bind(tokenHash, new Date().toISOString()).first();
  return row || null;
}

function requireBody(request) {
  return request.json().catch(() => ({}));
}

function userPayload(user) {
  return { id: user.id, username: user.username, displayName: user.displayName || user.display_name };
}

async function startSession(userId, db) {
  const token = `${crypto.randomUUID()}${crypto.randomUUID().replaceAll("-", "")}`;
  const now = new Date();
  const expires = new Date(now.getTime() + SESSION_DAYS * 86400000);
  await db.prepare("INSERT INTO sessions (token_hash, user_id, expires_at, created_at) VALUES (?, ?, ?, ?)").bind(await sha256(token), userId, expires.toISOString(), now.toISOString()).run();
  return `between_us_session=${encodeURIComponent(token)}; Path=/; Max-Age=${SESSION_DAYS * 86400}; HttpOnly; SameSite=Lax; Secure`;
}

function newCode() {
  const bytes = randomBytes(4);
  const number = ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]) >>> 0;
  return String(100000 + (number % 900000));
}

async function roomForUser(user, db) {
  const room = await db.prepare("SELECT s.id, s.code, s.created_at AS createdAt FROM spaces s JOIN members m ON m.space_id = s.id WHERE m.user_id = ? LIMIT 1").bind(user.id).first();
  if (!room) return null;
  const members = await db.prepare("SELECT u.id, u.display_name AS displayName FROM members m JOIN users u ON u.id = m.user_id WHERE m.space_id = ? ORDER BY m.joined_at").bind(room.id).all();
  const rows = await db.prepare("SELECT n.id, n.body, n.vessel, n.created_at AS createdAt, n.opened_at AS openedAt, n.author_id AS authorId, u.display_name AS authorName FROM notes n JOIN users u ON u.id = n.author_id WHERE n.space_id = ? AND n.deleted_at IS NULL ORDER BY n.created_at DESC").bind(room.id).all();
  const partner = members.results.find((member) => member.id !== user.id);
  return {
    id: room.id,
    code: room.code,
    createdAt: room.createdAt,
    partnerName: partner?.displayName || "正在等待对方加入",
    members: members.results,
    notes: rows.results.map((note) => ({ ...note, isMine: note.authorId === user.id })),
  };
}

async function handle(request, env, context) {
  const db = dbFor(env);
  await ensureSchema(db);
  const url = new URL(request.url);
  const path = url.pathname.replace(/^\/api\/?/, "").replace(/\/$/, "");
  const method = request.method.toUpperCase();

  if (method === "GET" && path === "me") {
    const user = await currentUser(request, db);
    return response({ user: user ? userPayload(user) : null });
  }

  if (method === "POST" && (path === "auth/register" || path === "auth/login")) {
    const { username = "", password = "", displayName = "" } = await requireBody(request);
    const cleanUsername = String(username).trim().toLowerCase();
    if (!/^[a-z0-9_\-.]{3,32}$/.test(cleanUsername)) return response({ error: "账号使用 3–32 位字母、数字、下划线、短横线或点" }, 400);
    if (String(password).length < 6 || String(password).length > 72) return response({ error: "密码需要 6–72 位" }, 400);
    const existing = await db.prepare("SELECT id, username, display_name AS displayName, password_hash AS passwordHash FROM users WHERE username = ?").bind(cleanUsername).first();
    let user;
    if (path.endsWith("register")) {
      if (existing) return response({ error: "这个账号已经存在，换一个名字吧" }, 409);
      user = { id: crypto.randomUUID(), username: cleanUsername, displayName: String(displayName).trim().slice(0, 32) || cleanUsername };
      await db.prepare("INSERT INTO users (id, username, display_name, password_hash, created_at) VALUES (?, ?, ?, ?, ?)").bind(user.id, user.username, user.displayName, await passwordHash(String(password)), new Date().toISOString()).run();
    } else {
      if (!existing || !(await passwordMatches(String(password), existing.passwordHash))) return response({ error: "账号或密码不对" }, 401);
      user = { id: existing.id, username: existing.username, displayName: existing.displayName };
    }
    return response({ user: userPayload(user) }, 200, { "set-cookie": await startSession(user.id, db) });
  }

  if (method === "POST" && path === "auth/logout") {
    const token = cookieValue(request, "between_us_session");
    if (token) await db.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(await sha256(token)).run();
    return response({ ok: true }, 200, { "set-cookie": "between_us_session=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax; Secure" });
  }

  const user = await currentUser(request, db);
  if (!user) return response({ error: "请先登录" }, 401);

  if (method === "GET" && path === "room") return response({ room: await roomForUser(user, db) });

  if (method === "POST" && path === "pair/create") {
    const existing = await roomForUser(user, db);
    if (existing) return response({ room: existing });
    const now = new Date().toISOString();
    let room;
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const candidate = { id: crypto.randomUUID(), code: newCode() };
      try {
        await db.batch([
          db.prepare("INSERT INTO spaces (id, code, created_at) VALUES (?, ?, ?)").bind(candidate.id, candidate.code, now),
          db.prepare("INSERT INTO members (space_id, user_id, joined_at) VALUES (?, ?, ?)").bind(candidate.id, user.id, now),
        ]);
        room = candidate;
        break;
      } catch (error) {
        if (attempt === 4) throw error;
      }
    }
    return response({ room: { ...room, createdAt: now, partnerName: "正在等待对方加入", members: [{ id: user.id, displayName: user.displayName }], notes: [] } }, 201);
  }

  if (method === "POST" && path === "pair/join") {
    const { code = "" } = await requireBody(request);
    const room = await db.prepare("SELECT id, code, created_at AS createdAt FROM spaces WHERE code = ?").bind(String(code).trim()).first();
    if (!room) return response({ error: "没有找到这个配对码" }, 404);
    const memberCount = await db.prepare("SELECT COUNT(*) AS count FROM members WHERE space_id = ?").bind(room.id).first();
    const already = await db.prepare("SELECT 1 FROM members WHERE space_id = ? AND user_id = ?").bind(room.id, user.id).first();
    if (!already && Number(memberCount.count) >= 2) return response({ error: "这个配对码已经被使用" }, 409);
    if (!already) await db.prepare("INSERT INTO members (space_id, user_id, joined_at) VALUES (?, ?, ?)").bind(room.id, user.id, new Date().toISOString()).run();
    return response({ room: await roomForUser(user, db) });
  }

  if (method === "POST" && path === "notes") {
    const { body = "", vessel = "paper" } = await requireBody(request);
    const cleanBody = String(body).trim();
    if (!cleanBody || cleanBody.length > 1000) return response({ error: "这句话需要有内容，且不超过 1000 字" }, 400);
    if (!["paper", "star", "capsule"].includes(vessel)) return response({ error: "表达的形状不对" }, 400);
    const room = await roomForUser(user, db);
    if (!room || room.members.length < 2) return response({ error: "请先和对方配对" }, 409);
    const note = { id: crypto.randomUUID(), spaceId: room.id, authorId: user.id, body: cleanBody, vessel, createdAt: new Date().toISOString() };
    await db.prepare("INSERT INTO notes (id, space_id, author_id, body, vessel, created_at) VALUES (?, ?, ?, ?, ?, ?)").bind(note.id, note.spaceId, note.authorId, note.body, note.vessel, note.createdAt).run();
    return response({ note: { ...note, authorName: user.displayName, isMine: true, openedAt: null } }, 201);
  }

  const openMatch = path.match(/^notes\/([^/]+)\/open$/);
  if (method === "POST" && openMatch) {
    const room = await roomForUser(user, db);
    if (!room) return response({ error: "还没有空间" }, 409);
    const openedAt = new Date().toISOString();
    const result = await db.prepare("UPDATE notes SET opened_at = ?, opened_by = ? WHERE id = ? AND space_id = ? AND author_id != ? AND deleted_at IS NULL").bind(openedAt, user.id, openMatch[1], room.id, user.id).run();
    if (!result.meta.changes) return response({ error: "这件表达不存在，或属于你自己" }, 404);
    return response({ openedAt });
  }

  return response({ error: "找不到这个请求" }, 404);
}

export async function onRequest(context) {
  try {
    return await handle(context.request, context.env, context);
  } catch (error) {
    return response({ error: error.message || "服务暂时不可用" }, 503);
  }
}
