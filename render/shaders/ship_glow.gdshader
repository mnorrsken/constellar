// Glowing ship parts (rings, bands, engine discs) that pulse in a pattern
// (ship_blink.gdshaderinc). `wave` shifts the phase along the mesh's Z, so
// a pulse runs along the ship.
shader_type spatial;

#include "res://render/shaders/ship_blink.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0);
uniform float energy = 2.0;
uniform int pattern = 0;
uniform float period = 1.0;
uniform float phase = 0.0;
uniform float wave = 0.0;
uniform float low = 0.0;               // the dimmest it gets

varying float z;

void vertex() {
	z = VERTEX.z;
}

void fragment() {
	ALBEDO = vec3(0.0);
	EMISSION = color * energy * mix(low, 1.0, blink(pattern, period, phase - z * wave, TIME));
}
