class_name CombatMath
extends RefCounted

## Fórmulas de combate. Funções puras — nada aqui lê estado global, o que as
## torna testáveis isoladamente.
##
## Toda constante vem do bloco `rules` de data/bestiary.json, nunca escrita
## à mão aqui. Se um número de balanceamento mudar no bestiário, ele chega
## pelo próximo export e este arquivo não precisa ser tocado. O que está
## fixo aqui é só a *forma* da aritmética.
##
## Especificação legível: documentos `combate`, `carga-e-despertar` e
## `captura` no bestiário.


## Valor efetivo de um stat no nível dado.
##
##     valor(nível) = floor(base * (1 + growthRate * (nível - 1)))
##
## Um único `growth_rate` escala todos os stats da espécie — uma manopla por
## criatura em vez de cinco.
static func stat_at_level(base: int, growth_rate: float, level: int) -> int:
	return int(floor(float(base) * (1.0 + growth_rate * float(level - 1))))


## Aplica o bônus da classe a UM stat já escalado pelo nível.
##
##     valor = floor(valor_no_nivel * (1 + pct / 100))
##
## `pct` é o `primaryStatBonusPct` da classe, em pontos percentuais — `20`
## significa +20%. O número vem do bundle; nenhum multiplicador de classe está
## escrito neste arquivo, o que é a regra 1 aplicada ao caso.
##
## A classe modifica **um** stat, o `primaryStat` dela, e é `BestiaryData` que
## sabe qual — aqui só mora a aritmética, como no resto de `CombatMath`. Dois
## detalhes que a forma esconde:
##
## - o bônus entra DEPOIS da curva de nível, não sobre a base. Aplicar antes
##   faria a vantagem da classe crescer junto com `growthRate` e uma criatura
##   de nível 50 abriria uma distância que ninguém dimensionou.
## - o piso é 1 pelo mesmo motivo de `effective_attack`: a fórmula de dano
##   divide pela defesa, e um zero vindo de um stat base 0 travaria a conta.
static func stat_with_class_bonus(value: int, bonus_pct: float) -> int:
	if bonus_pct <= 0.0:
		return value
	return maxi(1, int(floor(float(value) * (1.0 + bonus_pct / 100.0))))


## Multiplicador elemental do atacante contra o defensor.
##
## O anel cobre 12 pares; qualquer combinação ausente é neutra. Tratar a
## ausência como 1.0 (em vez de exigir 36 linhas) é o que mantém a tabela
## pequena e o ciclo legível.
static func element_multiplier(
	attacker_element: String,
	defender_element: String,
	advantages: Array,
	rules: Dictionary
) -> float:
	for row in advantages:
		if row["attacker"] == attacker_element and row["defender"] == defender_element:
			return float(row["multiplier"])
	return float(rules["elementNeutralMultiplier"])


## Dano de um golpe.
##
##     dano = floor((poder * ataque / defesa) * constante * multElemental * variância)
##
## `variance` negativo sorteia dentro da faixa das regras. Passe um valor
## explícito para tornar o cálculo determinístico — é o que os testes fazem.
##
## Poder 0 significa movimento de status: não causa dano nenhum, e o trabalho
## dele acontece pelo `effectCode`.
static func damage(
	power: int,
	attack: int,
	defense: int,
	elem_mult: float,
	rules: Dictionary,
	variance: float = -1.0
) -> int:
	if power <= 0:
		return 0

	var d: Dictionary = rules["damage"]
	var v := variance
	if v < 0.0:
		v = randf_range(float(d["varianceMin"]), float(d["varianceMax"]))

	var raw := (float(power) * float(attack) / float(defense)) * float(d["constant"]) * elem_mult * v
	return maxi(int(floor(raw)), int(d["minimum"]))


## Pontos de carga ganhos ao SOFRER dano.
##
## Enche o dobro do que causar dano enche, e isso é o eixo do balanceamento:
## se causar dano enchesse mais, quem já está ganhando despertaria primeiro e
## o Despertar viraria amplificador de vitória em vez de virada de jogo.
static func charge_from_damage_taken(
	damage_taken: int,
	own_max_hp: int,
	effective_charge: int,
	rules: Dictionary
) -> float:
	return _charge_gain(
		damage_taken, own_max_hp, effective_charge,
		float(rules["charge"]["takenMultiplier"]), rules
	)


## Pontos de carga ganhos ao CAUSAR dano. Metade do peso de sofrer.
static func charge_from_damage_dealt(
	damage_dealt: int,
	target_max_hp: int,
	effective_charge: int,
	rules: Dictionary
) -> float:
	return _charge_gain(
		damage_dealt, target_max_hp, effective_charge,
		float(rules["charge"]["dealtMultiplier"]), rules
	)


static func _charge_gain(
	dmg: int,
	max_hp: int,
	effective_charge: int,
	side_multiplier: float,
	rules: Dictionary
) -> float:
	if max_hp <= 0:
		return 0.0
	var c: Dictionary = rules["charge"]
	var fraction := clampf(float(dmg) / float(max_hp), 0.0, 1.0)
	var charge_scale := float(effective_charge) / float(c["neutralCharge"])
	return fraction * float(c["max"]) * side_multiplier * charge_scale


## Captura: ver `RelicMath.capture_chance`. A fórmula antiga baseada em HP e
## Despertar (`chance = catchRate/255 * hp_term * item_bonus * mult_despertar`)
## foi substituída pelo sistema de Relicário — sem consumível, sem termo de
## HP. `rules["capture"]` (`combat_rules.captureMinChance/maxChance`) segue
## exportado por compatibilidade histórica do bundle, mas nada aqui o lê mais.


## Quem age primeiro. Devolve > 0 se `a` age antes, < 0 se `b` age antes,
## 0 no empate — que a chamadora resolve por sorteio.
##
## Prioridade domina velocidade: um golpe de prioridade 1 age antes de
## qualquer coisa, por mais lenta que seja a criatura.
static func turn_order_compare(
	a_priority: int, a_speed: int,
	b_priority: int, b_speed: int
) -> int:
	if a_priority != b_priority:
		return a_priority - b_priority
	return a_speed - b_speed
