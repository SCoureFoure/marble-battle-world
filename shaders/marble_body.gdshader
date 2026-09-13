shader_type canvas_item;

varying vec4 custom;
varying float glow;

void vertex() {
	custom = INSTANCE_CUSTOM;
	glow = COLOR.r;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float d = length(p);
	if (d > 1.0) {
		discard;
	}
	vec3 col = custom.rgb;
	// dull low-spin marbles toward grey
	float dull = clamp((0.35 - glow) / 0.35, 0.0, 1.0);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma * 0.7), 0.6 * dull);
	// rim highlight driven by spin glow (replaces the fixed rim lighten)
	float rim = smoothstep(0.80, 1.0, d);
	col = mix(col, mix(col, vec3(1.0), 0.1 + 0.6 * glow), rim);
	// rank ring / captain marker (unchanged)
	bool cap = custom.a >= 2.0;
	float rank = cap ? custom.a - 2.0 : custom.a;
	float ring = step(0.55, d) * step(d, 0.65);
	col = mix(col, vec3(0.08), ring * rank);
	if (cap && d < 0.25) { col = vec3(0.05); }
	COLOR = vec4(col, 1.0);
}
