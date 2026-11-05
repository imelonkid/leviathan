# 倒吊者：本机授权素材原型

乱葬岗三棵枯树的高枝下各悬挂一名倒吊者。它保持缠裹与倒悬造型，以绳端为支点缓慢摇摆，不追逐、不发声。死光碰到绳端、身体中心或头部时保持当前姿势，离开后从同一相位继续，不突然归正。70 米外或窗口失焦时停止动画，实体保持可见且不删除。模型共用一份网格、材质和贴图，无骨骼、布料模拟、寻路或新增阴影。

2026-11-06 试玩调整：两个方向的摆幅较初版增大 50%，主摆约 1.8°、横摆约 1.0°，头部离静止位置最大约 8 厘米。摆动速度、死光冻结/恢复规则、模型和更新频率保持原样；不新增资源、节点或绘制批次，复核八种布局的原有碰撞净空。

同时修正头部死光取样位置：先将头部局部坐标转换到世界空间，避免把悬挂点的世界位置一起放大；增加仅头部被真实死光边缘照到的停摆回归。

## 素材与公开分发边界

本机源素材为 BlenderKit 下载的 **Last Offering**，assetBaseId `3eb3b7fe-46d9-48b7-8df4-1a74628593cb`，下载记录标记免费及 `royalty_free`。免费不等于 CC0。本项目的 MIT 许可不覆盖该素材；原文件、贴图和转换模型不提交公共仓库。

[官方许可 FAQ](https://www.blendkit.com/docs/licenses/licensing-faq/) 允许用于游戏，但要求不能被用户轻易提取。当前普通 Godot 资源包尚未落实这一分发条件，因此三个公开导出预设都显式排除 `assets/private/*`；公开构建会说明缺少本地模型并跳过倒吊者。公开 PR 提供行为、转换工具和不含授权素材的测试夹具，不能据此认为公开安装包已经包含该怪物。后续需确认合适分发方式或取得明确再分发许可。

## 本地准备

通过 BlenderKit 正常下载上述素材后，将自己的缓存 `.blend` 绝对路径传给转换工具。工具在独立 Blender 进程读取原文件，不修改原文件或已打开场景；输出到被 Git 忽略的 `assets/private/hanged_one.glb`。

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --disable-autoexec --python tools/blender/hanged_one.py -- /absolute/path/to/last-offering.blend
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --audio-driver Dummy --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --audio-driver Dummy --path . --script res://tests/hanged_one.gd -- --require-private
```

不提供占位怪物替代授权模型。默认 CI 使用明确的测试夹具检查相同的悬挂、摇摆和碰撞逻辑；本地 `--require-private` 额外检查实际模型的原点、三角形、材质和贴图。成本记录见 [entity-costs.md](entity-costs.md)。
