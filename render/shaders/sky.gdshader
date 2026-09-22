// Background sky: faint far-away stars and the Milky Way. World +Y is
// galactic north, so the band follows the horizon and the bulge sits toward
// +X (the galactic centre), as seen from the real neighbourhood of Sol.
shader_type sky;

uniform vec3 base_color : source_color = vec3(0.012, 0.018, 0.04);
uniform vec3 band_color : source_color = vec3(0.05, 0.065, 0.11);
uniform vec3 bulge_color : source_color = vec3(0.11, 0.08, 0.06);

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

float stars(vec3 d, float scale, float density) {
	vec3 q = d * scale;
	vec3 cell = floor(q);
	float h = hash(cell);
	float s = 1.0 - smoothstep(0.0, 0.16, length(fract(q) - 0.5));
	return s * step(1.0 - density, h) * (0.35 + 0.65 * hash(cell + 3.1));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float n = fbm(d * 5.0 + 1.3);
	float band = exp(-pow(d.y / (0.13 + 0.05 * n), 2.0));
	float bulge = pow(max(d.x, 0.0), 4.0);
	vec3 col = base_color;
	col += band_color * band * (0.45 + 0.9 * n);
	col += bulge_color * band * bulge * (0.6 + 0.8 * n);
	// Dark dust lanes along the band.
	col *= 1.0 - 0.45 * band * smoothstep(0.55, 0.75, fbm(d * 11.0 + 7.0));
	float s = stars(d, 170.0, 0.012) + stars(d, 320.0, 0.02 + 0.05 * band) * 0.6;
	col += vec3(0.75, 0.8, 1.0) * s * 0.55;
	COLOR = col;
}
