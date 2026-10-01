// An engine flame: a see-through additive cone that flickers and stretches
// with its pattern (ship_blink.gdshaderinc). The cone's base is at
// -height / 2 on its Y axis.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://render/shaders/ship_blink.gdshaderinc"

uniform vec3 color : source_color = vec3(0.45, 0.75, 1.0);
uniform int pattern = 0;
uniform float period = 1.0;
uniform float phase = 0.0;
uniform float height = 1.0;

varying float b;

void vertex() {
	b = blink(pattern, period, phase, TIME);
	VERTEX.y = (VERTEX.y + height * 0.5) * (0.75 + 0.25 * b) - height * 0.5;
}

void fragment() {
	ALBEDO = color;
	ALPHA = 0.35 * (0.6 + 0.4 * b);
}
