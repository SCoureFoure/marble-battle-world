class_name Follow extends RefCounted
## Follow-legacy stepping for the camera-follow scene feature. Pure, never
## writes to `World` — callers apply the returned log line themselves.
## docs/ARCHITECTURE.md §17.9, .warboss-horde/slices/m9-ui.md.


## Returns `[new_unit, new_stack, log_line]`. `unit == -1` (not following)
## returns `[-1, -1, ""]`. Otherwise defers to `Heroes.successor`: no
## successor ends the tale; a different successor passes it on with a log
## line; the same unit still active returns an empty log line.
static func step(w: World, unit: int, stack: int) -> Array:
	if unit == -1:
		return [-1, -1, ""]

	var nu := Heroes.successor(w, unit, stack)
	if nu == -1:
		return [-1, -1, "The tale of %s ends" % _name(w, unit)]

	if nu == unit:
		return [unit, w.units.stack[unit], ""]

	return [nu, w.units.stack[nu], "The tale passes to %s" % _name(w, nu)]


static func _name(w: World, u: int) -> String:
	return w.units.names.get(u, "Unit %d" % u)
