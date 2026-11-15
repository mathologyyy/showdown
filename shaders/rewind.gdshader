shader_type canvas_item;
// VHS-artiger Effekt fürs Zurückspulen (Phase.REWIND): zeilenweiser Jitter,
// wandernde Tracking-Störbänder, Farbversatz (R/B), Scanlines, Bildrauschen und
// Entsättigung. Das ColorRect mit diesem Shader liegt als erstes HUD-Kind über
// dem Spielbild – die HUD-Texte darüber bleiben scharf.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;      // 0 = aus, 1 = voller Effekt
uniform float desaturation : hint_range(0.0, 1.0) = 0.85; // Anteil Graustufen bei voller Stärke

// Pseudozufall aus einem 2D-Index
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = clamp(SCREEN_UV, 0.0, 1.0);
	float s = strength;
	float row = floor(uv.y * 240.0);

	// zeilenweiser horizontaler Versatz (Jitter), wechselt pro Zeile ~30x pro Sekunde
	float jitter = (hash(vec2(row, floor(TIME * 30.0))) - 0.5) * 2.0 * 0.004;

	// zwei wandernde Tracking-Störbänder: schmale Streifen, die mit TIME von
	// unten nach oben durchs Bild laufen
	float band = 0.0;      // 0..1: Band-Stärke an dieser Zeile
	float band_off = 0.0;  // zusätzlicher starker Versatz innerhalb des Bandes
	for (int i = 0; i < 2; i++) {
		float fi = float(i);
		float y = fract(uv.y - TIME * (0.11 + 0.06 * fi) + fi * 0.37);
		float d = abs(y - 0.5) * 2.0;              // Abstand zur Bandmitte, 0..1
		float w = 1.0 - smoothstep(0.0, 0.06, d);  // schmaler Streifen
		band = max(band, w);
		band_off += w * (hash(vec2(row * 1.7 + fi * 91.0, floor(TIME * 12.0))) - 0.5) * 2.0 * 0.03;
	}

	float off = (jitter + band_off) * s;
	vec2 cuv = clamp(uv + vec2(off, 0.0), 0.0, 1.0);

	// Farbversatz: R und B horizontal gegeneinander verschoben
	float ca = 0.003 * s;
	float r = texture(screen_tex, clamp(cuv + vec2(ca, 0.0), 0.0, 1.0)).r;
	float g = texture(screen_tex, cuv).g;
	float b = texture(screen_tex, clamp(cuv - vec2(ca, 0.0), 0.0, 1.0)).b;
	vec3 col = vec3(r, g, b);

	// helles Rauschen in den Tracking-Bändern
	col += band * s * (hash(vec2(row, floor(TIME * 24.0)) + 7.0) - 0.5) * 0.8;

	// feine Scanlines (~8 % Abdunkelung) und leichtes Bildrauschen (~6 %)
	col *= 1.0 - 0.08 * s * (0.5 + 0.5 * sin(uv.y * 240.0 * TAU));
	col += (hash(uv * vec2(1234.0, 987.0) + vec2(floor(TIME * 30.0))) - 0.5) * 0.06 * s;

	// Entsättigung
	float gray = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(gray), desaturation * s);

	COLOR = vec4(col, 1.0);
}
