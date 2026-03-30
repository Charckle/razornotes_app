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

	%RetryBtn.pressed.connect(func() -> void:
		%RetryBtn.hide()
		%ErrorLabel.hide()
		_load_notes()
	)
	%RetryBtn.hide()

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
			# Local index already contains every note we have cached.
			_load_from_local_cache()


func _load_notes() -> void:
	_showing_recent = false
	%LoadingLabel.text = "Loading…"
	%LoadingLabel.show()
	%ErrorLabel.hide()
	%RetryBtn.hide()
	_clear_notes()

	# full_mirror always serves from local cache — no auth needed.
	if _sync_mode == "full_mirror":
		_load_from_local_cache()
		return

	# For server modes, wait until we have a valid token.
	if not ApiClient.is_authenticated():
		%LoadingLabel.text = "Connecting to server…"
		ApiClient.authenticated.connect(_load_notes, CONNECT_ONE_SHOT)
		ApiClient.auth_failed.connect(_on_auth_failed_while_loading, CONNECT_ONE_SHOT)
		return

	match _sync_mode:
		"remote_only":
			_fetch_from_server(false)
		"local_some":
			_fetch_from_server(true)  # fall back to local on failure


func _fetch_from_server(allow_local_fallback: bool) -> void:
	var state := {
		"count": 2,
		"pinned": [],
		"index": [],
		"failed": 0
	}

	var _handle := func() -> void:
		state["count"] -= 1
		if state["count"] > 0:
			return
		if state["failed"] == 0:
			_display_notes(state["pinned"], state["index"])
		elif allow_local_fallback:
			_load_from_local_cache()
		else:
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

	var notes: Array = []
	for note_id_str in index:
		var entry: Dictionary = index[note_id_str]
		notes.append({
			"_id": int(note_id_str),
			"title": entry.get("title", ""),
			"text": entry.get("preview", "")
		})
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
	%LoadingLabel.hide()
	%ErrorLabel.text = "Could not connect to server."
	%ErrorLabel.show()
	%RetryBtn.show()


# ── Full mirror sync ──────────────────────────────────────────────────────────

func _start_full_mirror_sync() -> void:
	%SyncNowBtn.disabled = true
	%SyncNowBtn.text = "Syncing…"
	%SyncStatusLabel.text = "Syncing…"

	ApiClient.get_notes_hashes(func(ok: bool, data) -> void:
		if not ok or not data is Array:
			_finish_sync(false)
			return
		_process_hash_diff(data)
	)


func _process_hash_diff(server_hashes: Array) -> void:
	var local_index := LocalStorage.load_index()
	var to_fetch: Array = []

	for entry in server_hashes:
		var nid: int = entry.get("id", 0)
		var srv_hash: String = entry.get("v_hash", "")
		var local_hash: String = local_index.get(str(nid), {}).get("v_hash", "")
		if local_hash != srv_hash:
			to_fetch.append({"id": nid, "v_hash": srv_hash})

	if to_fetch.is_empty():
		LocalStorage.save_index(local_index)
		AccountManager.update_last_synced()
		_finish_sync(true)
		return

	var state := {"remaining": to_fetch.size(), "index": local_index}

	for item in to_fetch:
		var nid: int = item["id"]
		var srv_hash: String = item["v_hash"]
		ApiClient.get_note(nid, func(ok2: bool, note_data) -> void:
			if ok2 and note_data is Dictionary:
				LocalStorage.save_note(note_data)
				var nid2: int = note_data.get("_id", nid)
				state["index"][str(nid2)] = {
					"v_hash": srv_hash,
					"title": note_data.get("title", ""),
					"preview": note_data.get("text", "").left(100)
				}
			state["remaining"] -= 1
			if state["remaining"] == 0:
				LocalStorage.save_index(state["index"])
				AccountManager.update_last_synced()
				_finish_sync(true)
		)


func _finish_sync(success: bool) -> void:
	%SyncNowBtn.disabled = false
	%SyncNowBtn.text = "Sync Now"
	if success:
		%SyncStatusLabel.text = "Last synced: " + LocalStorage.get_last_synced_string()
		_load_from_local_cache()
	else:
		%SyncStatusLabel.text = "Sync failed."
