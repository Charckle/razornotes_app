extends Control


func _ready() -> void:
	%OKBtn.pressed.connect(hide)
	$Backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			hide()
	)


func popup_error(title: String, message: String) -> void:
	%TitleLabel.text = title
	%MessageLabel.text = message
	show()
