shader_type canvas_item;

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	float id = round(custom.r * 4.0);
	float flash = custom.g;
	float head_u = custom.b;
	float aspect = custom.a;

	// UV.x: 0 at the marble centre, 1 at the far edge of the hit circle.
	// UV.y: 0..1 across the quad's thickness, 0.5 = the weapon centreline.
	float u = UV.x;
	float v = UV.y;

	// Coords centred on the hit-circle centre, aspect-corrected so that
	// d <= 1.0 is exactly the hit circle (radius = half the quad height):
	// the visible head IS the hitbox.
	float cx = 2.0 * aspect * (u - head_u);
	float cy = 2.0 * (v - 0.5);
	float d = length(vec2(cx, cy));

	vec3 head_fill = mix(vec3(0.80, 0.82, 0.86), vec3(1.0, 0.55, 0.1), flash);
	vec3 outline = vec3(0.08, 0.06, 0.06);
	vec3 shaft_col = vec3(0.15, 0.12, 0.10);

	bool is_shield = id >= 3.5;

	// Shaft: from the marble rim to the head, thin dark bar along the
	// centreline. UNDECIDED: the exact rim ratio 1/(WEAPON_REACH+WEAPON_HIT_R)
	// is not recoverable from head_u/aspect alone (they only encode the
	// REACH:HIT_R ratio, not the absolute values), so the rim start is a
	// fixed small approximation rather than the literal marble-radius point.
	float rim_u = 0.06;
	bool shaft = (!is_shield) && u > rim_u && u < head_u && abs(v - 0.5) < 0.10;

	bool head = false;
	if (id < 0.5) {
		// dagger: short leaf blade
		head = d < 1.0 && abs(cy) < 0.55 * sqrt(max(0.0, 1.0 - cx * cx));
	} else if (id < 1.5) {
		// sword: long blade from rim to a point at the tip
		float taper = mix(0.55, 0.0, clamp((cx + 1.0) * 0.5, 0.0, 1.0));
		head = d < 1.0 && abs(cy) < taper;
	} else if (id < 2.5) {
		// spear: diamond point on a thin pole
		head = d < 1.0 && abs(cy) < (1.0 - abs(cx)) * 0.6;
	} else if (id < 3.5) {
		// axe: crescent blade on one side
		head = d < 1.0 && cy > -0.15 && length(vec2(cx, cy - 0.35)) > 0.72;
	} else {
		// shield: thick arc across the head circle, no shaft
		head = d < 1.0 && d > 0.5 && cx > -0.6;
	}

	if (head) {
		float edge = smoothstep(0.75, 1.0, d);
		COLOR = vec4(mix(head_fill, outline, edge), 1.0);
	} else if (shaft) {
		COLOR = vec4(shaft_col, 1.0);
	} else {
		discard;
	}
}
