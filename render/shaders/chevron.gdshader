// Ship marker: a screen-sized chevron pointing along the ship's heading.
// INSTANCE_CUSTOM.xyz = heading in world space (zero = docked, points up),
// INSTANCE_CUSTOM.w = 1 for the selected ship. COLOR = company colour.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform float size_px = 20.0;

varying vec3 v_color;
varying float v_selected;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float depth = max(-center.z, 0.01);
	float px = 2.0 * depth / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	vec2 up = (MODELVIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xy;
	up = length(up) > 1e-5 ? normalize(up) : vec2(0.0, 1.0);
	vec2 right = vec2(up.y, -up.x);
	vec2 v = right * VERTEX.x + up * VERTEX.y;
	float size = size_px * (1.0 + 0.35 * INSTANCE_CUSTOM.w);
	POSITION = PROJECTION_MATRIX * (center + vec4(v * size * px, 0.0, 0.0));
	v_color = COLOR.rgb;
	v_selected = INSTANCE_CUSTOM.w;
}

void fragment() {
	// QuadMesh UV.y grows toward +VERTEX.y, so the tip (+p.y) points along the heading.
	vec2 p = vec2(UV.x * 2.0 - 1.0, UV.y * 2.0 - 1.0);
	float ax = abs(p.x);
	// Outer triangle minus a lower triangle = a "^" chevron.
	float d_outer = (0.85 - 1.9 * ax - p.y) / 2.15;
	float d_base = p.y + 0.7;
	float d_notch = (p.y - (0.2 - 1.9 * ax)) / 2.15;
	float d = min(min(d_outer, d_base), d_notch);
	float w = max(fwidth(d), 1e-4);
	float shape = smoothstep(-w, w, d);
	float halo = exp(-dot(p, p) * 2.5) * (0.18 + 0.25 * v_selected);
	ALBEDO = mix(v_color, vec3(1.0), 0.15 + 0.25 * v_selected);
	ALPHA = clamp(shape + halo * (1.0 - shape), 0.0, 1.0);
}
