extends Node

## HTTP client singleton. Configured from AccountManager's account_unlocked signal.
## All API callbacks have signature: func(success: bool, data: Variant)
## On success: data is the parsed JSON (Dictionary or Array).
## On failure: data is an error String.

signal auth_failed
signal authenticated  ## Emitted once a valid access token is obtained.

var _server_url: String = ""
var _access_token: String = ""


func _ready() -> void:
	AccountManager.account_unlocked.connect(_on_account_unlocked)


func _on_account_unlocked(account_meta: Dictionary) -> void:
	_server_url = account_meta.get("server_url", "")
	_access_token = ""

	var refresh_token := AccountManager.get_refresh_token()
	if not refresh_token.is_empty():
		AppLogger.log("[ApiClient] Stored refresh token found — attempting token refresh.")
		_do_refresh(refresh_token, func(ok: bool, _d) -> void:
			if not ok:
				AppLogger.log("[ApiClient] Refresh token rejected — clearing and falling back to password login.")
				AccountManager.clear_refresh_token()
				_try_auto_login()
		)
	else:
		AppLogger.log("[ApiClient] No refresh token — attempting password login.")
		_try_auto_login()


## Attempt login using the server password stored (encrypted) in AccountManager.
## Called automatically on unlock — no user interaction needed.
func _try_auto_login() -> void:
	var username : String = AccountManager.get_current_account().get("username", "")
	var password := AccountManager.get_server_password()
	if username.is_empty() or password.is_empty():
		AppLogger.log("[ApiClient] Password login aborted — username or password not stored (empty).")
		auth_failed.emit()
		return
	AppLogger.log("[ApiClient] Attempting password login for user '%s'." % username)
	login(username, password, func(ok: bool, data) -> void:
		if not ok:
			AppLogger.log("[ApiClient] Password login failed: %s" % str(data))
			auth_failed.emit()
		else:
			AppLogger.log("[ApiClient] Password login succeeded.")
	)


func is_authenticated() -> bool:
	return not _access_token.is_empty()


## Re-attempt login with stored credentials. Safe to call when already authenticated.
func retry_auth() -> void:
	if is_authenticated():
		return
	_try_auto_login()


func _set_access_token(token: String) -> void:
	_access_token = token
	if not token.is_empty():
		authenticated.emit()


# ── Auth ──────────────────────────────────────────────────────────────────────

func login(username: String, password: String, callback: Callable) -> void:
	var url := _server_url + "/api/v1/login"
	var body := "username=%s&password=%s" % [username.uri_encode(), password.uri_encode()]
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	_make_request(HTTPClient.METHOD_POST, url, headers, body, func(ok: bool, data) -> void:
		if ok and data is Dictionary:
			_set_access_token(data.get("access", ""))
			var refresh: String = data.get("refresh", "")
			if not refresh.is_empty():
				AccountManager.save_refresh_token(refresh)
		callback.call(ok, data)
	)


func _do_refresh(refresh_token: String, callback: Callable) -> void:
	var url := _server_url + "/api/v1/refresh"
	var headers := PackedStringArray([
		"Authorization: Bearer " + refresh_token,
		"Content-Type: application/json"
	])
	_make_request(HTTPClient.METHOD_POST, url, headers, "", func(ok: bool, data) -> void:
		if ok and data is Dictionary:
			_set_access_token(data.get("access", ""))
			AppLogger.log("[ApiClient] Token refresh completed — new access token obtained.")
		else:
			AppLogger.log("[ApiClient] Token refresh request failed: %s" % str(data))
		callback.call(ok, data)
	, true)


## Check whether the server is reachable (no auth required).
## Callback: func(reachable: bool, error_message: String)
## error_message is "" on success, human-readable reason on failure.
func check_reachable(callback: Callable) -> void:
	if _server_url.is_empty():
		callback.call(false, "No server URL configured. Go to Settings → User credentials.")
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(result: int, _code, _h, _b) -> void:
		http.queue_free()
		# Any HTTP response at all means the server is up.
		if result == HTTPRequest.RESULT_SUCCESS:
			callback.call(true, "")
		else:
			var reason := _http_result_string(result)
			callback.call(false, "Could not reach %s\n\n%s" % [_server_url, reason])
	)
	# GET /api/v1/login returns 405 but proves the server is alive.
	var err := http.request(_server_url + "/api/v1/login",
			PackedStringArray([]), HTTPClient.METHOD_GET, "")
	if err != OK:
		http.queue_free()
		var hint := ""
		if err == ERR_INVALID_PARAMETER:
			hint = "\n\nThe URL \"%s\" looks malformed. Make sure it starts with http:// or https://." % _server_url
		callback.call(false, "Could not send request to server.%s" % hint)


func _http_result_string(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Connection refused. Check that the server is running and the URL is correct."
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Could not resolve hostname. Check the server URL."
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connection error. Check your network."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS/SSL handshake failed. Check the server certificate."
		HTTPRequest.RESULT_NO_RESPONSE:
			return "No response from server (timeout)."
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Request failed."
		_:
			return "Network error (code %d)." % result


# ── Notes API ─────────────────────────────────────────────────────────────────

func get_notes_index(callback: Callable) -> void:
	_auth_get("/api/v1/notes/index", callback)

func get_notes_pinned(callback: Callable) -> void:
	_auth_get("/api/v1/notes/pinned", callback)

func get_notes_hashes(callback: Callable) -> void:
	_auth_get("/api/v1/notes/hashes", callback)

func get_all_notes(callback: Callable) -> void:
	_auth_get("/api/v1/notes", callback)

func get_note(note_id: int, callback: Callable) -> void:
	_auth_get("/api/v1/note/%d" % note_id, func(ok: bool, data) -> void:
		# Normalize server's 'id' field to '_id' to match list response format.
		if ok and data is Dictionary and data.has("id") and not data.has("_id"):
			data["_id"] = data["id"]
		callback.call(ok, data)
	)

func get_note_hash(note_id: int, callback: Callable) -> void:
	_auth_get("/api/v1/note/%d/hash" % note_id, callback)

func search_notes(key: String, callback: Callable) -> void:
	var url := _server_url + "/api/v1/search"
	var body := JSON.stringify({"key": key})
	var headers := PackedStringArray([
		"Authorization: Bearer " + _access_token,
		"Content-Type: application/json"
	])
	_make_request(HTTPClient.METHOD_POST, url, headers, body, callback)


func get_clipboard(callback: Callable) -> void:
	_auth_get("/api/v1/clipboard", callback)


func set_clipboard(text: String, callback: Callable) -> void:
	var url := _server_url + "/api/v1/clipboard"
	var body := JSON.stringify({"key": text})
	var headers := PackedStringArray([
		"Authorization: Bearer " + _access_token,
		"Content-Type: application/json"
	])
	_make_request(HTTPClient.METHOD_POST, url, headers, body, callback)


# ── Private ───────────────────────────────────────────────────────────────────

func _auth_get(path: String, callback: Callable) -> void:
	var url := _server_url + path
	var headers := PackedStringArray(["Authorization: Bearer " + _access_token])
	_make_request(HTTPClient.METHOD_GET, url, headers, "", callback)


func _make_request(method: int, url: String, headers: PackedStringArray,
		body: String, callback: Callable, is_retry: bool = false) -> void:
	if _server_url.is_empty() and not url.begins_with("http"):
		callback.call(false, "No server configured.")
		return

	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(func(
			result: int, response_code: int, _resp_headers, resp_body: PackedByteArray) -> void:
		http.queue_free()

		if result != HTTPRequest.RESULT_SUCCESS:
			callback.call(false, "Network error (%d)." % result)
			return

		# Flask-JWT-Extended returns 422 for a missing/malformed token,
		# and 401 for an expired one. Treat both as auth failures.
		if (response_code == 401 or response_code == 422) and not is_retry:
			AppLogger.log("[ApiClient] HTTP %d on %s — access token rejected." % [response_code, url])
			var refresh_token := AccountManager.get_refresh_token()
			if not refresh_token.is_empty():
				AppLogger.log("[ApiClient] Attempting token refresh after %d." % response_code)
				_do_refresh(refresh_token, func(ok: bool, _d) -> void:
					if not ok:
						AppLogger.log("[ApiClient] Token refresh failed — clearing and falling back to password login.")
						AccountManager.clear_refresh_token()
						_try_auto_login()
						auth_failed.emit()
						callback.call(false, "Session expired.")
						return
					AppLogger.log("[ApiClient] Token refresh succeeded — retrying original request.")
					var new_headers := PackedStringArray()
					for h in headers:
						if (h as String).begins_with("Authorization:"):
							new_headers.append("Authorization: Bearer " + _access_token)
						else:
							new_headers.append(h)
					_make_request(method, url, new_headers, body, callback, true)
				)
			else:
				AppLogger.log("[ApiClient] No refresh token available — triggering password login.")
				_try_auto_login()
				auth_failed.emit()
				callback.call(false, "Not authenticated.")
			return

		if response_code < 200 or response_code >= 300:
			callback.call(false, "HTTP %d" % response_code)
			return

		var json := JSON.new()
		if json.parse(resp_body.get_string_from_utf8()) != OK:
			callback.call(false, "Invalid JSON response.")
			return

		callback.call(true, json.get_data())
	)

	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		callback.call(false, "Request setup failed: %s" % error_string(err))
