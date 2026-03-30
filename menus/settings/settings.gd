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
		%SyncNowBtn.pressed.connect(_on_sync_now_pressed)

	%SwitchAccountBtn.pressed.connect(_on_switch_account)
	%AddAccountBtn.pressed.connect(_on_add_account)
	%LogoutBtn.pressed.connect(_on_logout)
	%CheckServerBtn.pressed.connect(_check_server_status)

	%RemoveAccountBtn.pressed.connect(func() -> void: %ConfirmRemovePanel.show())
	%ConfirmNoBtn.pressed.connect(func() -> void: %ConfirmRemovePanel.hide())
	%ConfirmYesBtn.pressed.connect(_on_remove_account)

	_check_server_status()


func _on_sync_now_pressed() -> void:
	%SyncNowBtn.disabled = true
	%SyncNowBtn.text = "Syncing…"
	# Delegate to note_list logic via signal would be clean,
	# but for settings we just trigger a hashes check directly.
	ApiClient.get_notes_hashes(func(ok: bool, data) -> void:
		%SyncNowBtn.disabled = false
		%SyncNowBtn.text = "Sync Now"
		if ok:
			AccountManager.update_last_synced()
			%LastSyncedLabel.text = "Last synced: " + LocalStorage.get_last_synced_string()
		else:
			%LastSyncedLabel.text = "Sync failed."
	)


func _check_server_status() -> void:
	%ServerStatusLabel.text = "Checking…"
	%ServerStatusLabel.modulate = Color(0.7, 0.7, 0.7, 1)
	%CheckServerBtn.disabled = true
	ApiClient.check_reachable(func(reachable: bool) -> void:
		%CheckServerBtn.disabled = false
		if reachable:
			%ServerStatusLabel.text = "Online"
			%ServerStatusLabel.modulate = Color(0.3, 1.0, 0.4, 1)
		else:
			%ServerStatusLabel.text = "Unreachable"
			%ServerStatusLabel.modulate = Color(1.0, 0.35, 0.35, 1)
	)


func _on_switch_account() -> void:
	AccountManager.logout()
	get_tree().change_scene_to_file("res://menus/account_select/account_select.tscn")


func _on_add_account() -> void:
	get_tree().change_scene_to_file("res://menus/add_account/add_account.tscn")


func _on_logout() -> void:
	AccountManager.clear_refresh_token()
	AccountManager.logout()
	get_tree().change_scene_to_file("res://menus/account_select/account_select.tscn")


func _on_remove_account() -> void:
	var account_id: String = AccountManager.get_current_account().get("id", "")
	if account_id.is_empty():
		return
	LocalStorage.clear_account_cache(account_id)
	AccountManager.remove_account(account_id)
	get_tree().change_scene_to_file("res://menus/account_select/account_select.tscn")
