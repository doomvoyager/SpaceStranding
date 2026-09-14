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
// What is left is albedo, a regolith detail layer, a lunar reflectance model
// and two overlays. The two overlays are gameplay and are the original reason
// this is a shader at all rather than a StandardMaterial3D:
//
//   - **Lattice coverage**, painted on the ground. See [[The-Lattice]].
//   - **The scan pulse**, on ground and rock. See [[Scanner]].
//
// **The lighting is the Moon's, not a style** (2026-09-14, Mac asked for a
// realistic regolith). Regolith is not a Lambert surface: it is a fine dark
// powder whose grains shadow each other, and the classic model for it is
// Lommel-Seeliger - reflectance goes as `cos_i / (cos_i + cos_e)` rather than
// `cos_i` alone. Two things follow that a Lambert ground cannot do, and both
// are what a lunar photograph looks like. The far ground under a grazing sun
// stays bright: at 5.5 deg `N.L` is 0.096, and a flat plane seen from a
// standing eye has `N.V` of a few hundredths out at range, so the ratio sits
// near one where Lambert has already gone black - this is the real reason the
// Moon's horizon is not dark, and the fill term below used to fake it. And the
// surface is strongly backscattering, so looking down-sun it washes out flat
// and shadowless (the opposition surge, the bright halo round your own
// shadow's head) while up-sun it is dark and every rise is a silhouette.
// `lunar_brdf` is per material: on for regolith and rock, off for crates and
// hulls, which get a plain Lambert from the same `light()`.
//
// **`LIGHT_COLOR` inside `light()` carries a factor of pi.** Measured: a
// `light()` writing `dot(N,L) * ATTENUATION * LIGHT_COLOR` rendered 60%
// brighter than Godot's own diffuse on the same frames, and `/ PI` matched the
// built-in to three decimals. The docs' example omits the division.
//
// **Ambient is rolled by hand, and that is not a style choice.** The sky is
// black, so Godot's sky-sourced ambient contributes nothing, and a coloured
// ambient at the level needed to read tinted the whole ground. Measured both
// ways in `previews/2026-09-03/`. So `ambient_light_disabled` stays, and a
// flat fill in EMISSION stands in for what the sunlit ground around you
// bounces back - grey, because it is regolith lit by a white sun. It is far
// smaller than it was: the Lommel-Seeliger term now carries the far ground,
// so the fill only has to keep the shadows from rendering as holes.

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

group_uniforms detail;
// Regolith detail, mapped on the world's ground plane in metres rather than
// through the mesh's UVs, so it is the same on every tile and on anything
// else the material lands on, and so no mesh needs tangents. Two things:
//
//   - a **normal map** sampled at two scales - a fine one for the grain and
//     the dimples a metre across, a coarse one for the soft undulation the
//     5 m DEM cannot carry - which is what gives a grazing sun something to
//     rake across;
//   - **brightness variation**, at a coarse scale for the patches and a fine
//     one for the grain, multiplied into ALBEDO.
//
// The textures are NoiseTexture2Ds authored on the material, so all of it
// opens in the inspector. Off by default: only the regolith turns it on.
uniform bool use_detail = false;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_albedo : hint_default_white, filter_linear_mipmap, repeat_enable;
// Metres per repeat of the fine normal, and how far it tilts the surface.
uniform float detail_tile_m : hint_range(0.5, 50.0) = 5.0;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.5;
// The same normal texture again, larger, for the undulation.
uniform float detail_coarse_tile_m : hint_range(5.0, 500.0) = 60.0;
uniform float detail_coarse_strength : hint_range(0.0, 2.0) = 0.35;
// Brightness variation, as a fraction either side of 1.
uniform float detail_albedo_tile_m : hint_range(5.0, 1000.0) = 120.0;
uniform float detail_albedo_variation : hint_range(0.0, 0.6) = 0.18;
uniform float detail_grain_variation : hint_range(0.0, 0.6) = 0.10;

group_uniforms lighting;
// Lommel-Seeliger with a backscatter lobe and an opposition surge; see the
// note at the top. Off, the material is plain Lambert.
uniform bool lunar_brdf = false;
// How much brighter the surface is with the sun behind the eye than side-on.
uniform float lunar_backscatter : hint_range(0.0, 3.0) = 0.6;
// The narrow surge right at zero phase - the halo round your shadow's head -
// and how narrow it is (a power; higher is tighter).
uniform float lunar_opposition : hint_range(0.0, 3.0) = 0.6;
uniform float lunar_opposition_width : hint_range(1.0, 200.0) = 40.0;

group_uniforms tracks;
// Wheel tracks, from the TrackMap's window, sampled by world position; see
// [[Tracks]]. Per material: on for regolith, off elsewhere. A track does what
// compressed regolith does - darker, smoother (the opposition surge goes, in
// light()), pressed into a rut with the tread across it. The tread is drawn
// here from the stored direction of travel, which is what lets the map be
// coarse: 8 cm texels resolve the rut, and the chevrons cost arithmetic.
uniform bool tracks_enabled = false;
uniform float track_darkening : hint_range(0.0, 1.0) = 0.25;
// How deep a full track is, metres. Sets the tilt of the rut's walls from
// the depth gradient: at 0.04 a stamp's soft edge leans about thirty degrees.
uniform float track_rut_depth : hint_range(0.0, 0.3) = 0.04;
// Metres between chevron ridges, how hard they tilt the normal, and how far
// back a chevron sweeps between the centre line and the tyre's edge, metres.
// The map does not store where the centre line is; the stamp's depth is a U
// across the tyre, so `1 - depth` stands in for the distance from it.
uniform float track_tread_spacing : hint_range(0.02, 1.0) = 0.1;
uniform float track_tread_strength : hint_range(0.0, 2.0) = 0.18;
uniform float track_chevron_reach : hint_range(0.0, 1.0) = 0.1;
// Written by TrackMap. Declared in project.godot under [shader_globals].
global uniform sampler2D track_map;
global uniform vec2 track_origin;
global uniform float track_extent;
global uniform float track_texel;
global uniform bool track_active;

group_uniforms fill;
// Stands in for scene ambient, which this planet's sky cannot provide: the
// light the sunlit ground around you throws back into a shadow. Multiplied by
// ALBEDO so it tints the surface rather than washing over it. Warm grey,
// because it is regolith under a white sun - the blue it used to be was
// chosen against a red star.
uniform vec4 fill_color : source_color = vec4(1.0, 0.96, 0.90, 1.0);
uniform float fill_strength : hint_range(0.0, 2.0) = 0.15;

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
// Track depth under this fragment, 0..1, for light(): compressed regolith
// loses the opposition surge. Written in fragment(), read in light().
varying float track_depth;


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

	// Everything that bends the normal adds a tilt on the ground plane here,
	// and the normal is rebuilt once at the end.
	vec2 tilt = vec2(0.0);
	if (use_detail) {
		vec2 ground = world_position.xz;
		vec2 v = vec2(detail_albedo_variation, detail_grain_variation);
		float patches = texture(detail_albedo, ground / detail_albedo_tile_m).r;
		float grain = texture(detail_albedo, ground / detail_tile_m * 1.73 + 0.5).r;
		base *= mix(1.0 - v.x, 1.0 + v.x, patches) * mix(1.0 - v.y, 1.0 + v.y, grain);

		// Two octaves of the one normal map, in tangent space with +Z up.
		vec3 fine = texture(detail_normal, ground / detail_tile_m).xyz * 2.0 - 1.0;
		vec3 coarse = texture(detail_normal,
			ground / detail_coarse_tile_m + vec2(0.37, 0.11)).xyz * 2.0 - 1.0;
		tilt += fine.xy * detail_strength + coarse.xy * detail_coarse_strength;
	}

	// --- Wheel tracks ----------------------------------------------------
	track_depth = 0.0;
	if (tracks_enabled && track_active) {
		vec2 rel = world_position.xz - track_origin;
		if (all(greaterThanEqual(rel, vec2(0.0)))
				&& all(lessThan(rel, vec2(track_extent)))) {
			// The map is toroidal in world space, so the texel a point lands
			// on does not depend on where the window is - only whether the
			// point is inside it, which is the check above.
			vec2 uv = fract(world_position.xz / track_extent);
			vec3 t = texture(track_map, uv).rgb;
			if (t.r > 0.01) {
				float d = t.r;
				float du = track_texel / track_extent;
				vec2 grad = vec2(
					texture(track_map, fract(uv + vec2(du, 0.0))).r
						- texture(track_map, fract(uv - vec2(du, 0.0))).r,
					texture(track_map, fract(uv + vec2(0.0, du))).r
						- texture(track_map, fract(uv - vec2(0.0, du))).r)
					/ (2.0 * track_texel);
				// The stored direction is the heading doubled; halve it back.
				vec2 v = t.gb * 2.0 - 1.0;
				float heading = atan(v.y, v.x) * 0.5;
				vec2 travel = vec2(cos(heading), sin(heading));
				float along = dot(world_position.xz, travel);
				// Chevrons: ridges across the track, swept back from the
				// centre line toward both edges. The sweep rides on the
				// depth, which is deepest on the line and shallower out.
				float phase = (along + (1.0 - d) * track_chevron_reach)
					/ track_tread_spacing * TAU;
				// And gone once a ridge is under three pixels, or it is a
				// moire at any distance - the map has no mip chain to do it.
				float tread_fade = 1.0 - smoothstep(1.2, 2.2, fwidth(phase));
				tilt += travel * cos(phase) * track_tread_strength * d * tread_fade;
				// The rut: the surface goes down where the depth goes up, so
				// the normal leans toward the shallower side.
				tilt += grad * track_rut_depth;
				base *= 1.0 - track_darkening * d;
				track_depth = d;
			}
		}
	}

	if (dot(tilt, tilt) > 0.0) {
		// Planar mapping on the ground plane, so the tangent frame is the
		// world's X and Z. Good on any slope the rover can drive; a cliff face
		// would smear, and a cliff is rock's job. The geometric normal stays
		// in `world_normal` for the scan, which reports the slope as built.
		vec3 bent = normalize(world_normal + vec3(tilt.x, 0.0, tilt.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
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


void light() {
	float n_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	// LIGHT_COLOR is energy * pi; see the note at the top.
	vec3 incoming = ATTENUATION * LIGHT_COLOR / PI;
	// No early return: Godot rejects `return` inside light().
	if (!lunar_brdf) {
		DIFFUSE_LIGHT += n_l * incoming;
	} else {
		float n_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		// Lommel-Seeliger, scaled so it equals Lambert at normal incidence
		// and normal view, which keeps the tunables comparable between the
		// two models. The floor keeps the ratio finite on the terminator.
		float ls = 2.0 * n_l / max(n_l + n_v, 0.02);
		// Phase: cos of the angle between the sun and the eye, seen from the
		// surface. 1 with the sun straight behind the eye, 0 side-on.
		float cos_g = clamp(dot(LIGHT, VIEW), 0.0, 1.0);
		// A wheel presses the fairy-castle structure flat, and with it goes
		// most of the surge: a track reads darker down-sun than the ground
		// beside it, which is what makes it visible from the cab.
		float intact = 1.0 - track_depth;
		float phase = 1.0 + lunar_backscatter * cos_g * cos_g * mix(0.5, 1.0, intact)
			+ lunar_opposition * intact * pow(cos_g, lunar_opposition_width);
		DIFFUSE_LIGHT += ls * phase * incoming;
	}
}
