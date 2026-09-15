class_name InfoWindow
extends PanelContainer
## Draggable, closable detail popover (title bar, portrait + text body, optional Follow/Centre buttons).
## Owned by SpectatePanel. Source: .warboss-horde/slices/info-window.md.

signal close_pressed
signal follow_pressed
signal center_pressed

const WIDTH := 300.0
const PORTRAIT_SIZE := 64.0
const BG_COLOR := Color(0.08, 0.08, 0.1, 0.88)

var key: String = ""
var _title_bar: HBoxContainer
var _title: Label
var _close: Button
var _portrait: TextureRect
var _body: Label
var _buttons: HBoxContainer
var _follow: Button
var _center: Button
var _dragging: bool = false


func _init() -> void:
	# Stylebox setup
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6.0)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(WIDTH, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Root container
	var root := VBoxContainer.new()
	add_child(root)

	# Title bar
	_title_bar = HBoxContainer.new()
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.gui_input.connect(_on_title_input)
	root.add_child(_title_bar)

	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title_bar.add_child(_title)

	_close = Button.new()
	_close.text = "x"
	_close.pressed.connect(func(): close_pressed.emit())
	_title_bar.add_child(_close)

	# Body row
	var body_row := HBoxContainer.new()
	root.add_child(body_row)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body_row.add_child(_portrait)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(WIDTH - PORTRAIT_SIZE - 24.0, 0.0)
	body_row.add_child(_body)

	# Buttons
	_buttons = HBoxContainer.new()
	root.add_child(_buttons)

	_follow = Button.new()
	_follow.text = "Follow"
	_follow.pressed.connect(func(): follow_pressed.emit())
	_buttons.add_child(_follow)

	_center = Button.new()
	_center.text = "Centre"
	_center.pressed.connect(func(): center_pressed.emit())
	_buttons.add_child(_center)


func set_content(title: String, lines: PackedStringArray, portrait: Texture2D, show_buttons: bool) -> void:
	_title.text = title
	_body.text = "\n".join(lines)
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_buttons.visible = show_buttons


func set_buttons_enabled(v: bool) -> void:
	_follow.disabled = not v
	_center.disabled = not v


static func clamp_pos(pos: Vector2, size: Vector2, view: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 0.0, maxf(0.0, view.x - size.x)), clampf(pos.y, 0.0, maxf(0.0, view.y - size.y)))


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed and get_parent() != null:
				move_to_front()
			if is_inside_tree():
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		position += mm.relative
		if is_inside_tree():
			position = clamp_pos(position, size, get_viewport_rect().size)
			accept_event()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and get_parent() != null:
			move_to_front()
