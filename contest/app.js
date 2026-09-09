const state = {
  mode: "login",
  user: null,
  room: null,
  notes: [],
  apiReady: true,
  localOnly: false,
  selectedVessel: "paper",
  pollTimer: null,
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const LOCAL_KEY = "between-us-contest-local-v1";
const vesselNames = { paper: "纸团", star: "星星", capsule: "胶囊" };
const vesselImages = {
  paper: ["paper-6.png", "paper-3.png", "paper-9.png", "paper-1.png"],
  star: ["star-charm.png"],
  capsule: ["paper-4.png", "paper-8.png"],
};

function showView(name) {
  ["auth", "pairing", "room"].forEach((viewName) => {
    const element = $(`#${viewName}-view`);
    const active = viewName === name;
    element.hidden = !active;
    element.classList.toggle("active", active);
  });
}

function setConnection(kind, label) {
  const dot = $("#connection-dot");
  dot.className = `connection-dot ${kind ? `is-${kind}` : ""}`;
  $("#connection-label").textContent = label;
}

function message(target, text) {
  $(target).textContent = text || "";
}

function toast(text) {
  const element = $("#toast");
  element.textContent = text;
  element.classList.add("is-visible");
  window.clearTimeout(toast.timer);
  toast.timer = window.setTimeout(() => element.classList.remove("is-visible"), 2400);
}

async function request(path, options = {}) {
  const response = await fetch(path, {
    credentials: "include",
    headers: { "content-type": "application/json", ...(options.headers || {}) },
    ...options,
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || "请求没有完成");
  return body;
}

async function hashText(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function readLocal() {
  try { return JSON.parse(localStorage.getItem(LOCAL_KEY)) || { users: [], rooms: [], notes: [], session: null }; }
  catch { return { users: [], rooms: [], notes: [], session: null }; }
}

function writeLocal(data) { localStorage.setItem(LOCAL_KEY, JSON.stringify(data)); }

function localUserRoom(userId) {
  const data = readLocal();
  const room = data.rooms.find((candidate) => candidate.members.includes(userId));
  if (!room) return null;
  const members = room.members.map((memberId) => data.users.find((user) => user.id === memberId)).filter(Boolean);
  return {
    ...room,
    partnerName: members.find((member) => member.id !== userId)?.displayName || "正在等待对方加入",
    members,
    notes: data.notes.filter((note) => note.roomId === room.id).map((note) => ({
      ...note,
      authorName: data.users.find((user) => user.id === note.authorId)?.displayName || "对方",
      isMine: note.authorId === userId,
    })),
  };
}

function randomId(prefix) { return `${prefix}_${crypto.randomUUID()}`; }

async function localAuthenticate(mode, username, password, displayName) {
  const data = readLocal();
  const passwordHash = await hashText(password);
  let user = data.users.find((candidate) => candidate.username === username);
  if (mode === "register") {
    if (user) throw new Error("这个账号已经存在，换一个名字吧");
    user = { id: randomId("user"), username, displayName: displayName || username, passwordHash };
    data.users.push(user);
  } else {
    if (!user || user.passwordHash !== passwordHash) throw new Error("账号或密码不对");
  }
  data.session = user.id;
  writeLocal(data);
  return { user: { id: user.id, username: user.username, displayName: user.displayName } };
}

function localCreatePair() {
  const data = readLocal();
  const existing = data.rooms.find((room) => room.members.includes(state.user.id));
  if (existing) return existing;
  let code = "";
  do { code = String(Math.floor(100000 + Math.random() * 900000)); } while (data.rooms.some((room) => room.code === code));
  const room = { id: randomId("room"), code, members: [state.user.id], createdAt: new Date().toISOString() };
  data.rooms.push(room);
  writeLocal(data);
  return room;
}

function localJoinPair(code) {
  const data = readLocal();
  const room = data.rooms.find((candidate) => candidate.code === code);
  if (!room) throw new Error("没有找到这个配对码");
  if (room.members.includes(state.user.id)) return room;
  if (room.members.length >= 2) throw new Error("这个配对码已经被使用");
  room.members.push(state.user.id);
  writeLocal(data);
  return room;
}

function localCreateNote(body, vessel) {
  const data = readLocal();
  const room = data.rooms.find((candidate) => candidate.members.includes(state.user.id));
  const note = { id: randomId("note"), roomId: room.id, authorId: state.user.id, body, vessel, createdAt: new Date().toISOString(), openedAt: null };
  data.notes.push(note);
  writeLocal(data);
  return note;
}

function localOpenNote(id) {
  const data = readLocal();
  const note = data.notes.find((candidate) => candidate.id === id);
  if (note) note.openedAt = new Date().toISOString();
  writeLocal(data);
  return note;
}

async function authenticate(event) {
  event.preventDefault();
  const submit = $("#auth-submit");
  const username = $("#auth-username").value.trim();
  const password = $("#auth-password").value;
  const displayName = $("#auth-display-name").value.trim();
  message("#auth-message", "");
  submit.disabled = true;
  try {
    let result;
    try {
      result = await request(`/api/auth/${state.mode === "register" ? "register" : "login"}`, {
        method: "POST",
        body: JSON.stringify({ username, password, displayName }),
      });
      state.localOnly = false;
      setConnection("online", "已连接");
    } catch (error) {
      result = await localAuthenticate(state.mode, username, password, displayName);
      state.localOnly = true;
      state.apiReady = false;
      setConnection("waiting", "离线保存");
    }
    state.user = result.user;
    await enterNextStage();
  } catch (error) {
    message("#auth-message", error.message);
  } finally {
    submit.disabled = false;
  }
}

async function enterNextStage() {
  let room = null;
  if (!state.localOnly) {
    try { room = (await request("/api/room")).room; }
    catch { state.localOnly = true; state.apiReady = false; setConnection("waiting", "离线保存"); }
  }
  if (state.localOnly) room = localUserRoom(state.user.id);
  state.room = room;
  if (room) {
    showView("room");
    renderRoom(room);
    startPolling();
  } else {
    showView("pairing");
    setConnection(state.localOnly ? "waiting" : "online", state.localOnly ? "离线保存" : "已连接");
  }
}

function setAuthMode(mode) {
  state.mode = mode;
  $("#login-tab").classList.toggle("is-active", mode === "login");
  $("#register-tab").classList.toggle("is-active", mode === "register");
  $("#login-tab").setAttribute("aria-selected", String(mode === "login"));
  $("#register-tab").setAttribute("aria-selected", String(mode === "register"));
  $$(".register-only").forEach((element) => { element.hidden = mode !== "register"; });
  $("#auth-submit").textContent = mode === "register" ? "创建账号" : "进入空间";
  message("#auth-message", "");
}

async function createPair() {
  const button = $("#create-pair");
  button.disabled = true;
  message("#create-pair-note", "正在生成配对码…");
  try {
    let room;
    try {
      room = (await request("/api/pair/create", { method: "POST" })).room;
    } catch {
      state.localOnly = true;
      state.apiReady = false;
      room = localCreatePair();
      setConnection("waiting", "离线保存");
    }
    state.room = room;
    $("#pair-code span").textContent = room.code;
    $("#pair-code").hidden = false;
    message("#create-pair-note", "把这 6 位数字告诉对方，不需要扫码。");
  } catch (error) {
    message("#create-pair-note", error.message);
  } finally {
    button.disabled = false;
  }
}

async function joinPair(event) {
  event.preventDefault();
  const form = $("#join-form");
  const code = $("#join-code").value.trim();
  const button = form.querySelector("button");
  button.disabled = true;
  message("#join-message", "");
  try {
    let room;
    try {
      room = (await request("/api/pair/join", { method: "POST", body: JSON.stringify({ code }) })).room;
    } catch {
      state.localOnly = true;
      state.apiReady = false;
      room = localJoinPair(code);
      setConnection("waiting", "离线保存");
    }
    state.room = room;
    showView("room");
    renderRoom(localUserRoom(state.user.id) || room);
    startPolling();
  } catch (error) {
    message("#join-message", error.message);
  } finally {
    button.disabled = false;
  }
}

function formatTime(value) {
  if (!value) return "还没有打开";
  return new Intl.DateTimeFormat("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

function imageFor(note, index) {
  const options = vesselImages[note.vessel] || vesselImages.paper;
  return `/assets/${options[index % options.length]}`;
}

function notesForVessel(vessel) {
  return state.notes.filter((note) => !note.isMine && note.vessel === vessel).sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
}

function renderNoteObjects(vessel, target) {
  const notes = notesForVessel(vessel);
  target.innerHTML = "";
  notes.slice(0, 4).forEach((note, index) => {
    const button = document.createElement("button");
    button.className = `paper-note ${note.openedAt ? "is-opened" : ""}`;
    button.type = "button";
    button.dataset.noteId = note.id;
    button.setAttribute("aria-label", `${note.openedAt ? "已打开" : "打开"}一件${vesselNames[vessel]}表达`);
    button.style.setProperty("--note-index", index);
    const image = document.createElement("img");
    image.src = imageFor(note, index);
    image.alt = "";
    button.append(image);
    target.append(button);
  });
}

function renderHistory() {
  const history = $("#rail-history");
  history.innerHTML = "";
  [...state.notes].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)).slice(0, 12).forEach((note, index) => {
    const row = document.createElement("div");
    row.className = `history-row ${note.openedAt ? "is-opened" : ""}`;
    const image = document.createElement("img");
    image.className = "history-note";
    image.src = imageFor(note, index);
    image.alt = "";
    const copy = document.createElement("div");
    copy.className = "history-copy";
    const title = document.createElement("strong");
    title.textContent = note.isMine ? `你留下了${vesselNames[note.vessel]}` : `${note.authorName || "对方"}留下了${vesselNames[note.vessel]}`;
    const time = document.createElement("span");
    time.textContent = note.isMine ? (note.openedAt ? `对方已打开 · ${formatTime(note.openedAt)}` : `等待打开 · ${formatTime(note.createdAt)}`) : (note.openedAt ? `已经打开 · ${formatTime(note.openedAt)}` : `还没有打开 · ${formatTime(note.createdAt)}`);
    copy.append(title, time);
    row.append(image, copy);
    history.append(row);
  });
}

function renderRoom(room) {
  state.room = room;
  state.notes = room.notes || [];
  const unread = state.notes.filter((note) => !note.isMine && !note.openedAt);
  const total = state.notes.length;
  $("#room-partner").textContent = room.partnerName && room.partnerName !== "正在等待对方加入" ? `和 ${room.partnerName} 在一起 · ${total} 件表达` : "配对码已生成，等对方加入";
  $("#room-code").textContent = room.code || "------";
  $("#set-label").innerHTML = `你们的表达 · <span>${total}</span>`;
  $("#rail-status").textContent = unread.length ? `${unread.length} 件表达等你发现` : (total ? "这里安静下来了一点" : "还没有新的表达");
  $("#stage-caption").textContent = unread.length ? "有些话还没有展开，选一件打开。" : (total ? "你们留下过的东西，都还在这里。" : "这里还没有对方留下的话。");
  $("#open-action").hidden = unread.length === 0;
  $("#vessel-stage").classList.toggle("has-new", unread.length > 0);
  ["paper", "star", "capsule"].forEach((vessel) => renderNoteObjects(vessel, $(`#vessel-notes-${vessel}`)));
  renderHistory();
}

async function refreshRoom() {
  if (!state.user || !state.room) return;
  try {
    const result = state.localOnly ? { room: localUserRoom(state.user.id) } : await request("/api/room");
    if (result.room) renderRoom(result.room);
  } catch {
    state.localOnly = true;
    state.apiReady = false;
    setConnection("waiting", "离线保存");
  }
}

function startPolling() {
  window.clearInterval(state.pollTimer);
  state.pollTimer = window.setInterval(refreshRoom, 4200);
}

function openComposer(vessel = state.selectedVessel) {
  state.selectedVessel = vessel;
  $$('input[name="vessel"]').forEach((input) => {
    input.checked = input.value === vessel;
    input.closest(".choice").classList.toggle("is-selected", input.checked);
  });
  $("#compose-message").textContent = "";
  $("#note-body").value = "";
  $("#char-count").textContent = "0 / 1000";
  $("#compose-dialog").showModal();
  window.setTimeout(() => $("#note-body").focus(), 50);
}

async function createNote(event) {
  event.preventDefault();
  const body = $("#note-body").value.trim();
  const vessel = document.querySelector('input[name="vessel"]:checked')?.value || "paper";
  if (!body) return;
  const submit = $("#compose-form").querySelector(".button-primary");
  submit.disabled = true;
  message("#compose-message", "");
  try {
    let note;
    try {
      note = (await request("/api/notes", { method: "POST", body: JSON.stringify({ body, vessel }) })).note;
    } catch {
      state.localOnly = true;
      state.apiReady = false;
      note = localCreateNote(body, vessel);
      setConnection("waiting", "离线保存");
    }
    $("#compose-dialog").close();
    toast("已经放进你们之间");
    await refreshRoom();
    animateDeposit(vessel);
  } catch (error) {
    message("#compose-message", error.message);
  } finally {
    submit.disabled = false;
  }
}

function animateDeposit(vessel) {
  const element = $(`.vessel-${vessel}`);
  if (!element) return;
  element.animate([
    { transform: getComputedStyle(element).transform, opacity: 1 },
    { transform: `${getComputedStyle(element).transform} translateY(-14px)`, opacity: 0.72 },
    { transform: getComputedStyle(element).transform, opacity: 1 },
  ], { duration: 620, easing: "cubic-bezier(.2,.82,.24,1)" });
}

async function openNote(id) {
  const note = state.notes.find((candidate) => candidate.id === id);
  if (!note || note.isMine) return;
  const object = document.querySelector(`[data-note-id="${CSS.escape(id)}"]`);
  object?.classList.add("is-opening");
  $(`#vessel-stage .vessel-${note.vessel}`)?.classList.add("is-open");
  await new Promise((resolve) => window.setTimeout(resolve, 470));
  try {
    if (state.localOnly) localOpenNote(id);
    else await request(`/api/notes/${encodeURIComponent(id)}/open`, { method: "POST" });
    note.openedAt = new Date().toISOString();
    $("#reveal-note img").src = imageFor(note, 0);
    $("#revealed-body").textContent = note.body;
    $("#revealed-meta").textContent = `${note.authorName || "对方"} 留下 · ${formatTime(note.createdAt)}`;
    $("#reply-button").dataset.vessel = note.vessel;
    $("#reveal-dialog").showModal();
    renderRoom(state.room);
  } catch (error) {
    toast(error.message);
  } finally {
    object?.classList.remove("is-opening");
  }
}

async function openLatest() {
  const note = state.notes.find((candidate) => !candidate.isMine && !candidate.openedAt);
  if (note) await openNote(note.id);
}

async function logout() {
  try { await request("/api/auth/logout", { method: "POST" }); } catch {}
  const data = readLocal();
  data.session = null;
  writeLocal(data);
  state.user = null;
  state.room = null;
  state.notes = [];
  window.clearInterval(state.pollTimer);
  setConnection("", "尚未进入空间");
  showView("auth");
}

async function boot() {
  setAuthMode("login");
  try {
    const result = await request("/api/me");
    if (result.user) {
      state.user = result.user;
      setConnection("online", "已连接");
      await enterNextStage();
      return;
    }
  } catch {
    state.apiReady = false;
  }
  const local = readLocal();
  if (local.session) {
    const user = local.users.find((candidate) => candidate.id === local.session);
    if (user) {
      state.localOnly = true;
      state.user = { id: user.id, username: user.username, displayName: user.displayName };
      setConnection("waiting", "离线保存");
      await enterNextStage();
      return;
    }
  }
  setConnection(state.apiReady ? "" : "waiting", state.apiReady ? "尚未进入空间" : "离线保存");
  showView("auth");
}

$("#login-tab").addEventListener("click", () => setAuthMode("login"));
$("#register-tab").addEventListener("click", () => setAuthMode("register"));
$("#auth-form").addEventListener("submit", authenticate);
$("#create-pair").addEventListener("click", createPair);
$("#join-form").addEventListener("submit", joinPair);
$("#copy-code").addEventListener("click", async () => {
  try { await navigator.clipboard.writeText($("#pair-code span").textContent); toast("配对码已复制"); }
  catch { toast("请记下这 6 位配对码"); }
});
$("#write-button").addEventListener("click", () => openComposer());
$("#open-action").addEventListener("click", openLatest);
$("#logout-button").addEventListener("click", logout);
$("#compose-form").addEventListener("submit", createNote);
$("#note-body").addEventListener("input", (event) => { $("#char-count").textContent = `${event.target.value.length} / 1000`; });
$$('input[name="vessel"]').forEach((input) => input.addEventListener("change", (event) => {
  state.selectedVessel = event.target.value;
  $$(".choice").forEach((choice) => choice.classList.toggle("is-selected", choice.querySelector("input").checked));
}));
$("#note-layer")?.addEventListener("click", (event) => event.target.closest("[data-note-id]") && openNote(event.target.closest("[data-note-id]").dataset.noteId));
$("#vessel-stage").addEventListener("click", (event) => {
  const vessel = event.target.closest(".vessel")?.dataset.vessel;
  if (vessel) {
    const note = notesForVessel(vessel).find((candidate) => !candidate.openedAt);
    if (note) openNote(note.id); else toast(`这里还没有新的${vesselNames[vessel]}表达`);
  }
  const note = event.target.closest("[data-note-id]");
  if (note) openNote(note.dataset.noteId);
});
$("#reveal-close").addEventListener("click", () => $("#reveal-dialog").close());
$("#reply-button").addEventListener("click", () => {
  const vessel = $("#reply-button").dataset.vessel || "paper";
  $("#reveal-dialog").close();
  openComposer(vessel);
});

boot();
