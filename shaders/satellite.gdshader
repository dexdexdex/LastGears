shader_type canvas_item;
// "Grainy, faltering old satellite" feed: desaturated green tint, grain,
// scanlines, vignette and the occasional horizontal tear.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.07;
uniform float scan = 0.06;
uniform float vignette = 0.45;
uniform float tint_amt = 0.35;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float frame = floor(TIME * 12.0);
	float band = step(0.992, rand(vec2(frame, floor(uv.y * 30.0))));
	uv.x += band * 0.006 * (rand(vec2(frame, uv.y)) - 0.5);
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 mono = vec3(l * 0.9, l * 1.02, l * 0.82);
	c = mix(c, mono, tint_amt);
	c += (rand(uv * 913.0 + fract(TIME * 7.0) * 61.0) - 0.5) * grain;
	c -= (0.5 + 0.5 * sin(SCREEN_UV.y / SCREEN_PIXEL_SIZE.y * 1.6)) * scan;
	float d = distance(SCREEN_UV, vec2(0.5));
	c *= 1.0 - smoothstep(0.42, 0.85, d) * vignette;
	c += band * 0.04;
	COLOR = vec4(c, 1.0);
}
