shader_type spatial;

// Recolore os corpos placeholder compartilhados pela rampa do elemento.
//
// ## Por que isto é um shader e não uma textura gerada
//
// Os atlas do Quaternius são paleta chapada: 1024x1024 com ~50 cores
// distintas e 84% da imagem em branco não usado. Dava para gerar um atlas
// variante por elemento com `Image`, mas seriam ~1 milhão de pixels por
// variante percorridos em GDScript — segundos de carregamento por corpo, e
// um cache para invalidar toda vez que a paleta mudasse no bestiário. Aqui a
// rampa é um `GradientTexture1D` de 256 texels: trocar a paleta é trocar um
// uniform, e o custo de carregamento é zero.
//
// Nada se perde nessa troca porque os placeholders NÃO têm normal map nem
// metallic-roughness — o material do `.glb` é só o atlas de base color. Este
// shader é o material inteiro deles, não uma camada por cima.
//
// ## Como a rampa lê o atlas
//
// A posição na rampa vem da LUMINÂNCIA do texel original: o mais escuro do
// atlas cai no `shadow` da rampa, o mais claro no `highlight`. É isso que faz
// "amarelo com preto" existir como UM elemento — Eletricidade é uma rampa que
// sai de quase-preto e chega em amarelo, e a forma do bicho distribui as duas
// pontas sozinha.
//
// ## Por que a saturação entra na conta
//
// Remapear TUDO pela luminância pinta os dentes, os olhos e as garras da cor
// do elemento junto, e o bicho vira uma mancha só. O texel neutro (branco,
// cinza, preto) é justamente o que o artista usou para essas partes, então
// ele passa quase intacto: `neutral_mix` deixa só um respingo da família nele
// para não destoar. Quem é saturado — o corpo — vai inteiro para a rampa.
//
// As constantes de mistura são de APRESENTAÇÃO e moram aqui de propósito
// (CLAUDE.md, regra 1: número que um designer ajusta mora no bestiário; o
// que ajusta um pintor de shader, não). As CORES vêm do banco, via
// `ElementPalette`.

render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ramp : source_color, filter_linear, repeat_disable;

// ATENÇÃO: os dois limiares abaixo, e os de luminância, são medidos em espaço
// GAMA — os valores que se lê num conta-gotas — e NÃO no que `texture()`
// devolve. Com o hint `source_color` o Godot já linearizou o texel na
// amostragem, e comparar limiar de sRGB contra valor linear foi o primeiro
// defeito real desta função: o corpo roxo do Dino (#5c364b, saturação 0,15 em
// gama) media 0,07 em linear, ficava abaixo do piso e passava quase inteiro
// sem recolorir. Todas as seis criaturas saíam da mesma cor suja. Por isso o
// `fragment()` reconverte para gama antes de MEDIR, e mistura em linear.

// Abaixo de `saturation_low` o texel conta como neutro; acima de
// `saturation_high` conta como cor do corpo. Entre os dois, transição suave —
// sem ela, blocos vizinhos do atlas com saturação parecida cortariam em
// degrau visível na malha.
//
// O teto é baixo (0,12) porque nesses atlas a cor de corpo é modesta: o roxo
// do Dino tem 0,15 de saturação. Com teto em 0,22 ele entrava pela metade e
// arrastava um terço do roxo original para dentro de toda paleta.
uniform float saturation_low : hint_range(0.0, 1.0) = 0.05;
uniform float saturation_high : hint_range(0.0, 1.0) = 0.12;
uniform float neutral_mix : hint_range(0.0, 1.0) = 0.25;

// Janela de luminância do atlas esticada para a rampa inteira.
//
// Não são os extremos medidos do atlas (0,126 a 0,666): é a janela que põe uma
// cor de CORPO típica no MEIO da rampa. Os corpos desses placeholders são uma
// cor só, de luminância baixa — o roxo do Dino mede 0,25 —, então mapear pelos
// extremos joga o bicho inteiro perto da sombra e toda criatura sai escura.
// Com 0,05–0,52, esse mesmo roxo cai em 0,43 (meio da rampa) e os detalhes
// claros, como os espinhos amarelos em 0,59, alcançam o brilho.
//
// Linear e não `smoothstep`: suavizar aqui achataria as pontas justamente
// onde vivem a sombra e o brilho, que são a assinatura do elemento.
uniform float luminance_low : hint_range(0.0, 1.0) = 0.05;
uniform float luminance_high : hint_range(0.0, 1.0) = 0.52;

uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

// Deslocamento da criatura DENTRO da família, derivado do código dela por
// `ElementPalette.creature_bias`. Instance uniform, e não uniform comum, é o
// que permite um único material por elemento servir todas as criaturas
// daquele elemento sem quebrar o batching — o valor viaja no buffer da
// instância, não numa cópia do material.
//
// Aplicado como GAMA sobre a posição na rampa, nunca como soma: gama preserva
// as duas pontas (0 continua 0, 1 continua 1), então a criatura clareia ou
// escurece dentro da família e nunca vaza para fora dela. Soma achataria as
// pontas e mudaria a cor da sombra e do brilho, que são a assinatura do
// elemento.
instance uniform float ramp_bias;

void fragment() {
	vec4 src = texture(atlas, UV);

	// De volta ao gama só para MEDIR — ver o aviso junto aos uniforms. A
	// mistura no fim continua em linear, que é o espaço em que `ALBEDO` é
	// interpretado.
	vec3 gamma = pow(max(src.rgb, vec3(0.0)), vec3(1.0 / 2.2));

	float lum = dot(gamma, vec3(0.2126, 0.7152, 0.0722));
	lum = clamp((lum - luminance_low) / max(luminance_high - luminance_low, 0.001), 0.0, 1.0);
	float t = pow(lum, exp(-ramp_bias * 1.5));
	vec3 ramped = texture(ramp, vec2(t, 0.0)).rgb;

	float hi = max(gamma.r, max(gamma.g, gamma.b));
	float lo = min(gamma.r, min(gamma.g, gamma.b));
	float sat = hi - lo;
	float amount = mix(neutral_mix, 1.0, smoothstep(saturation_low, saturation_high, sat));

	ALBEDO = mix(src.rgb, ramped, amount);
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	// SEM escrever em ALPHA, de propósito. O atlas destes placeholders é RGB
	// puro (sem canal alfa — conferido nos PNGs de origem, Quaternius e
	// Dungeon Monsters), então `src.a` sempre voltava 1.0: a linha nunca
	// mudou a opacidade de nada. O problema é que ATRIBUIR a ALPHA, mesmo
	// com 1.0, já empurra o material pra fila de transparência do Godot —
	// invisível num corpo de UMA malha só (os placeholders antigos), mas
	// visível como "translúcido, com outra silhueta vazando atrás" num corpo
	// de VÁRIAS malhas sobrepostas como o Imp/Puglin (Body/Chains/Mace/
	// Shorts/SpikedCollar): objetos transparentes não fazem depth-sort
	// confiável entre si. Corpo novo com várias malhas por baixo do mesmo
	// material é o que expôs o defeito — ele sempre esteve aqui.
}
