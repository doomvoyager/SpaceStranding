shader_type spatial;
// One grain of thrown regolith: a billboard drawn as a tiny sphere.
//
// A billboard is a quad whose normal faces the eye, so Godot lights it as a
// wall you are looking at - cross-sun, where a spray is most visible, that
// wall is edge-on to the sun and goes black, which is why the first grain
// was unshaded. This one keeps the quad but lies about the normal: each
// pixel takes the normal of a sphere bulging toward the camera, so the sun
// lights the sun's side, the shadow map darkens a grain in the rover's or a
// crater's shadow, and the scene's ambient fills it like any other prop.
// Cross-sun a grain reads half-lit, like a very small moon.
//
// The vertex half is Godot's own BILLBOARD_PARTICLES code, keeping the
// particle's scale and rotation; nothing here is specific to dust but the
// name.

render_mode cull_disabled, depth_draw_opaque;

uniform vec4 albedo : source_color = vec4(0.62, 0.6, 0.57, 1.0);


void vertex() {
	mat4 mat_world = mat4(
		normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]),
		normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mat_world = mat_world * mat4(
		vec4(cos(INSTANCE_CUSTOM.x), -sin(INSTANCE_CUSTOM.x), 0.0, 0.0),
		vec4(sin(INSTANCE_CUSTOM.x), cos(INSTANCE_CUSTOM.x), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	// Keep the particle's scale.
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	if (r2 > 1.0) {
		discard;
	}
	// The sphere's normal, in view space. UV.y runs down the quad and view
	// Y runs up, and +Z is toward the camera.
	NORMAL = normalize(vec3(p.x, -p.y, sqrt(1.0 - r2)));
	ALBEDO = albedo.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
