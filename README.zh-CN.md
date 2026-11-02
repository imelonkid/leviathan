# Leviathan · 利维坦地狱

[English](README.md) · **简体中文**

一个第一人称氛围漫游场景：一座层层升高的土墙迷宫，上空悬浮着缓慢自转的几何神明，周期性射出“吸走光线”的黑光。没有战斗、任务和胜负，只有走、看和迷路。

灵感来自 1988 年电影《养鬼吃人2》（Hellbound: Hellraiser II）里“几何神明统治迷宫”的意象，场景、造型与声音均为原创。

![利维坦悬浮在风暴中的迷宫上空](docs/screenshots/hero.jpg)

| | |
| --- | --- |
| ![阶梯金字塔](docs/screenshots/tiers.jpg) | ![拱门走道](docs/screenshots/corridor.jpg) |
| ![黑光扫过迷宫](docs/screenshots/beam.jpg) | ![闪电](docs/screenshots/lightning.jpg) |

- 引擎：Godot 4.6（Forward+ 渲染器）
- 素材：场景全部程序化生成；背景音乐由作者提供
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
| Shift | 奔跑 |
| 空格 | 跳跃；**空中按住升空，松开滑翔**（从地面一直按着也会接着升空） |
| F | 开关提灯 |
| Esc | 菜单与设置（点击窗口重新锁定鼠标） |
| R | 换一座迷宫（随机种子，回到出生点） |
| M | 开关小地图（默认显示） |
| F3 | 调试信息：帧率、绘制调用、坐标、种子 |
| F12 | 截图，保存到用户数据目录的 `screenshots/` |
| V | 自由飞行（穿墙、无重力，空格上升、Ctrl 下降、Shift 加速）；只在菜单里打开「拍照模式」后可用 |

开局站在最外一圈观景台上，隔着迷宫远远望见利维坦。R、F3 是开发调试用的。

**滑翔**：升空和滑翔都消耗屏幕下方的能量条，在地面走动时积攒（走约 50 米充满），用完就落回地面，不会摔伤。最多升到比最近站过的地面高 13 米：越得过层内的墙、看得见周围，翻不上一层的挡土墙（12 米加栏杆），上层还是得走楼梯。滑翔也出不了最外圈围墙。

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

- **阶梯金字塔**：整座迷宫约 255 米见方，分 4 层，从外到内一层比一层高 12 米：第 0 层外环（出生点）→ 第 1 层 → 第 2 层 → 顶层广场。每一层是一圈独立的迷宫（递归回溯生成，额外打通少量墙制造回路），层内墙高 8～11 米。
- **大楼梯**：层与层之间是 12 米高的挡土墙，每道只开两段大楼梯（约 39°，夹在石墙之间），从低层最里一排爬进高层迷宫。每往上一层，楼梯的方位转 90°，得穿过这一层的迷宫才找得到下一段。
- **观景台**：挡土墙顶是一圈与高层齐平的观景台，高层迷宫的外墙上开了几道门通向它。崖边有齐腰高的栏杆（跳不过去），站在栏杆边能俯瞰下面各层的迷宫。
- **出生点**：最外一圈观景台（离中心约 100 米，正对着一扇矮墙“观景窗”），往里要穿过第 1、2 层的迷宫、爬两段大楼梯才到利维坦正下方。
- **顶层广场**：最高处的空地。四角立方尖柱，正上方就是利维坦，四周望出去是层层下降的迷宫。
- **建筑**：墙面是风化的旧灰泥和夯土，有斑驳、龟裂、水渍和墙根积土，灰泥剥落处露出土坯砖；地面是踩实的土（`wall.gdshader`，按世界坐标程序生成，带凹凸）。部分通道上方架着拱门，通向观景台的门一律是拱门；朝向走道的墙面上一层层开着带窗框和窗台的拱窗。
- **深渊区**：某几层的一段没有墙也没有地面，格子变成立在细柱上的悬空平台，通道变成 1.4 米宽的窄桥。掉下去会回到最近站稳的位置。
- **矮墙**：同层的部分隔墙降成 1.4 米高，能看见隔壁走道却过不去。
- **拱廊墙**：部分隔墙的墙身开着并排两个穿透整块墙的拱洞，能看见隔壁，走不过去也滑翔不过去；庭院围墙上更多。
- **庭院与墙顶步道**：每层有几个 2×2 格子打通成的方形庭院（15 米见方），围墙统一 8 米高。院里贴着一面墙有两段楼梯，爬到角上一块和墙顶齐平的挑台，从挑台能走上围墙顶，在走道上方绕院子一圈。
- **房间**：每层一间带屋顶的房间（15 米见方、6 米高），原来通向那几格的通道都变成拱门门洞。屋里不吃外面的环境光，只靠自己的灯，三个主题每座迷宫各一间（小地图上是暗红色方块）：
  - **病房**：发黄的瓷砖墙裙和地面，两排铁床，有的歪了、翻了、没床垫；三盏日光灯一亮、一闪、一灭，闪的那盏伴着镇流器的嗡嗡声。
  - **神龛**：屋顶一圈天光照下来，三级台座上悬着一个缩小的黄铜菱形，刻纹和天上的利维坦一样，缓缓自转；地上一圈残烛，越走近低鸣越响。
  - **钟房**：四面墙挂满大小不一的钟，各走各的（飞转、倒走、停摆），角落一座落地钟在摆；滴答声此起彼伏，从不对齐。
- **无尽迷宫**：最外圈围墙之外还有一大片走不到的迷宫，一直延伸进雾里。
- **利维坦**：竖直悬浮的巨大菱形体（宽 84 米、高 340 米），中心在 250 米高空，绕自身竖轴缓慢自转。表面是旧黄铜，刻满纹样：沿棱的边框、每 34 米一道横带、带子里的回纹、腰部的大徽章（`leviathan.gdshader`，程序生成）。一盏只照它的主光让它一面亮一面暗。
- **黑光**：两束光从利维坦腰部朝相反方向射出，以 66° 的俯角稳定旋转（约 52 秒一圈），落在离中心约 110 米的一圈上，像探照灯一样扫过迷宫。每束是一道越往外越宽的锥体，正中浓黑、边缘渐淡、远端消散，里面有往外流动的暗纹。
- **被黑光扫中**：镜头进入光锥时，画面褪色、从四周往中间压黑、微微扭动、轻微抖动，同时响起一记低沉的压迫声；光束扫过后慢慢缓过来（`beam_fx.gd`）。
- **风暴**：天空是光线步进的体积乌云（`sky.gdshader`），云顶亮、云底暗，背光的边缘透出亮边。利维坦腰部缠着一圈浓重的体积云（`cloud_ring.gdshader`），绕着它缓慢盘旋，挡在前面的云会遮住本体。每隔 5～14 秒一道闪电，劈向迷宫或在云间横窜，照亮云层和整个场景，一两秒后传来雷声。
- **氛围**：冷色低角度平行光；远景指数雾让利维坦半隐半现；近景体积雾让光束和提灯显形；SSAO、辉光、降饱和。
- **声音**：背景音乐 `assets/audio/liweitan.mp3`（36 秒循环，走单独的 Music 总线，音量在 Esc 菜单里调）。雷声和被黑光扫中时的低频压迫声是程序合成的（`drone.gd`），走带大空间混响的 Ambience 总线；被黑光扫中时音乐也会被压下去。

## 目录结构

```
leviathan/
├── project.godot        项目配置
├── export_presets.cfg   三个平台的导出配置
├── main.tscn            主场景（只有一个根节点，内容全部由脚本生成）
├── assets/audio/        背景音乐
├── docs/screenshots/    README 用的截图（.gdignore，不进游戏包）
├── scripts/
│   ├── main.gd          入口：环境、灯光、组装各模块、换种子、截图
│   ├── maze_gen.gd      迷宫数据生成：分层、楼梯、观景台、深渊区、庭院、拱廊墙、墙高（不碰节点）
│   ├── maze.gd          把网格数据搭成场景：墙、地面、楼梯、栏杆、平台、窄桥、拱门、拱窗、拱廊墙、外圈装饰迷宫
│   ├── arch_mesh.gd     拱门和拱窗的网格
│   ├── wall.gdshader    程序化旧土墙：灰泥、剥落的土坯、裂纹、水渍、土地面
│   ├── leviathan.gd     利维坦本体、照亮它的灯、黑光光束
│   ├── leviathan.gdshader  利维坦的旧黄铜与刻纹
│   ├── beam_fx.gd       被黑光扫中时的画面效果
│   ├── storm.gd         风暴：天空、闪电
│   ├── sky.gdshader     光线步进的体积乌云
│   ├── cloud_ring.gdshader  缠绕利维坦的体积云环
│   ├── rooms/           房间：room.gd（公共部分：内衬、灯、声音）、ward.gd 病房、shrine.gd 神龛、clocks.gd 钟房、tiles.gdshader 瓷砖
│   ├── player.gd        第一人称控制器、提灯、能量滑翔、拍照模式的自由飞行
│   ├── energy_bar.gd    滑翔能量条
│   ├── drone.gd         程序化雷声、黑光压迫声（无背景音乐时还有嗡鸣与号角）
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
| 层数与每层宽度 | `maze_gen.gd` → `BANDS`（挡土墙所在的格子环）、`maze.gd` → `cells` |
| 层高 | `maze_gen.gd` → `TIER_H` |
| 层内墙高（越矮从上面越看得清下层） | `maze_gen.gd` → `WALL_MIN` / `WALL_MAX` |
| 每层楼梯数 / 观景台门数 | `maze_gen.gd` → `STAIRS_PER_BAND` / `GATES_PER_BAND` |
| 深渊区数量 | `maze_gen.gd` → `CHASM_COUNT` |
| 栏杆高度（看起来 / 实际挡住） | `maze.gd` → `RAIL_H` / `RAIL_BLOCK_H` |
| 外圈装饰迷宫范围 | `maze.gd` → `FIELD_RADIUS` |
| 拱门出现概率 | `maze_gen.gd` → `ARCH_CHANCE` |
| 拱门 / 拱窗尺寸、拱窗出现概率 | `maze.gd` → `GATE_*` / `WINDOW_*` |
| 墙面颜色、剥落程度、裂纹、水渍、凹凸 | `wall.gdshader` 顶部的 `uniform` |
| 矮墙出现概率 | `maze_gen.gd` → `_make_parapets()` |
| 每层庭院数、庭院围墙 / 挑台高度 | `maze_gen.gd` → `COURTYARDS_PER_TIER` / `COURT_H` |
| 拱廊墙出现概率（普通 / 庭院围墙） | `maze_gen.gd` → `ARCADE_CHANCE` / `COURT_ARCADE_CHANCE` |
| 拱廊墙的拱洞尺寸与高度 | `maze.gd` → `ARCADE_*` |
| 房间主题、屋顶高度 | `maze_gen.gd` → `ROOM_THEMES` / `ROOM_H` |
| 房间里的东西 | `scripts/rooms/` 下各主题脚本顶部的常量；道具的可见距离 `room.gd` → `VIS` |
| 窄桥宽度 / 平台大小 | `maze.gd` → `PLANK_W` / `PLATFORM_W` |
| 利维坦高度 | `main.gd` → `LEVIATHAN_HEIGHT` |
| 利维坦尺寸 | `leviathan.gd` → `HALF_WIDTH` / `HALF_HEIGHT` |
| 利维坦的铜色、刻纹、磨损 | `leviathan.gdshader` 顶部的 `uniform` 和 `fragment()` 里的纹样 |
| 闪电频率 / 粗细 | `storm.gd` → `STRIKE_MIN` / `STRIKE_MAX` / `BOLT_WIDTH` |
| 云量、云层高度、云团大小、步进次数 | `sky.gdshader` → `coverage` / `cloud_bottom` / `cloud_top` / `scale` / `steps` |
| 云的明暗、亮边方向 | `sky.gdshader` → `ambient_color` / `shadow_color` / `light_color` / `light_dir` |
| 利维坦的主光 | `leviathan.gd` → `_ready()` 里的 `key` |
| 黑光的俯角 / 转速 / 粗细浓淡 | `leviathan.gd` → `BEAM_DIP` / `BEAM_SPEED` / `BEAM_CONES` |
| 被黑光扫中的强度 | `beam_fx.gd` 着色器里的压黑、褪色、扭动系数；声音在 `drone.gd` 的 `press` |
| 云环的范围、浓度、盘旋速度、明暗 | `cloud_ring.gdshader` 顶部的 `uniform`（包围盒大小在 `storm.gd` → `RING_*`） |
| 滑翔：升空速度与耗能、下落速度、水平速度、充能距离、升空上限 | `player.gd` → `RISE_SPEED` / `RISE_COST` / `GLIDE_FALL` / `GLIDE_SPEED` / `GLIDE_COST` / `CHARGE_PER_M` / `CEILING` |
| 光束数量 / 摆幅 / 明灭节奏 | `leviathan.gd` → `BEAM_COUNT`、`_process()` |
| 走路 / 奔跑 / 自由飞行速度 | `player.gd` → `WALK_SPEED` / `RUN_SPEED` / `FLY_SPEED` |
| 画质预设 | `settings.gd` → `PRESETS` |
| 背景音乐 | 替换 `assets/audio/liweitan.mp3`，或改 `main.gd` 里的 `MUSIC` |
| 背景音乐被黑光压低的程度 | `main.gd` → `_process()` 里的 `0.75` |
| 号角音高 / 节奏（无背景音乐时） | `drone.gd` → `HORN_FREQ` / `UNIT` |

## 发布

版本一律走 tag：在 `main` 上打 `vX.Y.Z` 并推送，GitHub Actions 自动导出三个平台的版本并创建 Release。每个阶段结束发一个版本，见 [ROADMAP.md](ROADMAP.md)。

## 技术选型例外

本项目是游戏，不在运维基线的技术栈（TypeScript / NestJS 等）范围内：引擎用 Godot 4.6，语言用 GDScript。不部署到服务器，也不登记服务注册表；发布产物是 GitHub Releases 上的安装包。由项目所有者决定（2026-11-01）。

## 许可证

代码以 [MIT](LICENSE) 许可证开源。之后加入的自制美术、音频素材另行标注许可证（计划使用 CC BY-NC 4.0），第三方素材遵循各自的许可证。

背景音乐 `assets/audio/liweitan.mp3` 由项目作者提供，不适用 MIT 许可证；许可方式待作者标注，在此之前请勿在本项目以外使用。

## 关于版权

本项目非商业，只借用“几何神明悬浮于迷宫上空”这一抽象意象。原片中的具体角色（如钉子头、修道士）、造型、配乐和名称均受版权保护，**不会加入本项目**；欢迎贡献，但请只提交原创内容或许可证允许再分发的素材。
