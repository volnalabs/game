class_name DiplomacyPanel
extends RefCounted
## Diplomacy in the HUD (Phase 2F): the dock tab (offers to the player with accept / decline, help
## requests, every state's relation, shipments on the way) and the inspector's actions for one state
## (propose an alliance or a pact, renew, break, send troops or gold, ask for help). Everything is
## read from DiplomacySystem; actions go through the match controller as Commands. Every disabled
## action carries its reason.

const REL_ICON := {"team": "ui_users", "alliance": "ui_users", "nap": "ui_shield", "war": "ui_swords", "neutral": "ui_flag"}
const REL_ORDER := ["team", "alliance", "nap", "war", "neutral"]


static func tr_(k: String) -> String:
	return TranslationServer.translate(k)


static func rel_color(rel: String) -> Color:
	match rel:
		"team", "alliance":
			return UITheme.GOOD
		"nap":
			return UITheme.ACCENT
		"war":
			return UITheme.BAD
	return UITheme.TEXT_DIM


static func rel_name(rel: String) -> String:
	return tr_("REL_" + rel.to_upper())


static func secs(sim: Sim, ticks: int) -> int:
	return ceili(float(ticks) / float(sim.rules.tick_rate))


static func duration(sim: Sim, ticks: int) -> String:
	var s := secs(sim, ticks)
	return "%d:%02d" % [s / 60, s % 60]


## "Alliance · 3:20 left" for the relation between the player and `id`.
static func relation_line(sim: Sim, id: int) -> String:
	var pid := sim.player_id
	var dip := sim.diplomacy
	var rel := dip.relation(pid, id)
	var text := rel_name(rel)
	var left := dip.time_left(pid, id)
	if left < 0:
		text += " · " + tr_("DIPLO_FOREVER")
	elif left > 0:
		text += " · " + tr_("DIPLO_LEFT") % duration(sim, left)
	return text


## Relation badge (icon + name + time left) with a hint.
static func relation_badge(sim: Sim, id: int) -> Control:
	var rel := sim.diplomacy.relation(sim.player_id, id)
	var row := UITheme.icon_label(REL_ICON[rel], relation_line(sim, id), rel_color(rel), UITheme.T_BODY - 1)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	Hints.attach(row, {"title": rel_name(rel), "text": tr_("REL_%s_HINT" % rel.to_upper())})
	return row


# ---------------------------------------------------------------------------------------------
# Reasons (shown on disabled buttons)
# ---------------------------------------------------------------------------------------------

## Why the player cannot propose `kind` to `id` ("" = they can).
static func request_blocker(sim: Sim, id: int, kind: String) -> String:
	var pid := sim.player_id
	var dip := sim.diplomacy
	var st := sim.st
	if st.o_kind[id] == Rules.KIND_TRIBE:
		return tr_("DIPLO_R_TRIBE")
	if dip.same_team(pid, id):
		return tr_("DIPLO_R_TEAM")
	var cur := String(dip.pact(pid, id).get("kind", ""))
	if cur == DiplomacySystem.ALLIANCE or (cur == DiplomacySystem.NAP and kind == DiplomacySystem.NAP):
		return tr_("DIPLO_R_ALREADY")
	if not dip.pending(pid, id).is_empty():
		return tr_("DIPLO_R_ASKED")
	var maxa := int(sim.rules.dip.get("max_allies", 3))
	if kind == DiplomacySystem.ALLIANCE:
		if dip.allies_of(pid).size() >= maxa:
			return tr_("DIPLO_R_TOO_MANY") % maxa
		if dip.allies_of(id).size() >= maxa:
			return tr_("DIPLO_R_THEY_FULL")
	var back := dip.pending(id, pid)
	if not back.is_empty() and String(back["kind"]) == kind:
		return ""  # proposing the same back accepts theirs
	var cd := dip.cooldown_left(pid, id)
	if cd > 0:
		return tr_("DIPLO_R_COOLDOWN") % secs(sim, cd)
	return ""


## The enemy the player would ask help against: whoever attacks the player with most troops.
static func main_enemy(sim: Sim) -> int:
	var best := 0
	var best_t := 0.0
	for a in sim.attacks.incoming(sim.player_id):
		if a.attacker > 0 and a.troops > best_t:
			best_t = a.troops
			best = a.attacker
	return best


static func help_blocker(sim: Sim, ally: int) -> String:
	var pid := sim.player_id
	var dip := sim.diplomacy
	if not dip.allied(pid, ally):
		return tr_("DIPLO_R_NOT_ALLY")
	var enemy := main_enemy(sim)
	if enemy == 0:
		return tr_("DIPLO_R_NO_ENEMY")
	if not dip.can_attack(ally, enemy):
		return tr_("REJECT_BAD_TARGET")
	for h: Dictionary in dip.help:
		if int(h["from"]) == pid and int(h["to"]) == ally:
			return tr_("DIPLO_R_HELP_ASKED")
	return ""


# ---------------------------------------------------------------------------------------------
# Dock tab
# ---------------------------------------------------------------------------------------------

static func panel(hud: GameHUD, body: VBoxContainer) -> void:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	var dip := sim.diplomacy
	var maxa := int(sim.rules.dip.get("max_allies", 3))
	var note := UITheme.label(tr_("DIPLO_NOTE"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 330
	body.add_child(note)
	# Offers waiting for the player's answer.
	var reqs := dip.requests_to(pid)
	if not reqs.is_empty():
		body.add_child(UITheme.section(tr_("DIPLO_SEC_REQUESTS"), "ui_users"))
		for r: Dictionary in reqs:
			body.add_child(request_card(hud, int(r["from"]), String(r["kind"]), int(r["tick"])))
	var helps := dip.help_for(pid)
	if not helps.is_empty():
		body.add_child(UITheme.section(tr_("DIPLO_SEC_HELP"), "ui_swords"))
		for h: Dictionary in helps:
			body.add_child(help_card(hud, int(h["from"]), int(h["enemy"])))
	# Every state, grouped by relation.
	body.add_child(UITheme.section(tr_("DIPLO_SEC_STATES") + " · " + tr_("DIPLO_ALLIES") % [dip.allies_of(pid).size(), maxa], "ui_world"))
	var list: Array = []
	for o in range(1, st.owner_count + 1):
		if o != pid and st.o_alive[o] == 1 and st.o_tiles[o] > 0 and st.o_kind[o] != Rules.KIND_TRIBE:
			list.append(o)
	list.sort_custom(func(a: int, b: int) -> bool:
		var ra := REL_ORDER.find(dip.relation(pid, a))
		var rb := REL_ORDER.find(dip.relation(pid, b))
		return ra < rb if ra != rb else st.o_tiles[a] > st.o_tiles[b])
	if list.is_empty():
		body.add_child(UITheme.label(tr_("DIPLO_NONE"), UITheme.T_BODY, UITheme.TEXT_FAINT))
	for o: int in list:
		body.add_child(state_row(hud, o))
	# Shipments on the way to or from the player.
	var mine: Array = []
	for c in dip.convoys:
		if c.from == pid or c.to == pid:
			mine.append(c)
	if not mine.is_empty():
		body.add_child(UITheme.section(tr_("DIPLO_SEC_CONVOYS"), "ui_packages"))
		for c: DiplomacySystem.Convoy in mine:
			var what := (tr_("CONVOY_TROOPS") if c.kind == "troops" else tr_("CONVOY_GOLD")) % UITheme.num(c.amount)
			body.add_child(UITheme.icon_label("r_army" if c.kind == "troops" else "r_gold",
				tr_("DIPLO_CONVOY_LINE") % [st.o_name[c.from], st.o_name[c.to], what, secs(sim, maxi(0, c.arrive - st.tick))],
				UITheme.TEXT_DIM, UITheme.T_CAPTION + 1))


static func request_card(hud: GameHUD, from: int, kind: String, tick: int) -> Control:
	var sim := hud.sim
	var st := sim.st
	var c := UITheme.card(8, Color(UITheme.ACCENT, 0.5))
	var v := UITheme.vbox(6)
	c.add_child(v)
	var head := UITheme.hbox(8)
	head.add_child(UITheme.flag_rect(hud.flag_of(from), 24, 16))
	var t := UITheme.label(tr_("DIPLO_OFFERS") % [st.o_name[from], rel_name(kind)], UITheme.T_BODY, UITheme.TEXT, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.custom_minimum_size.x = 250
	head.add_child(t)
	v.add_child(head)
	var left := int(sim.rules.dip.get("request_ticks", 200)) - (st.tick - tick)
	v.add_child(UITheme.label(tr_("DIPLO_OFFER_LEFT") % secs(sim, maxi(0, left)), UITheme.T_CAPTION, UITheme.TEXT_DIM))
	var acts := UITheme.hbox(8)
	var ok := UITheme.accent_button(tr_("DIPLO_ACCEPT"), func() -> void: hud.ctl.diplo("reply", from, "", true), 0, "ui_check")
	ok.focus_mode = Control.FOCUS_NONE
	Hints.attach(ok, {"title": tr_("DIPLO_ACCEPT"), "text": tr_("DIPLO_ACCEPT_HINT")})
	acts.add_child(ok)
	var no := UITheme.ghost_button(tr_("DIPLO_DECLINE"), func() -> void: hud.ctl.diplo("reply", from, "", false), "ui_close")
	no.focus_mode = Control.FOCUS_NONE
	Hints.attach(no, {"title": tr_("DIPLO_DECLINE"), "text": tr_("DIPLO_DECLINE_HINT")})
	acts.add_child(no)
	v.add_child(acts)
	c.set_meta("diplo_request", from)
	return c


static func help_card(hud: GameHUD, asker: int, enemy: int) -> Control:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	var c := UITheme.card(8, Color(UITheme.WARN, 0.5))
	var v := UITheme.vbox(6)
	c.add_child(v)
	var t := UITheme.label(tr_("DIPLO_HELP_LINE") % [st.o_name[asker], st.o_name[enemy]], UITheme.T_BODY, UITheme.TEXT, true)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 300
	v.add_child(t)
	var acts := UITheme.hbox(8)
	var amount := floorf(st.o_troops[pid] * hud.ctl.ratio)
	var ok := UITheme.accent_button(tr_("DIPLO_HELP_GIVE") % UITheme.num(amount), func() -> void: hud.ctl.answer_help(asker, true), 0, "ui_swords")
	ok.focus_mode = Control.FOCUS_NONE
	Hints.attach(ok, {"title": tr_("DIPLO_HELP_GIVE") % UITheme.num(amount), "text": tr_("DIPLO_HELP_GIVE_HINT")})
	Hints.disable(ok, tr_("DIPLO_R_NO_TROOPS") if amount < 1.0 else "")
	acts.add_child(ok)
	var no := UITheme.ghost_button(tr_("DIPLO_HELP_REFUSE"), func() -> void: hud.ctl.answer_help(asker, false), "ui_close")
	no.focus_mode = Control.FOCUS_NONE
	acts.add_child(no)
	v.add_child(acts)
	return c


## One state in the list: colour, name, relation; a click opens it in the inspector's diplomacy tab.
static func state_row(hud: GameHUD, o: int) -> Control:
	var sim := hud.sim
	var st := sim.st
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UITheme.box(Color.TRANSPARENT, UITheme.R_S, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.06), UITheme.R_S, Color.TRANSPARENT, 4))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(1, 1, 1, 0.1), UITheme.R_S, Color.TRANSPARENT, 4))
	b.custom_minimum_size = Vector2(330, 40)
	var h := UITheme.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	b.add_child(h)
	var sw := ColorRect.new()
	sw.color = st.o_color[o]
	sw.custom_minimum_size = Vector2(10, 10)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sw)
	var v := UITheme.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := UITheme.label(st.o_name[o], UITheme.T_BODY, UITheme.TEXT)
	nm.clip_text = true
	v.add_child(nm)
	var rel := sim.diplomacy.relation(sim.player_id, o)
	var rl := UITheme.label(relation_line(sim, o), UITheme.T_CAPTION, rel_color(rel))
	v.add_child(rl)
	h.add_child(v)
	if sim.diplomacy.is_traitor(o):
		h.add_child(UITheme.badge(tr_("TRAITOR_SHORT"), UITheme.BAD))
	var ic := Icons.rect(REL_ICON[rel], 16, rel_color(rel))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	b.pressed.connect(func() -> void:
		hud.ctl.select_owner(o, true)
		hud.inspector.set_tab("diplomacy"))
	Hints.attach(b, func() -> Dictionary: return {"title": st.o_name[o], "text": tr_("REL_%s_HINT" % rel.to_upper()),
		"rows": [[tr_("INFO_LAND"), "%.1f%%" % (st.land_share(o) * 100.0)], [tr_("INFO_TROOPS"), UITheme.num(st.o_troops[o])]]})
	b.set_meta("diplo_state", o)
	return b


# ---------------------------------------------------------------------------------------------
# Inspector tab: actions with one state
# ---------------------------------------------------------------------------------------------

static func actions(hud: GameHUD, body: VBoxContainer, id: int) -> void:
	var sim := hud.sim
	var st := sim.st
	var pid := sim.player_id
	var dip := sim.diplomacy
	var d := sim.rules.dip
	body.add_child(UITheme.section(tr_("DIPLO_RELATION"), "ui_users"))
	body.add_child(relation_badge(sim, id))
	if dip.is_traitor(id):
		var tl := UITheme.label(tr_("DIPLO_TRAITOR") % secs(sim, int(dip.traitor_until[id]) - st.tick), UITheme.T_CAPTION, UITheme.BAD)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size.x = 270
		body.add_child(tl)
	if st.o_kind[id] == Rules.KIND_TRIBE:
		body.add_child(UITheme.label(tr_("DIPLO_R_TRIBE"), UITheme.T_BODY, UITheme.TEXT_FAINT))
		return
	var back := dip.pending(id, pid)
	if not back.is_empty():
		body.add_child(request_card(hud, id, String(back["kind"]), int(back["tick"])))
	var rel := dip.relation(pid, id)
	if rel != "team":
		if rel != "alliance":
			body.add_child(UITheme.section(tr_("DIPLO_SEC_ACTIONS")))
			var secs_a := secs(sim, int(d.get("alliance_ticks", 3000)))
			var a := _action(tr_("DIPLO_ASK_ALLIANCE"), "ui_users", func() -> void: hud.ctl.diplo("request", id, DiplomacySystem.ALLIANCE),
				tr_("DIPLO_ASK_ALLIANCE_HINT") % secs_a, request_blocker(sim, id, DiplomacySystem.ALLIANCE))
			a.set_meta("diplo_action", "ask_alliance")
			body.add_child(a)
			if rel != "nap":
				var n := _action(tr_("DIPLO_ASK_NAP"), "ui_shield", func() -> void: hud.ctl.diplo("request", id, DiplomacySystem.NAP),
					tr_("DIPLO_ASK_NAP_HINT") % secs(sim, int(d.get("nap_ticks", 2400))), request_blocker(sim, id, DiplomacySystem.NAP))
				n.set_meta("diplo_action", "ask_nap")
				body.add_child(n)
		if rel == "alliance":
			body.add_child(UITheme.section(tr_("DIPLO_SEC_ALLY")))
			var p := dip.pact(pid, id)
			var mine_key := "ext_a" if pid < id else "ext_b"
			var renew_reason := ""
			if bool(p.get(mine_key, false)):
				renew_reason = tr_("DIPLO_RENEW_ASKED")
			elif not dip.in_extend_window(pid, id):
				renew_reason = tr_("DIPLO_RENEW_LATER") % secs(sim, int(d.get("extend_window_ticks", 300)))
			var rn := _action(tr_("DIPLO_RENEW"), "ui_restart", func() -> void: hud.ctl.diplo("extend", id),
				tr_("DIPLO_RENEW_HINT") % secs(sim, int(d.get("alliance_ticks", 3000))), renew_reason)
			rn.set_meta("diplo_action", "renew")
			body.add_child(rn)
			var travel := travel_secs(sim, pid, id)
			var troops := floorf(st.o_troops[pid] * hud.ctl.ratio)
			var gold := floorf(st.o_gold[pid] * hud.ctl.ratio)
			var tb := _action(tr_("DIPLO_SEND_TROOPS") % UITheme.num(troops), "r_army", func() -> void: hud.ctl.send_aid(id, "troops"),
				tr_("DIPLO_SEND_HINT") % travel, tr_("DIPLO_R_NO_TROOPS") if troops < 1.0 else "")
			tb.set_meta("diplo_action", "send_troops")
			body.add_child(tb)
			var gb := _action(tr_("DIPLO_SEND_GOLD") % UITheme.num(gold), "r_gold", func() -> void: hud.ctl.send_aid(id, "gold"),
				tr_("DIPLO_SEND_HINT") % travel, tr_("DIPLO_R_NO_GOLD") if gold < 1.0 else "")
			gb.set_meta("diplo_action", "send_gold")
			body.add_child(gb)
			var enemy := main_enemy(sim)
			var hb := _action(tr_("DIPLO_ASK_HELP") % (st.o_name[enemy] if enemy > 0 else "…"), "ui_swords",
				func() -> void: hud.ctl.ask_help(id), tr_("DIPLO_ASK_HELP_HINT"), help_blocker(sim, id))
			hb.set_meta("diplo_action", "ask_help")
			body.add_child(hb)
		if rel == "alliance" or rel == "nap":
			var br := _action(tr_("DIPLO_BREAK"), "ui_close", func() -> void: hud.ctl.diplo("break", id),
				tr_("DIPLO_BREAK_HINT") % secs(sim, int(d.get("traitor_ticks", 300))), "")
			br.add_theme_color_override("font_color", UITheme.BAD)
			br.set_meta("diplo_action", "break")
			body.add_child(br)
	else:
		var tl2 := UITheme.label(tr_("REL_TEAM_HINT"), UITheme.T_CAPTION, UITheme.TEXT_DIM)
		tl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl2.custom_minimum_size.x = 270
		body.add_child(tl2)
		var enemy2 := main_enemy(sim)
		var hb2 := _action(tr_("DIPLO_ASK_HELP") % (st.o_name[enemy2] if enemy2 > 0 else "…"), "ui_swords",
			func() -> void: hud.ctl.ask_help(id), tr_("DIPLO_ASK_HELP_HINT"), help_blocker(sim, id))
		hb2.set_meta("diplo_action", "ask_help")
		body.add_child(hb2)
		var troops2 := floorf(st.o_troops[pid] * hud.ctl.ratio)
		var tb2 := _action(tr_("DIPLO_SEND_TROOPS") % UITheme.num(troops2), "r_army", func() -> void: hud.ctl.send_aid(id, "troops"),
			tr_("DIPLO_SEND_HINT") % travel_secs(sim, pid, id), tr_("DIPLO_R_NO_TROOPS") if troops2 < 1.0 else "")
		tb2.set_meta("diplo_action", "send_troops")
		body.add_child(tb2)


## Convoy travel time between two capitals, in seconds (same formula as DiplomacySystem.send).
static func travel_secs(sim: Sim, a: int, b: int) -> int:
	var d := sim.rules.dip
	var dip := sim.diplomacy
	var dist := dip._capital(a).distance_to(dip._capital(b))
	return secs(sim, maxi(int(d.get("convoy_min_ticks", 20)), ceili(dist / maxf(float(d.get("convoy_speed", 4.0)), 0.01))))


## A full-width labelled action with a hint and, when disabled, its reason shown under it.
static func _action(text: String, icon: String, cb: Callable, hint: String, reason: String) -> Control:
	var b := UITheme.ghost_button(text, cb, icon)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(270, 32)
	Hints.disable(b, reason)
	Hints.attach(b, {"title": text, "text": hint + ("\n\n" + reason if reason != "" else "")})
	return b
