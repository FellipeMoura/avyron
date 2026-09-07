shader_type canvas_item;

// `clip_contents` do Control só recorta em retângulo — o retrato da ativa
// precisa da abertura circular da moldura, então o corte é por distância ao
// centro em espaço UV em vez de um recorte de retângulo.

// Zoom na AMOSTRA, não no nó: o recorte (o `if` abaixo) continua testando o
// UV original, então a janela circular visível nunca muda de tamanho — só o
// que é lido da textura dentro dela aproxima, deixando a criatura ocupar mais
// da abertura sem esticar a moldura ao redor.
uniform float zoom : hint_range(0.5, 2.0) = 1.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	if (length(centered) > 0.5) {
		discard;
	}
	vec2 sample_uv = centered / zoom + vec2(0.5);
	COLOR = texture(TEXTURE, sample_uv);
}
