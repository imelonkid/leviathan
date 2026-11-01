# leviathan

第一人称氛围漫游场景（Godot 4.6 / GDScript），以 GitHub 开源项目的形式公开发布，供玩家下载体验，不商用。

## 边界（强制）

Claude 在本项目里只做下面「负责」的事；越界的需求先停下来和用户确认，不要顺手改到别的项目里。

- **本项目负责**：迷宫生成、场景与氛围（`scripts/`）、画质设置与菜单、导出配置（`export_presets.cfg`）、GitHub Actions 构建与 Releases 发布（`.github/workflows/`）、开发路线图（`ROADMAP.md`）
- **本项目不负责**：服务器部署、注册表登记、门户发布流水线（游戏不部署到服务器，不走 melon-ci）；玩法系统（战斗、任务、AI 追逐）不在当前定位内，要加先确认；原片中的角色、造型、配乐、名称一律不加入
- **与其他项目的关系**：无

## 运行

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

冒烟检查（跑几百帧后退出，看有没有脚本错误）：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . --quit-after 300
```

## 约定

- 场景全部由代码搭建，`main.tscn` 只有根节点；新模块写成 `scripts/` 下的脚本，在 `main.gd` 里组装
- 生成算法（迷宫网格数据）与 Godot 节点构建分开写，给可能的 UE5 迁移留退路
- 素材只用原创或许可证允许再分发的（CC0 优先），来源与许可证记进 README
- 用户可调的画质项放 `settings.gd`，并在 Esc 菜单里给出控件
- 提交信息 `<类型>(<范围>): <中文描述>`；默认分支 `main`，PR 一律以 `main` 为目标
- **PR 合并（或关闭）后这个分支就作废**：后续改动先 `git switch main && git pull` 再开新分支
- 发布走 tag：`vX.Y.Z` 推上去由 Actions 构建并发 Release；修 bug → patch，新功能 → minor
