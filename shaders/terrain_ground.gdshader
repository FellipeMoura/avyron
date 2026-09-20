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
// A costa deixou de ser banda de Z em 2026-08-28 e virou LOBO (círculo da
// barriga ∪ retângulo da largura, hoje com canto arredondado + warp de duas
// oitavas). Até 2026-09-18 essa forma era recalculada aqui em GLSL a partir
// de 6 uniforms; virou máscara BAKEADA (`coast_mask_tex`, abaixo, mesma
// técnica de `glacial_mask_tex`) porque reproduzir o SDF arredondado E as
// duas oitavas de ruído em GLSL duplicaria a mesma geometria em dois
// lugares — e porque o shader recalculado exigia um raio de círculo > 0 só
// pra ligar o retângulo também (o gate `coast_lobe_r > 0.0` cobria os dois),
// uma armadilha que a máscara pronta apaga de vez.
uniform vec3 color_coast : source_color = vec3(0.70, 0.64, 0.49);
// Máscara da costa BAKEADA pelo `MapTerrain` (mesma grade, mesmo
// `_coast_profile` com warp e SDF arredondado) — ver comentário de
// `glacial_mask_tex` abaixo pra a mesma lição (geografia e cor não podem
// discordar).
uniform sampler2D coast_mask_tex;
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

// Os dois trechos secos com textura própria em vez de cor lisa: o platô
// glacial (BIO-014) logo abaixo e a costa (BIO-002) mais adiante. Mapeamento
// planar em XZ — o relevo aqui é só platô raso e rampa de borda, sem parede
// vertical que justifique triplanar. Máscara vazia desliga o trecho: textura
// sem a máscara correspondente não aparece, mesmo num mapa que não atribua
// uniform nenhum.
// Platô glacial (BIO-014) em duas camadas, mesma receita da costa (2026-09-18,
// no lugar da textura de gelo única que vinha desde a Fase 2):
//
//   - `snow_rock_tex` Snow Ground 4 — rocha exposta com neve nas frestas, na
//     BORDA, onde o gelo quebra contra o mar e o vento varre a neve;
//   - `snow_tex`      Snow 8 — placas de neve claras, no miolo do platô.
//
// A ordem é a inversa da costa por geologia, não por capricho: lá o material
// "sujo" fica para dentro (terra seca) e o liso na água; aqui o liso é o
// interior intocado e o quebrado é a borda.
uniform sampler2D snow_tex : source_color;
uniform sampler2D snow_height_tex;
uniform float snow_tex_scale = 0.12;
uniform sampler2D snow_rock_tex : source_color;
uniform sampler2D snow_rock_height_tex;
uniform float snow_rock_tex_scale = 0.12;
// Neve é a superfície mais clara do mapa, e a câmera ortográfica não tem
// exposição automática: sem escurecer, o platô estoura e o corpo do jogador
// vira silhueta preta em cima dele. Vinha de `ice_darken` (0,65) na textura
// antiga, que era mais escura de origem.
uniform float glacial_darken = 0.82;
// Distância (m) da borda do platô para dentro, bakeada pelo `MapTerrain` —
// mesma técnica de `coast_inland_tex`, pelo mesmo motivo: o platô é plano, e
// altura não distingue "beira" de "miolo".
uniform sampler2D glacial_inland_tex : filter_linear, repeat_disable;
uniform float glacial_snow_start = 9.0;
uniform float glacial_snow_feather = 4.0;
uniform float glacial_snow_jitter = 5.0;
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

// Costa (BIO-002) em duas camadas do mesmo tema do pack (variações escolhidas
// a olho em 2026-09-17, ver `textures/terrain/`):
//
//   - `mud_tex`     Mud 4  — placas com fenda escura, na beira d'água;
//   - `mud_dry_tex` Mud 10 — placas grandes e claras, platô adentro.
//
// Cada uma traz o mapa de ALTURA do pack, usado só para misturar (ver
// `height_blend` e `hex_sample`), nunca para luz: o cel-shading do projeto
// dispensa normal map, e a altura serve aqui como máscara, não como relevo.
//
// Uma terceira camada de pedras (Mud 8, em manchas de ruído) existiu no
// primeiro protótipo e saiu: a mancha de textura lia como tapete colado, e
// pedra no chão é trabalho de PROP, não de textura — quem faz isso agora são
// os matacões e seixos do MegaKit que o `MapDressing` planta na linha da
// água.
uniform sampler2D mud_tex : source_color;
uniform sampler2D mud_height_tex;
uniform float mud_tex_scale = 0.12;
uniform sampler2D mud_dry_tex : source_color;
uniform sampler2D mud_dry_height_tex;
uniform float mud_dry_tex_scale = 0.12;

// A praça da vila (2026-09-20): terceira camada da costa, POR CIMA da lama, só
// dentro da máscara bakeada em volta dos serviços (`village_mask_tex`, escrita
// pelo `MapDressing` — ver `plaza_profile` lá: é a MESMA função que decide
// onde o scatter não entra e onde as lajes soltas ficam, então cor e cenário
// não discordam). Stone Wall 1 do mesmo pack — lajes irregulares
// cinza-azuladas, sem planta (a variante 5, mais bonita, tem tufos de capim,
// e planta terrestre contradiz a época do PZ-01); `paved_tint` aquece para a
// família do `color_coast`, como o `TINT` do MapDressing faz com o seixo do
// MegaKit. Mesmo par diffuse+altura, mesmo `hex_sample`, e entra por
// `height_blend` para a lama subir pelas juntas das lajes na ORLA — no miolo
// (máscara perto de 1) a laje vence por inteiro, senão a praça leria como
// piso sujo.
//
// `hint_default_black` porque mapa sem praça não atribui a máscara — e ela tem
// de ler 0 (sampler2D sem hint lê branco, e a praça cobriria o mapa inteiro).
uniform sampler2D village_mask_tex : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D paved_tex : source_color;
uniform sampler2D paved_height_tex;
uniform float paved_tex_scale = 0.16;
uniform vec3 paved_tint : source_color = vec3(1.0);

// Distância (m) da borda de cima da rampa para dentro do platô, bakeada pelo
// `MapTerrain` da mesma forma que levanta a malha. A costa é plana, então é
// esta medida — e não a altura — que diz "perto da água".
uniform sampler2D coast_inland_tex : filter_linear, repeat_disable;
// Até onde a lama úmida alcança platô adentro, e a largura da passagem para o
// seco. O ruído `coast_wet_jitter` (± m) desalinha a linha, que de outro modo
// seguiria a borda da rampa como uma faixa paralela.
uniform float coast_wet_width = 7.0;
uniform float coast_wet_feather = 3.0;
uniform float coast_wet_jitter = 5.0;
// Quanto de altura a mistura "enxerga" ao decidir quem aparece. Menor = borda
// mais dura, seguindo o desenho do mapa de altura; maior = mais esfumado.
uniform float height_blend_depth = 0.12;

// ## Anti-ladrilho hexagonal
//
// Quanto mais GRÁFICA a textura, mais a repetição aparece: as placas da Mud 10
// desenhavam um azulejo visível a cada 8 m na captura de 2026-09-17, e era o
// defeito que sobrava depois de a faixa úmida ficar boa.
//
// A técnica: a costa é dividida numa grade triangular (que dá células
// hexagonais), cada célula sorteia um DESLOCAMENTO de UV próprio, e o ponto
// mistura as três células mais próximas. O padrão continua sendo a mesma
// imagem repetida, mas a posição dela muda de célula em célula — o olho perde
// a grade.
//
// `hex_scale` é em células por metro: 0,05 dá célula de ~20 m, maior que o
// ladrilho (8 m) de propósito. Célula menor que o ladrilho embaralharia a
// textura em vez de esconder a emenda.
uniform float hex_scale = 0.05;
// Peso da altura na mistura entre células. A mistura linear das três amostras
// é o que "lava" a imagem nas bordas da célula (o defeito clássico desta
// técnica); deixar a altura participar faz a amostra com o ponto mais alto
// vencer, e a emenda fica onde o desenho da textura já tinha uma quina.
uniform float hex_height_weight = 0.35;

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

// Mistura por altura: `t` = 0 é só `a`, 1 é só `b`. No meio, quem tem o ponto
// mais ALTO aparece primeiro — a lama úmida entra pelas rachaduras (baixas)
// da terra seca antes de cobrir as placas, e as pedras (altas) surgem da
// terra pelo topo. Uma mistura linear faria a mesma passagem como as duas
// imagens semitransparentes uma sobre a outra.
vec3 height_blend(vec3 a, float ha, vec3 b, float hb, float t) {
	float wa = ha + (1.0 - t);
	float wb = hb + t;
	float top = max(wa, wb) - height_blend_depth;
	float ka = max(wa - top, 0.0);
	float kb = max(wb - top, 0.0);
	return (a * ka + b * kb) / max(ka + kb, 0.0001);
}

// Ruído de célula: dois valores em [0,1) a partir do índice inteiro dela.
// `sin`/`fract` em vez de textura porque isto roda 3× por camada e precisa ser
// o mesmo valor para a mesma célula, sem depender de amostragem.
vec2 hex_hash(vec2 cell) {
	return fract(sin(vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)))) * 43758.5453);
}

// A grade triangular por trás das células hexagonais: devolve as três células
// vizinhas e o peso baricêntrico de cada uma no ponto.
void hex_cells(vec2 p, out vec2 c1, out vec2 c2, out vec2 c3, out vec3 w) {
	// Inclina a grade quadrada em 60° — é o que transforma quadrados em
	// triângulos equiláteros, e a vizinhança de cada vértice num hexágono.
	vec2 skewed = mat2(vec2(1.0, 0.0), vec2(-0.57735027, 1.15470054)) * p;
	vec2 base = floor(skewed);
	vec3 bary = vec3(fract(skewed), 0.0);
	bary.z = 1.0 - bary.x - bary.y;
	if (bary.z > 0.0) {
		w = vec3(bary.z, bary.y, bary.x);
		c1 = base;
		c2 = base + vec2(0.0, 1.0);
		c3 = base + vec2(1.0, 0.0);
	} else {
		// Metade de cima do quadrado: o triângulo é o espelhado.
		w = vec3(-bary.z, 1.0 - bary.y, 1.0 - bary.x);
		c1 = base + vec2(1.0, 1.0);
		c2 = base + vec2(1.0, 0.0);
		c3 = base + vec2(0.0, 1.0);
	}
}

// A textura amostrada sem grade visível: três deslocamentos de UV, um por
// célula, misturados por peso baricêntrico E altura.
void hex_sample(sampler2D tex, sampler2D height_tex, vec2 xz, float tex_scale, out vec3 color, out float height) {
	vec2 c1;
	vec2 c2;
	vec2 c3;
	vec3 w;
	hex_cells(xz * hex_scale, c1, c2, c3, w);
	vec2 uv = xz * tex_scale;
	// Amostra com a DERIVADA explícita, e não `texture()`.
	//
	// O deslocamento por célula SALTA de uma célula para a vizinha. A GPU
	// escolhe o nível de mipmap pela variação da UV dentro do quadrado de 2×2
	// pixels que ela sombreia junto; no quadrado que cruza a fronteira, essa
	// variação é o salto inteiro, e ela cai no mip mais grosseiro — um pixel
	// borrado e escuro. O resultado é uma linha PONTILHADA ao longo de cada
	// fronteira de célula, achada em captura em 2026-09-17 e confirmada por
	// eliminação (desligar o anti-ladrilho apagava; desligar a altura não).
	//
	// `dFdx`/`dFdy` sobre a UV sem deslocamento dão a variação de verdade —
	// a mesma para as três amostras, porque as três são a mesma textura na
	// mesma escala.
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 o1 = hex_hash(c1);
	vec2 o2 = hex_hash(c2);
	vec2 o3 = hex_hash(c3);
	vec3 s1 = textureGrad(tex, uv + o1, dx, dy).rgb;
	vec3 s2 = textureGrad(tex, uv + o2, dx, dy).rgb;
	vec3 s3 = textureGrad(tex, uv + o3, dx, dy).rgb;
	float h1 = textureGrad(height_tex, uv + o1, dx, dy).r;
	float h2 = textureGrad(height_tex, uv + o2, dx, dy).r;
	float h3 = textureGrad(height_tex, uv + o3, dx, dy).r;
	// Pesos ao cubo: afinam a transição para perto da borda da célula, senão a
	// mistura cobre a célula inteira e a textura perde contraste no miolo dela.
	vec3 k = w * w * w;
	vec3 e = k + vec3(h1, h2, h3) * hex_height_weight;
	float top = max(e.x, max(e.y, e.z)) - height_blend_depth;
	e = max(e - vec3(top), vec3(0.0));
	float sum = e.x + e.y + e.z;
	color = (s1 * e.x + s2 * e.y + s3 * e.z) / max(sum, 0.0001);
	height = dot(vec3(h1, h2, h3), e) / max(sum, 0.0001);
}

// `height` devolve a altura da lama resultante — é o que deixa a praça entrar
// por cima pelo mesmo `height_blend` (ver `village_mask_tex`).
vec3 coast_mud(vec2 xz, out float height) {
	vec3 wet;
	float wet_h;
	hex_sample(mud_tex, mud_height_tex, xz, mud_tex_scale, wet, wet_h);
	// A camada do platô anda com a grade hexagonal deslocada: as duas usam a
	// mesma célula, e sem isto as emendas das duas cairiam no mesmo lugar.
	vec3 dry;
	float dry_h;
	hex_sample(mud_dry_tex, mud_dry_height_tex, xz + vec2(137.0, 61.0), mud_dry_tex_scale, dry, dry_h);

	float inland = texture(coast_inland_tex, (xz + vec2(map_half)) / (map_half * 2.0)).r;
	float jitter = (texture(noise_tex, xz * 0.03).r - 0.5) * 2.0 * coast_wet_jitter;
	float dryness = smoothstep(coast_wet_width - coast_wet_feather,
		coast_wet_width + coast_wet_feather, inland + jitter);

	height = mix(wet_h, dry_h, dryness);
	return height_blend(wet, wet_h, dry, dry_h, dryness);
}

// A praça sobre a lama: `paved` é a máscara (0 fora, 1 no miolo). Na orla a
// mistura é por altura (lama nas juntas das lajes); do meio para dentro
// converge para a laje pura.
vec3 village_paving(vec2 xz, vec3 mud, float mud_h, float paved) {
	vec3 stone;
	float stone_h;
	// Deslocamento próprio da grade hexagonal, como cada camada da costa tem.
	hex_sample(paved_tex, paved_height_tex, xz + vec2(53.0, 211.0), paved_tex_scale, stone, stone_h);
	stone *= paved_tint;
	vec3 fringe = height_blend(mud, mud_h, stone, stone_h, paved);
	return mix(fringe, stone, smoothstep(0.7, 1.0, paved));
}

// O chão do platô glacial: rocha exposta na borda, neve no miolo. Espelha
// `coast_mud` — a diferença é o que cada lado significa (ver os uniforms).
vec3 glacial_snow(vec2 xz) {
	vec3 rock;
	float rock_h;
	hex_sample(snow_rock_tex, snow_rock_height_tex, xz, snow_rock_tex_scale, rock, rock_h);
	vec3 snow;
	float snow_h;
	hex_sample(snow_tex, snow_height_tex, xz + vec2(211.0, 97.0), snow_tex_scale, snow, snow_h);

	float inland = texture(glacial_inland_tex, (xz + vec2(map_half)) / (map_half * 2.0)).r;
	float jitter = (texture(noise_tex, xz * 0.03 + vec2(0.25)).r - 0.5) * 2.0 * glacial_snow_jitter;
	float snowiness = smoothstep(glacial_snow_start - glacial_snow_feather,
		glacial_snow_start + glacial_snow_feather, inland + jitter);

	return height_blend(rock, rock_h, snow, snow_h, snowiness) * glacial_darken;
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
	// que as duas compartilhem o tom seco liso logo abaixo. Bakeada (ver
	// `coast_mask_tex`), mesma UV que `glacial_mask_tex`/`heightmap_tex` usam
	// (mundo → [0, 2·map_half] → [0,1], porque as três vêm da MESMA grade).
	float coast_only = texture(coast_mask_tex, (world_xz + vec2(map_half)) / (map_half * 2.0)).r * dry_gate;
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

	if (coast_only > 0.0) {
		float mud_h;
		vec3 mud = coast_mud(world_xz, mud_h);
		// `* coast_only`: a máscara da praça é bakeada num retângulo com warp e
		// não sabe da forma da costa — multiplicar impede a laje de vazar para
		// a rampa ou para o mar se alguém deslocar a vila até a borda.
		float paved = texture(village_mask_tex, (world_xz + vec2(map_half)) / (map_half * 2.0)).r * coast_only;
		if (paved > 0.0) {
			mud = village_paving(world_xz, mud, mud_h, paved);
		}
		c = mix(c, mud, coast_only);
	}
	if (glacial > 0.0) {
		c = mix(c, glacial_snow(world_xz), glacial);
	}
	vec2 beach_uv = (world_xz - island_center) * beach_tex_scale + vec2(0.5);
	vec3 beach_color = texture(beach_tex, beach_uv).rgb;
	c = mix(c, beach_color, island_only);

	c = mix(c, color_slope, smoothstep(0.18, 0.45, slope) * (1.0 - coastal * 0.6) * (1.0 - glacial * 0.6));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
