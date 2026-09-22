// Screen-sized marker ring (hover / selection) drawn on a quad billboard.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 ring_color : source_color = vec4(1.0, 0.75, 0.3, 1.0);
uniform float diameter_px = 34.0;
uniform float thickness = 0.07;
uniform float segments = 0.0;   // 0 = solid ring, else number of dashes
uniform float spin = 0.0;       // radians per second
uniform float intensity = 1.6;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float depth = max(-center.z, 0.01);
	float px = 2.0 * depth / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	POSITION = PROJECTION_MATRIX * (center + vec4(VERTEX.xy * diameter_px * px, 0.0, 0.0));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float w = max(fwidth(r), 1e-4);
	float ring = 1.0 - smoothstep(thickness - w, thickness + w, abs(r - 0.82));
	if (segments > 0.0) {
		float a = atan(p.y, p.x) + TIME * spin;
		ring *= step(0.4, fract(a / TAU * segments));
	}
	ALBEDO = ring_color.rgb * intensity;
	ALPHA = ring * ring_color.a;
}
