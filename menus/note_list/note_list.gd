extends Control

signal note_requested(note_id: int)

const NoteCard := preload("res://components/note_card/note_card.tscn")

var _sync_mode: String = ""
var _showing_recent: bool = false


func _ready() -> void:
	var account := AccountManager.get_current_account()
	_sync_mode = account.get("sync_mode", "remote_only")

	%SyncBar.visible = _sync_mode == "full_mirror"
	if _sync_mode == "full_mirror":
		%SyncStatusLabel.text = "Last synced: " + LocalStorage.get_last_synced_string()
		%SyncNowBtn.pressed.connect(_start_full_mirror_sync)
		SyncManager.sync_completed.connect(_on_background_sync_done)

	%RetryBtn.pressed.connect(func() -> void:
		%RetryBtn.hide()
		%ErrorLabel.hide()
		_load_notes()
	)
	%RetryBtn.hide()
	%RetryTimer.timeout.connect(_on_retry_timer_timeout)

	_load_notes()


func show_recent() -> void:
	_showing_recent = true
	_clear_notes()
	%LoadingLabel.text = "Recent"
	%LoadingLabel.show()
	%ErrorLabel.hide()

	var recent_ids := LocalStorage.get_recent_note_ids()
	var index := LocalStorage.load_index()
	var notes: Array = []
	for nid in recent_ids:
		var entry = index.get(str(nid), {})
		notes.append({
			"_id": nid,
			"title": entry.get("title", "Note %d" % nid),
			"text": entry.get("preview", "")
		})
	_display_notes([], notes)


func show_all() -> void:
	%RetryTimer.stop()
	_showing_recent = false
	_clear_notes()
	%LoadingLabel.text = "Loading all notes…"
	%LoadingLabel.show()
	%ErrorLabel.hide()
	%RetryBtn.hide()

	match _sync_mode:
		"remote_only":
			if not ApiClient.is_authenticated():
				%LoadingLabel.text = "Connecting to server…"
				ApiClient.authenticated.connect(show_all, CONNECT_ONE_SHOT)
				ApiClient.auth_failed.connect(_on_auth_failed_while_loading, CONNECT_ONE_SHOT)
				ApiClient.retry_auth()
				%RetryTimer.start()
				return
			ApiClient.get_all_notes(func(ok: bool, data) -> void:
				if ok and data is Array:
					_display_notes([], data)
				else:
					%LoadingLabel.hide()
					%ErrorLabel.text = "Failed to load all notes."
					%ErrorLabel.show()
					%RetryBtn.show()
			)
		"local_some", "full_mirror":
			_load_all_from_local_cache()


func _load_notes() -> void:
	%RetryTimer.stop()
	_showing_recent = false
	%LoadingLabel.text = "Loading…"
	%LoadingLabel.show()
	%ErrorLabel.hide()
	%RetryBtn.hide()
	_clear_notes()

	# For server modes, wait until we have a valid token.
	if not ApiClient.is_authenticated():
		%LoadingLabel.text = "Connecting to server…"
		ApiClient.authenticated.connect(_load_notes, CONNECT_ONE_SHOT)
		ApiClient.auth_failed.connect(_on_auth_failed_while_loading, CONNECT_ONE_SHOT)
		ApiClient.retry_auth()
		%RetryTimer.start()
		return

	match _sync_mode:
		"remote_only":
			_fetch_from_server(false)
		"local_some", "full_mirror":
			_fetch_from_server(true)  # fall back to local on failure


func _fetch_from_server(allow_local_fallback: bool) -> void:
	AppLogger.log("[NoteList] Fetching note list from server…")
	var state := {
		"count": 2,
		"pinned": [],
		"index": [],
		"failed": 0
	}

	var _handle := func() -> void:
		if not is_instance_valid(self):
			return
		state["count"] -= 1
		if state["count"] > 0:
			return
		if state["failed"] == 0:
			AppLogger.log("[NoteList] Server responded — displaying live data.")
			_display_notes(state["pinned"], state["index"])
		elif allow_local_fallback:
			AppLogger.log("[NoteList] Server unreachable — falling back to local cache.")
			_load_from_local_cache()
		else:
			AppLogger.log("[NoteList] Server unreachable — no local fallback available.")
			%LoadingLabel.hide()
			%ErrorLabel.text = "Could not reach server."
			%ErrorLabel.show()

	ApiClient.get_notes_pinned(func(ok: bool, data) -> void:
		if ok and data is Array:
			state["pinned"] = data
		else:
			state["failed"] += 1
		_handle.call()
	)
	ApiClient.get_notes_index(func(ok: bool, data) -> void:
		if ok and data is Array:
			state["index"] = data
		else:
			state["failed"] += 1
		_handle.call()
	)


func _load_from_local_cache() -> void:
	var index := LocalStorage.load_index()
	if index.is_empty():
		%LoadingLabel.text = "No local notes. Use Sync to download."
		return

	var pinned: Array = []
	var relevant: Array = []
	for note_id_str in index:
		var entry: Dictionary = index[note_id_str]
		var card := {
			"_id": int(note_id_str),
			"title": entry.get("title", ""),
			"text": entry.get("preview", ""),
			"date_mod": entry.get("date_mod", "")
		}
		if entry.get("pinned", false):
			pinned.append(card)
		elif entry.get("relevant", true):
			relevant.append(card)

	relevant.sort_custom(func(a, b): return a["date_mod"] > b["date_mod"])
	if relevant.size() > 15:
		relevant.resize(15)

	_display_notes(pinned, relevant)


func _load_all_from_local_cache() -> void:
	var index := LocalStorage.load_index()
	if index.is_empty():
		%LoadingLabel.text = "No local notes. Use Sync to download."
		return

	var notes: Array = []
	for note_id_str in index:
		var entry: Dictionary = index[note_id_str]
		notes.append({
			"_id": int(note_id_str),
			"title": entry.get("title", ""),
			"text": entry.get("preview", ""),
			"date_mod": entry.get("date_mod", "")
		})
	notes.sort_custom(func(a, b): return a["date_mod"] > b["date_mod"])
	_display_notes([], notes)


func _display_notes(pinned: Array, index_notes: Array) -> void:
	%LoadingLabel.hide()
	_clear_notes()

	if pinned.size() > 0:
		_add_section_header("Pinned")
		for note in pinned:
			_add_card(note)
		%NotesContainer.add_child(HSeparator.new())

	if index_notes.size() > 0:
		if pinned.size() > 0:
			_add_section_header("Recent")
		for note in index_notes:
			_add_card(note)
	elif pinned.is_empty():
		var lbl := Label.new()
		lbl.text = "No notes here."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%NotesContainer.add_child(lbl)


func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.modulate = Color(0.7, 0.7, 0.7, 1)
	%NotesContainer.add_child(lbl)


func _add_card(note: Dictionary) -> void:
	var card := NoteCard.instantiate()
	%NotesContainer.add_child(card)
	var note_id: int = note.get("_id", 0)
	card.setup(note_id, note.get("title", "Untitled"), note.get("text", ""))
	card.set_cached(LocalStorage.has_note(note_id))
	card.note_pressed.connect(func(nid: int) -> void: note_requested.emit(nid))


func _clear_notes() -> void:
	for child in %NotesContainer.get_children():
		child.queue_free()


func _on_auth_failed_while_loading() -> void:
	%RetryTimer.stop()
	if _sync_mode == "full_mirror":
		AppLogger.log("[NoteList] Auth failed — falling back to local cache.")
		_load_from_local_cache()
		return
	%LoadingLabel.hide()
	%ErrorLabel.text = "Could not connect to server."
	%ErrorLabel.show()
	%RetryBtn.show()


func _on_retry_timer_timeout() -> void:
	ApiClient.retry_auth()


# ── Full mirror sync ──────────────────────────────────────────────────────────

func _start_full_mirror_sync() -> void:
	%SyncNowBtn.disabled = true
	%SyncNowBtn.text = "Syncing…"
	%SyncStatusLabel.text = "Syncing…"
	SyncManager.start_sync(func(success: bool, msg: String) -> void:
		%SyncNowBtn.disabled = false
		%SyncNowBtn.text = "Sync Now"
		if success:
			%SyncStatusLabel.text = "Last synced: " + LocalStorage.get_last_synced_string()
			%SyncErrorDialog.popup_error("Sync complete", msg)
			_load_from_local_cache()
		else:
			%SyncStatusLabel.text = "Sync failed."
			%SyncErrorDialog.popup_error("Sync failed", msg)
	)


func _on_background_sync_done(success: bool) -> void:
	if success:
		%SyncStatusLabel.text = "Last synced: " + LocalStorage.get_last_synced_string()
		_load_from_local_cache()
