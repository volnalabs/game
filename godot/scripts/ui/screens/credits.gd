extends ScreenBase
## Credits and licences: OpenFront (AGPL §7 notice), RoWorld, map data, font, flags, icons, Godot (MIT).


func _ready() -> void:
	var c := build_frame(tr("CREDITS_TITLE"), 980)
	var text := RichTextLabel.new()
	text.custom_minimum_size = Vector2(980, 560)
	text.bbcode_enabled = true
	text.scroll_active = true
	var s := "[b]TerraFront[/b] %s\n\n" % ProjectSettings.get_setting("application/config/version", "")
	s += tr("CREDITS_BODY") + "\n\n"
	s += "[b]%s[/b]\n" % tr("CREDITS_ICONS")
	for line in Icons.attribution():
		s += "• %s\n" % line
	s += "\n"
	s += "[b]Godot Engine[/b]\n" + Engine.get_license_text() + "\n\n"
	s += "[b]%s[/b]\n" % tr("CREDITS_ENGINE_PARTS")
	for info: Dictionary in Engine.get_copyright_info():
		s += "• %s\n" % info.get("name", "")
	text.text = s
	c.add_child(text)
	c.add_child(back_button())
	footer()
