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

// Chão residual de dois biomas com textura própria em vez de cor lisa: o
// platô glacial (BIO-014, gelo) e a costa (BIO-002, lama seca). Mapeamento
// planar em XZ — o relevo aqui é só platô raso + rampas de acesso estreitas,
// sem parede vertical que justifique triplanar. Raio 0 desliga o trecho,
// mesmo padrão da costa/ilha acima; textura sem máscara correspondente não
// aparece, mesmo sem uniform atribuído por outro mapa.
uniform sampler2D ice_tex : source_color;
uniform float ice_tex_scale = 0.12;
uniform float ice_darken = 0.65;
// Máscara do platô glacial BAKEADA pelo `MapTerrain` (mesma grade de altura,
// mesmo `_glacial_profile` COM warp) — não recalculada aqui por fórmula
// própria. A primeira versão desenhava um retângulo liso (sem o `_warp` que
// a malha usa pra desalinhar a borda), e como o relevo do platô é degrau
// reto (sobe pra LAND_HEIGHT quase exatamente na borda verdadeira, warp
// incluso), qualquer feather de cor virava ou "quadrado demais" (estreito)
// ou "marrom por cima de gelo andável" (largo) — os dois defeitos eram o
// MESMO descompasso: a cor não sabia da mesma borda irregular que a altura
// já tinha. Ler a máscara pronta garante concordância pixel a pixel, mesma
// lição de sempre (geografia e altura não podem discordar).
uniform sampler2D glacial_mask_tex;

uniform sampler2D mud_tex : source_color;
uniform float mud_tex_scale = 0.12;

// A ilha (arena, sem bioma) usa uma textura à parte, e diferente das duas
// acima ela NÃO é ladrilhada: as variantes da pasta Beach são cena inteira
// (água + espuma + areia + pedra), não um padrão uniforme — repetir em XZ
// criaria faixas de praia se repetindo. Em vez disso a escala é calibrada
// pra UM tile cobrir o diâmetro inteiro da ilha (2 · island_base_radius), e
// o UV é deslocado por +0,5 pra a costura do wrap cair fora da área visível
// (fora do raio da ilha), não bem no meio dela.
uniform sampler2D beach_tex : source_color;
uniform float beach_tex_scale = 0.056;

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
	// `coast_only`: só o lobo/retângulo da costa (BIO-002) — é a máscara da
	// textura de lama, que não deve vazar pra ilha (arena, sem bioma) mesmo
	// que as duas compartilhem o tom seco liso logo abaixo.
	float coast_only = 0.0;
	if (coast_lobe_r > 0.0) {
		// A barriga: círculo centrado na borda -Z.
		float dc = distance(world_xz, vec2(coast_center_x, -map_half));
		float lobe = 1.0 - smoothstep(coast_lobe_r - coast_feather, coast_lobe_r, dc);
		// A largura: retângulo com as bordas suavizadas pela mesma folga.
		float band = 1.0 - smoothstep(coast_rect_z, coast_rect_z + coast_feather, world_xz.y);
		float side = 1.0 - smoothstep(coast_rect_half_w - coast_feather, coast_rect_half_w,
			abs(world_xz.x - coast_rect_center_x));
		coast_only = max(lobe, band * side) * dry_gate;
	}
	// `island_only`: só a ilha (arena, sem bioma) — é a máscara da textura de
	// praia, separada de `coast_only` pelo mesmo motivo (uma não deve vazar
	// pra área da outra), mesmo as duas compartilhando o tom seco liso logo
	// abaixo via `coastal`.
	float island_only = 0.0;
	if (island_base_radius > 0.0) {
		float d = distance(world_xz, island_center);
		island_only = (1.0 - smoothstep(island_top_radius, island_base_radius, d)) * dry_gate;
	}
	float coastal = max(coast_only, island_only);
	c = mix(c, color_coast, coastal);

	// Platô glacial (BIO-014): a máscara já vem pronta (com warp) de
	// `glacial_mask_tex` — mesma UV que `terrain_water.gdshader` usa pro
	// `heightmap_tex` (mundo → [0, 2·map_half] → [0,1]), porque as duas vêm
	// da MESMA grade. A filtragem bilinear da textura já dá o anti-aliasing
	// da borda; não precisa de feather em separado.
	float glacial = texture(glacial_mask_tex, (world_xz + vec2(map_half)) / (map_half * 2.0)).r;

	vec3 mud_color = texture(mud_tex, world_xz * mud_tex_scale).rgb;
	c = mix(c, mud_color, coast_only);
	vec3 ice_color = texture(ice_tex, world_xz * ice_tex_scale).rgb * ice_darken;
	c = mix(c, ice_color, glacial);
	vec2 beach_uv = (world_xz - island_center) * beach_tex_scale + vec2(0.5);
	vec3 beach_color = texture(beach_tex, beach_uv).rgb;
	c = mix(c, beach_color, island_only);

	c = mix(c, color_slope, smoothstep(0.18, 0.45, slope) * (1.0 - coastal * 0.6) * (1.0 - glacial * 0.6));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
