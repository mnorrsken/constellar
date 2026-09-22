// Starlane ribbons with a constant on-screen width and a slow flowing dash.
// Each lane is a quad; every vertex carries its own end in VERTEX and the
// other end in CUSTOM0.xyz, CUSTOM0.w = which side of the ribbon (+1/-1).
// UV.x = distance along the lane (ly), UV.y = -1..1 across it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float width_px = 2.0;
uniform float dash_length = 1.6;   // ly
uniform float flow_speed = 0.5;    // ly per second

varying float v_side;
varying float v_along;

void vertex() {
	mat4 mvp = PROJECTION_MATRIX * MODELVIEW_MATRIX;
	vec4 clip = mvp * vec4(VERTEX, 1.0);
	vec4 other = mvp * vec4(CUSTOM0.xyz, 1.0);
	vec2 a = clip.xy / max(clip.w, 1e-4);
	vec2 b = other.xy / max(other.w, 1e-4);
	vec2 dir = (b - a) * VIEWPORT_SIZE;
	dir = length(dir) > 1e-5 ? normalize(dir) : vec2(1.0, 0.0);
	vec2 n = vec2(-dir.y, dir.x);
	clip.xy += n * CUSTOM0.w * width_px / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
	v_side = UV.y;
	v_along = UV.x;
}

void fragment() {
	float edge = smoothstep(0.0, 0.9, 1.0 - abs(v_side));
	float f = fract(v_along / dash_length - TIME * flow_speed / dash_length);
	float dash = smoothstep(0.0, 0.2, f) * (1.0 - smoothstep(0.3, 0.55, f));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * (0.6 + 0.4 * dash) * edge;
}
