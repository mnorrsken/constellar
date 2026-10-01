// A soft dark patch behind a star's name labels, so a big star glow does
// not wash the text out when the camera is close. Sized in the labels' own
// units (Label3D pixels at pixel_size, fixed size), so it matches the text
// at any window size. Fades in only when the camera is near the star.
// INSTANCE_CUSTOM: x = width, y = height, z = centre's y offset (label
// units, down is negative), w = the labels' alpha.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform float pixel_size = 0.0007;
uniform vec4 shade : source_color = vec4(0.01, 0.015, 0.04, 0.72);
// Camera distance (ly) where the patch starts to show, and where it is full.
uniform float show_far = 14.0;
uniform float show_near = 8.0;

varying vec2 v_half;
varying vec2 v_units;
varying float v_alpha;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float depth = max(-center.z, 0.01);
	// Label3D with fixed_size scales by depth the same way.
	vec2 units = VERTEX.xy * INSTANCE_CUSTOM.xy + vec2(0.0, INSTANCE_CUSTOM.z);
	POSITION = PROJECTION_MATRIX * (center + vec4(units * pixel_size * depth, 0.0, 0.0));
	v_half = INSTANCE_CUSTOM.xy * 0.5;
	v_units = VERTEX.xy * INSTANCE_CUSTOM.xy;
	float zoom = 1.0 - smoothstep(show_near, show_far, length(center.xyz));
	v_alpha = INSTANCE_CUSTOM.w * zoom;
}

void fragment() {
	// Rounded box with a soft edge (distance in label units).
	float radius = 16.0;
	vec2 q = abs(v_units) - (v_half - vec2(radius));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float a = 1.0 - smoothstep(-16.0, 0.0, d);
	ALBEDO = shade.rgb;
	ALPHA = a * shade.a * v_alpha;
}
