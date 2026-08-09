class_name PlayerRoster
extends RefCounted

## O time do jogador: uma criatura **ativa**, as **reservas**, e o HP de cada
## uma — que persiste entre batalhas e se recupera com o tempo.
##
## A ativa é o slot 0 conceitualmente, mas guardar um índice em vez de
## reordenar o array significa que trocar quem vai à frente não embaralha a
## ordem em que as criaturas foram capturadas — a lista na janela do time fica
## estável entre trocas, que é o que deixa a memória muscular funcionar.
##
## Quem a ativa é importa em quatro lugares: é ela que anda ao lado do jogador
## (`CompanionActor`), é ela que **entra em campo** no duelo, a **classe** dela
## decide o que a mineração produz (`MiningTable`), e é o HP dela que o próximo
## combate herda.
##
## ## O que persiste e o que não
##
## Só o HP. Carga do Despertar, buffs e usos de golpe continuam começando do
## zero a cada batalha — são o arco de uma luta, não um orçamento administrado
## ao longo do dia (ver o cabeçalho de `Combatant`). O HP é a exceção porque é
## o que transforma uma sequência de encontros em uma expedição com custo: sem
## ele, seis criaturas são seis opções e nenhuma é um recurso.

signal changed

## Seis é o teto clássico do gênero e o que a HUD comporta sem virar lista
## rolável. Quando o bestiário exportar um limite, ele vem do bundle.
const MAX_SLOTS := 6

## Fração do HP máximo recuperada por minuto, fora de combate.
##
## Dez minutos do zero até cheio. A escala foi escolhida contra o cooldown de
## mineração (3 s) e o respawn de criatura (20–40 s): recuperar é a coisa lenta
## do mapa, então voltar para o bioma custa tempo de verdade e trocar a ativa
## por uma reserva inteira vira decisão, não formalidade.
const REGEN_FRACTION_PER_MINUTE := 0.10

var _db: BestiaryData
var _level := 1

## `[{code, hp, accum}]`. `accum` é o resto fracionário da regeneração — sem
## ele, `max_hp * 0.1/60 * delta` a 60 fps é sempre muito menor que 1 e a cura
## inteira desaparece no arredondamento, quadro após quadro.
var _members: Array[Dictionary] = []
var _active := 0


## Começa o time com a criatura inicial, em HP cheio.
##
## `db` e `level` ficam guardados porque o HP máximo de cada membro é derivado
## (`stats_at_level`), não armazenado: mudar o nível do encontro não pode
## deixar um teto de HP velho pendurado no time.
func setup(db: BestiaryData, level: int, starter_code: String) -> void:
	_db = db
	_level = maxi(1, level)
	_members.clear()
	_active = 0
	if starter_code != "":
		_members.append(_make_member(starter_code, -1))
	changed.emit()


func _make_member(code: String, hp: int) -> Dictionary:
	var top := _max_hp_of(code)
	# hp < 0 é o pedido de "cheia"; qualquer outro valor entra limitado ao teto.
	var start := top if hp < 0 else clampi(hp, 0, top)
	return {"code": code, "hp": start, "accum": 0.0}


func _max_hp_of(code: String) -> int:
	if _db == null:
		return 1
	var stats := _db.stats_at_level(code, _level)
	return maxi(1, int(stats.get("hp", 1)))


# ---------------------------------------------------------------------------
# composição
# ---------------------------------------------------------------------------

func active() -> String:
	return code_at(_active)


func active_index() -> int:
	return _active


func code_at(index: int) -> String:
	if index < 0 or index >= _members.size():
		return ""
	return str(_members[index]["code"])


## Todos os códigos na ordem de captura, ativa incluída. Cópia: quem consome é
## painel, e painel não deve conseguir mexer no time por descuido.
func codes() -> Array[String]:
	var out: Array[String] = []
	for m in _members:
		out.append(str(m["code"]))
	return out


## Só as reservas, na ordem de captura.
func reserves() -> Array[String]:
	var out: Array[String] = []
	for i in _members.size():
		if i != _active:
			out.append(str(_members[i]["code"]))
	return out


func size() -> int:
	return _members.size()


func is_full() -> bool:
	return _members.size() >= MAX_SLOTS


func has(code: String) -> bool:
	return codes().has(code)


## Entra no time como reserva. Devolve `false` se o time está cheio — o
## chamador precisa saber, porque nesse caso a criatura tem de voltar ao mapa
## em vez de sumir.
##
## `hp` negativo entra cheia. A captura passa o HP com que a criatura saiu da
## batalha: pegou-se um bicho enfraquecido, e ele chega enfraquecido. É a mesma
## regra do resto do time, aplicada no momento em que ele entra nele.
##
## Repetir espécie é permitido de propósito: dois Anomalocaris são dois bichos,
## não um duplicado.
func add(code: String, hp: int = -1) -> bool:
	if code == "" or is_full():
		return false
	if _db != null and _db.creature(code).is_empty():
		return false
	_members.append(_make_member(code, hp))
	changed.emit()
	return true


## Manda a criatura do índice à frente. Devolve `false` para índice fora da
## lista ou para quem já está ativa — nos dois casos não há nada a fazer, e
## avisar evita que o chamador reconstrua a companheira à toa.
##
## Uma criatura caída **pode** ir à frente: no mapa ela é só uma criatura muito
## ferida, e regenera como qualquer outra. Quem barra desmaiada é o combate,
## que é onde isso significa algo.
func set_active(index: int) -> bool:
	if index < 0 or index >= _members.size() or index == _active:
		return false
	_active = index
	changed.emit()
	return true


# ---------------------------------------------------------------------------
# HP
# ---------------------------------------------------------------------------

func hp_at(index: int) -> int:
	if index < 0 or index >= _members.size():
		return 0
	return int(_members[index]["hp"])


func max_hp_at(index: int) -> int:
	if index < 0 or index >= _members.size():
		return 0
	return _max_hp_of(str(_members[index]["code"]))


func hp_ratio_at(index: int) -> float:
	var top := max_hp_at(index)
	return float(hp_at(index)) / float(top) if top > 0 else 0.0


func is_fainted_at(index: int) -> bool:
	return index >= 0 and index < _members.size() and hp_at(index) <= 0


## Grava o HP de um membro, limitado ao teto. Zera o resto fracionário: um
## membro que acabou de sair de uma batalha não deve levar meio ponto de cura
## acumulado antes dela.
func set_hp_at(index: int, value: int) -> void:
	if index < 0 or index >= _members.size():
		return
	var top := max_hp_at(index)
	var clamped := clampi(value, 0, top)
	if int(_members[index]["hp"]) == clamped:
		return
	_members[index]["hp"] = clamped
	_members[index]["accum"] = 0.0
	changed.emit()


func alive_count() -> int:
	var n := 0
	for i in _members.size():
		if hp_at(i) > 0:
			n += 1
	return n


## Índice da primeira criatura de pé, ou -1 se o time inteiro caiu. É quem
## entra em campo quando a ativa está desmaiada na hora do encontro.
func first_alive_index() -> int:
	for i in _members.size():
		if hp_at(i) > 0:
			return i
	return -1


## Recupera `REGEN_FRACTION_PER_MINUTE` do HP máximo por minuto, em todos os
## membros. Chamada do `_process` do mundo — e como o mundo pausa durante o
## combate, a cura não corre dentro da luta sem precisar de nenhuma trava.
##
## Uma criatura caída também regenera: com a cura contínua, desmaiar é uma
## interdição temporária, não um estado que precisa de item para sair. Se um
## dia isso mudar, é este método que ganha o `if`.
func regenerate(delta: float) -> void:
	if delta <= 0.0 or _members.is_empty():
		return

	var rate := REGEN_FRACTION_PER_MINUTE / 60.0
	var healed_any := false

	for i in _members.size():
		var top := max_hp_at(i)
		var current := int(_members[i]["hp"])
		if current >= top:
			# Zera o resto ao encher: sem isso, uma criatura curada sobra com
			# acúmulo que viraria 1 de cura instantânea no primeiro dano.
			_members[i]["accum"] = 0.0
			continue

		var accum := float(_members[i]["accum"]) + float(top) * rate * delta
		var whole := int(accum)
		if whole > 0:
			_members[i]["hp"] = mini(top, current + whole)
			accum -= float(whole)
			healed_any = true
		_members[i]["accum"] = accum

	if healed_any:
		changed.emit()


# ---------------------------------------------------------------------------
# ponte com a batalha
# ---------------------------------------------------------------------------

## O time no formato que a tela de duelo consome: `[{code, hp}]`, na mesma
## ordem dos slots. A tela monta os `Combatant` a partir disso e devolve o HP
## pelo `absorb_party`.
func to_party() -> Array:
	var out: Array = []
	for m in _members:
		out.append({"code": str(m["code"]), "hp": int(m["hp"])})
	return out


## Recebe de volta o estado pós-batalha. `party` são os `Combatant` na mesma
## ordem, e `new_active` é quem terminou a luta em campo — trocar durante o
## combate tem de valer fora dele, senão a criatura que lutou volta para a
## reserva sozinha assim que o overlay fecha.
##
## Casar por índice só é seguro porque a batalha nunca reordena nem remove
## membros; o pareamento é verificado por código, e um desencontro é ignorado
## em vez de gravar HP na criatura errada.
func absorb_party(party: Array, new_active: int) -> void:
	for i in mini(party.size(), _members.size()):
		var c: Combatant = party[i]
		if c == null or c.code != str(_members[i]["code"]):
			continue
		_members[i]["hp"] = clampi(c.hp, 0, max_hp_at(i))
		_members[i]["accum"] = 0.0
	if new_active >= 0 and new_active < _members.size():
		_active = new_active
	changed.emit()
