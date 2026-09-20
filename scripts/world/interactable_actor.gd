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

## Largura × profundidade (m) da estrutura carregada por `_load_model`, já
## escalada. Zero sem modelo. É a medida de que `attach_npc` precisa para pôr
## a pessoa DIANTE da fachada em vez de dentro dela, e a que o teste de
## layout usa para provar que duas estruturas vizinhas não se sobrepõem.
var model_footprint := Vector2.ZERO

## Onde o NPC está, no plano local do ator (y = 0) — a placa flutua sobre ele.
## Fica em `ZERO` (centro do ator) quando não há NPC, que é o comportamento
## de antes: placa sobre o corpo.
var _sign_anchor := Vector3.ZERO
var _has_npc := false

var _sign: MeshInstance3D
var _time := 0.0

## ## A pessoa diante da estrutura (2026-09-20)
##
## Desde 2026-09-18 os serviços da vila são estruturas `.glb` (barraca, posto,
## forja) e a receita de aparência dos NPCs tinha virado código morto — só
## rodava se o `.glb` falhasse. Só que uma barraca sem ninguém lê como
## cenário, não como serviço, e a placa flutuante ficava DENTRO do prédio
## (2,2 m de altura num volume de 3,9 m). A estrutura passa a ser enfeite e a
## pessoa, montada do kit de personagens (`CharacterRig`), fica diante dela —
## é sobre a cabeça dela que a placa flutua e é nela também que o clique pega.
##
## Filho do MESMO ator, e não um ator próprio: o contrato de clique/alcance/
## apoio no chão não muda, e não há segundo ponto de interação a manter em
## sincronia com o primeiro.
##
## Quanto à frente e quanto de lado: a pessoa fica `NPC_FRONT_GAP` além da
## fachada (metade do fundo da estrutura) e deslocada `NPC_SIDE_FRACTION` do
## meio-lado para um dos lados — "ao lado da porta", ainda sob a largura do
## prédio, sem tapar a abertura dele.
const NPC_FRONT_GAP := 0.8
const NPC_SIDE_FRACTION := 0.35

## Monta a pessoa e a põe diante da estrutura, encarando +Z (o mar, de onde o
## jogador chega — a vila fica na borda -Z do mapa).
##
## `side` é -1/+1 (esquerda/direita da porta). `clip` é a pose de espera; se o
## corpo não tiver o clipe, `play_clip` silencia e fica o `Idle` que a
## montagem já toca. Devolve `null` (sem NPC, sem erro) para receita vazia ou
## kit ausente — mesmo contrato de "degradar, não quebrar" do `_load_model`.
##
## O rig NÃO passa por `_load_model`: `local_aabb` não tem ramo de esqueleto,
## e o rig já nasce com os pés em y = 0 local — o chão, no referencial do
## ator, é `-body_height * 0.5` (ver `ground_on_spot`).
func attach_npc(recipe: Dictionary, side: float, clip: String) -> CharacterRig:
	var rig := CharacterRig.create(recipe)
	if rig == null:
		return null
	rig.name = "Npc"
	rig.position = npc_offset(side)
	rig.position.y = -body_height * 0.5
	# Regra 4 do CLAUDE.md: a frente de um nó é -Z, e `CharacterRig` já gira o
	# corpo do kit (que olha para +Z) por dentro. Meia-volta no rig = encarar +Z.
	rig.rotation.y = PI
	add_child(rig)
	rig.play_clip(clip)
	_sign_anchor = Vector3(rig.position.x, 0.0, rig.position.z)
	_has_npc = true
	return rig


## Onde a pessoa fica no plano local do ator (y = 0), a partir da medida da
## estrutura. Público para o `MapDressing` e os testes saberem onde NÃO
## plantar laje — é a mesma conta que `attach_npc` usa.
func npc_offset(side: float) -> Vector3:
	return Vector3(
		side * model_footprint.x * NPC_SIDE_FRACTION,
		0.0,
		model_footprint.y * 0.5 + NPC_FRONT_GAP)


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


## Carrega a estrutura `.glb` da vila (comerciante/ferreiro/posto), se existir,
## já escalado e apoiado no chão. `null` é retorno normal — cada subclasse
## mantém sua primitiva/rig como fallback, mesmo raciocínio de "não quebrar,
## só degradar" do resto do projeto (ver `MapDressing._place`).
##
## Os três `.glb` chegam normalizados (~1,9×1,3×1,5, pivô no CENTRO da malha,
## não na base — medido por sonda, `_tmp_measure_village.gd`, descartada) —
## mesma convenção do kit aquático. Por isso a colocação mede a AABB
## combinada em vez de assumir pivô na base (que é o que `CharacterRig`
## assume, e o motivo do primeiro corpo ter afundado no chão): o ator tem a
## origem no CENTRO do corpo de colisão (`ground_on_spot()`), então o "chão",
## no referencial dele, é `-body_height * 0.5` — e é lá que a base da AABB
## (escalada) precisa cair.
func _load_model(path: String, model_scale: float = 1.0) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("InteractableActor: modelo ausente em %s — usando visual de fallback" % path)
		return null
	var node := packed.instantiate() as Node3D
	var aabb := local_aabb(node)
	node.scale = Vector3.ONE * model_scale
	node.position.y = -body_height * 0.5 - aabb.position.y * model_scale
	model_footprint = Vector2(aabb.size.x, aabb.size.z) * model_scale
	return node


## AABB combinada das malhas de `node`, no espaço local dele (antes de
## qualquer escala aplicada pelo chamador) — mesma técnica de
## `CreatureActor._local_aabb`, sem o ramo de esqueleto: os `.glb` da vila são
## malha estática, sem skin. Estática e pública porque o `MapDressing` apoia
## os props da vila (mesma convenção de pivô no centro) pela mesma medida.
static func local_aabb(node: Node) -> AABB:
	return _local_aabb_rec(node, Transform3D.IDENTITY)


static func _local_aabb_rec(node: Node, xform: Transform3D) -> AABB:
	var local_xform := xform
	if node is Node3D:
		local_xform = xform * (node as Node3D).transform
	var result := AABB()
	var found := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		result = local_xform * (node as MeshInstance3D).mesh.get_aabb()
		found = true
	for child in node.get_children():
		var child_aabb := _local_aabb_rec(child, local_xform)
		if not found:
			result = child_aabb
			found = true
		else:
			result = result.merge(child_aabb)
	return result


## `offset` é a posição da forma no plano local do ator (y = 0 → centrada na
## altura do corpo). Existe para a segunda cápsula, a da pessoa diante da
## estrutura: o clique do mundo é raycast físico, e sem uma forma ali clicar
## no NPC não faria nada — o corpo dele é só malha skinada.
func attach_collision(shape: Shape3D, offset: Vector3 = Vector3.ZERO, shape_name: String = "Collision") -> void:
	var collision := CollisionShape3D.new()
	collision.name = shape_name
	collision.shape = shape
	collision.position = offset
	add_child(collision)


## Cápsula de clique sobre a pessoa montada por `attach_npc`. Separada de
## `attach_npc` porque a ordem importa nos atores: forma de colisão entra
## depois da placa, como sempre foi, e o rig entra antes de qualquer uma.
func attach_npc_collision(rig: CharacterRig) -> void:
	if rig == null:
		return
	var shape := CapsuleShape3D.new()
	shape.height = NPC_COLLISION_HEIGHT
	shape.radius = NPC_COLLISION_RADIUS
	# Centro da cápsula na metade da altura da pessoa, a partir dos pés dela.
	attach_collision(shape, Vector3(rig.position.x, rig.position.y + NPC_COLLISION_HEIGHT * 0.5, rig.position.z),
		"NpcCollision")


## Cápsula de clique da pessoa: altura de um humano do kit (~1,8 m), raio um
## pouco maior que o do corpo para o clique perdoar a borda.
const NPC_COLLISION_HEIGHT := 1.8
const NPC_COLLISION_RADIUS := 0.35


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


## Com uma pessoa diante da estrutura a placa flutua sobre a CABEÇA DELA —
## medida a partir dos pés (`-body_height/2`) mais a altura de um humano do
## kit —, e não sobre o corpo do ator: a altura do ator é a da estrutura de
## colisão (0,95 m na bancada), e uma placa a essa altura entraria pelo rosto
## de quem está em pé ali.
func _sign_rest_height() -> float:
	if _has_npc:
		return -body_height * 0.5 + NPC_COLLISION_HEIGHT + SIGN_CLEARANCE
	return body_height * 0.5 + SIGN_CLEARANCE


func _process(delta: float) -> void:
	if _sign == null:
		return
	_time += delta
	# Sobre a pessoa quando há uma (`_sign_anchor`), sobre o corpo quando não.
	_sign.position = _sign_anchor + Vector3(
		0.0, _sign_rest_height() + sin(_time * TAU * SIGN_BOB_HZ) * SIGN_BOB_AMPLITUDE, 0.0)
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
