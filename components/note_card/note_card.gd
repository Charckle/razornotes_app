extends PanelContainer

signal note_pressed(note_id: int)

var _note_id: int = 0


func setup(note_id: int, title: String, preview: String) -> void:
	_note_id = note_id
	%TitleLabel.text = title if not title.is_empty() else "Untitled"
	%PreviewLabel.text = preview.left(120)


func set_cached(is_cached: bool) -> void:
	%LocalBadge.visible = is_cached


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		note_pressed.emit(_note_id)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			note_pressed.emit(_note_id)
			get_viewport().set_input_as_handled()
