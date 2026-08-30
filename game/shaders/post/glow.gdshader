// StarChef — glow.gdshader
// Post stack 2 of 4: soft neutral glow on highlights.
//
// The broad, gentle spill — lens scatter rather than film chemistry. Halation
// is the separate, redder, wider effect that runs after this one; keeping them
// apart is what lets you have a clean bright bloom AND a warm fringe without
// one forcing the colour of the other.

shader_type canvas_item;

#include "res://shaders/include/post_common.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// Luminance above which a pixel starts to bloom. Knee is how soft that
// boundary is - keep it well above 0 or highlights pop in and out as they
// drift across the threshold.
uniform float glow_threshold : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float glow_knee : hint_range(0.0, 0.5, 0.005) = 0.15;

// Base mip level. Each step up roughly doubles the spread.
uniform float glow_radius : hint_range(0.0, 6.0, 0.1) = 3.0;
uniform float glow_intensity : hint_range(0.0, 4.0, 0.01) = 0.5;

// Tint the spill without tinting the picture. Slightly warm off-white by
// default; push it cool for the concourse, warm for the crew mess.
uniform vec4 glow_tint : source_color = vec4(1.0, 0.97, 0.9, 1.0);


void fragment() {
	vec3 base = texture(screen_texture, UV).rgb;

	// Three mip taps standing in for a bloom chain, weighted so the tightest
	// contributes most. Godot builds mips of the screen copy because of
	// filter_linear_mipmap, so each tap is a single fetch.
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
		vec3 s = textureLod(screen_texture, UV, lod).rgb;
		float weight = 1.0 / float(i + 1);
		spill += s * post_highlight(s, glow_threshold, glow_knee) * weight;
		total += weight;
	}
	spill /= max(total, 0.0001);

	COLOR = vec4(base + spill * glow_tint.rgb * glow_intensity, 1.0);
}
