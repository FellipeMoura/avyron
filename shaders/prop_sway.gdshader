shader_type spatial;
// `cull_disabled`: o kit aquático inteiro vem com dupla face (`cull_mode` 2 no
// material importado — medido por sonda em 2026-09-17). Com o cull padrão as
// costas das folhas somem, e a peça abre buraco exatamente no lado que o yaw
// sorteado virar para a câmera.
render_mode cull_disabled, diffuse_lambert, specular_disabled;

// Balanço de corrente para props de cenário moles (alga, coral mole, esponja).
//
// Substitui o `StandardMaterial3D` importado do glTF só nas peças que devem
// balançar — `MapDressing.SWAY` decide quais. O fragmento reproduz o que o
// material importado já era DEPOIS de `_flatten_specular`: cor de base
// texturizada, sem normal map, sem roughness/metallic, sem especular. Se aquele
// achatamento mudar, este fragmento tem de mudar junto, ou as peças que
// balançam passam a ler diferente das paradas ao lado.
//
// É corrente, não vento: o PZ-01 é o Mundo dos Mares, e o que se move no leito
// é empurrado pela água. Por isso `sway_dir` recebe a MESMA direção do arrasto
// de UV da superfície (`MapTerrain.WATER_FLOW_DIR`, que alimenta os dois
// materiais) — balanço e superfície andando para lados diferentes leriam como
// duas águas.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);

// Deslocamento horizontal na PONTA da peça, em unidades locais. Local de
// propósito: a escala do prop multiplica junto, então uma alga de 4× balança
// 4× mais em metros — que é o que uma alga 4× maior faz.
uniform float sway_amount = 0.0;
uniform float sway_speed = 0.8;
uniform vec2 sway_dir = vec2(0.6, 1.0);

// Altura local em que a peça encontra o chão (não se move) e altura local da
// ponta (move `sway_amount`). NÃO é 0 e 1: o kit do Meshy vem com a origem no
// centro do volume, e o `MapDressing` afunda cada peça uma fração da escala —
// o pivô é onde o chão corta a malha, e isso é conta de lá, não daqui.
uniform float sway_pivot_y = 0.0;
uniform float sway_top_y = 1.0;

void vertex() {
	// Fase pela posição de MUNDO da origem do prop, não do vértice: o prop
	// inteiro dobra como uma peça só. Fase por vértice rasgaria a malha, e
	// fase única para todos faria o leito inteiro balançar em uníssono — que
	// lê como a câmera tremendo, não como corrente.
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = origin.x * 0.37 + origin.z * 0.23;

	// Duas senoides de período incomensurável: uma só repete o gesto num
	// ciclo exato, e o olho acha o laço em poucos segundos.
	float w = sin(TIME * sway_speed + phase) * 0.7
		+ sin(TIME * sway_speed * 1.73 + phase * 1.31) * 0.3;

	// Altura normalizada ao QUADRADO: o pivô não se move, o meio mal se move,
	// a ponta se move tudo. É a curva de uma haste presa embaixo — linear
	// leria como a peça inteira inclinando sobre um pino. Abaixo do pivô
	// (a parte enterrada) fica parado.
	float span = max(sway_top_y - sway_pivot_y, 0.0001);
	float h = clamp((VERTEX.y - sway_pivot_y) / span, 0.0, 1.0);

	// `sway_dir` é direção de MUNDO, mas `VERTEX` é local — e cada prop nasce
	// com yaw sorteado (`MapDressing._place`). Somar a direção crua faria cada
	// peça balançar para um lado, que é o oposto de corrente. A transposta da
	// base do modelo desfaz o giro; ela também carrega a escala (uniforme no
	// kit), e o `normalize` a descarta — a escala já entra do jeito certo por
	// `sway_amount` ser local.
	//
	// Guarda de comprimento zero antes de normalizar, mesma regra do arrasto
	// da água: (0, 0) desliga o balanço em vez de virar NaN.
	vec3 local_dir = transpose(mat3(MODEL_MATRIX)) * vec3(sway_dir.x, 0.0, sway_dir.y);
	float len = length(local_dir.xz);
	vec2 dir = len > 0.0001 ? local_dir.xz / len : vec2(0.0);

	VERTEX.xz += dir * (w * sway_amount * h * h);
}

void fragment() {
	vec4 base = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = base.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
