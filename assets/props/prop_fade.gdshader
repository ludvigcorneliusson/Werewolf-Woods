shader_type canvas_item;
// Makes a tree/bush see-through when the local player stands behind it.
// main.gd updates player_pos every frame on prop_material.tres and pine_material.tres.
//
// color_variance (pine_material.tres): each pine's Sprite self_modulate carries
// its own colour shift, set by scripts/pine.gd. 0.5 in a channel = unchanged:
//   r = hue shift (0.5 +/- fraction of the colour wheel)
//   g = saturation multiplier / 2
//   b = brightness multiplier / 2

uniform vec2 player_pos = vec2(-99999.0);
uniform float fade_radius = 30.0;
uniform float faded_alpha = 0.35;
uniform bool color_variance = false;

varying vec2 world_pos;
varying float base_y;
varying vec4 variance;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	base_y = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y;   // node origin = foot of the prop
	variance = COLOR;
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	if (color_variance) {
		vec4 tex = texture(TEXTURE, UV);
		vec3 hsv = rgb2hsv(tex.rgb);
		hsv.x = fract(hsv.x + variance.r - 0.5);
		hsv.y = clamp(hsv.y * variance.g * 2.0, 0.0, 1.0);
		hsv.z = clamp(hsv.z * variance.b * 2.0, 0.0, 1.0);
		COLOR = vec4(hsv2rgb(hsv), tex.a * variance.a);
	}
	// Distance to the player's body (a bit above the feet), squashed for the 3/4 view.
	vec2 d = (world_pos - (player_pos + vec2(0.0, -20.0))) * vec2(1.0, 0.75);
	float near = 1.0 - smoothstep(fade_radius * 0.6, fade_radius, length(d));
	float behind = step(player_pos.y, base_y);   // player is above (= behind) the prop's foot
	COLOR.a *= mix(1.0, faded_alpha, near * behind);
}
