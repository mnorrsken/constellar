// Background sky: the Milky Way, faded, and faint far-away stars.
// The Milky Way is ESO's all-sky photo (assets/sky/milky_way.jpg), an
// equirectangular map in galactic coordinates: the galactic centre in the
// middle, longitude rising to the left, north up. World +Y is galactic north
// and +X points at the galactic centre (GalaxyCoords), so the band follows
// the grid plane and the bulge sits toward +X, as seen from Sol.
shader_type sky;

uniform sampler2D milky_way : source_color, filter_linear_mipmap, repeat_enable, hint_default_black;
uniform vec3 base_color : source_color = vec3(0.012, 0.018, 0.04);
// How much of the photo shows: low keeps it a faded backdrop.
uniform float strength = 0.2;
// The photo is a soft glow (a blurred mip level) with this much of the
// sharp photo, its stars and dust, on top.
uniform float blur_lod = 3.0;
uniform float detail = 0.35;
// Photo brightness below this is dropped: its dark sky and faintest stars.
uniform float black_point = 0.04;
// Less colour, tinted toward the map's ink blue.
uniform float saturation = 0.6;
uniform vec3 tint : source_color = vec3(0.8, 0.88, 1.0);

float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float stars(vec3 d, float scale, float density) {
	vec3 q = d * scale;
	vec3 cell = floor(q);
	float h = hash(cell);
	float s = 1.0 - smoothstep(0.0, 0.16, length(fract(q) - 0.5));
	return s * step(1.0 - density, h) * (0.35 + 0.65 * hash(cell + 3.1));
}

// Galactic longitude/latitude of a world direction -> the photo's UV.
// (Sampled at fixed mip levels, so the wrap at longitude 180 leaves no seam.)
vec2 galactic_uv(vec3 d) {
	vec3 g = vec3(d.x, -d.z, d.y);
	float l = atan(g.y, g.x);
	float b = asin(clamp(g.z, -1.0, 1.0));
	return vec2(0.5 - l / TAU, 0.5 - b / PI);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = galactic_uv(d);
	vec3 photo = mix(textureLod(milky_way, uv, blur_lod).rgb, textureLod(milky_way, uv, 0.0).rgb, detail);
	photo = max(photo - black_point, vec3(0.0)) / (1.0 - black_point);
	float grey = dot(photo, vec3(0.299, 0.587, 0.114));
	photo = mix(vec3(grey), photo, saturation) * tint;
	vec3 col = base_color + photo * strength;
	float s = stars(d, 170.0, 0.012) + stars(d, 320.0, 0.02) * 0.6;
	col += vec3(0.75, 0.8, 1.0) * s * 0.55;
	COLOR = col;
}
