class_name TestCase
extends RefCounted
## Base class of the project's tests (tests/run_tests.gd runs every test_* method).

var failures: Array[String] = []
var _current: String = ""


func check(cond: bool, msg: String = "") -> bool:
	if not cond:
		failures.append("%s: %s" % [_current, msg if msg != "" else "check failed"])
	return cond


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	if actual != expected:
		failures.append("%s: %s expected %s, got %s" % [_current, msg, str(expected), str(actual)])
		return false
	return true


func check_near(actual: float, expected: float, eps: float, msg: String = "") -> bool:
	if absf(actual - expected) > eps:
		failures.append("%s: %s expected %f ± %f, got %f" % [_current, msg, expected, eps, actual])
		return false
	return true


func before_each() -> void:
	pass
