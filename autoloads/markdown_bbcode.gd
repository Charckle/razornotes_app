class_name MarkdownBBCode


static func convert(md: String) -> String:
	var lines := md.split("\n")
	var out: PackedStringArray = []
	var in_code_block := false

	for raw_line in lines:
		var line: String = raw_line

		# ── Fenced code blocks ────────────────────────────────────────────────
		if line.begins_with("```"):
			if in_code_block:
				out.append("[/font][/color]")
				in_code_block = false
			else:
				out.append("[color=#7c7c7c][font_size=13]")
				in_code_block = true
			continue

		if in_code_block:
			out.append(line)
			continue

		# ── Headings ──────────────────────────────────────────────────────────
		if line.begins_with("### "):
			out.append("[font_size=17][b]" + line.substr(4) + "[/b][/font_size]")
			continue
		elif line.begins_with("## "):
			out.append("[font_size=21][b]" + line.substr(3) + "[/b][/font_size]")
			continue
		elif line.begins_with("# "):
			out.append("[font_size=26][b]" + line.substr(2) + "[/b][/font_size]")
			continue

		# ── Horizontal rule ───────────────────────────────────────────────────
		if line == "---" or line == "***" or line == "___":
			out.append("[color=#b0aa80]" + "─".repeat(36) + "[/color]")
			continue

		# ── Unordered lists ───────────────────────────────────────────────────
		if line.begins_with("- ") or line.begins_with("* "):
			line = "  • " + line.substr(2)
		elif line.begins_with("  - ") or line.begins_with("  * "):
			line = "    ◦ " + line.substr(4)

		# ── Blockquote ────────────────────────────────────────────────────────
		if line.begins_with("> "):
			line = "[color=#888888][i]" + line.substr(2) + "[/i][/color]"
		else:
			# ── Inline formatting (order matters: bold+italic before bold/italic)
			line = _apply_inline(line)

		out.append(line)

	return "\n".join(out)


static func _apply_inline(text: String) -> String:
	# Bold + italic
	text = _re_sub(text, "\\*\\*\\*(.*?)\\*\\*\\*", "[b][i]$1[/i][/b]")
	# Bold
	text = _re_sub(text, "\\*\\*(.*?)\\*\\*", "[b]$1[/b]")
	text = _re_sub(text, "__(.*?)__", "[b]$1[/b]")
	# Italic
	text = _re_sub(text, "\\*(.*?)\\*", "[i]$1[/i]")
	text = _re_sub(text, "_((?!_).*?)_", "[i]$1[/i]")
	# Inline code
	text = _re_sub(text, "`(.*?)`", "[color=#7c7c7c][font_size=13]$1[/font_size][/color]")
	# Links
	text = _re_sub(text, "\\[(.*?)\\]\\((.*?)\\)", "[url=$2]$1[/url]")
	return text


static func _re_sub(text: String, pattern: String, replacement: String) -> String:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return text
	return re.sub(text, replacement, true)
