shader_type canvas_item;
// Territory overlay: each texel holds an owner id (R + G * 256) and flags (B: bit 0 = border).
// Colours come from a palette texture, so recolouring or highlighting never re-uploads tiles.

uniform sampler2D palette : filter_nearest;
uniform int selected = 0;
uniform int hovered = 0;
uniform int player = 0;
uniform float fill_alpha = 0.48;

void fragment() {
	vec4 o = texture(TEXTURE, UV);
	if (o.a < 0.5) {
		COLOR = vec4(0.0);
	} else {
		int id = int(o.r * 255.0 + 0.5) + int(o.g * 255.0 + 0.5) * 256;
		int flags = int(o.b * 255.0 + 0.5);
		vec3 c = texelFetch(palette, ivec2(id % 512, 0), 0).rgb;
		float a = fill_alpha;
		if (id == hovered) {
			c = mix(c, vec3(1.0), 0.12);
			a += 0.1;
		}
		if (id == selected) {
			c = mix(c, vec3(1.0), 0.2);
			a += 0.16;
		}
		if ((flags & 1) != 0) {
			c *= (id == player) ? 0.55 : 0.68;
			a = 0.96;
			if (id == selected) {
				c = mix(c, vec3(1.0), 0.6);
			}
		}
		COLOR = vec4(c, a);
	}
}
