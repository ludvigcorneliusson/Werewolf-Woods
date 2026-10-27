shader_type canvas_item;
// Makes a tree/bush see-through when the local player stands behind it.
// main.gd updates player_pos every frame on the shared prop_material.tres.

uniform vec2 player_pos = vec2(-99999.0);
uniform float fade_radius = 30.0;
uniform float faded_alpha = 0.35;

varying vec2 world_pos;
varying float base_y;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	base_y = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y;   // node origin = foot of the prop
}

void fragment() {
	// Distance to the player's body (a bit above the feet), squashed for the 3/4 view.
	vec2 d = (world_pos - (player_pos + vec2(0.0, -20.0))) * vec2(1.0, 0.75);
	float near = 1.0 - smoothstep(fade_radius * 0.6, fade_radius, length(d));
	float behind = step(player_pos.y, base_y);   // player is above (= behind) the prop's foot
	COLOR.a *= mix(1.0, faded_alpha, near * behind);
}
