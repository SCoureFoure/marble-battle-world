extends RefCounted
## Minimal headless assertion helper. Preload it; do not give it a class_name.

var fails: int = 0
var count: int = 0


func check(cond: bool, name: String) -> void:
	count += 1
	if cond:
		print("ok   ", name)
	else:
		fails += 1
		print("FAIL ", name)


func approx(a: float, b: float, eps: float = 1e-4) -> bool:
	return absf(a - b) <= eps


func finish() -> void:
	if fails == 0:
		print("ALL_PASS (%d checks)" % count)
	else:
		print("FAILURES=%d of %d" % [fails, count])
