shader_type canvas_item;
// Idle breathing for the settler: the sprite is gently stretched up from the feet
// and swayed on a sine wave (same idea as the tree wind). The feet never move.
// player.gd fades "active" in when he stands still and out when he moves.

uniform float active = 0.0;          // 0 = off (moving), 1 = full idle
uniform float breath_amount = 1.0;   // px the top of his head rises at full breath
uniform float breath_speed = 0.35;   // breaths per second
uniform float sway_amount = 0.4;     // px the top of his head drifts sideways
uniform float sway_speed = 0.18;     // sway cycles per second

void vertex() {
	if (active > 0.0 && UV.y < 0.5) {   // top corners only: base stays planted
		float breath = 0.5 - 0.5 * cos(TIME * breath_speed * 6.2831);
		float sway = sin(TIME * sway_speed * 6.2831);
		VERTEX.y -= breath_amount * breath * active;
		VERTEX.x += sway_amount * sway * active;
	}
}
