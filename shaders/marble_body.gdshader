shader_type canvas_item;

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float d = length(p);
	if (d > 1.0) {
		discard;
	}
	vec3 col = custom.rgb;
	// rim highlight (upper-left) and dark edge
	float rim = smoothstep(0.80, 1.0, d);
	col = mix(col, col * 0.55, rim);
	float hl = smoothstep(0.55, 0.0, length(p - vec2(-0.35, -0.35)));
	col = mix(col, vec3(1.0), hl * 0.35);
	// rank ring / captain marker
	bool cap = custom.a >= 2.0;
	float rank = cap ? custom.a - 2.0 : custom.a;
	float ring = step(0.55, d) * step(d, 0.65);
	col = mix(col, vec3(0.08), ring * rank);
	if (cap && d < 0.25) { col = vec3(0.05); }
	COLOR = vec4(col, 1.0);
}
