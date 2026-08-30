// StarChef — film.gdshader
// The entire post stack in one pass: lens -> glow -> halation -> grain.
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

shader_type canvas_item;

#include "res://shaders/include/post_common.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// repeat_disable is load-bearing: once the aberration samples past the frame
// edge, repeat would wrap and pull red from the opposite side of the screen.


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


float noise(vec2 p) {
	return (fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;
}

vec3 soft_light(vec3 A, vec3 B) {
	vec3 branch1 = 2.0 * A * B + A * A * (1.0 - 2.0 * B);
	vec3 branch2 = 2.0 * A * (1.0 - B) + sqrt(A) * (2.0 * B - 1.0);
	vec3 condition = step(0.5, B);
	return mix(branch1, branch2, condition);
}


// --- 1 of 4: chromatic aberration and lens softness ---------------------------
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


// --- 2 of 4: soft neutral glow on highlights ---------------------------------
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


// --- 3 of 4: the warm fringe around highlights -------------------------------
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


// --- 4 of 4: grain, and it must stay last ------------------------------------
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

	// Grain last, on the composed image — and soft_light's sqrt(A) needs the
	// clamp above to have already happened.
	COLOR = vec4(grain_pass(col, uv), 1.0);
}
