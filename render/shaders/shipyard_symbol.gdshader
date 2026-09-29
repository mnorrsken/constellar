// Shipyard symbol beside a star on the map: a hollow lime triangle, screen-sized,
// drawn a few pixels up and right of the star, and faded out when the
// camera is far away so the zoomed-out map stays clean. COLOR = its colour.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform float size_px = 26.0;
uniform vec2 offset_px = vec2(28.0, 21.0);
// Camera distance (ly) where the symbols start to fade, and where they are gone.
uniform float fade_near = 28.0;
uniform float fade_far = 42.0;

varying vec4 v_color;
varying float v_fade;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float depth = max(-center.z, 0.01);
	// abs(): the projection can flip Y, which would put the symbol on the
	// wrong side of the star.
	float px = 2.0 * depth / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	POSITION = PROJECTION_MATRIX * (center + vec4((VERTEX.xy * size_px + offset_px) * px, 0.0, 0.0));
	v_color = COLOR;
	v_fade = 1.0 - smoothstep(fade_near, fade_far, depth);
}

void fragment() {
	// QuadMesh UV.y runs top to bottom on screen: flip so +p.y is up.
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	// Upward triangle: inside all three edges (signed distances).
	float d = min(p.y + 0.62, (0.72 - p.y - 1.73 * abs(p.x)) / 2.0);
	float w = max(fwidth(d), 1e-4);
	// Only a band inside the edge: a hollow outline.
	float band = 0.16;
	float shape = smoothstep(-w, w, d) * (1.0 - smoothstep(band - w, band + w, d));
	// A dark rim on both sides keeps it readable over lanes and glow.
	float edge = smoothstep(-w, w, d + 0.08) * (1.0 - smoothstep(band + 0.08 - w, band + 0.08 + w, d));
	ALBEDO = v_color.rgb * shape * 1.3;
	ALPHA = max(shape, edge * 0.6) * v_color.a * v_fade;
}
