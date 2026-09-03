shader_type spatial;
render_mode blend_mix, cull_back, diffuse_lambert, specular_schlick_ggx;

// Superfície da água: cor por profundidade (rasa clara → funda escura),
// espuma na linha onde o relevo encontra a cota, leve ondulação vertical só
// de leitura (não é física de onda).
//
// A profundidade vem da MESMA grade de altura que gera a malha e a colisão
// do terreno (`MapTerrain.build_water_mesh` bake essa grade num `heightmap_tex`
// de um canal), não de depth-buffer de tela: câmera ortográfica não dá um
// "olho" único pra reconstruir posição de mundo a partir da profundidade de
// tela do jeito que perspectiva dá, e a grade já existe pronta em memória —
// reusar é mais simples e mais correto que a técnica de depth-fade padrão.

uniform sampler2D heightmap_tex;
uniform float map_half = 60.0;
uniform float map_size = 120.0;
uniform float water_line = 1.25;

uniform vec3 color_shallow : source_color = vec3(0.30, 0.75, 0.70);
uniform vec3 color_deep : source_color = vec3(0.05, 0.24, 0.36);
// Profundidade (m) em que a cor já bateu no fundo da rampa — além disso é
// tudo a mesma cor funda. Era 8,0 até 2026-09-01, calibrado para um mar com
// profundidade de verdade (Mar Profundo incluso, >10 m). Desde que o leito
// ficou raso de propósito (`MapTerrain.SEA_HEIGHT`, ~1,65 m de profundidade
// máxima em mar aberto — ver o comentário lá), o valor antigo nunca chegava
// nem perto do fundo da rampa: o mar inteiro lia como raso, sem gradiente
// nenhum. 1,6 m faz a cor variar de verdade no pouco de profundidade que
// existe.
uniform float depth_fade = 1.6;

uniform vec3 color_foam : source_color = vec3(0.92, 0.98, 0.97);
// Folga de profundidade (m) em que a espuma ainda aparece — não é linha dura,
// é gradiente, para não ler como corte de textura.
uniform float foam_width = 0.35;

uniform float wave_speed = 0.35;
uniform float wave_amplitude = 0.06;
uniform float wave_scale = 0.08;

// Detalhe de superfície opcional — textura tileável em XZ, só luminância,
// multiplicando o gradiente de profundidade em vez de substituir a cor: o
// gradiente raso→fundo e a espuma continuam sendo o que fazem a água ler
// certo (calibrados contra a grade de altura de verdade), a textura só quebra
// a leitura "tinta lisa". Sem normal/metallic de propósito, mesma regra do
// resto do jogo — força seria mudar ROUGHNESS/SPECULAR, não isto.
uniform sampler2D water_tex : source_color;
uniform float water_tex_scale = 0.15;
uniform float water_detail_strength = 1.0;
// Deslocamento de UV por tempo — a mesma textura estática, arrastada, lê
// como corrente. Direção normalizada dentro do shader, não pelo uniform, pra
// (0,0) continuar uma opção válida (desliga o arrasto) em vez de indefinido.
uniform vec2 water_flow_dir = vec2(0.6, 1.0);
uniform float water_flow_speed = 0.03;

varying vec2 world_xz;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = world.xz;
	// Duas ondas cruzadas, período e fase diferentes — evita a leitura de
	// "grade" que uma onda só, alinhada aos eixos, produziria.
	float w = sin((world.x + world.z) * wave_scale + TIME * wave_speed) * 0.5
		+ sin((world.x - world.z) * wave_scale * 1.7 - TIME * wave_speed * 1.3) * 0.5;
	VERTEX.y += w * wave_amplitude;
}

void fragment() {
	// Mesma normalização que `MapTerrain.height_at` usa para indexar a grade
	// (mundo → [0, map_size] → UV [0,1]) — tem de ser a MESMA conta, ou a
	// água lê profundidade de um ponto que não é o que está sob ela.
	vec2 uv = (world_xz + vec2(map_half)) / map_size;
	float ground = texture(heightmap_tex, uv).r;
	float depth = max(water_line - ground, 0.0);

	float depth_t = clamp(depth / depth_fade, 0.0, 1.0);
	vec3 c = mix(color_shallow, color_deep, depth_t);

	float flow_len = length(water_flow_dir);
	vec2 flow = flow_len > 0.0001 ? water_flow_dir / flow_len : vec2(0.0);
	vec2 water_uv = world_xz * water_tex_scale + flow * TIME * water_flow_speed;
	float wl = dot(texture(water_tex, water_uv).rgb, vec3(0.299, 0.587, 0.114));
	vec3 rippled = c * (wl * 1.6);
	// Multiplicar sozinho esmaga a variação onde `c` já é quase preto (mar
	// fundo) — a mesma ondulação em módulo RELATIVO vira imperceptível em
	// módulo ABSOLUTO. A parcela aditiva fixa garante contraste visível
	// mesmo lá, sem mudar a leitura da água rasa — lá o termo multiplicativo
	// já domina, porque `c` é claro.
	vec3 additive = (wl - 0.6) * vec3(0.08, 0.14, 0.16);
	c = mix(c, clamp(rippled + additive, vec3(0.0), vec3(1.0)), water_detail_strength);

	float foam = 1.0 - smoothstep(0.0, foam_width, depth);
	c = mix(c, color_foam, foam);

	ALBEDO = c;
	// Luz direcional + câmera ortográfica de ângulo travado num plano
	// horizontal brilhante colocam o ponto de reflexo especular sempre no
	// MESMO lugar da tela — nada na geometria muda quando o jogador anda, só
	// translada, então a "bolha" branca segue a câmera por toda a água.
	// Existia desde a Fase 2 (nunca foi tocado); 0,05/0,6 ficava sutil sobre
	// o gradiente liso original, mas ficou visível ao lado da textura nova da
	// costa. Reduzido pra sheen mais espalhado em vez de ponto duro — ainda
	// lê como água, sem virar espelho.
	ROUGHNESS = 0.4;
	SPECULAR = 0.15;
	// Raso mais transparente (deixa ver o leito perto da praia), fundo mais
	// opaco (não há o que ver lá embaixo mesmo). Era 0,55–0,92 até
	// 2026-09-01 — com o leito agora numa profundidade uniforme (dois
	// níveis fixos, sem Mar Profundo pra "merecer" opacidade extra), isso
	// lia como parede opaca em quase toda a água. Reduzido de novo em
	// 2026-09-02 (0,20–0,45 → 0,12–0,30) pra deixar ver personagem nadando
	// por baixo, não só o leito raso.
	ALPHA = mix(0.12, 0.30, depth_t);
}
