shader_type canvas_item;
// Shared prop shader (varied_material.tres):
//   - fade: see-through when the local player stands behind the prop
//   - colour variation per instance
//   - wind sway: the sprite bends like a hinge at its base on a plain sine wave
// main.gd sets player_pos and the wind settings every frame / on change.
//
// Per-instance data comes in the Sprite's self_modulate (set by scripts/varied_prop.gd),
// used when color_variance is on. 0.5 in a channel = unchanged:
//   r = hue shift (0.5 +/- fraction of the colour wheel)
//   g = saturation multiplier / 2
//   b = brightness multiplier / 2
//   a = 0.5 + sway / 2   (sway 0..1 = how much wind bends this prop; never 0 so Godot keeps drawing it)

uniform vec2 player_pos = vec2(-99999.0);
uniform float fade_radius = 30.0;
uniform float faded_alpha = 0.35;
uniform bool color_variance = false;

// Wind (set from main.gd's Wind settings). Plain sine sway: each prop's sprite is
// bent like a hinge at its base - the top moves sideways, the base stays put.
uniform float wind_strength = 3.0;      // world px the top of a sway=1 prop swings each way
uniform float wind_speed = 0.6;         // swings per second
uniform float wind_lean = 1.0;          // constant lean downwind, world px at the top
uniform float wave_spread = 0.003;      // how much the timing shifts across the map (0 = all in sync)
uniform vec2 wind_dir = vec2(1.0, 0.25);

// Night darkness (set by scripts/darkness.gd). The whole prop takes the light at
// its BASE, so tall props are never cut by their own shadow.
uniform sampler2D dk_player_light : filter_linear, repeat_disable;
uniform sampler2D dk_static_light : filter_linear, repeat_disable;
uniform vec2 dk_player_origin;
uniform vec2 dk_player_size = vec2(1.0);
uniform vec2 dk_static_origin;
uniform vec2 dk_static_size = vec2(1.0);
uniform float dk_static_strength = 1.0;
uniform vec3 dk_dark_color = vec3(0.0);
uniform float dk_darkness = 0.0;          // 0 = no darkness (fog off)
uniform float dk_radius = 380.0;          // the player's light, for proximity lighting of props
uniform float dk_squash = 0.78;
uniform float dk_start = 0.3;
uniform float dk_density = 1.5;

varying vec2 world_pos;
varying float base_lit;
varying float base_y;
varying vec2 base_pos;
varying vec4 variance;
varying float sway;

void vertex() {
	base_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;   // node origin = foot of the prop
	base_y = base_pos.y;
	// Props are lit by PROXIMITY to the player (no shadows on props - those are
	// only on the ground). Distance is measured from the player to the closest
	// point on the prop's trunk line (per sprite corner: bottom = base, top = up
	// to the prop's top), with the same fade as the ground light.
	float vy = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
	vec2 eye = player_pos - vec2(0.0, 16.0);
	vec2 sp = vec2(base_pos.x, clamp(eye.y, min(vy, base_pos.y), base_pos.y));
	float r = length((sp - eye) * vec2(1.0, 1.0 / dk_squash)) / max(dk_radius, 1.0);
	float k = clamp((r - dk_start) / max(1.0 - dk_start, 0.001), 0.0, 1.0);
	float lp = pow(1.0 - smoothstep(0.0, 1.0, k), dk_density);
	vec2 su = (base_pos - dk_static_origin) / dk_static_size;
	float ls = (su.x < 0.0 || su.y < 0.0 || su.x > 1.0 || su.y > 1.0) ? 0.0 : textureLod(dk_static_light, su, 0.0).r;
	base_lit = clamp(max(lp, ls * dk_static_strength), 0.0, 1.0);
	variance = COLOR;
	sway = color_variance ? clamp((COLOR.a - 0.5) * 2.0, 0.0, 1.0) : 0.0;
	if (sway > 0.0 && UV.y < 0.5) {
		// Top corners of the sprite only: the quad is sheared, so the art bends
		// smoothly from base (no movement) to top (full movement).
		vec2 dir = normalize(wind_dir);
		float phase = dot(base_pos, dir) * wave_spread * 6.2831;   // a slow wave rolls across the forest
		float swing = sin(TIME * wind_speed * 6.2831 - phase);
		float px = sway * (wind_lean * sign(dir.x + 0.0001) + wind_strength * swing);
		// VERTEX is in the sprite's own pixels; convert world px using the node's scale.
		VERTEX.x += px / max(length(MODEL_MATRIX[0].xy), 0.001);
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
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
	vec4 tex = texture(TEXTURE, UV);
	if (color_variance) {
		vec3 hsv = rgb2hsv(tex.rgb);
		hsv.x = fract(hsv.x + variance.r - 0.5);
		hsv.y = clamp(hsv.y * variance.g * 2.0, 0.0, 1.0);
		hsv.z = clamp(hsv.z * variance.b * 2.0, 0.0, 1.0);
		COLOR = vec4(hsv2rgb(hsv), tex.a);
	} else {
		COLOR = tex * variance;
	}
	// Distance to the player's body (a bit above the feet), squashed for the 3/4 view.
	vec2 d = (world_pos - (player_pos + vec2(0.0, -20.0))) * vec2(1.0, 0.75);
	float near = 1.0 - smoothstep(fade_radius * 0.6, fade_radius, length(d));
	float behind = step(player_pos.y, base_y);   // player is above (= behind) the prop's foot
	COLOR.a *= mix(1.0, faded_alpha, near * behind);
	COLOR.rgb = mix(COLOR.rgb, dk_dark_color, dk_darkness * (1.0 - base_lit));
}
