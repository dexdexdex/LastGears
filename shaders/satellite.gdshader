shader_type canvas_item;
// Single full-screen pass:
//  1. darkness: the scene is multiplied by the light map (mech cones, halos,
//     beacons, flashes) that Lighting paints at half resolution;
//  2. "grainy, faltering old satellite" feed: green tint, grain, scanlines,
//     vignette (F2 toggles this part).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D light_tex : filter_linear;
uniform bool lit = true;
uniform vec3 ambient = vec3(0.035, 0.045, 0.045);
uniform float light_gain = 1.1;
uniform bool fx_on = true;
uniform float grain = 0.07;
uniform float scan = 0.06;
uniform float vignette = 0.45;
uniform float tint_amt = 0.35;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	if (lit) {
		// pow < 1 brightens the mid-range of the linear falloff baked into the cones
		vec3 L = pow(texture(light_tex, uv).rgb, vec3(0.7)) * light_gain;
		c *= min(ambient + L, vec3(1.6));
	}
	if (fx_on) {
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		vec3 mono = vec3(l * 0.9, l * 1.02, l * 0.82);
		c = mix(c, mono, tint_amt);
		c += (rand(uv * 913.0 + fract(TIME * 7.0) * 61.0) - 0.5) * grain;
		c -= (0.5 + 0.5 * sin(SCREEN_UV.y / SCREEN_PIXEL_SIZE.y * 1.6)) * scan;
		float d = distance(SCREEN_UV, vec2(0.5));
		c *= 1.0 - smoothstep(0.42, 0.85, d) * vignette;
	}
	COLOR = vec4(c, 1.0);
}
