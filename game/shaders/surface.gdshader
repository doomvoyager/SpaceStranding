shader_type spatial;
// The project's one surface shader: ground, rock, crate, hull.
//
// **Plain lighting on purpose.** This replaced `painterly.gdshader`
// (2026-09-03), which carried a stylised look — banded terminator, hue-shifted
// shadows, world-locked brush stamps, rim and fill terms and a custom `light()`
// — built as a look-dev experiment. Mac froze art direction while the style is
// still being decided, so the experiment is gone rather than parked: it was
// 416 lines of opinion nobody is currently building against, and leaving it in
// place would have meant every terrain change dragging it along.
//
// What is left is albedo and two overlays, and the two overlays are the entire
// reason this is a shader at all rather than a StandardMaterial3D. Both are
// gameplay:
//
//   - **Lattice coverage**, painted on the ground. See [[The-Lattice]].
//   - **The scan pulse**, on ground and rock. See [[Scanner]].
//
// Godot's own lighting handles everything else, which is what "simple" buys:
// no banding, no hue-shifted shadows, no brush stamps, no `light()` at all -
// scene ambient is replaced by a flat fill rather than reinterpreted.
//
// **Ambient is rolled by hand, and that is not a style choice.** Vesper c's sky
// is nearly black — `sky_top_color` 0.07 over a 0.09 ground hemisphere — so
// Godot's sky-sourced ambient contributes almost nothing, and the star sits 5°
// above the horizon, which puts N·L at about 0.09 on flat ground. Delete the
// fill term and the near ground renders **black**: measured, by capturing this
// scene with and without it. Raising `ambient_light_energy` instead does not
// work either. At 1.0-1.8 the environment's blue ambient turns red regolith
// violet, and driving it from the sky at 3.0 leaves the foreground where it
// started, because the dark half of the sky is most of what a ground normal
// sees. Both sweeps are in `previews/2026-09-03/`.
//
// So `ambient_light_disabled` and four lines of fill survive from the shader
// this replaced, at the values it used. Everything stylistic did not.

render_mode ambient_light_disabled;

group_uniforms base;
uniform vec4 albedo_color : source_color = vec4(0.34, 0.24, 0.19, 1.0);
// Detail, tiled through UV1 in world metres. Off by default.
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform bool use_albedo_texture = false;
uniform float albedo_uv_scale = 0.06;

// The authored map colour, sampled through UV2, which spans the patch 0..1.
// UV1 tiles hundreds of times across the terrain and cannot carry this.
uniform sampler2D macro_albedo : source_color, hint_default_white;
uniform bool use_macro_albedo = false;
uniform float macro_strength : hint_range(0.0, 1.0) = 1.0;

group_uniforms fill;
// Stands in for scene ambient, which this planet's sky cannot provide.
// Multiplied by ALBEDO so it tints the surface rather than washing over it -
// blue fill on red regolith reads as dark red, which is what an unlit slope
// under a black sky should look like.
uniform vec4 fill_color : source_color = vec4(0.30, 0.36, 0.60, 1.0);
uniform float fill_strength : hint_range(0.0, 2.0) = 0.42;

group_uniforms coverage;
// Lattice coverage. The mask is built by CoverageMap and spans the patch, so
// it is sampled through UV2 exactly like the macro albedo — which also means
// the terrain's world offset is handled for free.
//
// The mask stores 1 well inside coverage falling to 0 at the limit, so the
// boundary is wherever it crosses 0.5.
uniform bool coverage_enabled = false;
uniform sampler2D coverage_mask : hint_default_black;
uniform float coverage_intensity : hint_range(0.0, 1.0) = 1.0;
// Faint, and applied to ALBEDO rather than EMISSION so the ground inside
// coverage still lights and shades like ground. Owning the pixel over a region
// this large would flatten the whole area into a coloured card.
uniform vec4 coverage_fill_color : source_color = vec4(0.36, 0.78, 0.84, 1.0);
uniform float coverage_fill_strength : hint_range(0.0, 1.0) = 0.10;
// The edge does own its pixels — see the note where it is applied.
uniform vec4 coverage_edge_color : source_color = vec4(0.55, 0.95, 1.0, 1.0);
uniform float coverage_edge_glow : hint_range(0.0, 4.0) = 1.5;
// Half-width of the boundary band, in mask units either side of 0.5.
uniform float coverage_edge_width : hint_range(0.01, 0.45) = 0.10;

group_uniforms scan;

// The pulse is a GLOBAL uniform set: one scanner drives every surface in the
// world with a single write, rather than the scanner holding a list of
// materials and keeping it in step with the scene. Declared in project.godot
// under [shader_globals]; written by scanner.gd.
//
// The *tunables* live on scanner.gd as @export vars and are pushed into these,
// because a ShaderMaterial's uniforms carry PROPERTY_USAGE_EDITOR but not
// PROPERTY_USAGE_SCRIPT_VARIABLE — so the F1 panel cannot see them, and a
// number nobody can move while driving is a number nobody will tune.
global uniform vec3 scan_origin;
// Metres the wave front has travelled. Negative means no scan is running, which
// is also the resting state, so the whole block costs one compare when idle.
global uniform float scan_radius;
// Overall opacity, 0 when idle. Fades the grid out after the wave has passed.
global uniform float scan_strength;
global uniform float scan_ring_width;
global uniform float scan_dot_spacing;
global uniform float scan_dot_size;
global uniform vec4 scan_easy_color;
global uniform vec4 scan_hard_color;
// Degrees of slope that read as fully impassable. Measured against what the
// rover can actually climb — see tests/probe_rover_climb.tscn — so red means
// "you will not drive up that" rather than "this is steepish".
global uniform float scan_max_slope;
// How far the pulse can reach at all, and over how many metres it thins out
// before it gets there. Without these the scanned area ends on a hard circle.
global uniform float scan_reach;
global uniform float scan_edge_fade;
// The outline on anything the scan considers an obstacle. Driven off a rim
// term rather than an inverted hull: a second, slightly larger pass would mean
// a second MultiMesh per cell per variant, and draw calls are the thing the
// scatter's whole cell design is spending its budget on.
global uniform vec4 scan_outline_color;
global uniform float scan_outline_strength;
global uniform float scan_outline_power;
// How hard the dots emit. Deliberately a knob: the scene tonemaps with ACES,
// which clamps saturated colour hardest exactly where it is brightest, so a
// grid emitting at 1.5 comes out white and carries no information at all. The
// value that keeps green green is found by looking, not by reasoning — see
// tests/probe_scan_glow.tscn.
global uniform float scan_glow;

// Whether THIS material draws the grid. True on ground and rock; false on
// crates and hulls, where a slope-coloured dot grid would mean nothing. The
// pulse still reaches them — they get tagged by the scanner instead.
uniform bool scan_grid_enabled = false;

varying vec3 world_position;
varying vec3 world_normal;
// Per-instance, from the MultiMesh's custom data: 1 on a rock big enough to be
// an obstacle, 0 otherwise, and 0 on anything that is not a MultiMesh instance
// at all. INSTANCE_CUSTOM only exists in vertex(), hence the varying.
varying float instance_solid;


void vertex() {
	instance_solid = INSTANCE_CUSTOM.r;
}


void fragment() {
	world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	vec3 base = albedo_color.rgb;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, UV * albedo_uv_scale).rgb;
	}
	if (use_macro_albedo) {
		base = mix(base, texture(macro_albedo, UV2).rgb, macro_strength);
	}
	ALBEDO = base;

	// No specular. Kept from the shader this replaced: the surfaces are
	// regolith, powder-coated hull and shipping crates, none of which have a
	// highlight, and a stray one on a 12 km ground plane reads as wet rock.
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;

	EMISSION = ALBEDO * fill_color.rgb * fill_strength;

	// --- Lattice coverage ------------------------------------------------
	float coverage_edge_amount = 0.0;
	if (coverage_enabled && coverage_intensity > 0.0) {
		float cov = texture(coverage_mask, UV2).r;
		float inside = smoothstep(0.5 - coverage_edge_width,
			0.5 + coverage_edge_width, cov);
		coverage_edge_amount = (1.0 - smoothstep(0.0, coverage_edge_width,
			abs(cov - 0.5))) * coverage_intensity;
		ALBEDO = mix(ALBEDO, coverage_fill_color.rgb,
			inside * coverage_fill_strength * coverage_intensity);
	}

	// **The boundary owns both channels rather than adding to either.** Adding
	// a saturated colour over bright ground comes out white, because ACES
	// clamps saturation hardest where it is brightest. Darkening ALBEDO alone
	// is not enough either wherever something earlier has already written
	// EMISSION from the old albedo — which is why this replaces both. The rule
	// cost three separate bugs in this project before it was written down.
	//
	// Placed before the scan block so a pulse paints over the boundary rather
	// than under it: the pulse is the transient, and it should win.
	if (coverage_edge_amount > 0.001) {
		ALBEDO = mix(ALBEDO, vec3(0.0), coverage_edge_amount);
		EMISSION = mix(EMISSION,
			coverage_edge_color.rgb * coverage_edge_glow, coverage_edge_amount);
	}

	// --- Scan overlay ----------------------------------------------------
	if (scan_grid_enabled && scan_strength > 0.0) {
		vec2 ground = world_position.xz;
		float swept = distance(ground, scan_origin.xz);

		// Dots on a fixed world grid, so the pattern is nailed to the terrain
		// and does not swim when the camera moves.
		vec2 cell_uv = ground / max(scan_dot_spacing, 0.01);
		vec2 cell = abs(fract(cell_uv) - 0.5);
		float d = length(cell);
		// Antialias from the derivative of the CONTINUOUS coordinate. Taking it
		// from the fract()ed one puts a seam of full-width blur along every
		// cell boundary, because fract has a discontinuity there.
		float aa = max(length(fwidth(cell_uv)) * 0.7, 0.001);
		float dots = 1.0 - smoothstep(scan_dot_size - aa, scan_dot_size + aa, d);

		// Slope straight off the rendered normal, so it accounts for whatever
		// scale the terrain node is carrying. The player drives the terrain as
		// drawn, so that is the slope worth reporting.
		float slope_deg = degrees(acos(clamp(world_normal.y, 0.0, 1.0)));
		float hardness = clamp(slope_deg / max(scan_max_slope, 1.0), 0.0, 1.0);
		vec3 grid_col = mix(scan_easy_color.rgb, scan_hard_color.rgb, hardness);

		// Everything the wave has already passed keeps the grid; the wave front
		// itself is a brighter ring, which is what makes it read as a pulse
		// going out rather than a radius being resized.
		float inside = 1.0 - smoothstep(scan_radius - 1.0, scan_radius, swept);
		float ring = 1.0 - smoothstep(0.0, max(scan_ring_width, 0.01),
			abs(swept - scan_radius));

		// And it thins out over the last scan_edge_fade metres of its range, so
		// the scanned area ends by running out rather than by being cut.
		float edge = 1.0 - smoothstep(
			scan_reach - max(scan_edge_fade, 0.01), scan_reach, swept);
		inside *= edge;
		ring *= edge;

		// Same rule as the coverage edge: punch the surface out under the dot
		// and put the colour in EMISSION, so a green dot is green whatever it
		// is standing on. Additive over ferocious red came out yellow.
		float on = dots * inside * scan_strength;
		float front = ring * ring * scan_strength;
		float paint = clamp(on + front * 0.8, 0.0, 1.0);
		ALBEDO = mix(ALBEDO, vec3(0.0), paint);
		EMISSION = mix(EMISSION, grid_col * scan_glow, paint);

		// Obstacles get their silhouette drawn on. Gated by the same swept and
		// edge terms as the grid, so it arrives with the wave and thins out
		// with it rather than snapping on across the whole map.
		if (instance_solid > 0.5) {
			float facing = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)),
				0.0, 1.0);
			float outline = pow(facing, scan_outline_power)
				* scan_strength * inside * scan_outline_strength;
			EMISSION += scan_outline_color.rgb * outline;
		}
	}
}
