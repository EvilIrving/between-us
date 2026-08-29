# Dear Us 临时资产 harness

用 `gpt-image-2` 经 `https://api.shu.cool/v1` 生成首个正式视觉版本。母版未锁定前，只跑 `lock` 阶段。

密钥：环境变量 `SHU_API_KEY`。脚本不写明文。限流：每分钟 ≤ 5 次，并发 ≤ 3。

## 文件

```text
DesignAssets/visual_bible.md      造型合同
DesignAssets/asset_manifest.json  180 条 + 3 张锁定静帧
Scripts/asset_catalog.py          条目与提示词的唯一来源
Scripts/generate_assets.py        限流生成器
DesignAssets/generated/           输出 PNG（gitignored）
DesignAssets/work/                状态与日志（gitignored）
```

## 命令

```bash
# 核对条目数、分组、依赖
python3 Scripts/generate_assets.py status

# 看合成后的提示词
python3 Scripts/generate_assets.py prompt env_room_master

# 只生成母版 + 三容器形态（默认阶段）
python3 Scripts/generate_assets.py generate --stage lock

# 过母版之后，按组或按 id
python3 Scripts/generate_assets.py generate --id container_star_body
python3 Scripts/generate_assets.py generate --group containers --limit 5
python3 Scripts/generate_assets.py generate --stage production --yes
```

已存在的 PNG 默认跳过。`--force` 才覆盖。`--dry-run` 只打印将要请求的条目。

## 阶段

1. `lock`：`env_room_master`，再 edit 出 `lock_star_form` / `lock_capsule_form` / `lock_paper_form`。
2. 人工看图，不满意先改 bible / 提示词，再 `--force` 重跑 lock。
3. `production`：其余 179 条按依赖引用锁定图，透明图层 + 关键帧，不要一次随机出完。

`@2x`、`@3x`、深色模式、16/24/48pt 是导出，不在这里重复生成。
