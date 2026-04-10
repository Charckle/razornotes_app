extends Control


func _ready() -> void:
	var account := AccountManager.get_current_account()

	%AccountLabelValue.text  = account.get("label", "—")
	%ServerUrlValue.text     = account.get("server_url", "—")
	%UsernameValue.text      = account.get("username", "—")

	var sync_mode: String = account.get("sync_mode", "remote_only")
	%SyncModeValue.text = sync_mode.replace("_", " ").capitalize()

	%SyncSection.visible = sync_mode == "full_mirror"
	if sync_mode == "full_mirror":
		%LastSyncedLabel.text = "Last synced: " + LocalStorage.get_last_synced_string()
		%SyncNowBtn.visible = true
		%SyncNowBtn.pressed.connect(_on_sync_now_pressed)

	%UserCredentialsBtn.pressed.connect(_on_user_credentials)
	%SwitchAccountBtn.pressed.connect(_on_switch_account)
	%AddAccountBtn.pressed.connect(_on_add_account)
	%LogoutBtn.pressed.connect(_on_logout)
	%CheckServerBtn.pressed.connect(_check_server_status)

	%VersionLabel.text = "v" + ProjectSettings.get_setting("application/config/version", "?")

	_check_server_status()


func _on_sync_now_pressed() -> void:
	%SyncNowBtn.disabled = true
	%SyncNowBtn.text = "Syncing…"
	SyncManager.start_sync(func(success: bool, error_msg: String) -> void:
		%SyncNowBtn.disabled = false
		%SyncNowBtn.text = "Sync Now"
		if success:
			%LastSyncedLabel.text = "Last synced: " + LocalStorage.get_last_synced_string()
		else:
			%LastSyncedLabel.text = "Sync failed."
			_show_error_popup("Sync failed", error_msg)
	)


func _check_server_status() -> void:
	%ServerStatusLabel.text = "Checking…"
	%ServerStatusLabel.modulate = Color(0.7, 0.7, 0.7, 1)
	%CheckServerBtn.disabled = true
	ApiClient.check_reachable(func(reachable: bool, error_msg: String) -> void:
		%CheckServerBtn.disabled = false
		if reachable:
			%ServerStatusLabel.text = "Online"
			%ServerStatusLabel.modulate = Color(0.3, 1.0, 0.4, 1)
		else:
			%ServerStatusLabel.text = "Unreachable"
			%ServerStatusLabel.modulate = Color(1.0, 0.35, 0.35, 1)
			_show_error_popup("Server unreachable", error_msg)
	)


func _show_error_popup(title: String, message: String) -> void:
	%ErrorDialog.popup_error(title, message)


func _on_user_credentials() -> void:
	get_tree().change_scene_to_file("res://menus/edit_account/edit_account.tscn")


func _on_switch_account() -> void:
	AccountManager.logout()
	get_tree().change_scene_to_file("res://menus/account_select/account_select.tscn")


func _on_add_account() -> void:
	get_tree().change_scene_to_file("res://menus/add_account/add_account.tscn")


func _on_logout() -> void:
	AccountManager.clear_refresh_token()
	AccountManager.logout()
	get_tree().change_scene_to_file("res://menus/account_select/account_select.tscn")


