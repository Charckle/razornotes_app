extends Node

## Full-mirror sync shared between note_list and settings.
## Callback signature: func(success: bool)

var _syncing: bool = false
var _pending: Array[Callable] = []


func start_sync(on_done: Callable) -> void:
	_pending.append(on_done)
	if _syncing:
		return
	_syncing = true
	ApiClient.get_notes_hashes(func(ok: bool, data) -> void:
		if not ok or not data is Array:
			_finish_all(false)
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
		_finish_all(true)
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
				_finish_all(true)
		)


func _finish_all(success: bool) -> void:
	_syncing = false
	var cbs := _pending.duplicate()
	_pending.clear()
	for cb in cbs:
		cb.call(success)
