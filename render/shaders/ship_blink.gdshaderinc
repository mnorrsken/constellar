// Light patterns shared by the ship light shaders (ShipModel.PATTERNS):
// 0 steady, 1 flash, 2 breathe, 3 flicker, 4 heartbeat. 0..1.
float blink_hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float blink(int pattern, float period, float phase, float t) {
	float x = fract(t / period + phase);
	if (pattern == 1) {
		return smoothstep(0.0, 0.02, x) * (1.0 - smoothstep(0.06, 0.1, x));
	} else if (pattern == 2) {
		return 0.3 + 0.7 * (0.5 + 0.5 * sin(x * TAU));
	} else if (pattern == 3) {
		float n = blink_hash(floor(t * 12.0) + phase * 131.0);
		return n < 0.12 ? 0.1 : 0.7 + 0.3 * n;
	} else if (pattern == 4) {
		float a = smoothstep(0.0, 0.02, x) * (1.0 - smoothstep(0.05, 0.09, x));
		float b = smoothstep(0.14, 0.16, x) * (1.0 - smoothstep(0.19, 0.24, x));
		return max(a, b * 0.8);
	}
	return 1.0;
}
