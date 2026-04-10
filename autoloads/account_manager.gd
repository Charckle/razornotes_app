extends Node

## Manages account storage, encryption, and the current session.
##
## File layout:
##   user://accounts_meta.json       — plaintext list of {id, label, server_url, username, sync_mode, last_synced}
##   user://accounts/<id>.enc        — salt(16) + iv(16) + AES-256-CBC({ magic, server_pass, refresh_token })

signal account_unlocked(account_meta: Dictionary)
signal accounts_changed

const PBKDF2_ITERATIONS := 100_000
const KEY_SIZE := 32

var _accounts_meta: Array = []
var _current_meta: Dictionary = {}
var _derived_key: PackedByteArray = PackedByteArray()


func _ready() -> void:
	_ensure_accounts_dir()
	_load_accounts_meta()


# ── Public: queries ──────────────────────────────────────────────────────────

func has_accounts() -> bool:
	return not _accounts_meta.is_empty()

func get_accounts_meta() -> Array:
	return _accounts_meta

func is_unlocked() -> bool:
	return not _current_meta.is_empty()

func get_current_account() -> Dictionary:
	return _current_meta


# ── Public: account lifecycle ─────────────────────────────────────────────────

## Validates input, derives key, writes encrypted account file.
## Returns "" on success, an error string on failure.
## Does NOT emit signals — call notify_unlocked() or accounts_changed.emit() from the main thread.
func add_account(p_label: String, server_url: String, username: String,
		server_password: String, local_password: String, sync_mode: String) -> String:
	if p_label.strip_edges().is_empty():
		return "Account name cannot be empty."
	if server_url.strip_edges().is_empty():
		return "Server URL cannot be empty."
	if username.strip_edges().is_empty():
		return "Username cannot be empty."
	if local_password.length() < 4:
		return "Local password must be at least 4 characters."

	var account_id := _generate_id()
	var salt := Crypto.new().generate_random_bytes(16)
	var key := _pbkdf2(local_password.to_utf8_buffer(), salt, PBKDF2_ITERATIONS, KEY_SIZE)

	var secrets := {
		"magic": "razor_v1",
		"server_pass": server_password,
		"refresh_token": ""
	}
	var encrypted := _encrypt_account(JSON.stringify(secrets).to_utf8_buffer(), key, salt)
	if encrypted.is_empty():
		return "Encryption failed."

	var path := "user://accounts/%s.enc" % account_id
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "Could not write account file."
	f.store_buffer(encrypted)
	f.close()

	var meta := {
		"id": account_id,
		"label": p_label,
		"server_url": server_url.rstrip("/"),
		"username": username,
		"sync_mode": sync_mode,
		"last_synced": 0
	}
	_accounts_meta.append(meta)
	_save_accounts_meta()
	return ""


## Updates the unlocked account (metadata + optional server/local password changes).
## new_server_password: empty string keeps the current server password.
## new_local_password: empty keeps the current device key; if set, current_local_password must verify.
## Returns "" on success. Safe to call from a background thread.
func update_current_account(p_label: String, server_url: String, username: String, sync_mode: String,
		new_server_password: String, new_local_password: String, current_local_password: String) -> String:
	if _current_meta.is_empty() or _derived_key.is_empty():
		return "Session invalid."

	if p_label.strip_edges().is_empty():
		return "Account name cannot be empty."
	var url_clean := server_url.strip_edges()
	if url_clean.is_empty():
		return "Server URL cannot be empty."
	var user_clean := username.strip_edges()
	if user_clean.is_empty():
		return "Username cannot be empty."

	const VALID_MODES := ["remote_only", "local_some", "full_mirror"]
	if not sync_mode in VALID_MODES:
		return "Invalid sync mode."

	url_clean = url_clean.rstrip("/")

	var creds_changed := (
		url_clean != String(_current_meta.get("server_url", ""))
		or user_clean != String(_current_meta.get("username", ""))
		or not new_server_password.is_empty()
	)

	var srv_pass := String(_current_meta.get("_server_pass", ""))
	if not new_server_password.is_empty():
		srv_pass = new_server_password

	var refresh_keep := "" if creds_changed else String(_current_meta.get("_refresh_token", ""))

	if not new_local_password.is_empty():
		if new_local_password.length() < 4:
			return "New local password must be at least 4 characters."
		if not _verify_local_password(current_local_password):
			return "Current local password is incorrect."

		var account_id: String = _current_meta["id"]
		var enc_path := "user://accounts/%s.enc" % account_id
		var new_salt := Crypto.new().generate_random_bytes(16)
		var new_key := _pbkdf2(new_local_password.to_utf8_buffer(), new_salt, PBKDF2_ITERATIONS, KEY_SIZE)
		var secrets := {
			"magic": "razor_v1",
			"server_pass": srv_pass,
			"refresh_token": refresh_keep
		}
		var encrypted := _encrypt_account(JSON.stringify(secrets).to_utf8_buffer(), new_key, new_salt)
		if encrypted.is_empty():
			return "Encryption failed."
		var fw := FileAccess.open(enc_path, FileAccess.WRITE)
		if fw == null:
			return "Could not write account file."
		fw.store_buffer(encrypted)
		fw.close()
		_derived_key = new_key
		_current_meta["_server_pass"] = srv_pass
		_current_meta["_refresh_token"] = refresh_keep
	else:
		_current_meta["_server_pass"] = srv_pass
		_current_meta["_refresh_token"] = refresh_keep
		_rewrite_secrets_file()

	_current_meta["label"] = p_label.strip_edges()
	_current_meta["server_url"] = url_clean
	_current_meta["username"] = user_clean
	_current_meta["sync_mode"] = sync_mode

	for meta in _accounts_meta:
		if meta["id"] == _current_meta["id"]:
			meta["label"] = _current_meta["label"]
			meta["server_url"] = _current_meta["server_url"]
			meta["username"] = _current_meta["username"]
			meta["sync_mode"] = _current_meta["sync_mode"]
			meta["last_synced"] = _current_meta.get("last_synced", meta.get("last_synced", 0))
			break

	_save_accounts_meta()
	return ""


func _verify_local_password(password: String) -> bool:
	var account_id: String = _current_meta.get("id", "")
	if account_id.is_empty():
		return false
	var path := "user://accounts/%s.enc" % account_id
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var raw := f.get_buffer(f.get_length())
	f.close()
	if raw.size() < 33:
		return false
	var salt := raw.slice(0, 16)
	var key := _pbkdf2(password.to_utf8_buffer(), salt, PBKDF2_ITERATIONS, KEY_SIZE)
	if key.size() != _derived_key.size():
		return false
	for i in range(key.size()):
		if key[i] != _derived_key[i]:
			return false
	return true


## Derives the key from local_password, decrypts the account file, sets session state.
## Returns true on success, false on wrong password or missing file.
## Safe to call from a background thread — does NOT emit signals.
func unlock_account(account_id: String, local_password: String) -> bool:
	var path := "user://accounts/%s.enc" % account_id
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var raw := f.get_buffer(f.get_length())
	f.close()

	if raw.size() < 33:
		return false

	var salt := raw.slice(0, 16)
	var key := _pbkdf2(local_password.to_utf8_buffer(), salt, PBKDF2_ITERATIONS, KEY_SIZE)
	var decrypted := _decrypt_account(raw, key)
	if decrypted.is_empty():
		return false

	var json := JSON.new()
	if json.parse(decrypted.get_string_from_utf8()) != OK:
		return false
	var secrets: Dictionary = json.get_data()
	if secrets.get("magic") != "razor_v1":
		return false

	_derived_key = key
	for meta in _accounts_meta:
		if meta["id"] == account_id:
			_current_meta = meta.duplicate()
			break

	_current_meta["_server_pass"] = secrets.get("server_pass", "")
	_current_meta["_refresh_token"] = secrets.get("refresh_token", "")
	return true


## Emit account_unlocked from the main thread after unlock_account() succeeds.
func notify_unlocked() -> void:
	_save_last_account_id(_current_meta.get("id", ""))
	account_unlocked.emit(_current_meta)


## Returns the ID of the last successfully unlocked account, or "" if none.
func get_last_account_id() -> String:
	var f := FileAccess.open("user://last_account.txt", FileAccess.READ)
	if f == null:
		return ""
	var id := f.get_as_text().strip_edges()
	f.close()
	# Verify the account still exists in our meta list.
	for meta in _accounts_meta:
		if meta["id"] == id:
			return id
	return ""


func _save_last_account_id(account_id: String) -> void:
	var f := FileAccess.open("user://last_account.txt", FileAccess.WRITE)
	if f:
		f.store_string(account_id)
		f.close()


func logout() -> void:
	_current_meta = {}
	_derived_key = PackedByteArray()


## Permanently deletes an account and its local cache.
## If it was the current account, also logs out.
func remove_account(account_id: String) -> void:
	# Remove encrypted secrets file.
	var enc_path := "user://accounts/%s.enc" % account_id
	if FileAccess.file_exists(enc_path):
		DirAccess.remove_absolute(enc_path)

	# Remove from metadata list.
	for i in range(_accounts_meta.size()):
		if _accounts_meta[i]["id"] == account_id:
			_accounts_meta.remove_at(i)
			break
	_save_accounts_meta()

	# Clear last-account pointer if it was this one.
	if get_last_account_id() == account_id:
		var f := FileAccess.open("user://last_account.txt", FileAccess.WRITE)
		if f:
			f.store_string("")
			f.close()

	# If this was the active account, log out.
	if _current_meta.get("id", "") == account_id:
		logout()

	accounts_changed.emit()


# ── Public: session data ─────────────────────────────────────────────────────

func get_server_password() -> String:
	return _current_meta.get("_server_pass", "")

func get_refresh_token() -> String:
	return _current_meta.get("_refresh_token", "")

func save_refresh_token(token: String) -> void:
	if _derived_key.is_empty() or _current_meta.is_empty():
		return
	_current_meta["_refresh_token"] = token
	_rewrite_secrets_file()

func clear_refresh_token() -> void:
	save_refresh_token("")

func update_last_synced() -> void:
	if _current_meta.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	_current_meta["last_synced"] = now
	for meta in _accounts_meta:
		if meta["id"] == _current_meta["id"]:
			meta["last_synced"] = now
			break
	_save_accounts_meta()


# ── Public: encryption helpers (used by LocalStorage) ────────────────────────

## Encrypts arbitrary data with the current session key. Returns iv(16) + ciphertext.
func encrypt_data(data: PackedByteArray) -> PackedByteArray:
	if _derived_key.is_empty():
		return PackedByteArray()
	var iv := Crypto.new().generate_random_bytes(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, _derived_key, iv)
	var ciphertext := aes.update(_pkcs7_pad(data))
	aes.finish()
	return iv + ciphertext

## Decrypts data produced by encrypt_data(). Expects iv(16) + ciphertext.
func decrypt_data(data: PackedByteArray) -> PackedByteArray:
	if _derived_key.is_empty() or data.size() < 17:
		return PackedByteArray()
	var iv := data.slice(0, 16)
	var ciphertext := data.slice(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, _derived_key, iv)
	var decrypted := aes.update(ciphertext)
	aes.finish()
	return _pkcs7_unpad(decrypted)


# ── Private ───────────────────────────────────────────────────────────────────

func _rewrite_secrets_file() -> void:
	var account_id: String = _current_meta["id"]
	var path := "user://accounts/%s.enc" % account_id
	var f_read := FileAccess.open(path, FileAccess.READ)
	if f_read == null:
		return
	var salt := f_read.get_buffer(16)
	f_read.close()

	var secrets := {
		"magic": "razor_v1",
		"server_pass": _current_meta.get("_server_pass", ""),
		"refresh_token": _current_meta.get("_refresh_token", "")
	}
	var encrypted := _encrypt_account(JSON.stringify(secrets).to_utf8_buffer(), _derived_key, salt)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(encrypted)
		f.close()

func _ensure_accounts_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("accounts"):
		dir.make_dir("accounts")

func _load_accounts_meta() -> void:
	var f := FileAccess.open("user://accounts_meta.json", FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK:
		var data = json.get_data()
		if data is Array:
			_accounts_meta = data
	f.close()

func _save_accounts_meta() -> void:
	var f := FileAccess.open("user://accounts_meta.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_accounts_meta))
		f.close()

func _generate_id() -> String:
	var bytes := Crypto.new().generate_random_bytes(8)
	var result := ""
	for b in bytes:
		result += "%02x" % b
	return result


# ── Crypto ────────────────────────────────────────────────────────────────────

## PBKDF2-HMAC-SHA256 key derivation.
func _pbkdf2(password: PackedByteArray, salt: PackedByteArray,
		iterations: int, key_length: int) -> PackedByteArray:
	var crypto := Crypto.new()
	var result := PackedByteArray()
	var blocks_needed := ceili(float(key_length) / 32.0)

	for block_num in range(1, blocks_needed + 1):
		var counter := PackedByteArray([0, 0, 0, block_num])
		var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password, salt + counter)
		var t := u.duplicate()
		for _i in range(1, iterations):
			u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
			for j in range(t.size()):
				t[j] ^= u[j]
		result.append_array(t)

	return result.slice(0, key_length)

func _pkcs7_pad(data: PackedByteArray) -> PackedByteArray:
	var pad_len := 16 - (data.size() % 16)
	var padded := data.duplicate()
	for _i in range(pad_len):
		padded.append(pad_len)
	return padded

func _pkcs7_unpad(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return data
	var pad_len := data[data.size() - 1]
	if pad_len == 0 or pad_len > 16 or pad_len > data.size():
		return data
	return data.slice(0, data.size() - pad_len)

## Account file format: salt(16) + iv(16) + ciphertext
func _encrypt_account(data: PackedByteArray, key: PackedByteArray, salt: PackedByteArray) -> PackedByteArray:
	var iv := Crypto.new().generate_random_bytes(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv)
	var ciphertext := aes.update(_pkcs7_pad(data))
	aes.finish()
	return salt + iv + ciphertext

## raw = salt(16) + iv(16) + ciphertext; key is already derived by caller
func _decrypt_account(raw: PackedByteArray, key: PackedByteArray) -> PackedByteArray:
	if raw.size() < 33:
		return PackedByteArray()
	var iv := raw.slice(16, 32)
	var ciphertext := raw.slice(32)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, key, iv)
	var decrypted := aes.update(ciphertext)
	aes.finish()
	return _pkcs7_unpad(decrypted)
