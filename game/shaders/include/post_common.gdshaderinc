// StarChef — post_common.gdshaderinc
// Shared helpers for the fullscreen post stack in shaders/post/.
//
// Each effect is its own ColorRect under the CanvasLayer at layer 0, which
// means they have to agree on what counts as "a highlight" — otherwise the
// glow and the halation pick different bright areas and the two spill effects
// visibly disagree with each other.

float post_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


// 0 below the knee, ramping to 1 above it. Softness is how wide that ramp is;
// at 0 you get a hard cutoff, and anything drifting across it pops rather than
// fades — very visible on a moving highlight.
float post_highlight(vec3 c, float knee, float softness) {
	return smoothstep(knee, knee + max(softness, 0.001), post_luma(c));
}


// Aspect-corrected distance from the centre of the frame: 0 in the middle,
// 1 in the corners. stretch/aspect is "expand", so without the correction this
// is an ellipse stretched to whatever shape the monitor happens to be, and
// lens effects built on it stop behaving like a lens.
float post_edge(vec2 uv, vec2 screen_pixel_size) {
	vec2 res = 1.0 / screen_pixel_size;
	float aspect = res.x / res.y;
	vec2 from_centre = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	return clamp(length(from_centre) / length(vec2(aspect, 1.0) * 0.5), 0.0, 1.0);
}
