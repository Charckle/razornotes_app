extends Control

var _thread: Thread = null

const SYNC_MODES := ["remote_only", "local_some", "full_mirror"]
const _PassVis := preload("res://components/password_visibility_helper.gd")
const _LongPaste := preload("res://components/long_press_paste_helper.gd")


func _ready() -> void:
	var acc := AccountManager.get_current_account()
	if acc.is_empty():
		get_tree().change_scene_to_file("res://menus/account_select/account_select.tscn")
		return

	%SaveBtn.pressed.connect(_on_save_pressed)
	%CancelBtn.pressed.connect(_on_cancel_pressed)

	%SyncModeOption.add_item("Remote only (no local storage)", 0)
	%SyncModeOption.add_item("Local some (cache on open)", 1)
	%SyncModeOption.add_item("Full mirror (download everything)", 2)

	var sm: String = acc.get("sync_mode", "remote_only")
	var idx := SYNC_MODES.find(sm)
	if idx < 0:
		idx = 0
	%SyncModeOption.select(idx)

	%LabelInput.text = acc.get("label", "")
	%UrlInput.text = acc.get("server_url", "")
	%UsernameInput.text = acc.get("username", "")
	%ServerPassInput.text = ""
	%ServerPassInput.placeholder_text = "Leave blank to keep current password"
	%CurrentLocalPassInput.text = ""
	%NewLocalPassInput.text = ""

	_PassVis.bind_button(%ServerPassShowBtn, %ServerPassInput)
	_PassVis.bind_button(%CurrentLocalPassShowBtn, %CurrentLocalPassInput)
	_PassVis.bind_button(%NewLocalPassShowBtn, %NewLocalPassInput)
	_LongPaste.bind_field(%LabelInput)
	_LongPaste.bind_field(%UrlInput)
	_LongPaste.bind_field(%UsernameInput)
	_LongPaste.bind_field(%ServerPassInput)
	_LongPaste.bind_field(%CurrentLocalPassInput)
	_LongPaste.bind_field(%NewLocalPassInput)


func _on_save_pressed() -> void:
	%ErrorLabel.text = ""

	var label: String = %LabelInput.text.strip_edges()
	var url: String = %UrlInput.text.strip_edges()
	var username: String = %UsernameInput.text.strip_edges()
	var srv_pass: String = %ServerPassInput.text
	var cur_local: String = %CurrentLocalPassInput.text
	var new_local: String = %NewLocalPassInput.text

	if not new_local.is_empty() and cur_local.is_empty():
		%ErrorLabel.text = "Enter your current local password to set a new one."
		return

	var sync_mode: String = SYNC_MODES[%SyncModeOption.selected]

	%SaveBtn.disabled = true
	%SaveBtn.text = "Saving…"

	_thread = Thread.new()
	_thread.start(func() -> void:
		var err := AccountManager.update_current_account(
			label, url, username, sync_mode, srv_pass, new_local, cur_local)
		_finish_save.call_deferred(err)
	)


func _finish_save(err: String) -> void:
	_thread.wait_to_finish()
	_thread = null
	%SaveBtn.disabled = false
	%SaveBtn.text = "Save changes"

	if err.is_empty():
		AccountManager.accounts_changed.emit()
		AccountManager.notify_unlocked()
		get_tree().change_scene_to_file("res://menus/main_menu/main_menu.tscn")
	else:
		%ErrorLabel.text = err


func _on_cancel_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/main_menu/main_menu.tscn")
