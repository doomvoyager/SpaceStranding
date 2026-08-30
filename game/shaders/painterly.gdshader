shader_type spatial;

// Engine ambient is disabled and replaced with the fill_* uniforms below. It is
// added after light() as a smooth gradient, which completely erases the banding
// on smooth-normal surfaces — measured: terrain rendered as an untouched CG
// gradient with this on. Cost: WorldEnvironment ambient no longer reaches
// painterly surfaces, so fill lives on the material instead. Drop this render
// mode to hand control back.
render_mode ambient_light_disabled;

// Painterly surface shader for Vesper c.
//
// Replaces PBR response with the three things Mac's concept paintings actually
// do: banded values, hue-shifted shadow, and rectangular brush stamps. There is
// no specular anywhere — metal reads through value and rim light, exactly as it
// does in the paintings.
//
// Deliberately generic so terrain and hulls share one shader. Per-surface
// differences live in the .tres materials in res://materials/, not in forks of
// this file.

// --- Base -----------------------------------------------------------------

group_uniforms base;
uniform vec4 albedo_color : source_color = vec4(0.34, 0.24, 0.19, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform bool use_albedo_texture = false;
uniform float albedo_uv_scale = 0.06;

// --- Banded lighting ------------------------------------------------------

group_uniforms banding;
// How many discrete values the lit surface is allowed. 3 is the painting.
uniform int band_count : hint_range(2, 8) = 3;
// 0 = hard steps (most painterly), 1 = smooth PBR falloff (no banding at all).
uniform float band_softness : hint_range(0.0, 1.0) = 0.08;
// Spreads the terminator. Load-bearing here: the star sits ~5 degrees up, so
// most of the map is at grazing incidence and unwrapped lambert bunches every
// band into a thin strip.
uniform float light_wrap : hint_range(0.0, 1.0) = 0.45;

// --- Shadow colour --------------------------------------------------------

group_uniforms shadow;
// Multiplied into the shadowed end of the ramp. Keep it cool against the star.
uniform vec4 shadow_tint : source_color = vec4(0.30, 0.34, 0.58, 1.0);
// 0 = shadow keeps the surface hue and just darkens.
// 1 = shadow abandons the surface hue entirely for shadow_tint.
uniform float shadow_hue_shift : hint_range(0.0, 1.0) = 0.45;

// --- Brush stamps ---------------------------------------------------------

group_uniforms brush;
// Metres per stamp cell at brush_ref_distance. Cells scale in power-of-two
// steps with distance so their *screen* size stays roughly constant.
uniform float brush_scale = 0.55;
// Distance at which brush_scale applies, in metres.
uniform float brush_ref_distance = 11.0;
// >1 makes stamps wider than tall, which is how they read in the paintings.
uniform float brush_aspect : hint_range(0.2, 5.0) = 2.4;
// How much the stamps push value around.
uniform float brush_strength : hint_range(0.0, 1.0) = 0.14;
// Hue the brighter stamps drift toward. The teal in the red dirt.
uniform vec4 brush_tint : source_color = vec4(0.22, 0.45, 0.44, 1.0);
uniform float brush_hue_amount : hint_range(0.0, 1.0) = 0.22;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

// --- Fill -----------------------------------------------------------------

group_uniforms fill;
// Stands in for engine ambient, which is disabled above. Keep it cool: this is
// the skylight opposing the red star, and it is what stops shadows going black.
uniform vec4 fill_color : source_color = vec4(0.30, 0.36, 0.60, 1.0);
uniform float fill_strength : hint_range(0.0, 2.0) = 0.42;

// --- Rim ------------------------------------------------------------------

group_uniforms rim;
// Always-on edge light. Unlike a real fresnel this survives into shadow, which
// is what keeps hull silhouettes reading against a dark sky.
uniform vec4 rim_color : source_color = vec4(0.95, 0.55, 0.42, 1.0);
uniform float rim_strength : hint_range(0.0, 4.0) = 0.35;
uniform float rim_power : hint_range(0.5, 12.0) = 3.5;

// --- Slope tint (terrain only) --------------------------------------------

group_uniforms slope;
// Colour for near-vertical faces. Zero the amount on anything that is not
// ground or it will tint the sides of props.
uniform vec4 slope_color : source_color = vec4(0.46, 0.30, 0.26, 1.0);
uniform float slope_amount : hint_range(0.0, 1.0) = 0.0;
uniform float slope_sharpness : hint_range(0.5, 8.0) = 2.5;

varying vec3 world_position;
varying vec3 world_normal;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


// One axis of stamps: quantise to a rectangular grid and hash the cell id.
// Rectangular cells are the whole trick — organic brushwork needs a flow field
// and swims under camera motion, blocky patches hold still.
float stamp_plane(vec2 uv, float scale) {
	vec2 cell = vec2(uv.x, uv.y * brush_aspect) / max(scale, 0.001);
	return hash21(floor(cell));
}


float stamp_triplanar(vec3 wpos, vec3 wnrm, float scale) {
	vec3 w = pow(abs(wnrm), vec3(triplanar_sharpness));
	w /= max(w.x + w.y + w.z, 0.0001);
	return stamp_plane(wpos.zy, scale) * w.x
		 + stamp_plane(wpos.xz, scale) * w.y
		 + stamp_plane(wpos.xy, scale) * w.z;
}


void fragment() {
	world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	vec3 base = albedo_color.rgb;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, UV * albedo_uv_scale).rgb;
	}

	// Flatter ground vs steeper walls. No-op unless slope_amount is dialled up.
	if (slope_amount > 0.0) {
		float steep = pow(1.0 - clamp(world_normal.y, 0.0, 1.0), slope_sharpness);
		base = mix(base, slope_color.rgb, steep * slope_amount);
	}

	// Stamp cells are world-locked so they never swim under camera motion, but
	// a fixed world size aliases into moire the moment cells drop below a pixel
	// — which is what the first pass did across every mid-distance dune. Walking
	// the cell size up a power-of-two ladder with distance keeps them at a
	// roughly constant size on screen, and cross-fading adjacent rungs hides
	// the switch. World-locked within a rung, so still no swimming.
	float view_dist = max(length(VERTEX), 0.001);
	float rung = log2(view_dist / max(brush_ref_distance, 0.001));
	float rung_floor = floor(rung);
	float near_scale = brush_scale * exp2(rung_floor);
	float stamp = mix(
		stamp_triplanar(world_position, world_normal, near_scale),
		stamp_triplanar(world_position, world_normal, near_scale * 2.0),
		rung - rung_floor
	);

	float signed_stamp = stamp * 2.0 - 1.0;
	base *= 1.0 + signed_stamp * brush_strength;
	// Only the lighter stamps pick up the accent hue, which keeps the tint from
	// flattening into an overall colour cast.
	base = mix(base, brush_tint.rgb, max(signed_stamp, 0.0) * brush_hue_amount);

	ALBEDO = base;

	// No specular anywhere. There is not one highlight in any of the paintings.
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;

	// Albedo-modulated so dark materials stay dark, the way real ambient behaves.
	EMISSION += ALBEDO * fill_color.rgb * fill_strength;

	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION += rim_color.rgb * rim * rim_strength;

	// No ambient dial here on purpose: AMBIENT_LIGHT is not a built-in in
	// fragment() or light() on 4.7.1 — measured, both fail to compile. Scene
	// ambient passes through untouched, so WorldEnvironment stays the one place
	// it is tuned. Killing it would need render_mode ambient_light_disabled and
	// a hand-rolled fill term.
}


void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	// Wrapped diffuse: light_wrap 0 is clamped lambert, 1 is half-lambert.
	float wrapped = clamp((ndl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);

	// Quantise the terminator ONLY, then apply the shadow term smoothly on top.
	//
	// Folding ATTENUATION in before the floor() is tempting — it puts cast
	// shadows on the same value steps as the terminator — but it thresholds the
	// soft-shadow penumbra, which carries Godot's per-pixel PCSS filter noise.
	// Measured: that turns normally-invisible filter dither into a loud ordered
	// stipple all along every shadow edge. Banding amplifies any noise you
	// quantise. Keep the noisy signal on the smooth side of the floor().
	float t = clamp(wrapped, 0.0, 0.999);

	float bands = float(band_count);
	float stepped = floor(t * bands) / max(bands - 1.0, 1.0);
	float shade = clamp(mix(stepped, t, band_softness), 0.0, 1.0) * ATTENUATION;

	// Shadow end of the ramp: darkened albedo, optionally dragged off its own
	// hue toward shadow_tint. That hue drag is what puts teal in the red dirt.
	vec3 luma = vec3(dot(ALBEDO, vec3(0.2126, 0.7152, 0.0722)));
	vec3 shadow_col = mix(ALBEDO * shadow_tint.rgb, luma * shadow_tint.rgb, shadow_hue_shift);
	vec3 lit_col = ALBEDO * LIGHT_COLOR;

	DIFFUSE_LIGHT += mix(shadow_col, lit_col, shade);
	// SPECULAR_LIGHT deliberately untouched.
}
