shader_type canvas_item;

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	float id = round(custom.r * 4.0);

	if (id == 4.0) {
		// shield: short thick bar near the rim only
		if (UV.x < 0.45 && abs(UV.y - 0.5) < 0.5) {
			COLOR = vec4(vec3(0.35, 0.25, 0.1), 1.0);
		} else {
			discard;
		}
	} else {
		bool shaft = abs(UV.y - 0.5) < 0.18;
		if (id == 0.0) {
			// dagger: shorter shaft
			shaft = shaft && UV.x < 0.7;
		}
		bool head = id == 3.0 && UV.x > 0.7 && abs(UV.y - 0.5) < 0.5;

		if (shaft || head) {
			COLOR = vec4(vec3(0.15), 1.0);
		} else {
			discard;
		}
	}
}
