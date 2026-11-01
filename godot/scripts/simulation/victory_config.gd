class_name VictoryConfig
extends RefCounted
## Win conditions of a match (set on the "New game" screen; defaults in data/rules/default_rules.json).

## Share of contestable land that wins the match.
var domination_share: float = 0.7
## Win when every other non-tribe state is eliminated.
var eliminate_all: bool = true
## 0 = no limit; otherwise the largest state wins when time runs out.
var time_limit_minutes: int = 0


func to_dict() -> Dictionary:
	return {"domination_share": domination_share, "eliminate_all": eliminate_all,
		"time_limit_minutes": time_limit_minutes}


static func from_dict(d: Dictionary) -> VictoryConfig:
	var v := VictoryConfig.new()
	var defaults: Dictionary = Rules.for_k(1.0).victory_defaults
	v.domination_share = float(d.get("domination_share", defaults.get("domination_share", 0.7)))
	v.eliminate_all = bool(d.get("eliminate_all", defaults.get("eliminate_all", true)))
	v.time_limit_minutes = int(d.get("time_limit_minutes", defaults.get("time_limit_minutes", 0)))
	return v
