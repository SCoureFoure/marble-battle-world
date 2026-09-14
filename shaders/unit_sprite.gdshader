shader_type canvas_item;

// Unit sprites from a UnitAtlas texture: atlas_cols x atlas_rows character
// sheets, each 3 walk frames x 4 facings of 16x16 frames.
// INSTANCE_CUSTOM: r = atlas slot, g = facing row (0 toward camera, 1 left,
// 2 right, 3 away), b = walk frame column (0..2), a = alpha.

uniform float atlas_cols = 4.0;
uniform float atlas_rows = 4.0;
uniform bool flip_y = true;   // QuadMesh UVs run bottom-up in 2D; flip so sheets draw upright

varying vec4 custom;

void vertex() {
	custom = INSTANCE_CUSTOM;
}

void fragment() {
	float slot = floor(custom.r + 0.5);
	float facing = floor(custom.g + 0.5);
	float frame = floor(custom.b + 0.5);
	vec2 uv = UV;
	if (flip_y) {
		uv.y = 1.0 - uv.y;
	}
	// keep half a texel inside the frame so nearest sampling never bleeds
	uv = clamp(uv, vec2(0.5 / 16.0), vec2(1.0 - 0.5 / 16.0));
	vec2 cell = vec2(mod(slot, atlas_cols), floor(slot / atlas_cols));
	vec2 frame_cell = vec2(cell.x * 3.0 + frame, cell.y * 4.0 + facing);
	vec2 atlas_frames = vec2(atlas_cols * 3.0, atlas_rows * 4.0);
	vec4 c = texture(TEXTURE, (frame_cell + uv) / atlas_frames);
	COLOR = vec4(c.rgb, c.a * custom.a);
}
