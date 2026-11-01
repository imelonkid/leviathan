# Leviathan · 利维坦地狱

一个第一人称氛围漫游场景：一座巨大的石砌迷宫，上空悬浮着缓慢自转的几何神明，周期性射出“吸走光线”的黑光。没有战斗、任务和胜负，只有走、看和迷路。

灵感来自 1988 年电影《养鬼吃人2》（Hellbound: Hellraiser II）里“几何神明统治迷宫”的意象，场景、造型与声音均为原创。当前是**灰盒原型**，用来打磨空间尺度、迷失感和氛围。

<!-- TODO: 截图（游戏内按 F12 保存） -->

- 引擎：Godot 4.6（Forward+ 渲染器）
- 素材：目前全部程序化生成，没有外部资源
- 平台：macOS / Windows / Linux

## 下载试玩

到 [Releases](https://github.com/imelonkid/leviathan/releases) 下载对应平台的压缩包，解压后运行。

- **macOS**：应用没有 Apple 开发者签名，第一次打开会被系统拦截。在终端执行 `xattr -cr Leviathan.app` 后再双击，或者在 Finder 里右键 →「打开」。
- **Windows**：SmartScreen 提示“未知发布者”时，点「更多信息」→「仍要运行」。
- **配置**：需要支持 Vulkan 或 Metal 的独立显卡或较新的核显。卡顿时按 Esc 把画质调到「低」。

## 从源码运行

1. 安装 [Godot 4.6](https://godotengine.org/download)
2. 在项目管理器中「导入」本目录（选择 `project.godot`），按 F5 运行

也可以直接用命令行：

```bash
godot --path .
```

## 操作

| 按键 | 功能 |
| --- | --- |
| W / A / S / D | 移动 |
| Shift | 奔跑（飞行时加速） |
| 空格 | 跳跃（飞行时上升） |
| F | 开关提灯 |
| Esc | 菜单与设置（点击窗口重新锁定鼠标） |
| V | 飞行模式：穿墙、无重力，Ctrl 下降 |
| R | 换一座迷宫（随机种子，回到出生点） |
| M | 俯视小地图 |
| F3 | 调试信息：帧率、绘制调用、坐标、种子 |
| F12 | 截图，保存到用户数据目录的 `screenshots/` |

V、R、M、F3 是开发调试用的，会破坏迷失感，正常体验建议不用。

## 画质设置

Esc 菜单里有低 / 中 / 高三档预设，也可以单独调整：

| 项 | 说明 |
| --- | --- |
| 体积雾 | 最吃性能，也最影响氛围；关闭后黑光几乎看不见 |
| SSAO | 墙角和缝隙的暗部 |
| 辉光 | 利维坦棱线的光晕 |
| 阴影距离 | 远处墙体的阴影 |
| 渲染分辨率 | 低于 100% 时用 FSR 放大 |

设置保存在用户数据目录的 `settings.cfg`。

## 场景内容

- **迷宫**：35×35 网格（约 175 米见方），递归回溯算法生成，额外打通少量墙制造回路。墙高 18～42 米随机，外圈 70 米。
- **高差**：地面分 0～4 层（每层 3 米），广场在最低处，越往外越高，走向利维坦就是一路下行。相邻格子最多差一层，差一层的通道是楼梯。
- **深渊区**：两片没有墙也没有地面的区域，格子变成立在细柱上的悬空平台，通道变成 1.4 米宽的窄桥（有高差时斜着搭）。掉下去会回到最近站稳的位置。
- **矮墙**：部分隔墙降成 1.4 米高的矮墙，能看见隔壁走道却过不去，两侧有高差时更常见。
- **中心广场**：9×9 网格的空地，四角立方尖柱，正上方是利维坦。
- **利维坦**：拉长的菱形体（宽 32 米、高 140 米），悬于 170 米高空，倾斜缓慢自转，棱线发光。
- **黑光**：三道光束绕中心旋转、来回摆动扫过迷宫，每道亮 7 秒灭 5 秒、彼此错开。用黑色 FogVolume 实现，在体积雾中呈现为“吸走光线”的暗柱。
- **氛围**：冷色低角度平行光；远景指数雾让利维坦半隐半现；近景体积雾让光束和提灯显形；SSAO、辉光、降饱和。
- **声音**：程序合成。持续的低频嗡鸣，周期性响起按摩斯电码 “GOD”（`--. --- -..`）节奏鸣响的号角。主总线挂了大空间混响。

## 目录结构

```
leviathan/
├── project.godot        项目配置
├── export_presets.cfg   三个平台的导出配置
├── main.tscn            主场景（只有一个根节点，内容全部由脚本生成）
├── scripts/
│   ├── main.gd          入口：环境、灯光、组装各模块、换种子、截图
│   ├── maze_gen.gd      迷宫数据生成：类型、层数、楼梯方向、墙高（不碰节点）
│   ├── maze.gd          把网格数据搭成场景：墙、地面、楼梯、平台、窄桥
│   ├── leviathan.gd     利维坦本体、棱线、黑光光束
│   ├── player.gd        第一人称控制器、提灯、飞行模式
│   ├── drone.gd         程序化环境音与号角
│   ├── settings.gd      画质与操作设置，读写 settings.cfg
│   ├── menu.gd          Esc 菜单
│   └── debug_hud.gd     调试信息与小地图
└── .github/workflows/
    └── build.yml        构建三个平台；推 v* tag 时发布到 Releases
```

## 常用调参

| 想调整 | 位置 |
| --- | --- |
| 近处雾浓度 | `main.gd` → `volumetric_fog_density` |
| 远处雾浓度（利维坦清晰度） | `main.gd` → `fog_density` |
| 主光亮度 / 角度 | `main.gd` → `sun.light_energy` / `sun.rotation_degrees` |
| 走道暗部亮度（墙面） | `main.gd` → `ambient_light_energy` |
| 走道地面亮度（竖直天光） | `main.gd` → `sky_fill.light_energy` |
| 走道里雾的亮度 | `main.gd` → `volumetric_fog_ambient_inject` |
| 迷宫布局 | `maze.gd` → `seed_value`（运行时按 R 随机） |
| 迷宫大小 / 走道宽度 | `maze.gd` → `cells` / `block` |
| 墙高范围 | `maze_gen.gd` → `_assign_wall_heights()` 中的 `randf_range` |
| 层数 / 层高 | `maze_gen.gd` → `MAX_LEVEL` / `LEVEL_H` |
| 楼梯密度 | `maze_gen.gd` → `TERRAIN_FREQ`（越大越密） |
| 深渊区数量 | `maze_gen.gd` → `CHASM_COUNT` |
| 矮墙出现概率 | `maze_gen.gd` → `_make_parapets()` |
| 窄桥宽度 / 平台大小 | `maze.gd` → `PLANK_W` / `PLATFORM_W` |
| 利维坦高度 | `main.gd` → `LEVIATHAN_HEIGHT` |
| 利维坦尺寸 | `leviathan.gd` → `HALF_WIDTH` / `HALF_HEIGHT` |
| 光束数量 / 摆幅 / 明灭节奏 | `leviathan.gd` → `BEAM_COUNT`、`_process()` |
| 移动 / 飞行速度 | `player.gd` 顶部常量 |
| 画质预设 | `settings.gd` → `PRESETS` |
| 号角音高 / 节奏 | `drone.gd` → `HORN_FREQ` / `UNIT` |

## 发布

版本一律走 tag：在 `main` 上打 `vX.Y.Z` 并推送，GitHub Actions 自动导出三个平台的版本并创建 Release。每个阶段结束发一个版本，见 [ROADMAP.md](ROADMAP.md)。

## 技术选型例外

本项目是游戏，不在运维基线的技术栈（TypeScript / NestJS 等）范围内：引擎用 Godot 4.6，语言用 GDScript。不部署到服务器，也不登记服务注册表；发布产物是 GitHub Releases 上的安装包。由项目所有者决定（2026-11-01）。

## 许可证

代码以 [MIT](LICENSE) 许可证开源。之后加入的自制美术、音频素材另行标注许可证（计划使用 CC BY-NC 4.0），第三方素材遵循各自的许可证。

## 关于版权

本项目非商业，只借用“几何神明悬浮于迷宫上空”这一抽象意象。原片中的具体角色（如钉子头、修道士）、造型、配乐和名称均受版权保护，**不会加入本项目**；欢迎贡献，但请只提交原创内容或许可证允许再分发的素材。
