shader_type canvas_item;
// Dunkelt alles ab, was nicht in der Sichtmaske liegt.
// mask_tex: weiß = sichtbar (Sichtkegel-Polygone aus dem SubViewport), schwarz = verdeckt.

uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform float darkness = 0.93;
uniform vec2 blur = vec2(0.003, 0.005);

void fragment() {
	// kleiner 5-Tap-Blur für weiche Kegelkanten
	float m = texture(mask_tex, UV).r * 0.4;
	m += texture(mask_tex, UV + vec2(blur.x, 0.0)).r * 0.15;
	m += texture(mask_tex, UV - vec2(blur.x, 0.0)).r * 0.15;
	m += texture(mask_tex, UV + vec2(0.0, blur.y)).r * 0.15;
	m += texture(mask_tex, UV - vec2(0.0, blur.y)).r * 0.15;
	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - m) * darkness);
}
