// Polar grid on the galactic plane, centred on Sol: rings every 5 ly
// (brighter every 25 ly) and spokes every 30 degrees, fading at the edge.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 line_color : source_color = vec3(0.22, 0.55, 0.72);
uniform float ring_step = 5.0;
uniform float fade_start = 42.0;
uniform float fade_end = 62.0;

varying vec2 v_xz;

void vertex() {
	v_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float line(float x, float width) {
	float w = max(fwidth(x), 1e-5);
	float d = abs(fract(x + 0.5) - 0.5);
	return 1.0 - smoothstep(0.0, w * width, d);
}

void fragment() {
	float d = length(v_xz);
	float rings = line(d / ring_step, 1.2) * 0.2 + line(d / (ring_step * 5.0), 1.4) * 0.3;
	float spokes = line(atan(v_xz.y, v_xz.x) / TAU * 12.0, 1.0) * 0.12 * smoothstep(3.0, 10.0, d);
	float disc = 0.02 * (1.0 - smoothstep(0.0, fade_end, d));
	float fade = 1.0 - smoothstep(fade_start, fade_end, d);
	ALBEDO = line_color;
	ALPHA = clamp((max(rings, spokes) + disc) * fade, 0.0, 1.0);
}
