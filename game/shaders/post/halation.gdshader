// StarChef — halation.gdshader
// Post stack 3 of 4: the warm fringe around highlights.
//
// Halation is not bloom. Light passes THROUGH the emulsion, reflects off the
// film base, and comes back up to re-expose the layer around a highlight. The
// anti-halation backing absorbs short wavelengths, so it is the red end that
// survives the round trip — which is why the fringe is red-orange rather than
// whatever colour the highlight was.
//
// That physical cause is worth reproducing rather than faking with a flat
// tint: the channels here spread at DIFFERENT radii, red widest, so the colour
// emerges from the spread the way it does on film. `halation_tint` is then a
// nudge on top rather than the whole effect.

shader_type canvas_item;

#include "res://shaders/include/post_common.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;

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


void fragment() {
	vec3 base = texture(screen_texture, UV).rgb;

	float lod_r = halation_radius + channel_spread;
	float lod_g = halation_radius;
	float lod_b = max(halation_radius - channel_spread, 0.0);

	vec3 wide = vec3(
		textureLod(screen_texture, UV, lod_r).r,
		textureLod(screen_texture, UV, lod_g).g,
		textureLod(screen_texture, UV, lod_b).b
	);

	float mask = post_highlight(wide, halation_threshold, halation_knee);
	vec3 spill = wide * mask * halation_tint.rgb * halation_intensity;

	COLOR = vec4(base + spill, 1.0);
}
