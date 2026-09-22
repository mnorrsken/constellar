class_name Format
## Number formatting for the UI.

## 7 200 000 000 -> "7.2 billion", 180 000 000 -> "180 million",
## 60 000 -> "60,000".
static func population(n: int) -> String:
	if n >= 1_000_000_000:
		return "%s billion" % _short(n / 1e9)
	if n >= 1_000_000:
		return "%s million" % _short(n / 1e6)
	return thousands(n)

## 1234567 -> "1,234,567"
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## Orbit distance: "0.029 AU", "1.33 AU", "45 AU".
static func au(a: float) -> String:
	if a < 0.1:
		return "%.3f AU" % a
	if a < 10.0:
		return "%.2f AU" % a
	return "%d AU" % roundi(a)

## Spectral type text: "G2 V", "M5.5 V", "white dwarf".
static func spectral(star: Dictionary) -> String:
	var cls: String = star.get("class", "")
	match cls:
		"D":
			return "white dwarf"
		"L", "T", "Y":
			return "brown dwarf"
	var sub: Variant = star.get("subclass")
	var sub_text := "" if sub == null else str(snappedf(float(sub), 0.1)).trim_suffix(".0")
	var lum_class: String = star.get("lum_class", "")
	return ("%s%s %s" % [cls, sub_text, lum_class]).strip_edges()

static func _short(x: float) -> String:
	return str(snappedf(x, 0.1)).trim_suffix(".0") if x < 100.0 else str(roundi(x))
