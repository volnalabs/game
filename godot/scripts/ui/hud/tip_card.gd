class_name HudTipCard
extends PanelContainer
## A compact beginner tip in the message slot: a title, one or two sentences and three small
## actions — "Got it", "More" (opens the encyclopedia article), "Turn tips off".

var hud: GameHUD
var current: String = ""
var _title: Label
var _text: Label


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE_2, 10, Color.TRANSPARENT, 10))
	custom_minimum_size.x = 360
	var v := UITheme.vbox(4)
	add_child(v)
	var head := UITheme.hbox(6)
	head.add_child(Icons.rect("ui_info", 16, UITheme.ACCENT))
	_title = UITheme.label("", UITheme.T_BODY, UITheme.TEXT)
	_title.add_theme_font_override("font", UITheme.font_medium)
	head.add_child(_title)
	v.add_child(head)
	_text = UITheme.label("", 13, UITheme.TEXT_DIM)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 340
	v.add_child(_text)
	var b := UITheme.hbox(2)
	for a: Array in [["TIP_OK", close], ["TIP_MORE", func() -> void:
			var t: Dictionary = Tips.data().get(current, {})
			close()
			hud.ctl.open_encyclopedia(String(t.get("article", "")))]]:
		var btn := UITheme.ghost_button(tr(a[0]), a[1])
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", UITheme.ACCENT if a[0] == "TIP_OK" else UITheme.TEXT_DIM)
		b.add_child(btn)
	b.add_child(UITheme.spacer())
	var off := UITheme.ghost_button(tr("TIP_OFF"), func() -> void:
		Tips.disable_all()
		close())
	off.add_theme_font_size_override("font_size", 12)
	off.add_theme_color_override("font_color", UITheme.TEXT_FAINT)
	b.add_child(off)
	v.add_child(b)
	visible = false


## Shows tip `id` once (no-op if tips are off or it was seen).
func show_tip(id: String) -> bool:
	if visible or not Tips.should_show(id):
		return false
	var t: Dictionary = Tips.data()[id]
	current = id
	_title.text = MetaData.text(t["title"])
	_text.text = MetaData.text(t["text"])
	visible = true
	reset_size()
	Tips.mark_seen(id)
	for c in find_children("*", "BaseButton", true, false):
		(c as BaseButton).focus_mode = Control.FOCUS_NONE
	return true


func close() -> void:
	visible = false
	current = ""
