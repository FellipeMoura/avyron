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
// Trecho "seco" da costa: tom próprio, só acima de coast_dry_level — a base
// da rampa continua molhada.
//
// A costa deixou de ser banda de Z em 2026-08-28 e virou LOBO: as quatro
// medidas abaixo são a mesma forma composta (círculo da barriga ∪ retângulo
// da largura) que o MapTerrain usa para levantar a malha, e que o catálogo
// descreve em coordenada normalizada. Vêm em uniform pelo mesmo motivo de
// sempre — a geografia é do terreno, o shader é neutro. Raio 0 desliga o
// trecho, como já acontece com a ilha.
uniform vec3 color_coast : source_color = vec3(0.70, 0.64, 0.49);
uniform float coast_center_x = 0.0;
uniform float coast_lobe_r = 0.0;
uniform float coast_rect_z = 0.0;
// Centro do retângulo, independente do centro do círculo acima — ver
// comentário de COAST_RECT_CENTER_X em map_terrain.gd.
uniform float coast_rect_center_x = 0.0;
uniform float coast_rect_half_w = 0.0;
uniform float coast_feather = 5.0;
uniform float coast_dry_level = 0.9;
// Meio-lado do mapa: o centro do lobo fica NA borda -Z, fora da malha, e sem
// esta medida o shader não sabe onde essa borda está.
uniform float map_half = 30.0;
// A ilha do miolo usa o MESMO tom seco da costa, em faixa radial em vez de
// banda de Z. Raio de base 0 = mapa sem ilha, e o trecho nem roda. Os valores
// chegam do MapTerrain (é a geografia dele que levanta a malha).
uniform vec2 island_center = vec2(0.0);
uniform float island_top_radius = 0.0;
uniform float island_base_radius = 0.0;
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
	float dry_gate = smoothstep(coast_dry_level * 0.5, coast_dry_level, world_y);
	float coastal = 0.0;
	if (coast_lobe_r > 0.0) {
		// A barriga: círculo centrado na borda -Z.
		float dc = distance(world_xz, vec2(coast_center_x, -map_half));
		float lobe = 1.0 - smoothstep(coast_lobe_r - coast_feather, coast_lobe_r, dc);
		// A largura: retângulo com as bordas suavizadas pela mesma folga.
		float band = 1.0 - smoothstep(coast_rect_z, coast_rect_z + coast_feather, world_xz.y);
		float side = 1.0 - smoothstep(coast_rect_half_w - coast_feather, coast_rect_half_w,
			abs(world_xz.x - coast_rect_center_x));
		coastal = max(lobe, band * side) * dry_gate;
	}
	if (island_base_radius > 0.0) {
		float d = distance(world_xz, island_center);
		coastal = max(coastal,
			(1.0 - smoothstep(island_top_radius, island_base_radius, d)) * dry_gate);
	}
	c = mix(c, color_coast, coastal);
	c = mix(c, color_slope, smoothstep(0.18, 0.45, slope) * (1.0 - coastal * 0.6));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
