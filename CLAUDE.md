# Marble Battle World — agent notes

- Godot 4.7, GDScript only, GL Compatibility. Binary: `C:/Users/SCora/Desktop/Godot_v4.7-stable_win64.exe`.
- Read `docs/ARCHITECTURE.md` before touching `scripts/sim/`. It is the seam every module agrees on.
- No node per marble. Packed arrays on `BattleState`; mutate only via `s.field[i] = v`.
- Every random draw goes through `s.rng`. Tests assume determinism.
- Tests: `bash tools/verify.sh <test_basename>` — green needs exit 0 + `ALL_PASS` + no parse error.
- New `class_name` scripts need `--import` once; `verify.sh` does it.
- Tabs in `.gd` files.
- GDScript pitfalls seen here: `var x := Tuning.SOME_ARRAY[k]` fails (cannot infer from an untyped Array element) — write `var x: float = ...`; a name declared with `var` cannot be re-declared or reused as a `for` variable in the same function scope.
