shader_type spatial;

// Aura do Despertar Ancestral: casca aditiva em volta do corpo.
//
// ## Como a casca funciona
//
// A malha é a MESMA do corpo, duplicada como irmã do `MeshInstance3D`
// original e inflada ao longo da normal. `cull_front` descarta as faces
// viradas para a câmera, então o que sobra é o interior do fundo da casca —
// visível só onde escapa da silhueta do corpo, que é exatamente o halo. O
// teste de profundidade continua LIGADO de propósito: é ele que recorta o
// halo contra o corpo. `depth_draw_never` só evita que a casca escreva
// profundidade e ocluda o que estiver atrás dela.
//
// Irmã, e não filha: o `skeleton` de um `MeshInstance3D` rigado é um
// NodePath relativo, quase sempre `..`. Duplicando como irmã, o caminho
// continua resolvendo para o mesmo `Skeleton3D` e a casca acompanha a
// animação sem nenhum código de sincronia.
//
// ## Por que a aura não é da cor do corpo
//
// Com o corpo já recolorido pelo elemento, uma aura na mesma cor some
// justamente na criatura em que ela mais precisa aparecer. Duas defesas: a
// cor vem de `palette_aura` (coluna própria no banco, autorada mais clara que
// o highlight), e o sinal principal é MOVIMENTO — a pulsação abaixo — que lê
// mesmo quando a cor não contrasta.

render_mode blend_add, unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec3 aura_color : source_color = vec3(1.0);

// Inflagem em espaço de modelo. Quem cria o material calcula isto a partir do
// AABB da malha, para a aura de um trilobita de 15 cm e a de um Arthropleura
// de 2,5 m terem a mesma espessura RELATIVA ao corpo — a mesma razão pela
// qual `CreatureActor` escala o modelo pelo maior eixo em vez de usar a
// escala do arquivo.
uniform float grow = 0.03;

uniform float pulse_hz = 0.9;
// Fundo da pulsação: 1.0 - pulse_depth. Nunca chega a zero, senão a aura
// pisca "desligada" e lê como bug em vez de respiração.
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.35;
// Quanto do halo sobrevive de frente. O grosso do brilho fica na borda
// (fresnel); este piso evita que o meio da casca fique oco.
uniform float core_floor : hint_range(0.0, 1.0) = 0.22;

// 0 = desligada. Instance uniform pelo mesmo motivo do shader de paleta, com
// um agravante: a casca só existe enquanto o Despertar dura, e um uniform
// comum acenderia todas as criaturas que dividissem o material.
instance uniform float aura_energy;

void vertex() {
	VERTEX += NORMAL * grow;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float pulse = (1.0 - pulse_depth) + pulse_depth * (0.5 + 0.5 * sin(TIME * TAU * pulse_hz));
	ALBEDO = aura_color * aura_energy * pulse * mix(core_floor, 1.0, rim);
	ALPHA = 1.0;
}
