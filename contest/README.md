# Between us · 参赛版

这是独立于正式 iOS 产品和官网的比赛外部项目。它保留 Between us 的核心 idea，但为比赛重新组织成一套完整互动作品：

> 三件物件是一套，统一承接两个人难以说出口的话。

星星瓶、胶囊盒和纸团篓不再代表三种固定情绪，而是同一句表达的三种形状。用户登录后用 6 位配对码进入同一个空间，写下内容，选择它长成的形状，再把它放入空间；另一方刷新后可以从对应物件中主动打开。

## 本地查看

没有 D1 绑定时，页面会自动进入离线保存模式，账号、配对和内容保存在当前浏览器，适合先看完整交互。绑定 D1 后使用同一套页面即可进行真实双设备配对。

```sh
cd contest
npx wrangler pages dev .
```

## Cloudflare Pages + D1

1. 创建 D1 数据库：

```sh
npx wrangler d1 create between-us-contest
```

2. 将返回的 `database_id` 写入 `wrangler.toml`。
3. 首次部署：

```sh
npx wrangler pages deploy . --project-name between-us-contest --branch main
```

Pages Function 会在首次请求时创建表，也可以手动执行：

```sh
npx wrangler d1 execute between-us-contest --remote --file=schema.sql
```

## 页面主流程

登录 / 注册 → 生成或输入配对码 → 进入空间 → 选择星星、胶囊或纸团 → 留下表达 → 对方主动打开 → 留下一句回应。
