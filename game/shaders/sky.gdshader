shader_type sky;
// The Moon's sky: black, a sun of its real size, and the stars.
//
// There is no atmosphere, so there is nothing to draw between the ground and
// space - no gradient, no horizon glow, no scattering round the sun. What is
// up there is the sun's disc, at the 0.53 degrees the light already carries as
// `light_angular_distance`, and stars. On the real Moon a camera exposed for
// sunlit regolith records none of them, and the astronauts reported the same;
// they are here faint, because a black void reads as a rendering bug rather
// than as a vacuum, and `star_intensity` is the honesty slider. Earth is not
// here yet - where it sits is a navigation decision, and Mac's ([[The-Planet]]).
//
// The stars are one per grid cell on a cube map's faces, so they are neither
// crowded at the poles nor stretched, and they are fixed to the sky rather
// than to the camera. Cheap enough for a full-screen pass: nine cells looked
// up per pixel, no textures.

group_uniforms stars;
uniform float star_intensity : hint_range(0.0, 4.0) = 0.35;
// The fraction of cells that hold a star.
uniform float star_density : hint_range(0.0, 1.0) = 0.4;
// Cells along each cube face edge. 160 is about 60,000 candidates.
uniform float star_cells : hint_range(20.0, 400.0) = 160.0;
// Angular radius of a star, degrees. A pixel at 70 deg over 1600 px is 0.044.
uniform float star_size_deg : hint_range(0.02, 0.5) = 0.07;
uniform vec4 star_tint : source_color = vec4(0.88, 0.92, 1.0, 1.0);

group_uniforms sun;
// The disc's brightness, as a multiple of the light's energy. Far past white:
// it is the one thing in the sky the post stack's glow and halation should
// find, and a real sun has no top.
uniform float sun_disc_energy : hint_range(0.0, 200.0) = 40.0;
// Softness of the limb, as a fraction of the radius. A little hides aliasing
// on a disc a dozen pixels across.
uniform float sun_disc_softness : hint_range(0.0, 1.0) = 0.25;
// Glare round the disc. Not the sky - a vacuum scatters nothing - but the
// eye and the visor do, and every photograph of the sun from the surface is
// a bloom. Falls off exponentially over `sun_glare_width_deg`.
uniform float sun_glare_energy : hint_range(0.0, 10.0) = 1.2;
uniform float sun_glare_width_deg : hint_range(0.1, 20.0) = 1.5;


float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}


// Which cube face a direction lands on, and where on it, -1..1.
void cube_face(vec3 d, out int face, out vec2 uv) {
	vec3 a = abs(d);
	if (a.x >= a.y && a.x >= a.z) {
		face = d.x > 0.0 ? 0 : 1;
		uv = d.yz / a.x;
	} else if (a.y >= a.z) {
		face = d.y > 0.0 ? 2 : 3;
		uv = d.xz / a.y;
	} else {
		face = d.z > 0.0 ? 4 : 5;
		uv = d.xy / a.z;
	}
}


// The inverse: a direction for a point on a face.
vec3 cube_dir(int face, vec2 uv) {
	if (face == 0) {
		return normalize(vec3(1.0, uv.x, uv.y));
	} else if (face == 1) {
		return normalize(vec3(-1.0, uv.x, uv.y));
	} else if (face == 2) {
		return normalize(vec3(uv.x, 1.0, uv.y));
	} else if (face == 3) {
		return normalize(vec3(uv.x, -1.0, uv.y));
	} else if (face == 4) {
		return normalize(vec3(uv.x, uv.y, 1.0));
	}
	return normalize(vec3(uv.x, uv.y, -1.0));
}


vec3 stars(vec3 d) {
	int face;
	vec2 fuv;
	cube_face(d, face, fuv);
	vec2 g = (fuv * 0.5 + 0.5) * star_cells;
	vec2 cell = floor(g);
	float radius = radians(star_size_deg);
	vec3 total = vec3(0.0);
	// The neighbours too, so a star near a cell edge is not clipped by it.
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vec2 c = cell + vec2(float(i), float(j));
			vec2 seed = c + float(face) * 1000.0;
			float h = hash12(seed);
			if (h > star_density) {
				continue;
			}
			vec2 pos = c + hash22(seed + 7.0);
			vec3 sd = cube_dir(face, pos / star_cells * 2.0 - 1.0);
			// Small-angle: angle^2 is 2(1 - cos), and it dodges acos's float
			// trouble right next to 1.
			float ang2 = 2.0 * max(1.0 - dot(d, sd), 0.0);
			// Few bright, many faint.
			float bright = pow(hash12(seed + 13.0), 3.0);
			float r = radius * (0.6 + 0.8 * bright);
			total += star_tint.rgb * bright * exp(-ang2 / (0.5 * r * r));
		}
	}
	return total * star_intensity;
}


void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = vec3(0.0);
	// The radiance cubemap feeds reflections and sky ambient. A 40x sun disc
	// in it would put a hot spot on every glossy surface that the directional
	// light already provides, and stars in it are noise.
	if (!AT_CUBEMAP_PASS) {
		col += stars(d);
		if (LIGHT0_ENABLED) {
			// LIGHT0_SIZE is the light's angular distance in radians, which
			// for the sun is its diameter.
			float r = LIGHT0_SIZE * 0.5;
			float ang2 = 2.0 * max(1.0 - dot(d, LIGHT0_DIRECTION), 0.0);
			float rr = r * r;
			float disc = 1.0 - smoothstep(rr * (1.0 - sun_disc_softness),
				rr * (1.0 + sun_disc_softness), ang2);
			col += LIGHT0_COLOR * LIGHT0_ENERGY * sun_disc_energy * disc;
			float glare = exp(-sqrt(ang2) / radians(sun_glare_width_deg));
			col += LIGHT0_COLOR * LIGHT0_ENERGY * sun_glare_energy * glare;
		}
	}
	COLOR = col;
}
