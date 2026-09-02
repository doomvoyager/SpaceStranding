shader_type spatial;
// The map's terrain, not the world's.
//
// `render_mode unshaded` is the whole idea: a map is a *representation*, and
// the world's lighting is a grazing red dwarf sitting on the horizon. Lit by
// that, an aerial view is a black page with one bright edge — technically the
// truth and useless as a map. Everything here is computed instead, from a
// hillshade direction chosen for legibility rather than for the fiction.
render_mode unshaded, cull_back;

group_uniforms relief;
// Metres of world height that map to one full sweep of the elevation ramp. The
// mesh itself is exaggerated vertically by the builder; this is only about
// colour.
uniform float elevation_span = 220.0;
uniform float elevation_floor = 0.0;
// Gamma on the elevation ramp, and not a nicety.
//
// One massif owns the top of the range: the authored map runs -19.8 m to
// 189.0 m, and the ground you actually walk on sits around 8. On a linear ramp
// that is 13% of the way up, so essentially the whole map renders at the dark
// end with one bright peak — measured, then fixed here rather than by faking
// the range. Below 1.0 lifts the low ground into the middle of the ramp where
// it can be read.
uniform float elevation_curve : hint_range(0.2, 2.0) = 0.45;
uniform vec4 low_color : source_color = vec4(0.16, 0.20, 0.26, 1.0);
uniform vec4 mid_color : source_color = vec4(0.42, 0.40, 0.38, 1.0);
uniform vec4 high_color : source_color = vec4(0.86, 0.82, 0.74, 1.0);

group_uniforms contours;
// Contour lines are what makes a relief map readable rather than pretty. Spaced
// in metres of real world height, so the reading is honest even though the mesh
// is exaggerated.
uniform bool contours_enabled = true;
uniform float contour_interval = 20.0;
uniform float contour_width : hint_range(0.02, 0.6) = 0.14;
uniform vec4 contour_color : source_color = vec4(0.06, 0.07, 0.09, 0.55);

group_uniforms hillshade;
// A conventional map light: high and over the shoulder. Deliberately not
// World.star_direction().
uniform vec3 shade_direction = vec3(-0.45, 0.82, -0.35);
uniform float shade_strength : hint_range(0.0, 1.0) = 0.55;
uniform float shade_ambient : hint_range(0.0, 1.0) = 0.45;

group_uniforms coverage;
// The same mask the ground draws, sampled through the same UV2. Sharing the
// texture rather than recomputing is what stops the map and the world
// disagreeing about where the network reaches.
uniform bool coverage_enabled = false;
uniform sampler2D coverage_mask : hint_default_black;
uniform vec4 coverage_edge_color : source_color = vec4(0.55, 0.95, 1.0, 1.0);
uniform float coverage_edge_width : hint_range(0.01, 0.45) = 0.10;
uniform vec4 coverage_tint : source_color = vec4(0.36, 0.78, 0.84, 1.0);
uniform float coverage_tint_strength : hint_range(0.0, 1.0) = 0.10;
// How far ground outside coverage is pushed toward grey and dark. Mac's call
// 2026-09-02: the map shows everything and *marks* what is dark, rather than
// hiding it. See docs/07-Decisions/Decision-Log.md.
uniform float dark_desaturate : hint_range(0.0, 1.0) = 0.75;
uniform float dark_dim : hint_range(0.0, 1.0) = 0.45;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Distance to the nearest contour line, in line-widths, antialiased against the
// screen-space derivative so the lines stay one pixel wide at every zoom. A
// fixed width in metres turns into a solid wash when you pull the camera back.
float contour_mask(float height) {
	float scaled = height / max(contour_interval, 0.01);
	float d = abs(fract(scaled) - 0.5);
	float aa = max(fwidth(scaled), 0.0001);
	return 1.0 - smoothstep(contour_width - aa, contour_width + aa, d);
}

void fragment() {
	float height = world_position.y;

	// --- Elevation ramp -------------------------------------------------
	float t = clamp((height - elevation_floor) / max(elevation_span, 0.01),
		0.0, 1.0);
	t = pow(t, elevation_curve);
	vec3 base = t < 0.5
		? mix(low_color.rgb, mid_color.rgb, t * 2.0)
		: mix(mid_color.rgb, high_color.rgb, (t - 0.5) * 2.0);

	// --- Hillshade ------------------------------------------------------
	vec3 n = normalize(NORMAL);
	float lambert = clamp(dot(n, normalize(shade_direction)), 0.0, 1.0);
	base *= mix(1.0 - shade_strength, 1.0 + shade_strength * 0.35,
		mix(shade_ambient, 1.0, lambert));

	// --- Contours -------------------------------------------------------
	if (contours_enabled) {
		base = mix(base, contour_color.rgb, contour_mask(height) * contour_color.a);
	}

	// --- Coverage -------------------------------------------------------
	if (coverage_enabled) {
		float cov = texture(coverage_mask, UV2).r;
		float inside = smoothstep(0.5 - coverage_edge_width,
			0.5 + coverage_edge_width, cov);

		// Outside the network the ground is still drawn — it is just plainly
		// marked as unsurveyed: greyed and dimmed, so a route planned through
		// it reads as a route into the dark.
		vec3 grey = vec3(dot(base, vec3(0.2126, 0.7152, 0.0722)));
		vec3 dark = mix(base, grey, dark_desaturate) * (1.0 - dark_dim);
		base = mix(dark, base, inside);
		base = mix(base, coverage_tint.rgb, inside * coverage_tint_strength);

		float edge = 1.0 - smoothstep(0.0, coverage_edge_width,
			abs(cov - 0.5));
		base = mix(base, coverage_edge_color.rgb, edge);
	}

	ALBEDO = base;
}
