extends Control

var _selected_account_id: String = ""
var _thread: Thread = null

const _PassVis := preload("res://components/password_visibility_helper.gd")


func _ready() -> void:
	%AddAccountBtn.pressed.connect(_go_to_add_account)
	%UnlockBtn.pressed.connect(_on_unlock_pressed)
	%CancelUnlockBtn.pressed.connect(_show_account_list)
	%LocalPassInput.text_submitted.connect(func(_text): _on_unlock_pressed())
	_PassVis.bind_button(%UnlockPassShowBtn, %LocalPassInput)

	if not AccountManager.has_accounts():
		_go_to_add_account()
		return

	# Try to jump straight to the password prompt for the last-used account.
	var last_id := AccountManager.get_last_account_id()
	if not last_id.is_empty():
		for account in AccountManager.get_accounts_meta():
			if account["id"] == last_id:
				_refresh_list()
				_on_account_selected(last_id, account.get("label", "Account"))
				return

	_show_account_list()


func _show_account_list() -> void:
	%AccountListView.show()
	%UnlockView.hide()
	%LocalPassInput.text = ""
	_mask_unlock_pass_visible()
	%UnlockErrorLabel.text = ""
	_refresh_list()


func _refresh_list() -> void:
	for child in %AccountList.get_children():
		child.queue_free()

	var accounts := AccountManager.get_accounts_meta()
	%NoAccountsLabel.visible = accounts.is_empty()

	for account in accounts:
		var btn := Button.new()
		var sync_label: String = account.get("sync_mode", "remote_only").replace("_", " ")
		btn.text = "%s\n%s  •  %s  •  %s" % [
			account.get("label", ""),
			account.get("username", ""),
			account.get("server_url", ""),
			sync_label
		]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 80)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = account["id"]
		var lbl: String = account.get("label", "Account")
		btn.pressed.connect(_on_account_selected.bind(id, lbl))
		%AccountList.add_child(btn)


func _on_account_selected(account_id: String, label: String) -> void:
	_selected_account_id = account_id
	%UnlockTitleLabel.text = "Unlock: %s" % label
	%LocalPassInput.text = ""
	_mask_unlock_pass_visible()
	%UnlockErrorLabel.text = ""
	%AccountListView.hide()
	%UnlockView.show()
	%LocalPassInput.grab_focus()


func _on_unlock_pressed() -> void:
	var password : String= %LocalPassInput.text
	if password.is_empty():
		%UnlockErrorLabel.text = "Enter your local password."
		return

	%UnlockBtn.disabled = true
	%UnlockBtn.text = "Unlocking…"

	_thread = Thread.new()
	_thread.start(_thread_unlock.bind(_selected_account_id, password))


func _thread_unlock(account_id: String, password: String) -> void:
	var ok := AccountManager.unlock_account(account_id, password)
	_finish_unlock.call_deferred(ok)


func _finish_unlock(ok: bool) -> void:
	_thread.wait_to_finish()
	_thread = null
	%UnlockBtn.disabled = false
	%UnlockBtn.text = "Unlock"

	if ok:
		AccountManager.notify_unlocked()
		get_tree().change_scene_to_file("res://menus/main_menu/main_menu.tscn")
	else:
		%UnlockErrorLabel.text = "Wrong password."
		%LocalPassInput.text = ""
		_mask_unlock_pass_visible()


func _mask_unlock_pass_visible() -> void:
	%LocalPassInput.secret = true
	%UnlockPassShowBtn.text = "Show"


func _go_to_add_account() -> void:
	get_tree().change_scene_to_file("res://menus/add_account/add_account.tscn")
