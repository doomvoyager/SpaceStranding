shader_type spatial;
// A light pillar standing on a route stop.
//
// Additive and unshaded, because it is light in the air rather than a surface:
// it has to read against the bright terminator sky and against dark nightward
// ground without being lit by either.
//
// `depth_draw_never` so two beams never punch holes in each other, and
// `cull_disabled` because a billboard has no back worth hiding.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 beam_color : source_color = vec4(0.55, 1.0, 0.72, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.25;
// Fraction of the half-width spent fading out sideways. A hard-edged beam reads
// as a wall; a soft one reads as light.
uniform float edge_softness : hint_range(0.02, 1.0) = 0.55;
// How much of the beam has faded by the top. Below 1.0 the beam still has
// substance where it leaves the frame, which is what keeps it readable from far
// away — a beam that fades to nothing is only visible near its base, which is
// the one place you do not need it.
uniform float top_fade : hint_range(0.0, 1.0) = 0.85;
// Extra brightness in the first stretch above the ground, so the beam has a
// foot and does not look like it is hanging.
uniform float base_glow : hint_range(0.0, 3.0) = 1.1;
uniform float base_height : hint_range(0.01, 0.6) = 0.12;
// Fraction of the beam spent fading out at the very top.
uniform float top_taper : hint_range(0.02, 0.8) = 0.35;

void vertex() {
	// Fixed-Y billboard: turn to face the camera but stay upright. A full
	// billboard lies over as you look down at it from a rise, which is exactly
	// when you are trying to spot the thing.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
}

void fragment() {
	// QuadMesh UV has y = 0 at the top, so this is height above the base.
	float up = 1.0 - UV.y;

	float across = abs(UV.x - 0.5) * 2.0;
	float sides = 1.0 - smoothstep(1.0 - edge_softness, 1.0, across);

	float height = mix(1.0, 1.0 - top_fade, up);
	// And taper to nothing over the last stretch. Without this the beam keeps
	// whatever `top_fade` left it with all the way to the quad's edge and ends
	// in a flat cut — which reads as a bar standing in the world rather than as
	// light going up out of it.
	height *= 1.0 - smoothstep(1.0 - top_taper, 1.0, up);
	float foot = base_glow * (1.0 - smoothstep(0.0, base_height, up));

	ALBEDO = beam_color.rgb * intensity;
	ALPHA = clamp(sides * (height + foot), 0.0, 1.0) * beam_color.a;
}
