extends Control

const NoteListScene  := preload("res://menus/note_list/note_list.tscn")
const NoteViewScene  := preload("res://menus/note_view/note_view.tscn")
const SearchScene    := preload("res://menus/search/search.tscn")
const SettingsScene  := preload("res://menus/settings/settings.tscn")

var _current_view: Node = null


func _ready() -> void:
	ApiClient.auth_failed.connect(_on_auth_failed)

	%SearchBtn.pressed.connect(func() -> void: _close_browse_menu(); _swap_view(SearchScene))
	%HomeBtn.pressed.connect(func() -> void: _close_browse_menu(); _swap_view(NoteListScene))
	%LastBtn.pressed.connect(_toggle_browse_menu)
	%SettingsBtn.pressed.connect(func() -> void: _close_browse_menu(); _swap_view(SettingsScene))

	%RecentBtn.pressed.connect(_show_recent_notes)
	%AllNotesBtn.pressed.connect(_show_all_notes)

	_swap_view(NoteListScene)


func _swap_view(scene: PackedScene) -> void:
	if _current_view:
		_current_view.queue_free()
	_current_view = scene.instantiate()
	_wire_view(_current_view)
	%ContentArea.add_child(_current_view)


func _wire_view(view: Node) -> void:
	if view.has_signal("note_requested"):
		view.note_requested.connect(_open_note)


func _open_note(note_id: int) -> void:
	if _current_view:
		_current_view.queue_free()
	var view := NoteViewScene.instantiate()
	_current_view = view
	%ContentArea.add_child(view)
	view.back_requested.connect(func() -> void: _swap_view(NoteListScene))
	view.load_note(note_id)


func _toggle_browse_menu() -> void:
	%BrowseMenu.visible = not %BrowseMenu.visible


func _close_browse_menu() -> void:
	%BrowseMenu.hide()


func _show_recent_notes() -> void:
	_close_browse_menu()
	_swap_view(NoteListScene)
	if _current_view and _current_view.has_method("show_recent"):
		_current_view.show_recent()


func _show_all_notes() -> void:
	_close_browse_menu()
	_swap_view(NoteListScene)
	if _current_view and _current_view.has_method("show_all"):
		_current_view.show_all()


func _on_auth_failed() -> void:
	# Don't silently redirect — let note_list display the error and a retry button.
	# The user can go to Settings → Switch Account if they need to change accounts.
	pass
