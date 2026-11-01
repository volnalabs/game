class_name ColorAccess
extends RefCounted
## Map colours for colour vision deficiency (Settings.color_mode). States are told apart by colour,
## so for deuteranopia, protanopia and tritanopia every owner colour is daltonised: the colour is
## simulated as such a viewer sees it (LMS projection, Viénot / Brettel), and the difference that is
## lost is shifted into the channels they do see (Fidaner et al.). "high_contrast" keeps the colours
## but darkens borders and raises the fill. The acid green of radiation stays reserved.
## Only the display changes; the simulation never sees these colours.

const MODES := ["off", "deuteranopia", "protanopia", "tritanopia", "high_contrast"]

# RGB -> LMS and back (Viénot, Brettel & Mollon 1999).
const RGB2LMS := [[17.8824, 43.5161, 4.11935], [3.45565, 27.1554, 3.86714], [0.0299566, 0.184309, 1.46709]]
const LMS2RGB := [[0.0809444479, -0.130504409, 0.116721066], [-0.0102485335, 0.0540193266, -0.113614708],
	[-0.000365296938, -0.00412161469, 0.693511405]]


## The current mode (set by Settings.apply; cached so per-frame drawing stays cheap).
static var current: String = "off"


static func mode() -> String:
	return current


## Display colour of an owner colour under the current mode.
static func color(c: Color) -> Color:
	return c if current == "off" or current == "high_contrast" else color_for(c, current)


static func color_for(c: Color, m: String) -> Color:
	if m != "deuteranopia" and m != "protanopia" and m != "tritanopia":
		return c
	var sim_c := simulate(c, m)
	var e := Vector3(c.r - sim_c.r, c.g - sim_c.g, c.b - sim_c.b)
	var out := Vector3(c.r, c.g, c.b)
	if m == "tritanopia":
		out += Vector3(0.7 * e.z, 0.7 * e.z, 0.0)
	else:
		out += Vector3(0.0, 0.7 * e.x + e.y, 0.7 * e.x + e.z)
	var r := Color(clampf(out.x, 0.0, 1.0), clampf(out.y, 0.0, 1.0), clampf(out.z, 0.0, 1.0), c.a)
	return SimState.radiation_safe(r)


## How a viewer with deficiency `m` sees colour `c`.
static func simulate(c: Color, m: String) -> Color:
	var rgb := [c.r, c.g, c.b]
	var lms := [0.0, 0.0, 0.0]
	for i in 3:
		for j in 3:
			lms[i] += RGB2LMS[i][j] * rgb[j]
	match m:
		"protanopia":
			lms[0] = 2.02344 * lms[1] - 2.52581 * lms[2]
		"deuteranopia":
			lms[1] = 0.494207 * lms[0] + 1.24827 * lms[2]
		"tritanopia":
			lms[2] = -0.395913 * lms[0] + 0.801109 * lms[1]
	var out := [0.0, 0.0, 0.0]
	for i in 3:
		for j in 3:
			out[i] += LMS2RGB[i][j] * lms[j]
	return Color(clampf(out[0], 0.0, 1.0), clampf(out[1], 0.0, 1.0), clampf(out[2], 0.0, 1.0), c.a)


## Territory shader parameters for the mode: [border darkening, border alpha, fill alpha].
static func territory_params(m: String) -> Array:
	if m == "high_contrast":
		return [0.35, 0.95, 0.52]
	return [0.72, 0.78, 0.40]
