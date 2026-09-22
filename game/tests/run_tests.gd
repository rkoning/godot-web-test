extends SceneTree

## Headless test runner. Discovers every tests/test_*.gd, runs it, exits non-zero
## on any failure.
##
##   godot --headless --script tests/run_tests.gd            # everything
##   godot --headless --script tests/run_tests.gd -- supply  # only test_supply.gd
##
## Suites run on the first processed frame rather than in the constructor: the
## SceneTree's root window is not in the tree until then, and the campaign
## shell suite has to host a scene in it.
##
## Everything that can go wrong with discovery is a *failed check*, not a
## silent pass: an unreadable tests directory, a suite that will not load, a
## suite with no `run`, a suite that asserts nothing, and a `-- <suite>`
## filter that matched nothing all fail the run. A green run that tested
## nothing is the one outcome a test runner must never produce.

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true

	var t := TestHarness.new()
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]

	var dir := DirAccess.open("res://tests")
	if dir == null:
		print("  FAIL res://tests could not be opened (%s)"
			% error_string(DirAccess.get_open_error()))
		print("\n0 checks, 1 failed (0 suites)")
		quit(1)
		return true

	var names: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			if only == "" or f == "test_%s.gd" % only:
				names.append(f)
	names.sort()

	if names.is_empty():
		t.check("at least one suite matched '%s'" % only, false,
			"no tests/test_*.gd file matched; check the suite name")

	for f in names:
		print("\n== %s" % f)
		var before := t.checks
		var script := load("res://tests/" + f)
		if script == null:
			t.check("%s loads" % f, false, "load() returned null; the suite has a parse error")
			continue
		var suite = script.new()
		if not suite.has_method("run"):
			t.check("%s has run(t)" % f, false, "the suite has no run() method")
			continue
		suite.run(t)
		t.check("%s produced checks" % f, t.checks > before,
			"the suite ran but asserted nothing")

	print("\n%d checks, %d failed (%d suites)" % [t.checks, t.failures, names.size()])
	quit(1 if t.failures > 0 else 0)
	return true
