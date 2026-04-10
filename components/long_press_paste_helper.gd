extends RefCounted
## Adds double-tap-to-paste behaviour to a LineEdit.
## Tapping the field twice within DOUBLE_TAP_TIME seconds shows a floating "Paste" button.
## Useful on Android where the native long-press paste menu is suppressed
## for password-type inputs.

const DOUBLE_TAP_TIME := 0.35


static func bind_field(field: LineEdit) -> void:
	var last_tap_time := [-1.0]

	field.gui_input.connect(func(event: InputEvent) -> void:
		var pressed_now := false

		if event is InputEventScreenTouch:
			pressed_now = event.pressed
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			pressed_now = event.pressed

		if pressed_now:
			var now := Time.get_ticks_msec() / 1000.0
			var since_last: float = now - last_tap_time[0]
			if last_tap_time[0] >= 0.0 and since_last <= DOUBLE_TAP_TIME:
				_show_paste(field)
				last_tap_time[0] = -1.0
			else:
				last_tap_time[0] = now
	)


static func _show_paste(field: LineEdit) -> void:
	var clip := DisplayServer.clipboard_get()
	if clip.is_empty():
		return

	var layer := CanvasLayer.new()
	layer.layer = 128
	field.get_tree().root.add_child(layer)

	# Transparent full-screen area — tap anywhere outside to dismiss
	var backdrop := Button.new()
	backdrop.flat = true
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)

	var btn := Button.new()
	btn.text = "Paste"
	btn.custom_minimum_size = Vector2(108, 44)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(btn)

	# Position the button just above the field
	var rect: Rect2 = field.get_global_rect()
	btn.position = Vector2(rect.position.x, rect.position.y - 52)

	var dismiss := func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()

	btn.pressed.connect(func() -> void:
		field.text = clip
		field.caret_column = field.text.length()
		dismiss.call()
	)

	backdrop.pressed.connect(dismiss)

	# Auto-dismiss after 4 s in case the user ignores it
	field.get_tree().create_timer(4.0).timeout.connect(dismiss)
