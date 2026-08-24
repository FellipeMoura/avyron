shader_type spatial;

// Solo do mapa: dois tons misturados por ruído em espaço de MUNDO (sem UV —
// o mesmo shader serve qualquer malha de terreno), mais um terceiro tom nas
// inclinações, que é o que faz colinas e borda lerem como volume na câmera
// ortográfica. As cores vêm por uniform: a paleta é por mapa (MapDressing),
// o shader é neutro.

uniform sampler2D noise_tex;
uniform vec3 color_base : source_color = vec3(0.54, 0.51, 0.39);
uniform vec3 color_alt : source_color = vec3(0.45, 0.44, 0.33);
uniform vec3 color_slope : source_color = vec3(0.36, 0.38, 0.33);
// Faixa "seca" da costa: tom próprio na banda de Z além de coast_band_start,
// só acima de coast_dry_level — a base da rampa continua molhada. Bandas em
// uniform porque a geografia é do MapTerrain, não do shader.
uniform vec3 color_coast : source_color = vec3(0.70, 0.64, 0.49);
uniform float coast_band_start = 14.0;
uniform float coast_band_full = 19.0;
uniform float coast_dry_level = 0.9;
uniform float noise_scale = 0.045;

varying vec2 world_xz;
varying float world_y;
varying float slope;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = world.xz;
	world_y = world.y;
	// O terreno não roda nem escala; normal.y do modelo já é a inclinação.
	slope = 1.0 - normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	// Duas oitavas do mesmo ruído em escalas diferentes: mancha larga de
	// variação + granulado fino, sem precisar de segunda textura.
	float broad = texture(noise_tex, world_xz * noise_scale).r;
	float fine = texture(noise_tex, world_xz * noise_scale * 7.0).r;
	float n = broad * 0.7 + fine * 0.3;
	vec3 c = mix(color_base, color_alt, smoothstep(0.35, 0.65, n));
	float coastal = smoothstep(coast_band_start, coast_band_full, -world_xz.y)
		* smoothstep(coast_dry_level * 0.5, coast_dry_level, world_y);
	c = mix(c, color_coast, coastal);
	c = mix(c, color_slope, smoothstep(0.18, 0.45, slope) * (1.0 - coastal * 0.6));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
