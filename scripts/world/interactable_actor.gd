class_name InteractableActor
extends StaticBody3D

## Base dos pontos fixos com que o jogador interage por clique: comerciante,
## arena, posto do Relicário, guardião do portal.
##
## `StaticBody3D` porque o clique do mundo é um raycast físico — sem corpo de
## colisão o ator é invisível ao mouse. Estático e não `CharacterBody3D`
## porque nenhum deles anda, é empurrado ou persegue; quem tem máquina de
## estados é criatura selvagem (`CreatureActor`), que **não** herda daqui: ela
## responde ao clique por seleção + segundo clique, contrato diferente.
##
## O que mora aqui é o que as quatro faziam igual e, por isso mesmo, podiam
## deixar de fazer igual sem ninguém perceber. O que fica na subclasse é o que
## legitimamente difere: o corpo, o estado próprio e a silhueta da placa.
##
## Ator novo herda daqui e ganha de graça o despacho do clique — `WorldRoot`
## e `WorldSelection` testam contra este tipo, não contra a lista de classes
## concretas, que era editada à mão a cada ator e falhava em silêncio quando
## alguém esquecia a segunda lista.

## Emitido quando o jogador clica de perto o bastante. Quem escuta decide o
## que abrir — o ator não conhece tela nenhuma.
signal engaged(actor: InteractableActor)

## Distância a partir da qual o clique não engaja mais. Um comerciante do
## outro lado do mapa não deve abrir loja porque o raycast alcançou.
##
## Um valor para os quatro de propósito: a distância é do *gesto*, não do
## ator. Se um dia um deles precisar de alcance próprio, vira `var` com este
## valor de padrão — e aí a diferença é uma decisão, não uma cópia que
## divergiu.
const INTERACT_RANGE := 4.5

## Placa flutuante: a linguagem visual de "dá para interagir", sem ícone de
## HUD. Mesma altura, mesmo bob e mesma velocidade de giro nos quatro — o que
## muda por ator é a malha e a cor, que é justamente o que os distingue de
## longe.
const SIGN_CLEARANCE := 0.45
const SIGN_BOB_AMPLITUDE := 0.06
const SIGN_BOB_HZ := 0.5
const SIGN_SPIN_SPEED := 0.8

## Nome usado nas mensagens do mundo ("%s esta longe demais."). NPC preenche
## com o nome do bestiário; ponto de cenário sem identidade preenche com o
## próprio substantivo ("O posto do relicario"), o que deixa a mensagem sair
## de um lugar só em vez de uma string por handler.
var display_name := ""

## Altura do corpo, em metros. A subclasse grava no começo do `_ready()`,
## antes de chamar qualquer helper daqui: a placa e o apoio no chão dependem
## dela.
var body_height := 1.8

## Eixo do giro da placa. `Vector3.UP` para as placas chapadas (cubo, prisma),
## que giram sobre si; o torus do posto gira em `RIGHT` para mostrar o furo.
var sign_spin_axis := Vector3.UP

var _sign: MeshInstance3D
var _time := 0.0


## Monta a placa acima da cabeça. A subclasse passa só o que a distingue.
## `PrimitiveMesh` e não `Mesh`: as quatro placas são primitivas (cubo,
## torus, prisma) e só a primitiva expõe `material` direto. Tipar no que
## realmente se usa deixa o erro aparecer aqui, não no material silenciosamente
## não aplicado.
func attach_sign(mesh: PrimitiveMesh, color: Color, energy: float = 0.5) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	mesh.material = material

	_sign = MeshInstance3D.new()
	_sign.name = "Sign"
	_sign.mesh = mesh
	_sign.position.y = _sign_rest_height()
	add_child(_sign)


func attach_collision(shape: Shape3D) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	add_child(collision)


## Apoia o corpo no chão a partir do ponto recebido.
##
## **Soma, nunca atribuição.** O `y` do spot é a altura do terreno naquele
## ponto — zero no centro plano, mas não na costa, que é elevada — e a origem
## do ator é o *centro* do corpo, então ele sobe meia altura a partir dali.
## Atribuir daria o mesmo resultado só enquanto o ator estivesse em chão
## plano, e enterraria ou faria flutuar assim que alguém o movesse.
##
## Era exatamente essa a divergência: comerciante e posto (na costa) somavam,
## arena e guardião (no centro plano) atribuíam, e os dois pares estavam
## certos por coincidência de posição. Mover um deles exigia lembrar de editar
## o ator *e* o populador, sem nada que acusasse a falta de um dos dois.
func ground_on_spot() -> void:
	position.y += body_height * 0.5


func _sign_rest_height() -> float:
	return body_height * 0.5 + SIGN_CLEARANCE


func _process(delta: float) -> void:
	if _sign == null:
		return
	_time += delta
	_sign.position.y = _sign_rest_height() + sin(_time * TAU * SIGN_BOB_HZ) * SIGN_BOB_AMPLITUDE
	_sign.rotation = sign_spin_axis * (_time * SIGN_SPIN_SPEED)


## Distância no plano até um ponto. O clique do mundo usa isto para recusar
## interação a distância — no plano, e não no espaço, porque a diferença de
## altura entre o jogador e um ator na costa não deve encurtar o alcance.
func flat_distance_to(point: Vector3) -> float:
	var d := global_position - point
	d.y = 0.0
	return d.length()


func request_engage() -> void:
	engaged.emit(self)
