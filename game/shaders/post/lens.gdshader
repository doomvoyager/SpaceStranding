// StarChef — lens.gdshader
// Post stack 1 of 4: chromatic aberration and lens softness.
//
// Both worsen toward the corners off one shared falloff, because that is what
// a real lens does. Uniform CA reads as a broken video signal and uniform blur
// reads as a mistake.
//
// Stack order under the CanvasLayer: Lens -> Glow -> Halation -> Grain.

shader_type canvas_item;

#include "res://shaders/include/post_common.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// repeat_disable above is load-bearing: once the aberration samples past the
// frame edge, repeat would wrap and pull red from the opposite side of screen.

uniform float ca_amount : hint_range(0.0, 0.02, 0.0005) = 0.003;
uniform float lens_softness : hint_range(0.0, 4.0, 0.05) = 0.6;
uniform float edge_falloff : hint_range(0.5, 4.0, 0.05) = 2.0;


void fragment() {
	vec2 uv = UV;
	float edge = pow(post_edge(uv, SCREEN_PIXEL_SIZE), edge_falloff);

	// One set of three fetches carries both effects. Red is pulled inward
	// along the radius and blue pushed outward, the direction a real lens
	// splits them; green stays put so the image itself doesn't drift.
	// The LOD is the softness — filter_linear_mipmap is what makes Godot build
	// mips of the screen copy, so the blur costs an argument, not a tap loop.
	vec2 ca_offset = (uv - vec2(0.5)) * ca_amount * edge;
	float lod = lens_softness * edge;

	vec3 col;
	col.r = textureLod(screen_texture, uv - ca_offset, lod).r;
	col.g = textureLod(screen_texture, uv,             lod).g;
	col.b = textureLod(screen_texture, uv + ca_offset, lod).b;

	COLOR = vec4(col, 1.0);
}
