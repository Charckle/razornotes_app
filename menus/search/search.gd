extends Control

signal note_requested(note_id: int)

const NoteCard := preload("res://components/note_card/note_card.tscn")

var _sync_mode: String = ""


func _ready() -> void:
	_sync_mode = AccountManager.get_current_account().get("sync_mode", "remote_only")
	%SearchBtn.pressed.connect(_do_search)
	%SearchInput.text_submitted.connect(func(_t: String) -> void: _do_search())


func _do_search() -> void:
	var key : String = %SearchInput.text.strip_edges()
	if key.is_empty():
		return

	_clear_results()
	_set_status("Searching…", false)
	%SearchBtn.disabled = true

	# Always try server first. Fall back to local if unreachable.
	if not ApiClient.is_authenticated():
		_local_search(key, true)
		return

	ApiClient.search_notes(key, func(ok: bool, data) -> void:
		%SearchBtn.disabled = false
		print("[search] query=\"%s\" ok=%s" % [key, ok])
		if ok and (data is Dictionary or data is Array):
			print("[search] response JSON: ", JSON.stringify(data))
		else:
			print("[search] data (raw): ", data)
		if not ok:
			_local_search(key, true)
			return
		var results: Array = _normalize_server_search_results(data)
		print("[search] items shown after parse: %d" % results.size())
		_set_status("", false)
		_show_results(results)
	)


## Turns server JSON into [{_id, title, text}, ...] for _show_results.
func _normalize_server_search_results(data: Variant) -> Array:
	if data is Array:
		return data
	if not data is Dictionary:
		return []
	var d: Dictionary = data
	for wrap in ["notes", "results", "data", "items"]:
		if d.has(wrap) and d[wrap] is Array:
			return d[wrap]
	return _parse_search_id_match_map(d)


## Backend format: { "note_id_str": [match_term, html_snippet], ... } (WSearch / N_obj.search).
func _parse_search_id_match_map(data: Dictionary) -> Array:
	var out: Array = []
	for k in data:
		var v = data[k]
		if not v is Array or v.is_empty():
			continue
		var sid := str(k)
		if not sid.is_valid_int():
			continue
		var title := str(v[0]) if v.size() > 0 else ""
		var snippet := str(v[1]) if v.size() > 1 else ""
		out.append({
			"_id": int(sid),
			"title": title if not title.is_empty() else ("Note %s" % sid),
			"text": _strip_html(snippet)
		})
	# Stable order by id
	out.sort_custom(func(a, b): return a["_id"] < b["_id"])
	return out


func _strip_html(s: String) -> String:
	var rx := RegEx.new()
	if rx.compile("<[^>]*>") != OK:
		return s
	return rx.sub(s, "", true)


# ── Local string search ───────────────────────────────────────────────────────

func _local_search(key: String, is_offline: bool) -> void:
	%SearchBtn.disabled = false
	var index := LocalStorage.load_index()

	if index.is_empty():
		if is_offline:
			_set_status("Offline — no local cache to search.", true)
		else:
			_set_status("No results.", false)
		return

	var key_lower := key.to_lower()
	var results: Array = []

	for note_id_str in index:
		var entry: Dictionary = index[note_id_str]
		var title: String = entry.get("title", "").to_lower()
		var preview: String = entry.get("preview", "").to_lower()
		if key_lower in title or key_lower in preview:
			results.append({
				"_id": int(note_id_str),
				"title": entry.get("title", ""),
				"text": entry.get("preview", "")
			})

	if is_offline:
		_set_status("Offline — showing local results", true)
	else:
		_set_status("", false)

	_show_results(results)


# ── Display ───────────────────────────────────────────────────────────────────

func _show_results(results: Array) -> void:
	if results.is_empty():
		if %StatusLabel.text.is_empty():
			_set_status("No results.", false)
		return

	for item in results:
		if not item is Dictionary:
			continue
		var note_id: int = item.get("_id", item.get("id", 0))
		var card := NoteCard.instantiate()
		%ResultsContainer.add_child(card)
		card.setup(note_id, item.get("title", "Untitled"), item.get("text", ""))
		card.set_cached(LocalStorage.has_note(note_id))
		card.note_pressed.connect(func(nid: int) -> void: note_requested.emit(nid))


func _set_status(text: String, is_offline: bool) -> void:
	%StatusLabel.text = text
	%StatusLabel.visible = not text.is_empty()
	if is_offline:
		%OfflineLabel.show()
	else:
		%OfflineLabel.hide()


func _clear_results() -> void:
	for child in %ResultsContainer.get_children():
		child.queue_free()
