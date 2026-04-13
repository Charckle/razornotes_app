extends PanelContainer

signal note_pressed(note_id: int)

const DRAG_THRESHOLD := 12.0

var _note_id: int = 0
var _touch_start: Vector2 = Vector2.ZERO
var _tracking: bool = false
var _is_drag: bool = false


func setup(note_id: int, title: String, preview: String) -> void:
	_note_id = note_id
	%TitleLabel.text = title if not title.is_empty() else "Untitled"
	%PreviewLabel.text = preview.left(120)


func set_cached(is_cached: bool) -> void:
	%LocalBadge.visible = is_cached


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start = event.position
			_tracking = true
			_is_drag = false
		else:
			if _tracking and not _is_drag:
				note_pressed.emit(_note_id)
				get_viewport().set_input_as_handled()
			_tracking = false
	elif event is InputEventScreenDrag:
		if _tracking and event.position.distance_to(_touch_start) > DRAG_THRESHOLD:
			_is_drag = true
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			note_pressed.emit(_note_id)
			get_viewport().set_input_as_handled()
