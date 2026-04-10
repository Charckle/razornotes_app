extends Control

var _thread: Thread = null

const SYNC_MODES := ["remote_only", "local_some", "full_mirror"]
const _PassVis   := preload("res://components/password_visibility_helper.gd")
const _LongPaste := preload("res://components/long_press_paste_helper.gd")


func _ready() -> void:
	%SaveBtn.pressed.connect(_on_save_pressed)
	%CancelBtn.pressed.connect(_on_cancel_pressed)
	%SyncModeOption.add_item("Remote only (no local storage)", 0)
	%SyncModeOption.add_item("Local some (cache on open)", 1)
	%SyncModeOption.add_item("Full mirror (download everything)", 2)
	_PassVis.bind_button(%ServerPassShowBtn, %ServerPassInput)
	_PassVis.bind_button(%LocalPassShowBtn, %LocalPassInput)
	%ServerPassPasteBtn.pressed.connect(func() -> void:
		var clip := DisplayServer.clipboard_get()
		if not clip.is_empty():
			%ServerPassInput.text = clip
			%ServerPassInput.caret_column = clip.length()
	)
	_LongPaste.bind_field(%LabelInput)
	_LongPaste.bind_field(%UrlInput)
	_LongPaste.bind_field(%UsernameInput)
	_LongPaste.bind_field(%ServerPassInput)
	_LongPaste.bind_field(%LocalPassInput)


func _on_save_pressed() -> void:
	%ErrorLabel.text = ""

	var label    : String = %LabelInput.text.strip_edges()
	var url      : String = %UrlInput.text.strip_edges()
	var username : String = %UsernameInput.text.strip_edges()
	var srv_pass : String = %ServerPassInput.text
	var loc_pass : String = %LocalPassInput.text

	if loc_pass.length() < 4:
		%ErrorLabel.text = "Local password must be at least 4 characters."
		return

	var sync_mode: String = SYNC_MODES[%SyncModeOption.selected]

	%SaveBtn.disabled = true
	%SaveBtn.text = "Saving…"

	_thread = Thread.new()
	_thread.start(func() -> void:
		var err := AccountManager.add_account(label, url, username, srv_pass, loc_pass, sync_mode)
		_finish_save.call_deferred(err)
	)


func _finish_save(err: String) -> void:
	_thread.wait_to_finish()
	_thread = null
	%SaveBtn.disabled = false
	%SaveBtn.text = "Save Account"

	if err.is_empty():
		AccountManager.accounts_changed.emit()
		get_tree().change_scene_to_file("res://menus/account_select/account_select.tscn")
	else:
		%ErrorLabel.text = err


func _on_cancel_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/account_select/account_select.tscn")
