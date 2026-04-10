extends Node

## Full-mirror sync shared between note_list and settings.
## Callback signature: func(success: bool, error_message: String)
## error_message is "" on success, human-readable reason on failure.

signal sync_completed(success: bool)

const AUTO_SYNC_INTERVAL  := 180  ## seconds between automatic syncs
const FAILURE_BACKOFF     := 30   ## retry delay after a failed sync
const DOWNLOAD_CONCURRENCY := 8   ## max parallel note downloads

var _syncing: bool = false
var _pending: Array[Callable] = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_maybe_auto_sync()


func _maybe_auto_sync() -> void:
	var account := AccountManager.get_current_account()
	if account.get("sync_mode", "") != "full_mirror":
		return
	var elapsed = int(Time.get_unix_time_from_system()) - account.get("last_synced", 0)
	if elapsed >= AUTO_SYNC_INTERVAL:
		if not ApiClient.is_authenticated():
			ApiClient.authenticated.connect(_maybe_auto_sync, CONNECT_ONE_SHOT)
			return
		start_sync(func(success: bool, _err: String) -> void: sync_completed.emit(success))


func start_sync(on_done: Callable) -> void:
	_pending.append(on_done)
	if _syncing:
		return
	_syncing = true
	ApiClient.get_notes_hashes(func(ok: bool, data) -> void:
		if not ok or not data is Array:
			var msg := str(data) if data is String else "Could not fetch note list from server."
			_finish_all(false, msg)
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
		print("[sync] Done: already up to date.")
		_finish_all(true, "Already up to date.")
		return

	var state := {
		"remaining": to_fetch.size(),
		"index": local_index,
		"failed": 0,
		"downloaded": 0,
		"queue": to_fetch.duplicate()
	}

	for i in min(DOWNLOAD_CONCURRENCY, to_fetch.size()):
		_fetch_one(state)


func _fetch_one(state: Dictionary) -> void:
	if state["queue"].is_empty():
		return
	var item: Dictionary = state["queue"].pop_front()
	var nid: int = item["id"]
	var srv_hash: String = item["v_hash"]
	ApiClient.get_note(nid, func(ok2: bool, note_data) -> void:
		if ok2 and note_data is Dictionary:
			LocalStorage.save_note(note_data)
			var nid2: int = note_data.get("_id", nid)
			state["index"][str(nid2)] = {
				"v_hash": srv_hash,
				"title": note_data.get("title", ""),
				"preview": note_data.get("text", "").left(100),
				"pinned": note_data.get("pinned", false),
				"relevant": note_data.get("relevant", true),
				"date_mod": note_data.get("date_mod", "")
			}
			state["downloaded"] = state["downloaded"] + 1
		else:
			state["failed"] = state["failed"] + 1
		state["remaining"] -= 1
		if state["remaining"] == 0:
			LocalStorage.save_index(state["index"])
			AccountManager.update_last_synced()
			var downloaded: int = state["downloaded"]
			var failed_count: int = state["failed"]
			print("[sync] Done: %d downloaded, %d failed." % [downloaded, failed_count])
			if failed_count == 0:
				_finish_all(true, "%d note(s) downloaded." % downloaded)
			else:
				_finish_all(false, "%d note(s) could not be downloaded." % failed_count)
		else:
			_fetch_one(state)
	)


func _finish_all(success: bool, error_message: String) -> void:
	_syncing = false
	if not success:
		# Set last_synced to (now - interval + backoff) so the next focus-in
		# retries after FAILURE_BACKOFF seconds rather than immediately.
		var backoff_ts := int(Time.get_unix_time_from_system()) - AUTO_SYNC_INTERVAL + FAILURE_BACKOFF
		AccountManager.set_last_synced(backoff_ts)
	var cbs := _pending.duplicate()
	_pending.clear()
	for cb in cbs:
		cb.call(success, error_message)
