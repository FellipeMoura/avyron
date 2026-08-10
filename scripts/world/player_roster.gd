class_name PlayerRoster
extends RefCounted

## O time do jogador, em três níveis: uma criatura **ativa**, as **reservas**
## que viajam com ela no mapa, e o **storage** que fica pra trás — mais o HP
## de cada uma, que persiste entre batalhas e se recupera com o tempo.
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
## ## Ativo vs. storage
##
## `_members` é o que o jogador carrega no mapa agora — limitado pelo
## `slotCapacity` do Relicário equipado (`set_capacity`), não mais um teto
## fixo. `_storage` é tudo que ficou pra trás no posto do relicário: sem
## limite de código (o design deixa "storage geral" em aberto, ver documento
## `relicario`), só acessível lá, não no mapa. Ver `PlayerRelic`.
##
## ## O que persiste e o que não
##
## Só o HP. Carga do Despertar, buffs e usos de golpe continuam começando do
## zero a cada batalha — são o arco de uma luta, não um orçamento administrado
## ao longo do dia (ver o cabeçalho de `Combatant`). O HP é a exceção porque é
## o que transforma uma sequência de encontros em uma expedição com custo: sem
## ele, seis criaturas são seis opções e nenhuma é um recurso. HP regenera
## igual em `_members` e em `_storage` — são criaturas do jogador de um jeito
## ou de outro, e nada no design distingue as duas pra regeneração.

signal changed

## Teto de sanidade, não o limite operante — esse vem de
## `PlayerRelic.slot_capacity()` via `set_capacity`. Mesmo bound do CHECK de
## `relic_stats.slotCapacity` no banco (1–12); existe só pra `_capacity` nunca
## crescer descontrolado a partir de um dado de bundle ruim.
const HARD_CEILING := 12

## Fração do HP máximo recuperada por minuto, fora de combate.
##
## Dez minutos do zero até cheio. A escala foi escolhida contra o cooldown de
## mineração (3 s) e o respawn de criatura (20–40 s): recuperar é a coisa lenta
## do mapa, então voltar para o bioma custa tempo de verdade e trocar a ativa
## por uma reserva inteira vira decisão, não formalidade.
const REGEN_FRACTION_PER_MINUTE := 0.10

var _db: BestiaryData
var _level := 1
var _capacity := 6  # fallback antes de qualquer relicário equipado

## `[{code, hp, accum}]`. `accum` é o resto fracionário da regeneração — sem
## ele, `max_hp * 0.1/60 * delta` a 60 fps é sempre muito menor que 1 e a cura
## inteira desaparece no arredondamento, quadro após quadro.
var _members: Array[Dictionary] = []
var _active := 0

## Mesma forma de `_members` — criaturas que ficaram no posto do relicário,
## fora do alcance do mapa até o jogador voltar lá.
var _storage: Array[Dictionary] = []


## Começa o time com a criatura inicial, em HP cheio.
##
## `db` fica guardado porque o HP máximo de cada membro é derivado
## (`stats_at_level`), não armazenado. `level` vira o nível **inicial** da
## primeira criatura e o fallback de `add()` quando quem chama não sabe (ou
## não liga) em que nível a nova criatura deveria entrar — cada membro tem o
## próprio nível daqui pra frente, sobe sozinho por XP (`grant_xp_at`).
func setup(db: BestiaryData, level: int, starter_code: String) -> void:
	_db = db
	_level = maxi(1, level)
	_members.clear()
	_storage.clear()
	_active = 0
	if starter_code != "":
		_members.append(_make_member(starter_code, -1, _level))
	changed.emit()


## Ajusta a capacidade ativa pro `slotCapacity` do relicário equipado.
## Clampado ao `HARD_CEILING` — um valor de bundle ruim não deve deixar o
## array crescer sem limite.
func set_capacity(n: int) -> void:
	_capacity = clampi(n, 1, HARD_CEILING)


func capacity() -> int:
	return _capacity


func _make_member(code: String, hp: int, level: int) -> Dictionary:
	var lvl := maxi(1, level)
	var top := _max_hp_of(code, lvl)
	# hp < 0 é o pedido de "cheia"; qualquer outro valor entra limitado ao teto.
	var start := top if hp < 0 else clampi(hp, 0, top)
	return {"code": code, "hp": start, "accum": 0.0, "level": lvl, "xp": 0}


func _max_hp_of(code: String, level: int) -> int:
	if _db == null:
		return 1
	var stats := _db.stats_at_level(code, level)
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
	return _members.size() >= _capacity


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
## `level` negativo cai no nível padrão do time (`setup`) — quem captura sabe
## o nível de verdade do bicho selvagem (`Combatant.level`) e deve passá-lo;
## o fallback existe pra quem só quer testar composição sem se importar.
##
## Repetir espécie é permitido de propósito: dois Anomalocaris são dois bichos,
## não um duplicado.
func add(code: String, hp: int = -1, level: int = -1) -> bool:
	if code == "" or is_full():
		return false
	if _db != null and _db.creature(code).is_empty():
		return false
	_members.append(_make_member(code, hp, level if level > 0 else _level))
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
# storage — posto do relicário
# ---------------------------------------------------------------------------

func storage_entries() -> Array[String]:
	var out: Array[String] = []
	for m in _storage:
		out.append(str(m["code"]))
	return out


func storage_size() -> int:
	return _storage.size()


## HP de um membro guardado, pelo mesmo motivo que `hp_at` existe pro ativo:
## a HUD/tela do posto precisa mostrar sem expor o array privado.
func storage_hp_at(index: int) -> int:
	if index < 0 or index >= _storage.size():
		return 0
	return int(_storage[index]["hp"])


func storage_max_hp_at(index: int) -> int:
	if index < 0 or index >= _storage.size():
		return 0
	return _max_hp_of(str(_storage[index]["code"]), int(_storage[index]["level"]))


func storage_level_at(index: int) -> int:
	if index < 0 or index >= _storage.size():
		return 0
	return int(_storage[index]["level"])


## Move um ativo pro storage. Recusa se sobraria zero ativa — o jogador
## sempre precisa de alguém pra andar no mapa e entrar em campo — ou se o
## índice não existe. Se a depositada for a ativa, a próxima da lista assume.
func deposit(index: int) -> bool:
	if index < 0 or index >= _members.size() or _members.size() <= 1:
		return false
	var member: Dictionary = _members[index]
	_members.remove_at(index)
	_storage.append(member)
	if _active >= _members.size():
		_active = _members.size() - 1
	elif index < _active:
		_active -= 1
	changed.emit()
	return true


## Move um guardado pro time ativo. Recusa se o time já está no teto — mesma
## regra que já vale pra `add()` na captura.
func withdraw(storage_index: int) -> bool:
	if storage_index < 0 or storage_index >= _storage.size() or is_full():
		return false
	var member: Dictionary = _storage[storage_index]
	_storage.remove_at(storage_index)
	_members.append(member)
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
	return _max_hp_of(str(_members[index]["code"]), level_at(index))


func level_at(index: int) -> int:
	if index < 0 or index >= _members.size():
		return 0
	return int(_members[index]["level"])


func xp_at(index: int) -> int:
	if index < 0 or index >= _members.size():
		return 0
	return int(_members[index]["xp"])


## XP necessário pra `index` passar do nível atual ao seguinte. Zero se o
## bundle não tem o bloco `progression` (bundle anterior a este sistema).
func xp_to_next_at(index: int) -> int:
	if index < 0 or index >= _members.size() or _db == null:
		return 0
	var xp_rules: Dictionary = _db.progression_rules().get("xp", {})
	if xp_rules.is_empty():
		return 0
	return ProgressionMath.xp_to_next(
		float(xp_rules.get("curveBase", 14)), float(xp_rules.get("curveExponent", 1.7)), level_at(index))


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


## Recupera HP de um membro. Devolve quanto entrou **de fato** — zero quando
## não havia o que curar.
##
## O retorno é o que deixa o chamador decidir se o item se gasta. Um emplastro
## consumido numa criatura já cheia é o jogador perdendo 80 óbolos num clique,
## e quem sabe que a cura foi nula é este método; um `void` obrigaria cada
## chamador a refazer a conta de HP faltante antes de chamar, e um deles
## esqueceria.
##
## Curar uma criatura caída é permitido, pela mesma razão que ela regenera
## sozinha (ver `regenerate`): desmaiar é interdição temporária, não um estado
## que precise de item específico para sair.
func heal_at(index: int, amount: int) -> int:
	if index < 0 or index >= _members.size() or amount <= 0:
		return 0
	var current := int(_members[index]["hp"])
	var missing := max_hp_at(index) - current
	var healed := mini(amount, missing)
	if healed <= 0:
		return 0
	_members[index]["hp"] = current + healed
	# Mesma razão do `set_hp_at`: quem acabou de ser curado não deve carregar
	# resto fracionário de antes da cura.
	_members[index]["accum"] = 0.0
	changed.emit()
	return healed


## Quanto de HP falta para o membro encher. Zero para índice inválido — quem
## pergunta é a lista de itens, e um slot vazio simplesmente não tem o que
## curar.
func missing_hp_at(index: int) -> int:
	if index < 0 or index >= _members.size():
		return 0
	return maxi(0, max_hp_at(index) - int(_members[index]["hp"]))


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
	if delta <= 0.0:
		return
	var rate := REGEN_FRACTION_PER_MINUTE / 60.0
	# Ativa e storage regeneram igual — são criaturas do jogador de um jeito
	# ou de outro, e nada no design distingue as duas pra isso.
	var healed := _regenerate_array(_members, rate, delta)
	healed = _regenerate_array(_storage, rate, delta) or healed
	if healed:
		changed.emit()


func _regenerate_array(arr: Array[Dictionary], rate: float, delta: float) -> bool:
	if arr.is_empty():
		return false
	var healed_any := false
	for i in arr.size():
		var top := _max_hp_of(str(arr[i]["code"]), int(arr[i]["level"]))
		var current := int(arr[i]["hp"])
		if current >= top:
			# Zera o resto ao encher: sem isso, uma criatura curada sobra com
			# acúmulo que viraria 1 de cura instantânea no primeiro dano.
			arr[i]["accum"] = 0.0
			continue

		var accum := float(arr[i]["accum"]) + float(top) * rate * delta
		var whole := int(accum)
		if whole > 0:
			arr[i]["hp"] = mini(top, current + whole)
			accum -= float(whole)
			healed_any = true
		arr[i]["accum"] = accum
	return healed_any


# ---------------------------------------------------------------------------
# progressão — XP de criatura, mesma forma do Relicário
#
# Duas condições ao mesmo tempo: XP acumulado até o limiar **e** o material
# da própria classe da criatura que sobe, gasto no ato. Sem o material, a
# barra trava cheia até o jogador ter o item — não deixa passar do teto
# esperando, mesma regra de `PlayerRelic.grant_capture_xp`. Documento
# `progressao`.
# ---------------------------------------------------------------------------

## Concede XP a um membro ativo e sobe de nível enquanto der — XP cheio e
## material disponível na bolsa, no mesmo golpe. Devolve
## `{leveled_up, new_level, waiting_material}`, mesmo formato de
## `PlayerRelic.grant_capture_xp`.
func grant_xp_at(index: int, amount: int, inventory: PlayerInventory) -> Dictionary:
	var result := {"leveled_up": false, "new_level": level_at(index), "waiting_material": false}
	if index < 0 or index >= _members.size() or _db == null or inventory == null or amount <= 0:
		return result

	var xp_rules: Dictionary = _db.progression_rules().get("xp", {})
	var cost_rules: Dictionary = _db.progression_rules().get("levelUpCost", {})
	if xp_rules.is_empty() or cost_rules.is_empty():
		return result

	_members[index]["xp"] = int(_members[index]["xp"]) + amount
	var cap := _db.level_cap()

	while level_at(index) < cap and xp_at(index) >= xp_to_next_at(index):
		var threshold := xp_to_next_at(index)
		var class_code := str(_db.creature(str(_members[index]["code"])).get("class", ""))
		var material := _db.class_material_item(class_code)
		var units := ProgressionMath.material_cost(
			int(cost_rules.get("base", 1)), int(cost_rules.get("levelStep", 20)), level_at(index))

		if material == "" or not inventory.remove(material, units):
			_members[index]["xp"] = threshold  # trava no teto — ver cabeçalho da seção
			result["waiting_material"] = true
			break

		_members[index]["xp"] = xp_at(index) - threshold
		_members[index]["level"] = level_at(index) + 1
		result["leveled_up"] = true
		result["new_level"] = level_at(index)

	changed.emit()
	return result


# ---------------------------------------------------------------------------
# ponte com a batalha
# ---------------------------------------------------------------------------

## O time no formato que a tela de duelo consome: `[{code, hp, level}]`, na
## mesma ordem dos slots — cada criatura entra em campo no **próprio** nível,
## não mais um nível de encontro achatado pro time inteiro. A tela monta os
## `Combatant` a partir disso e devolve o HP pelo `absorb_party`.
func to_party() -> Array:
	var out: Array = []
	for m in _members:
		out.append({"code": str(m["code"]), "hp": int(m["hp"]), "level": int(m["level"])})
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
