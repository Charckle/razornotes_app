extends Control

signal back_requested

var _note_id: int = 0
var _sync_mode: String = ""
var _raw_text: String = ""
var _formatted: bool = true


func _ready() -> void:
	%BackBtn.pressed.connect(func() -> void: back_requested.emit())
	%FormatBtn.pressed.connect(_on_format_btn_pressed)
	_sync_mode = AccountManager.get_current_account().get("sync_mode", "remote_only")
	_update_format_btn()


func load_note(note_id: int) -> void:
	_note_id = note_id
	%TitleLabel.text = ""
	%NoteText.text = ""
	%StatusLabel.text = ""
	%LoadingLabel.show()

	match _sync_mode:
		"remote_only":
			_fetch_from_server()
		"local_some":
			_load_local_some()
		"full_mirror":
			_load_from_local()


# ── Load strategies ───────────────────────────────────────────────────────────

func _fetch_from_server() -> void:
	ApiClient.get_note(_note_id, func(ok: bool, data) -> void:
		if ok and data is Dictionary:
			_display(data, "live")
		else:
			%LoadingLabel.text = "Failed to load note."
	)


func _load_from_local() -> void:
	var note := LocalStorage.get_note(_note_id)
	if note.is_empty():
		%LoadingLabel.text = "Note not available offline."
	else:
		_display(note, "from cache")


func _load_local_some() -> void:
	# 1. Check server hash. If offline → serve local.
	ApiClient.get_note_hash(_note_id, func(ok: bool, data) -> void:
		if not ok:
			_load_from_local()
			return

		var server_hash: String = data.get("v_hash", "") if data is Dictionary else ""
		var local_hash  := LocalStorage.get_local_hash(_note_id)

		if server_hash == local_hash and LocalStorage.has_note(_note_id):
			_load_from_local()
		else:
			# Need fresh copy
			ApiClient.get_note(_note_id, func(ok2: bool, note_data) -> void:
				if ok2 and note_data is Dictionary:
					_cache_note(note_data, server_hash)
					_display(note_data, "live")
				elif LocalStorage.has_note(_note_id):
					_load_from_local()
				else:
					%LoadingLabel.text = "Failed to load note."
			)
	)


func _cache_note(note: Dictionary, server_hash: String) -> void:
	LocalStorage.save_note(note)
	var index := LocalStorage.load_index()
	var nid: int = note.get("_id", _note_id)
	index[str(nid)] = {
		"v_hash": server_hash,
		"title": note.get("title", ""),
		"preview": note.get("text", "").left(100)
	}
	LocalStorage.save_index(index)


# ── Display ───────────────────────────────────────────────────────────────────

func _display(note: Dictionary, source: String) -> void:
	LocalStorage.add_to_recent(note.get("_id", _note_id))
	%LoadingLabel.hide()
	%TitleLabel.text = note.get("title", "Untitled")
	_raw_text = note.get("text", "")
	_render_note()
	%StatusLabel.text = source


func _render_note() -> void:
	if _formatted:
		%NoteText.text = MarkdownBBCode.convert(_raw_text)
	else:
		%NoteText.text = _raw_text


func _on_format_btn_pressed() -> void:
	_formatted = not _formatted
	_update_format_btn()
	_render_note()


func _update_format_btn() -> void:
	%FormatBtn.text = "Raw" if _formatted else "Formatted"
