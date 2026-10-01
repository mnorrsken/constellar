// A ship's point light: a camera-facing quad with a hot core and a soft
// halo, blinking in its pattern (ship_blink.gdshaderinc). Pulled towards
// the camera so the hull under it doesn't cut the halo.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://render/shaders/ship_blink.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0);
uniform float energy = 2.0;
uniform int pattern = 0;
uniform float period = 1.0;
uniform float phase = 0.0;
uniform float pull = 0.1;

void vertex() {
	vec4 centre = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	centre.xyz -= normalize(centre.xyz) * pull;
	POSITION = PROJECTION_MATRIX * (centre + vec4(VERTEX.xy, 0.0, 0.0));
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = 1.0 - smoothstep(0.0, 0.2, r);
	float halo = pow(max(1.0 - r, 0.0), 2.5) * 0.5;
	vec3 col = color * energy * (core * 2.0 + halo) * blink(pattern, period, phase, TIME);
	// Light only where it glows: the viewer's background is see-through.
	float a = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
	ALBEDO = col / max(a, 1e-4);
	ALPHA = a;
}
