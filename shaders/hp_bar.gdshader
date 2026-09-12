shader_type canvas_item;

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	float frac = custom.r;
	vec3 col = vec3(0.1);
	if (UV.x < frac) {
		col = mix(vec3(0.8, 0.1, 0.1), vec3(0.2, 0.8, 0.2), frac);
	}
	COLOR = vec4(col, 1.0);
}
