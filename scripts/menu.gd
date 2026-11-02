extends CanvasLayer
## Esc 菜单：画质设置、鼠标灵敏度、按键说明。打开时释放鼠标，关闭后点击窗口重新锁定。

const PRESET_IDS := ["low", "medium", "high", "custom"]
const PRESET_NAMES := ["低", "中", "高", "自定义"]

var settings: Node
var panel: PanelContainer
var preset_btn: OptionButton
var controls := {}               # 设置项 → 对应控件，设置变化时回写


func _ready() -> void:
	layer = 10
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(460, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.06, 0.92)
	style.set_content_margin_all(24)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	preset_btn = OptionButton.new()
	for i in PRESET_NAMES.size():
		preset_btn.add_item(PRESET_NAMES[i], i)
	preset_btn.set_item_disabled(3, true)
	preset_btn.item_selected.connect(func(i: int) -> void: settings.set_preset(PRESET_IDS[i]))
	_row(box, "画质预设", preset_btn)

	_check(box, "volumetric_fog", "体积雾（关闭后黑光几乎不可见）")
	_check(box, "ssao", "环境光遮蔽 SSAO")
	_check(box, "glow", "辉光")
	_slider(box, "shadow_distance", "阴影距离", 60.0, 300.0, 10.0, "%d 米")
	_slider(box, "render_scale", "渲染分辨率", 0.5, 1.0, 0.05, "%d%%", 100.0)
	_choice(box, "clouds", "乌云", ["低", "中", "高"])
	box.add_child(HSeparator.new())
	_check(box, "fullscreen", "全屏")
	_check(box, "vsync", "垂直同步")
	_slider(box, "mouse_sens", "鼠标灵敏度", 0.0005, 0.006, 0.0001, "%.1f", 1000.0)
	_slider(box, "key_look_speed", "方向键转向", 45.0, 240.0, 5.0, "%d°/秒")
	_slider(box, "music_volume", "音乐音量", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_check(box, "photo_mode", "拍照模式：V 自由飞行，穿墙、不耗能量")
	box.add_child(HSeparator.new())

	var keys := Label.new()
	keys.text = "WASD 移动 · 方向键 / 鼠标 转视角 · Shift 奔跑 · 空格 跳跃，空中按住升空、松开滑翔 · F 提灯 · M 小地图\n" \
		+ "滑翔耗能量，在地面走动时积攒 · R 换一座迷宫 · F3 调试信息 · F12 截图"
	keys.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	keys.add_theme_font_size_override("font_size", 14)
	box.add_child(keys)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var quit := Button.new()
	quit.text = "退出"
	quit.pressed.connect(func() -> void:
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	buttons.add_child(quit)
	var resume := Button.new()
	resume.text = "继续"
	resume.pressed.connect(close)
	buttons.add_child(resume)

	settings.changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		if panel.visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func open() -> void:
	panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	preset_btn.select(PRESET_IDS.find(settings.get_value("preset")))
	for key: String in controls:
		var c: Control = controls[key]
		if c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(settings.get_value(key))
		elif c is OptionButton:
			(c as OptionButton).select(settings.get_value(key))
		elif c is HSlider:
			(c as HSlider).set_value_no_signal(settings.get_value(key))
			c.get_meta("update").call()


func _row(box: VBoxContainer, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 140
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	box.add_child(row)


func _check(box: VBoxContainer, key: String, text: String) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.toggled.connect(func(on: bool) -> void: settings.set_value(key, on))
	controls[key] = cb
	box.add_child(cb)


func _choice(box: VBoxContainer, key: String, text: String, names: Array) -> void:
	var ob := OptionButton.new()
	for i in names.size():
		ob.add_item(names[i], i)
	ob.item_selected.connect(func(i: int) -> void: settings.set_value(key, i))
	controls[key] = ob
	_row(box, text, ob)


## 滑条右侧显示数值；display_mul 用来把内部值换算成好读的数字
func _slider(box: VBoxContainer, key: String, text: String, lo: float, hi: float,
		step: float, fmt: String, display_mul := 1.0) -> void:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.x = 180
	var readout := Label.new()
	readout.custom_minimum_size.x = 64
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var update := func() -> void: readout.text = fmt % (s.value * display_mul)
	s.set_meta("update", update)
	s.value_changed.connect(func(v: float) -> void:
		update.call()
		settings.set_value(key, v))
	controls[key] = s

	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 140
	row.add_child(label)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	row.add_child(readout)
	box.add_child(row)
