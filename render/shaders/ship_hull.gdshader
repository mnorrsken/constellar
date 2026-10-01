// Ship hull plating: staggered panels with dark seams, a little brightness
// spread per panel, optional mismatched patches and grime. UV is in model
// units (around the hull section, along the ship), so panels are the same
// size on every ship (ShipModel._loft).
shader_type spatial;

uniform vec3 albedo : source_color = vec3(0.56, 0.6, 0.66);
uniform float metallic = 0.55;
uniform float roughness = 0.45;
uniform vec2 panel = vec2(0.9, 1.4);    // panel size: around, along
uniform float seam = 0.025;             // seam width in model units
uniform float seam_dark = 0.45;
uniform float variation = 0.05;         // brightness spread per panel
uniform float grime = 0.0;              // 0..1
uniform vec3 patch_color : source_color = vec3(0.5, 0.3, 0.2);
uniform float patches = 0.0;            // share of panels in patch_color

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV / panel;
	p.x += floor(p.y) * 0.5;  // stagger the rows like plating
	vec2 cell = floor(p);
	vec2 edge = min(fract(p), 1.0 - fract(p)) * panel;  // distance to a seam, model units
	vec2 w = fwidth(UV);
	float line = 1.0 - min(smoothstep(seam - w.x, seam + w.x, edge.x), smoothstep(seam - w.y, seam + w.y, edge.y));
	// Seams fade out when they get thinner than a pixel.
	line *= 1.0 - smoothstep(seam * 0.6, seam * 1.5, max(w.x, w.y));
	float h = hash(cell);
	vec3 col = albedo * (1.0 + (h - 0.5) * 2.0 * variation);
	if (hash(cell + 17.3) < patches) {
		col = mix(col, patch_color, 0.75);
	}
	float g = noise(UV * 2.5) * noise(UV * 9.0 + 3.1);
	float dirt = grime * smoothstep(0.15, 0.55, g);
	col = mix(col, col * vec3(0.45, 0.4, 0.34), dirt);
	col *= 1.0 - line * seam_dark;
	ALBEDO = col;
	METALLIC = metallic;
	ROUGHNESS = clamp(roughness + line * 0.25 + dirt * 0.35, 0.0, 1.0);
}
