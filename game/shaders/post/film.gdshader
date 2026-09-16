// StarChef — film.gdshader
// The entire post stack in one pass: lens -> glow -> halation -> lens dust ->
// flare and lens dirt -> grain.
//
// This replaces four ColorRects with a BackBufferCopy between each. That shape
// cost four full-screen backbuffer copies and three mip-chain rebuilds every
// frame. A discrete GPU absorbs that as bandwidth; an Apple tile-based GPU very
// much does not, because each backbuffer copy forces tile memory out to system
// memory and back — the one thing the architecture exists to avoid.
//
// One pass, one copy, one mip chain. The four effects still do exactly what
// they did and in the same order — they are statements now instead of nodes.
// To disable one, zero its intensity (ca_amount and lens_softness for the lens).
//
// One real behavioural change, worth knowing: glow and halation now sample the
// pre-lens image, because there is no longer an intermediate buffer holding the
// aberrated one. Both read at mip 1.0 and above, where a 0.0035-UV channel
// split is far below the resolution of the tap, so it does not show.
//
// Space Stranding added the camera's own glass on 2026-09-16, in the same pass
// for the same reason: regolith dust that builds up on the lens, the sun's
// flare, and the smudges the sun lights up. See docs/02-Systems/Lens.md.

shader_type canvas_item;

#include "res://shaders/include/post_common.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// repeat_disable is load-bearing: once the aberration samples past the frame
// edge, repeat would wrap and pull red from the opposite side of the screen.


// Where the sun is and how dusty the lens is, pushed every frame by the Lens
// script on this layer (scripts/ui/lens.gd). Globals rather than uniforms so
// the F1 panel, which lists this material's own uniforms, never offers them as
// sliders to fight the script with.
global uniform vec2 lens_sun_uv;       // the disc's centre, 0-1, y down like UV
global uniform vec2 lens_sun_radius;   // its radius, in the same units per axis
global uniform float lens_sun_ahead;   // 1 in front of the camera, 0 behind it
global uniform vec4 lens_sun_color;    // World.sun_color
global uniform float lens_dust;        // 0-1, how much of the dust has landed


group_uniforms Lens;

uniform float ca_amount : hint_range(0.0, 0.02, 0.0005) = 0.003;
uniform float lens_softness : hint_range(0.0, 4.0, 0.05) = 0.6;
uniform float edge_falloff : hint_range(0.5, 4.0, 0.05) = 2.0;

group_uniforms;


group_uniforms Glow;

// Luminance above which a pixel starts to bloom. Knee is how soft that
// boundary is - keep it well above 0 or highlights pop in and out as they
// drift across the threshold.
uniform float glow_threshold : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float glow_knee : hint_range(0.0, 0.5, 0.005) = 0.15;

// Base mip level. Each step up roughly doubles the spread.
uniform float glow_radius : hint_range(0.0, 6.0, 0.1) = 3.0;
uniform float glow_intensity : hint_range(0.0, 4.0, 0.01) = 0.5;

// Tint the spill without tinting the picture.
uniform vec4 glow_tint : source_color = vec4(1.0, 0.97, 0.9, 1.0);

group_uniforms;


group_uniforms Halation;

uniform float halation_threshold : hint_range(0.0, 1.0, 0.01) = 0.70;
uniform float halation_knee : hint_range(0.0, 0.5, 0.005) = 0.20;

// Wider than the glow — halation reaches further and sits lower in intensity.
uniform float halation_radius : hint_range(0.0, 8.0, 0.1) = 5.0;

// How far apart the three channels spread. 0 collapses to a neutral blur that
// only `halation_tint` colours; higher pushes red out past blue and the fringe
// colours itself. This is the knob that decides whether it reads as film.
uniform float channel_spread : hint_range(0.0, 3.0, 0.05) = 1.2;

uniform float halation_intensity : hint_range(0.0, 4.0, 0.01) = 0.6;
uniform vec4 halation_tint : source_color = vec4(1.0, 0.32, 0.12, 1.0);

group_uniforms;


group_uniforms Grain;

uniform float grain_intensity : hint_range(0.0, 1.0) = 0.1;

// 0 is monochrome emulsion, 1 is the look as authored, above 1 pushes the
// channels further apart than the noise alone would.
uniform float grain_saturation : hint_range(0.0, 2.0) = 1.0;

uniform float min_lum : hint_range(0.0, 1.0) = 0.0;
uniform float max_lum : hint_range(0.0, 1.0) = 1.0;
uniform float time_scale : hint_range(0.0, 1.0) = 0.5;

group_uniforms;


group_uniforms Sun;

// How white a pixel has to be to count as the sun's disc. The sky draws the
// disc far past white; its glare ring reads 0.5-0.6 and anything standing in
// front of the sun reads under 0.15, because it is lit from behind. Measured
// in tests/probe_sun_disc.tscn.
uniform float sun_threshold : hint_range(0.5, 1.0, 0.005) = 0.95;

// How far inside the frame the sun has to be before the lens gets all of it,
// in screen heights. At 0 the flare cuts off at the edge.
uniform float sun_edge_margin : hint_range(0.0, 0.5, 0.005) = 0.12;

group_uniforms;


group_uniforms Flare;

// The ghosts, with the whole disc in view. 0 turns the flare off.
uniform float flare_intensity : hint_range(0.0, 4.0, 0.01) = 1.4;
// The port's warm (1.4, 1.2, 1.0) is (1.0, 0.857, 0.714) at an intensity of
// 1.4. Warmer than a white sun needs; an orange haze reads as air.
uniform vec4 flare_tint : source_color = vec4(1.0, 0.857, 0.714, 1.0);
// The port's two kinds of ghost, weighted apart. The halo is its broad soft
// ring, which sits on the sun when you look straight at it and washes the
// frame; the ghosts are the small discs strung along the line through the
// centre. 1 and 1 is the port.
uniform float flare_halo : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float flare_ghosts : hint_range(0.0, 2.0, 0.01) = 1.0;
// The port's colour modifier: a bright ghost is pulled toward a grey of its
// own brightness, `flare_whiten` of it, by `flare_whiten_ramp` per unit.
uniform float flare_whiten : hint_range(0.0, 2.0, 0.01) = 0.5;
uniform float flare_whiten_ramp : hint_range(0.0, 1.0, 0.005) = 0.1;

group_uniforms;


group_uniforms Dirt;

// Smudges on the glass, dark until the sun lights them. Black is clean glass.
uniform sampler2D dirt_texture : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float dirt_intensity : hint_range(0.0, 4.0, 0.01) = 0.6;
// Every smudge gets this share of the light wherever it is on the lens...
uniform float dirt_floor : hint_range(0.0, 1.0, 0.01) = 0.25;
// ...and the rest falls off with distance from the sun, in screen heights.
uniform float dirt_spread : hint_range(0.02, 2.0, 0.01) = 0.45;

group_uniforms;


group_uniforms Dust;

// Regolith on the glass: the specks are the alpha, their hue the RGB.
uniform sampler2D dust_texture : hint_default_transparent, filter_linear_mipmap, repeat_disable;
uniform vec4 dust_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// A gain on the texture's alpha: how much of the picture a landed speck
// hides. Most of the specks are painted faint, so above 1 is normal.
uniform float dust_density : hint_range(0.0, 4.0, 0.01) = 1.5;
// How much of the frame's own light a speck gives back. Dust on the front
// element is lit by everything the lens looks at, so in shade it reads as a
// faint grey - brighter than a black sky, darker than sunlit ground - rather
// than as paint. Multiplies the frame's mean brightness.
uniform float dust_ambient : hint_range(0.0, 8.0, 0.05) = 2.0;
// A speck on the front element is out of focus. Mip bias, so it stays
// resolution-independent.
uniform float dust_softness : hint_range(0.0, 4.0, 0.05) = 0.5;
// The order the specks land in is a random field this many cells across the
// texture. Higher lands them one by one; lower lands them in patches.
uniform float dust_cells : hint_range(4.0, 400.0, 1.0) = 140.0;
// How much of the coverage range a speck takes to fade in.
uniform float dust_arrival : hint_range(0.001, 0.5, 0.001) = 0.04;
// A speck in the sun scatters it: how bright a lit speck glows, lit like the
// dirt above, falling off with distance from the sun.
uniform float dust_glow : hint_range(0.0, 4.0, 0.01) = 1.0;

group_uniforms;


// How much of the sun's disc the lens can see, 0-1: the fraction of the taps
// below that land on white. Measured at the rect's four corners rather than at
// every pixel - a canvas_item vertex() can read the screen texture, and reads
// what fragment() reads (tests/probe_sun_disc.tscn) - and flat, so the corners
// cannot disagree.
varying flat float sun_seen;
// The frame's mean colour, off the top of the mip chain: what lights the
// dust on the lens. Also flat, also four fetches a frame.
varying flat vec3 scene_mean;

// Where to look for the disc, in radii from its centre: the centre and two
// rings, all well inside the limb, so a soft or antialiased edge never counts.
const vec2 SUN_TAPS[9] = {
	vec2(0.0, 0.0),
	vec2(0.55, 0.0), vec2(-0.55, 0.0), vec2(0.0, 0.55), vec2(0.0, -0.55),
	vec2(0.35, 0.35), vec2(-0.35, 0.35), vec2(0.35, -0.35), vec2(-0.35, -0.35)
};


float noise(vec2 p) {
	return (fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;
}

vec3 soft_light(vec3 A, vec3 B) {
	vec3 branch1 = 2.0 * A * B + A * A * (1.0 - 2.0 * B);
	vec3 branch2 = 2.0 * A * (1.0 - B) + sqrt(A) * (2.0 * B - 1.0);
	vec3 condition = step(0.5, B);
	return mix(branch1, branch2, condition);
}


void vertex() {
	// Any LOD past the last mip clamps to the 1x1 one.
	scene_mean = textureLod(screen_texture, vec2(0.5), 14.0).rgb;
	sun_seen = 0.0;
	if (lens_sun_ahead > 0.0) {
		float lit = 0.0;
		for (int i = 0; i < 9; i++) {
			vec2 at = lens_sun_uv + SUN_TAPS[i] * lens_sun_radius;
			// Off the frame is not seen. repeat_disable would otherwise hand
			// back the edge pixel, which is white while the sun is on it.
			if (at.x < 0.0 || at.y < 0.0 || at.x > 1.0 || at.y > 1.0) {
				continue;
			}
			vec3 c = textureLod(screen_texture, at, 0.0).rgb;
			lit += smoothstep(sun_threshold - 0.05, sun_threshold, min(c.r, min(c.g, c.b)));
		}
		sun_seen = lit / 9.0 * lens_sun_ahead;
	}
}


// --- 1 of 7: chromatic aberration and lens softness ---------------------------
//
// Both worsen toward the corners off one shared falloff, because that is what a
// real lens does. Uniform CA reads as a broken video signal and uniform blur
// reads as a mistake.
vec3 lens_pass(vec2 uv, float edge) {
	// One set of three fetches carries both effects. Red is pulled inward along
	// the radius and blue pushed outward, the direction a real lens splits them;
	// green stays put so the image itself doesn't drift. The LOD is the softness
	// — filter_linear_mipmap is what makes Godot build mips of the screen copy,
	// so the blur costs an argument, not a tap loop.
	vec2 ca_offset = (uv - vec2(0.5)) * ca_amount * edge;
	float lod = lens_softness * edge;

	vec3 col;
	col.r = textureLod(screen_texture, uv - ca_offset, lod).r;
	col.g = textureLod(screen_texture, uv,             lod).g;
	col.b = textureLod(screen_texture, uv + ca_offset, lod).b;
	return col;
}


// --- 2 of 7: soft neutral glow on highlights ---------------------------------
//
// The broad, gentle spill — lens scatter rather than film chemistry. Halation
// is the separate, redder, wider effect below; keeping them apart is what lets
// you have a clean bright bloom AND a warm fringe without one forcing the
// colour of the other.
vec3 glow_pass(vec2 uv) {
	// Three mip taps standing in for a bloom chain, weighted so the tightest
	// contributes most.
	//
	// Worth knowing what this approximates and where it falls short: a proper
	// bloom thresholds FIRST and blurs the result. Sampling a mip gives the
	// blurred *scene*, so the threshold is applied after the blur. Large bright
	// areas behave correctly; small bright points get averaged down below the
	// knee and can vanish. If that ever matters more than the control this
	// gives you, Godot's Environment glow does the proper order natively.
	vec3 spill = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 3; i++) {
		float lod = glow_radius + float(i);
		vec3 s = textureLod(screen_texture, uv, lod).rgb;
		float weight = 1.0 / float(i + 1);
		spill += s * post_highlight(s, glow_threshold, glow_knee) * weight;
		total += weight;
	}
	spill /= max(total, 0.0001);

	return spill * glow_tint.rgb * glow_intensity;
}


// --- 3 of 7: the warm fringe around highlights -------------------------------
//
// Halation is not bloom. Light passes THROUGH the emulsion, reflects off the
// film base, and comes back up to re-expose the layer around a highlight. The
// anti-halation backing absorbs short wavelengths, so it is the red end that
// survives the round trip — which is why the fringe is red-orange rather than
// whatever colour the highlight was.
//
// That physical cause is worth reproducing rather than faking with a flat tint:
// the channels here spread at DIFFERENT radii, red widest, so the colour
// emerges from the spread the way it does on film. `halation_tint` is then a
// nudge on top rather than the whole effect.
vec3 halation_pass(vec2 uv) {
	float lod_r = halation_radius + channel_spread;
	float lod_g = halation_radius;
	float lod_b = max(halation_radius - channel_spread, 0.0);

	vec3 wide = vec3(
		textureLod(screen_texture, uv, lod_r).r,
		textureLod(screen_texture, uv, lod_g).g,
		textureLod(screen_texture, uv, lod_b).b
	);

	float mask = post_highlight(wide, halation_threshold, halation_knee);
	return wide * mask * halation_tint.rgb * halation_intensity;
}


// --- The glass: helpers for 4 to 6 --------------------------------------------

// Fill the frame with a texture of another shape by cropping it, not
// stretching it, so a speck stays the shape it was painted.
vec2 cover_uv(vec2 uv, vec2 tex_size, float aspect) {
	float tex_aspect = tex_size.x / max(tex_size.y, 1.0);
	vec2 scale = aspect > tex_aspect
		? vec2(1.0, tex_aspect / aspect)
		: vec2(aspect / tex_aspect, 1.0);
	return (uv - 0.5) * scale + 0.5;
}


// 1 with the sun's disc comfortably inside the frame, falling to 0 at its
// edge. In screen heights, so the margin is the same on all four sides.
float sun_edge_fade(float aspect) {
	vec2 inside = min(lens_sun_uv, vec2(1.0) - lens_sun_uv) * vec2(aspect, 1.0);
	return smoothstep(0.0, max(sun_edge_margin, 0.0001), min(inside.x, inside.y));
}


float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


// A smooth random field, 0-1. Smooth rather than one value per cell, because
// a cell edge would cut a speck in half while it lands.
float value_noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}


// --- 4 of 7: regolith on the lens ---------------------------------------------
//
// Returns the dust colour in rgb and how much of this pixel it covers in a.
// The texture is every speck the lens will ever carry; `lens_dust` says how
// many have landed. Each lands when the coverage passes its place in a random
// order - fixed to the texture, so a speck that has landed stays landed - and
// fades in over `dust_arrival` of the range. A smooth field averages toward
// the middle, so it is stretched back out, or the first and last specks would
// take most of the range to arrive.
//
// The texture's colour is taken as the dust's hue only. How bright a speck is
// depends on what is lighting it: the frame's own mean, `dust_ambient` of it.
vec4 dust_pass(vec2 uv, float aspect) {
	vec2 size = vec2(textureSize(dust_texture, 0));
	vec2 tuv = cover_uv(uv, size, aspect);
	vec4 d = texture(dust_texture, tuv, dust_softness);
	float order = value_noise(tuv * vec2(dust_cells, dust_cells * size.y / max(size.x, 1.0)));
	order = clamp((order - 0.5) * 1.7 + 0.5, 0.0, 1.0);
	float start = order * (1.0 - dust_arrival);
	float landed = smoothstep(start, start + dust_arrival, lens_dust);
	vec3 hue = d.rgb / max(max(d.r, max(d.g, d.b)), 0.001);
	float light = clamp(post_luma(scene_mean) * dust_ambient, 0.0, 1.0);
	return vec4(hue * dust_tint.rgb * light, clamp(d.a * dust_density, 0.0, 1.0) * landed);
}


// --- 5 of 7: the sun's flare ---------------------------------------------------
//
// The ghosts are mu6k's lensflare() from Shadertoy 4sX3Rs, by way of
// malhotraprateek's Godot port (godotshaders.com, MIT). Their positions and
// falloffs are unchanged. What did change, and why:
//   * this returns the flare alone. The port graded the whole frame with cc()
//     and darkened it with a dither, sun or no sun;
//   * it never goes negative. The port's `- length(uvd) * .05` darkened the
//     corners of every frame;
//   * f0 and f1 are gone. f0 is a sun, which the sky already draws; f1 was
//     computed and never used. The noise texture only fed f0 and the dither,
//     and the grain below dithers.
// `p` and `s` are the pixel and the sun, centred and aspect-corrected. y runs
// down here and up on Shadertoy; every term is a distance, and flipping both
// changes none of them.
vec3 flare_light(vec2 p, vec2 s) {
	vec2 pd = p * length(p);

	float f2 = max(1.0 / (1.0 + 32.0 * pow(length(pd + 0.8 * s), 2.0)), 0.0) * 0.25;
	float f22 = max(1.0 / (1.0 + 32.0 * pow(length(pd + 0.85 * s), 2.0)), 0.0) * 0.23;
	float f23 = max(1.0 / (1.0 + 32.0 * pow(length(pd + 0.9 * s), 2.0)), 0.0) * 0.21;

	vec2 px = mix(p, pd, -0.5);
	float f4 = max(0.01 - pow(length(px + 0.4 * s), 2.4), 0.0) * 6.0;
	float f42 = max(0.01 - pow(length(px + 0.45 * s), 2.4), 0.0) * 5.0;
	float f43 = max(0.01 - pow(length(px + 0.5 * s), 2.4), 0.0) * 3.0;

	px = mix(p, pd, -0.4);
	float f5 = max(0.01 - pow(length(px + 0.2 * s), 5.5), 0.0) * 2.0;
	float f52 = max(0.01 - pow(length(px + 0.4 * s), 5.5), 0.0) * 2.0;
	float f53 = max(0.01 - pow(length(px + 0.6 * s), 5.5), 0.0) * 2.0;

	px = mix(p, pd, -0.5);
	float f6 = max(0.01 - pow(length(px - 0.3 * s), 1.6), 0.0) * 6.0;
	float f62 = max(0.01 - pow(length(px - 0.325 * s), 1.6), 0.0) * 3.0;
	float f63 = max(0.01 - pow(length(px - 0.35 * s), 1.6), 0.0) * 5.0;

	// The port summed both kinds and then took the corner fade off once; here
	// each kind takes it, so the two can be weighted apart.
	vec3 fade = vec3(length(pd) * 0.05);
	vec3 halo = max(vec3(f2, f22, f23) * 1.3 - fade, vec3(0.0));
	vec3 ghosts = max(vec3(f4 + f5 + f6, f42 + f52 + f62, f43 + f53 + f63) * 1.3 - fade, vec3(0.0));
	return halo * flare_halo + ghosts * flare_ghosts;
}


vec3 flare_pass(vec2 p, vec2 s) {
	vec3 c = flare_light(p, s) * flare_tint.rgb * flare_intensity;
	float w = c.r + c.g + c.b;
	return mix(c, vec3(w) * flare_whiten, clamp(w * flare_whiten_ramp, 0.0, 1.0));
}


// --- 6 of 7: the smudges the sun lights ---------------------------------------
vec3 dirt_pass(vec2 uv, float aspect) {
	vec2 tuv = cover_uv(uv, vec2(textureSize(dirt_texture, 0)), aspect);
	return texture(dirt_texture, tuv).rgb * dirt_intensity;
}


// --- 7 of 7: grain, and it must stay last ------------------------------------
//
// Grain sits in the emulsion, so everything the lens and the film base do to
// the picture happens underneath it. Run grain before the glow or the halation
// and those effects bloom the noise instead of the image.
//
// Soft-light blended rather than added, weighted toward the shadows rather than
// the midtones, and coloured because the three channels get independent noise.
// All deliberate — `grain_saturation` is the control for that last part.
vec3 grain_pass(vec3 col, vec2 uv) {
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float factor = 1.0 - smoothstep(min_lum, max_lum, lum);

	vec2 offset = vec2(sin(TIME * time_scale), cos(TIME * time_scale)) * 20.0;
	vec2 noise_uv = uv + offset;

	float noise_r = noise(noise_uv);
	float noise_g = noise(noise_uv + vec2(0.1, 0.2));
	float noise_b = noise(noise_uv + vec2(0.3, 0.4));

	// The mean of the three is this noise's neutral grey, so mixing toward it
	// desaturates without shifting the brightness of the grain.
	vec3 grain_rgb = vec3(noise_r, noise_g, noise_b);
	float grain_grey = (noise_r + noise_g + noise_b) / 3.0;
	grain_rgb = mix(vec3(grain_grey), grain_rgb, grain_saturation);

	vec3 grain = grain_rgb * grain_intensity * factor;

	vec3 grain_color = clamp(vec3(0.5) + grain, 0.0, 1.0);
	return soft_light(col, grain_color);
}


void fragment() {
	vec2 uv = UV;
	float edge = pow(post_edge(uv, SCREEN_PIXEL_SIZE), edge_falloff);

	vec3 col = lens_pass(uv, edge);

	// The clamps reproduce what the old four-node chain did implicitly. Each
	// BackBufferCopy wrote to an LDR buffer, so anything the previous effect
	// pushed above 1.0 was flattened before the next effect saw it. Without
	// these, stacked glow and halation on an already-bright highlight would
	// composite hotter than the version Mac tuned against.
	col = clamp(col + glow_pass(uv), 0.0, 1.0);
	col = clamp(col + halation_pass(uv), 0.0, 1.0);

	// The glass. Dust hides the picture behind it first; then whatever light
	// the lens scatters is added on top - the flare, the smudges and the dust
	// itself, all of it only while the sun is in view, and brightest nearest
	// the sun.
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float sun = sun_seen * sun_edge_fade(aspect);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	vec2 s = (lens_sun_uv - 0.5) * vec2(aspect, 1.0);
	float near_sun = mix(exp(-length(p - s) / dirt_spread), 1.0, dirt_floor);
	vec3 lit = lens_sun_color.rgb * sun;
	vec3 scattered = vec3(0.0);

	if (lens_dust > 0.0) {
		vec4 dust = dust_pass(uv, aspect);
		col = mix(col, dust.rgb, dust.a);
		scattered += dust.a * dust_glow * near_sun * lit;
	}
	if (sun > 0.0) {
		scattered += flare_pass(p, s) * lit;
		scattered += dirt_pass(uv, aspect) * near_sun * lit;
	}
	col = clamp(col + scattered, 0.0, 1.0);

	// Grain last, on the composed image — and soft_light's sqrt(A) needs the
	// clamp above to have already happened.
	COLOR = vec4(grain_pass(col, uv), 1.0);
}
