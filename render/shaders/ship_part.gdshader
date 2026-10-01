// Ship parts (cargo modules): paint with optional ribs along local Z
// (corrugation or seam lines), rows of lit windows round the local Y axis,
// lumpy ore colour and grime. Works in the mesh's own space, so boxes,
// cylinders and capsules need no special UVs (ShipModel._part).
shader_type spatial;

uniform vec3 albedo : source_color = vec3(0.6);
uniform float metallic = 0.3;
uniform float roughness = 0.55;
uniform float rib = 0.0;            // rib spacing along local Z, 0 = none
uniform float rib_line = 0.0;       // 0 = corrugation, 1 = thin seam lines
uniform float rocky = 0.0;          // 0..1
uniform float grime = 0.0;          // 0..1
uniform vec3 window_color : source_color = vec3(1.0, 0.82, 0.5);
uniform float windows = 0.0;        // windows round the local Y axis, 0 = none
uniform float window_rows = 2.0;
uniform float window_half = 0.5;    // half length (local Y) of the window band

varying vec3 lp;
varying vec3 ln;

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

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 col = albedo;
	float rough = roughness;
	if (rib > 0.0) {
		float f = fract(lp.z / rib);
		float w = fwidth(lp.z / rib);
		float wave = 0.8 + 0.2 * abs(sin(f * PI));
		float line = 1.0 - 0.4 * (1.0 - smoothstep(0.02, 0.02 + w * 1.5, min(f, 1.0 - f)));
		float r = mix(wave, line, rib_line);
		// Fade when the ribs get finer than a pixel; none on the end faces.
		r = mix(r, 0.9, smoothstep(0.3, 0.6, w));
		col *= mix(1.0, r, 1.0 - abs(ln.z));
	}
	if (rocky > 0.0) {
		float n = noise(lp.xz * 9.0 + lp.y * 3.0) * 0.6 + noise(lp.xz * 27.0) * 0.4;
		col = mix(col, col * (0.5 + n), rocky);
		rough = mix(rough, 0.95, rocky);
	}
	float g = noise(lp.xz * 3.0 + lp.y * 2.0) * noise(lp.zy * 8.0);
	col = mix(col, col * vec3(0.5, 0.45, 0.38), grime * smoothstep(0.15, 0.5, g));
	vec3 emit = vec3(0.0);
	if (windows > 0.0 && abs(ln.y) < 0.5) {
		float a = atan(lp.z, lp.x) / TAU + 0.5;
		float cy = (lp.y / window_half * 0.5 + 0.5) * window_rows;
		vec2 c = vec2(fract(a * windows), fract(cy));
		float lit = step(0.3, c.x) * step(c.x, 0.7) * step(0.25, c.y) * step(c.y, 0.75)
			* step(0.0, cy) * step(cy, window_rows);
		lit *= step(0.2, hash(vec2(floor(a * windows), floor(cy))));  // a few dark cabins
		emit = window_color * 1.8 * lit;
		col = mix(col, vec3(0.04), lit);
	}
	ALBEDO = col;
	METALLIC = metallic;
	ROUGHNESS = rough;
	EMISSION = emit;
}
