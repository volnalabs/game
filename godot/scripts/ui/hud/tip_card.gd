class_name HudTipCard
extends PanelContainer
## The contextual tip card (bottom left): title, one or two sentences, "Got it", "More" (opens
## the encyclopedia article) and "Don't show tips".

var hud: GameHUD
var current: String = ""
var _title: Label
var _text: Label


func _init(h: GameHUD) -> void:
	hud = h
	add_theme_stylebox_override("panel", UITheme.box(UITheme.SURFACE_2, UITheme.R_M, Color(UITheme.ACCENT, 0.5), 12))
	custom_minimum_size.x = 340
	var v := UITheme.vbox(6)
	add_child(v)
	var head := UITheme.hbox(8)
	head.add_child(Icons.rect("ui_info", 18, UITheme.ACCENT))
	_title = UITheme.label("", UITheme.T_BODY_L, UITheme.TEXT, true)
	head.add_child(_title)
	v.add_child(head)
	_text = UITheme.label("", UITheme.T_BODY, UITheme.TEXT_DIM)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 310
	v.add_child(_text)
	var b := UITheme.hbox(6)
	b.add_child(UITheme.accent_button(tr("TIP_OK"), close, 0))
	b.add_child(UITheme.button(tr("TIP_MORE"), func() -> void:
		var t: Dictionary = Tips.data().get(current, {})
		close()
		hud.ctl.open_encyclopedia(String(t.get("article", ""))), 0, "ui_book"))
	b.add_child(UITheme.spacer())
	b.add_child(UITheme.ghost_button(tr("TIP_OFF"), func() -> void:
		Tips.disable_all()
		close()))
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
