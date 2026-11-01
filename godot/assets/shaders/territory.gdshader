shader_type canvas_item;
// Territory overlay: each texel holds an owner id (R + G * 256) and flags (B: bit 0 = border).
// Colours come from a palette texture, so recolouring or highlighting never re-uploads tiles.

uniform sampler2D palette : filter_nearest;
uniform int selected = 0;
uniform int hovered = 0;
uniform int player = 0;
uniform float fill_alpha = 0.40;
// Border strength (colour-vision modes make it stronger).
uniform float border_dark = 0.72;
uniform float border_alpha = 0.78;

void fragment() {
	vec4 o = texture(TEXTURE, UV);
	if (o.a < 0.5) {
		COLOR = vec4(0.0);
	} else {
		int id = int(o.r * 255.0 + 0.5) + int(o.g * 255.0 + 0.5) * 256;
		int flags = int(o.b * 255.0 + 0.5);
		vec3 c = texelFetch(palette, ivec2(id % 512, 0), 0).rgb;
		float a = fill_alpha;
		// Hover and selection only lift the fill a little: the map stays readable underneath.
		if (id == hovered) {
			c = mix(c, vec3(1.0), 0.08);
			a += 0.05;
		}
		if (id == selected) {
			c = mix(c, vec3(1.0), 0.12);
			a += 0.08;
		}
		if ((flags & 1) != 0) {
			// A quiet edge: a darker shade of the owner's colour, not a contrasting outline.
			c *= border_dark;
			a = border_alpha;
		}
		COLOR = vec4(c, a);
	}
}
