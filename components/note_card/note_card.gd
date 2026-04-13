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


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start = event.position
			_tracking = true
			_is_drag = false
		elif _tracking:
			if not _is_drag:
				note_pressed.emit(_note_id)
				get_viewport().set_input_as_handled()
			_tracking = false


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenDrag and _tracking:
		if event.position.distance_to(_touch_start) > DRAG_THRESHOLD:
			_is_drag = true
