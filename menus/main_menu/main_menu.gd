extends Control

const NoteListScene  := preload("res://menus/note_list/note_list.tscn")
const NoteViewScene  := preload("res://menus/note_view/note_view.tscn")
const SearchScene    := preload("res://menus/search/search.tscn")
const SettingsScene  := preload("res://menus/settings/settings.tscn")

var _current_view: Node = null
# Kept alive (hidden) while a note is open so Back returns instantly without a re-fetch.
var _note_list_view: Node = null


func _ready() -> void:
	ApiClient.auth_failed.connect(_on_auth_failed)

	%SearchBtn.pressed.connect(func() -> void: _close_browse_menu(); _swap_view(SearchScene))
	%HomeBtn.pressed.connect(func() -> void: _close_browse_menu(); _swap_view(NoteListScene))
	%LastBtn.pressed.connect(_toggle_browse_menu)
	%SettingsBtn.pressed.connect(func() -> void: _close_browse_menu(); _swap_view(SettingsScene))

	%RecentBtn.pressed.connect(_show_recent_notes)
	%AllNotesBtn.pressed.connect(_show_all_notes)
	%GetClBtn.pressed.connect(_on_get_clipboard_pressed)
	%SetClBtn.pressed.connect(_on_set_clipboard_pressed)

	%ToastHideTimer.timeout.connect(_hide_clipboard_toast)

	_swap_view(NoteListScene)


func _swap_view(scene: PackedScene) -> void:
	# Free the hidden note list if it's not the same node we're about to replace.
	if _note_list_view and _note_list_view != _current_view:
		_note_list_view.queue_free()
	_note_list_view = null
	if _current_view:
		_current_view.queue_free()
	_current_view = scene.instantiate()
	_wire_view(_current_view)
	%ContentArea.add_child(_current_view)
	if scene == NoteListScene:
		_note_list_view = _current_view


func _wire_view(view: Node) -> void:
	if view.has_signal("note_requested"):
		view.note_requested.connect(_open_note)


func _open_note(note_id: int) -> void:
	# Hide the current view (NoteList) instead of freeing it so Back can restore it instantly.
	if _current_view:
		_note_list_view = _current_view
		_current_view.hide()
	var view := NoteViewScene.instantiate()
	_current_view = view
	%ContentArea.add_child(view)
	view.back_requested.connect(func() -> void:
		view.queue_free()
		_current_view = _note_list_view
		if _note_list_view and is_instance_valid(_note_list_view):
			_note_list_view.show()
	)
	view.load_note(note_id)


func _toggle_browse_menu() -> void:
	%BrowseMenu.visible = not %BrowseMenu.visible


func _close_browse_menu() -> void:
	%BrowseMenu.hide()


func _show_clipboard_toast(message: String) -> void:
	%ToastLabel.text = message
	%ToastPanel.visible = true
	%ToastHideTimer.stop()
	%ToastHideTimer.start()


func _hide_clipboard_toast() -> void:
	%ToastPanel.visible = false


func _show_recent_notes() -> void:
	_close_browse_menu()
	_restore_or_swap_note_list()
	if _current_view and _current_view.has_method("show_recent"):
		_current_view.show_recent()


func _show_all_notes() -> void:
	_close_browse_menu()
	_restore_or_swap_note_list()
	if _current_view and _current_view.has_method("show_all"):
		_current_view.show_all()


func _restore_or_swap_note_list() -> void:
	if _note_list_view and is_instance_valid(_note_list_view):
		if _current_view and _current_view != _note_list_view:
			_current_view.queue_free()
		_current_view = _note_list_view
		_note_list_view.show()
	else:
		_swap_view(NoteListScene)


func _on_get_clipboard_pressed() -> void:
	var fetch := func() -> void:
		ApiClient.get_clipboard(func(ok: bool, data) -> void:
			if ok and data is Dictionary:
				DisplayServer.clipboard_set(str(data.get("clipboard", "")))
				_close_browse_menu()
				_show_clipboard_toast("Copied!")
			else:
				push_warning("Get clipboard failed: %s" % data)
				_show_clipboard_toast("Failed!")
		)
	if ApiClient.is_authenticated():
		fetch.call()
	else:
		ApiClient.authenticated.connect(fetch, CONNECT_ONE_SHOT)


func _on_set_clipboard_pressed() -> void:
	var clip := DisplayServer.clipboard_get()
	var push := func() -> void:
		ApiClient.set_clipboard(clip, func(ok: bool, data) -> void:
			if ok:
				_close_browse_menu()
				_show_clipboard_toast("Pushed!")
			else:
				push_warning("Set clipboard failed: %s" % data)
				_show_clipboard_toast("Failed!")
		)
	if ApiClient.is_authenticated():
		push.call()
	else:
		ApiClient.authenticated.connect(push, CONNECT_ONE_SHOT)


func _on_auth_failed() -> void:
	# Don't silently redirect — let note_list display the error and a retry button.
	# The user can go to Settings → Switch Account if they need to change accounts.
	pass
