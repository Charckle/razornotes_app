extends RefCounted
## Wires a Button to toggle LineEdit.secret (Show / Hide password).

static func bind_button(show_btn: Button, field: LineEdit) -> void:
	show_btn.text = "Show"
	show_btn.custom_minimum_size = Vector2(88, 48)
	show_btn.pressed.connect(func() -> void:
		field.secret = not field.secret
		show_btn.text = "Hide" if not field.secret else "Show"
	)
