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
	int kind = int(custom.r * 2.0 + 0.5);
	vec3 col;
	float a;
	if (kind == 0) {
		// warm orange ring, band 0.6..1.0
		col = vec3(1.0, 0.45, 0.05);
		a = step(0.6, d);
	} else if (kind == 1) {
		// dark grey ring, band 0.8..1.0
		col = vec3(0.2, 0.2, 0.2);
		a = step(0.8, d) * 0.7;
	} else {
		// soft cyan disc
		col = vec3(0.2, 0.85, 1.0);
		a = (1.0 - smoothstep(0.0, 1.0, d)) * 0.9;
	}
	COLOR = vec4(col, a * custom.g);
}
