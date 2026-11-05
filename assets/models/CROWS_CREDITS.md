# 乌鸦模型

- 原作：[Low Poly Crow – Rigged](https://blendswap.com/blend/7340)，作者 **Nodelete**，**CC0 / Public Domain**。
- 下载包：`Low Poly Crow - Rigged.zip`，SHA-256 `a96adda0bf60ebc27ea8a34ff364a677423492ffabd62b9b9e9cd2494eecfc7d`。
- 原始文件 `Crow - rev001.blend` 保存为 `tools/blender/sources/crow/Crow.blend`；原包许可原样保存在同目录的 `BLENDSWAP_LICENSE.txt`。许可中的旧网址 `blends/view/61014` 是原包的历史地址。
- 适配脚本：`tools/blender/crows.py`。移除原细分和旧绑定，轻量减面、统一坐标与黑羽材质，补齐原作 37 个未绑定顶点的分区，再按原顶点组拆为身体/头/右翅，左翅复用镜像网格；为栖枝补充简化脚爪。导出 `crows.glb`，游戏中不携带骨骼或贴图。
- 原作未包含动画片段；转头、收翅、振翅与起落由 `scripts/crows.gd` 驱动。没有把“带绑定”当作“带动画”。
- [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。声音另见 `assets/audio/crows/CREDITS.md`。
