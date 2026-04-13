extends Panel


func _ready() -> void:
	%BackBtn.pressed.connect(func() -> void:
		queue_free()
	)
	%ClearBtn.pressed.connect(_on_clear_pressed)
	_populate()


func _populate() -> void:
	for child in %LogContainer.get_children():
		child.queue_free()

	var entries := AppLogger.get_entries()
	if entries.is_empty():
		var lbl := Label.new()
		lbl.text = "No log entries yet."
		lbl.theme_override_colors = {}
		%LogContainer.add_child(lbl)
		return

	for entry in entries:
		var row := Label.new()
		row.text = "[%s]  %s" % [entry["time"], entry["msg"]]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		%LogContainer.add_child(row)

	await get_tree().process_frame
	%ScrollContainer.scroll_vertical = %ScrollContainer.get_v_scroll_bar().max_value


func _on_clear_pressed() -> void:
	AppLogger.clear()
	_populate()
