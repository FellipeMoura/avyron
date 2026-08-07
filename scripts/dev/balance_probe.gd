extends SceneTree

## Sonda de balanceamento: simula o elenco inteiro lutando contra si mesmo e
## reporta taxas de vitória.
##
##     godot --headless --script res://scripts/dev/balance_probe.gd
##
## Não é teste — não falha, não afirma nada. É instrumento de leitura, para
## as decisões de tuning saírem de números e não de impressão. Os stats do
## bestiário são um primeiro passe declaradamente provisório; isto é o que
## mostra onde ele está torto.
##
## Ambos os lados jogam com a mesma IA e despertam assim que o medidor enche,
## então a diferença de resultado vem dos stats, não da qualidade do piloto.

const LEVEL := 25
const BATTLES_PER_PAIR := 4
const MAX_ROUNDS := 60

var _duration_override := 0


func _init() -> void:
	var db := BestiaryData.new()
	if db.load_bundle() != "":
		printerr("bundle nao carregou")
		db.free()
		quit(1)
		return

	# Permite variar a constante de dano sem tocar no bundle, para medir o
	# efeito antes de decidir a mudança:
	#
	#     godot --headless --script res://scripts/dev/balance_probe.gd -- 0.2
	#
	# É override local da sonda; o valor de verdade vive no export.
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0 and user_args[0].is_valid_float():
		var override := user_args[0].to_float()
		db.rules["damage"]["constant"] = override
		print("override: damage.constant = %s" % str(override))

	# Segundo argumento sobrescreve a duração do Despertar em todas as
	# criaturas, para medir se a transformação está durando o bastante
	# em relação ao comprimento da luta.
	var duration_override := 0
	if user_args.size() > 1 and user_args[1].is_valid_int():
		duration_override = user_args[1].to_int()
		print("override: awakeningDurationTurns = %d" % duration_override)
	_duration_override = duration_override

	# Terceiro argumento escala a velocidade de enchimento da carga.
	#
	# Com os valores atuais, uma criatura de carga neutra (50) precisa sofrer
	# dano igual ao próprio HP máximo para encher o medidor — ou seja, ela
	# desperta exatamente quando deveria estar morta. Este botão mede o que
	# acontece ao antecipar isso.
	if user_args.size() > 2 and user_args[2].is_valid_float():
		var scale := user_args[2].to_float()
		db.rules["charge"]["takenMultiplier"] = float(db.rules["charge"]["takenMultiplier"]) * scale
		db.rules["charge"]["dealtMultiplier"] = float(db.rules["charge"]["dealtMultiplier"]) * scale
		print("override: enchimento de carga x%s" % str(scale))

	var codes := db.creature_codes()
	codes.sort()

	var wins := {}
	var fights := {}
	var awakened_wins := 0
	var awakened_fights := 0
	var total_rounds := 0
	var total_battles := 0

	for c in codes:
		wins[c] = 0
		fights[c] = 0

	for i in codes.size():
		for j in codes.size():
			if i == j:
				continue
			for n in BATTLES_PER_PAIR:
				var result := _simulate(db, codes[i], codes[j], i * 1000 + j * 10 + n)
				total_battles += 1
				total_rounds += result["rounds"]
				fights[codes[i]] += 1
				fights[codes[j]] += 1
				wins[result["winner"]] = wins[result["winner"]] + 1

				if result["first_to_awaken"] != "":
					awakened_fights += 1
					if result["first_to_awaken"] == result["winner"]:
						awakened_wins += 1

	# ---- relatório --------------------------------------------------------
	var rows: Array = []
	for c in codes:
		var rate := float(wins[c]) / float(fights[c]) if fights[c] > 0 else 0.0
		var data := db.creature(c)
		var s: Dictionary = data["stats"]
		var bst: int = int(s["hp"]) + int(s["attack"]) + int(s["defense"]) + int(s["speed"])
		rows.append({
			"code": c, "name": str(data["name"]), "rate": rate, "bst": bst,
			"hp": int(s["hp"]), "atk": int(s["attack"]),
			"def": int(s["defense"]), "spd": int(s["speed"]),
		})
	rows.sort_custom(func(a, b): return a["rate"] > b["rate"])

	print("")
	print("=== sonda de balanceamento — nivel %d, %d batalhas ===" % [LEVEL, total_battles])
	print("media de %.1f rodadas por luta" % (float(total_rounds) / float(total_battles)))
	print("")
	print("%-9s %-18s %6s %5s  %4s %4s %4s %4s" % ["codigo", "nome", "vit%", "soma", "hp", "atk", "def", "spd"])
	for r in rows:
		print("%-9s %-18s %5.1f%% %5d  %4d %4d %4d %4d"
			% [r["code"], r["name"].substr(0, 18), r["rate"] * 100.0, r["bst"],
			   r["hp"], r["atk"], r["def"], r["spd"]])

	print("")
	if awakened_fights > 0:
		print("quem despertou primeiro venceu em %.1f%% das %d lutas com Despertar"
			% [float(awakened_wins) / float(awakened_fights) * 100.0, awakened_fights])

	# Correlação entre defesa e vitória, para ver se a muralha domina.
	print("")
	print("perfil dos 5 melhores:  %s" % _profile(rows.slice(0, 5)))
	print("perfil dos 5 piores:    %s" % _profile(rows.slice(rows.size() - 5)))

	db.free()
	quit(0)


func _profile(rows: Array) -> String:
	var hp := 0.0
	var atk := 0.0
	var def := 0.0
	var spd := 0.0
	for r in rows:
		hp += r["hp"]; atk += r["atk"]; def += r["def"]; spd += r["spd"]
	var n := float(rows.size())
	return "hp %.0f, atk %.0f, def %.0f, spd %.0f" % [hp / n, atk / n, def / n, spd / n]


func _simulate(db: BestiaryData, a_code: String, b_code: String, seed_value: int) -> Dictionary:
	var a := Combatant.from_bestiary(db, a_code, LEVEL)
	var b := Combatant.from_bestiary(db, b_code, LEVEL)
	if _duration_override > 0:
		a.awakening_duration = _duration_override
		b.awakening_duration = _duration_override
	var battle := Battle.new(db, [a], b, false)
	battle.rng.seed = seed_value

	var first_to_awaken := ""
	var rounds := 0

	while not battle.is_over() and rounds < MAX_ROUNDS:
		rounds += 1
		if a.can_awaken(battle.charge_max()):
			battle.activate_awakening(true)
			if first_to_awaken == "":
				first_to_awaken = a_code
		if b.can_awaken(battle.charge_max()):
			battle.activate_awakening(false)
			if first_to_awaken == "":
				first_to_awaken = b_code

		battle.resolve_round(
			battle.choose_action_for(a, b),
			battle.choose_action_for(b, a)
		)

	# Estouro do limite de rodadas conta para quem estava com mais vida
	# proporcional — luta arrastada não deve virar vitória de ninguém por sorteio.
	var winner := a_code
	if battle.outcome == Battle.Outcome.PLAYER_LOST:
		winner = b_code
	elif battle.outcome == Battle.Outcome.ONGOING:
		winner = a_code if a.hp_ratio() >= b.hp_ratio() else b_code

	return {"winner": winner, "rounds": rounds, "first_to_awaken": first_to_awaken}
