// Star glow billboard, one MultiMesh instance per star.
// INSTANCE_CUSTOM: x = world diameter (ly), y = HDR brightness,
//                  z = minimum on-screen diameter (px). COLOR = star colour.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

varying vec3 v_color;
varying float v_bright;

void vertex() {
	vec4 center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float depth = max(-center.z, 0.01);
	// World units per screen pixel at this depth.
	float px = 2.0 * depth / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float size = max(INSTANCE_CUSTOM.x, INSTANCE_CUSTOM.z * px);
	POSITION = PROJECTION_MATRIX * (center + vec4(VERTEX.xy * size, 0.0, 0.0));
	v_color = COLOR.rgb;
	v_bright = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float core = 1.0 - smoothstep(0.0, 0.34, r);
	float halo = exp(-r * r * 5.0) * (1.0 - smoothstep(0.75, 1.0, r));
	vec3 col = mix(v_color, vec3(1.0), core * 0.85) * v_bright;
	ALBEDO = col;
	ALPHA = clamp(halo + core, 0.0, 1.0);
}
