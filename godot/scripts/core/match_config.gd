class_name MatchConfig
extends RefCounted
## Everything that defines a match before it starts (the "New game" screen fills this in).

var map_id: String = "earth"
## For generated worlds: GenParams dictionary (map_id is then "generated").
var generator: Dictionary = {}
var seed: int = 1
var bots: int = 20
var difficulty: String = "normal"
var tribes: int = 40
## "mixed" (deterministic spread of every personality) or one personality id for all bots.
var personality_mix: String = "mixed"
## Map nation index the player wants to play (-1 = choose a free tile).
var player_nation: int = -1
var has_player: bool = true
var player_name: String = ""
var victory: VictoryConfig = VictoryConfig.new()
## AI implementation for bots: "strategic" (VolnaLabs AI) or "legacy" (baseline port of RoWorld's AI).
var ai_kind: String = "strategic"
## Optional per-bot overrides for AI tests: [{"difficulty": "hard", "personality": "aggressive", "ai": "legacy"}, ...]
var bot_overrides: Array = []
## Unique id of this match (rewards are paid once per id; kept in saves).
var match_id: String = ""
## Fair mode: profile perks off for everyone (Phase 2D); a small reward bonus.
var fair_mode: bool = false


func to_dict() -> Dictionary:
	return {"map_id": map_id, "generator": generator, "seed": seed, "bots": bots, "difficulty": difficulty,
		"tribes": tribes, "personality_mix": personality_mix, "player_nation": player_nation,
		"has_player": has_player, "player_name": player_name, "victory": victory.to_dict(),
		"ai_kind": ai_kind, "bot_overrides": bot_overrides, "match_id": match_id, "fair_mode": fair_mode}


static func from_dict(d: Dictionary) -> MatchConfig:
	var c := MatchConfig.new()
	c.map_id = d.get("map_id", "earth")
	c.generator = d.get("generator", {})
	c.seed = int(d.get("seed", 1))
	c.bots = int(d.get("bots", 20))
	c.difficulty = d.get("difficulty", "normal")
	c.tribes = int(d.get("tribes", 40))
	c.personality_mix = d.get("personality_mix", "mixed")
	c.player_nation = int(d.get("player_nation", -1))
	c.has_player = bool(d.get("has_player", true))
	c.player_name = d.get("player_name", "")
	c.victory = VictoryConfig.from_dict(d.get("victory", {}))
	c.ai_kind = d.get("ai_kind", "strategic")
	c.bot_overrides = d.get("bot_overrides", [])
	c.match_id = d.get("match_id", "")
	c.fair_mode = bool(d.get("fair_mode", false))
	return c
