// StarChef — grain.gdshader
// Post stack 4 of 4, and it must stay last.
//
// Grain sits in the emulsion, so everything the lens and the film base do to
// the picture happens underneath it. Put grain before the glow or the halation
// and those effects bloom the noise instead of the image.
//
// Mac's implementation: soft-light blended rather than added, weighted toward
// the shadows rather than the midtones, and coloured because the three
// channels get independent noise. All deliberate — `grain_saturation` is the
// control for that last part.

shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

uniform float grain_intensity : hint_range(0.0, 1.0) = 0.1;

// 0 is monochrome emulsion, 1 is the look as authored, above 1 pushes the
// channels further apart than the noise alone would.
uniform float grain_saturation : hint_range(0.0, 2.0) = 1.0;

uniform float min_lum : hint_range(0.0, 1.0) = 0.0;
uniform float max_lum : hint_range(0.0, 1.0) = 1.0;
uniform float time_scale : hint_range(0.0, 1.0) = 0.5;


float noise(vec2 p) {
    return (fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;
}

vec3 soft_light(vec3 A, vec3 B) {
    vec3 branch1 = 2.0 * A * B + A * A * (1.0 - 2.0 * B);
    vec3 branch2 = 2.0 * A * (1.0 - B) + sqrt(A) * (2.0 * B - 1.0);
    vec3 condition = step(0.5, B);
    return mix(branch1, branch2, condition);
}

void fragment() {
    vec2 uv = UV;
    vec3 original_color = texture(screen_texture, uv).rgb;

    float lum = dot(original_color, vec3(0.299, 0.587, 0.114));
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
    vec3 final_color = soft_light(original_color, grain_color);

    COLOR = vec4(final_color, 1.0);
}
