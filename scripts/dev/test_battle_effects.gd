extends SceneTree

## Valida o efeito visual de golpe/status em duelo — ausente até 2026-09
## (golpe e buff só mudavam texto; os corpos ficavam parados em `Idle`).
## Três peças, cada uma com contrato próprio:
##
## 1. `Battle._log` marca `is_player` por REFERÊNCIA (não por `actor.code`) —
##    sem isso, um duelo espécie-contra-a-mesma-espécie atribuiria todo
##    evento ao lado errado.
## 2. `ElementPalette.play_battle_effect` instancia a forma certa por
##    categoria (golpe: swing/claw por sorteio estável; buff: aura Shatter
##    do StatusFX; debuff/cura: shield; carga: charge). Saem na cor do
##    elemento, lida de `elements[].palette` no bundle: o BUFF, o FEIXE do
##    Despertar e o golpe ELEMENTAR (corte tingido + estouro de impacto). O
##    resto segue na rampa neutra fixa — ver o topo de `element_palette.gd`.
## 3. `EncounterDirector._animate_one_event`/`_animate_round_events` despacha
##    pro corpo certo — dano no ALVO, status em quem usou, debuff no
##    oponente — e agora também toca o CLIPE do corpo (`Attack`/`HitReact`),
##    não só o VFX. `_animate_round_events` é uma corrotina (`await` por
##    evento, o compasso que `DuelScreen` acaba herdando); por isso esta
##    suíte também precisa esperar, não só chamar.
## 4. Variantes de ataque (`Attack2`/`Attack3`, desde 2026-09) e `Dodge` —
##    `_attack_clip_for` decide pelo dado do bestiário (`attackVariant`),
##    nunca sorteio; `Attack3` virou a encenação `Cast_Enter`→`Cast`→
##    `Cast_Exit`; `Dodge` toca em quem apanharia um golpe que errou OU numa
##    criatura selvagem que escapou de uma captura (`miss`/`capture_failed`).
##
##     godot --headless --script res://scripts/dev/test_battle_effects.gd

var _db: BestiaryData
var _failures := 0
var _checks := 0
var _frames := 0


func _initialize() -> void:
	_db = BestiaryData.new()
	var err := _db.load_bundle()
	if err != "":
		printerr("FALHA ao carregar o bundle: ", err)
		quit(1)
		return

	_test_log_is_player()


## `ElementPalette.play_battle_effect` precisa de um `Node3D` DENTRO da
## árvore (usa `get_tree().create_timer`) — e, como o resto da suíte de
## atores, um nó criado dentro de `_initialize()` não conta como "na árvore"
## até o primeiro `_process` (mesma pegadinha do `CLAUDE.md`). Por isso as
## partes 2 e 3 esperam 2 quadros.
var _dispatch_done := false


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false
	if _frames == 2:
		_test_play_battle_effect_shapes()
		# `_animate_round_events` é corrotina — `_process` não pode conter
		# `await` direto (o motor chama de novo no quadro seguinte antes de
		# terminar), então dispara e espera o sinal via `_dispatch_done` em
		# vez de `await` aqui.
		_run_dispatch_test()
		return false
	if not _dispatch_done:
		return false

	_db.free()
	print("")
	if _failures == 0:
		print("OK — %d verificacoes passaram" % _checks)
		quit(0)
	else:
		printerr("%d de %d verificacoes FALHARAM" % [_failures, _checks])
		quit(1)
	return true


func _run_dispatch_test() -> void:
	await _test_director_dispatch()
	_dispatch_done = true


# ---------------------------------------------------------------------------
# 1. is_player por referência
# ---------------------------------------------------------------------------

func _test_log_is_player() -> void:
	print("-- Battle._log marca is_player")

	# Espécies DIFERENTES — o caso comum.
	var hero := Combatant.from_bestiary(_db, "CRT-021", 20)
	var foe := Combatant.from_bestiary(_db, "CRT-023", 20)
	var b := Battle.new(_db, [hero], foe)
	b.rng.seed = 1234
	var events := b.resolve_round(BattleAction.use_ability("HAB-001"), BattleAction.use_ability("HAB-010"))
	var by_player := events.filter(func(e: Dictionary) -> bool: return bool(e.get("is_player", false)))
	var by_enemy := events.filter(func(e: Dictionary) -> bool: return not bool(e.get("is_player", false)))
	_check_true("evento do jogador tem is_player=true", not by_player.is_empty())
	_check_true("evento do inimigo tem is_player=false", not by_enemy.is_empty())
	for e in by_player:
		_check_true("is_player=true -> actor é o codigo do heroi (%s)" % str(e.get("actor")),
			str(e.get("actor")) == hero.code)

	# MESMA espécie dos dois lados — o caso que `actor.code` sozinho não
	# resolveria. `is_player` continua certo porque compara por referência.
	var hero2 := Combatant.from_bestiary(_db, "CRT-001", 20)
	var foe2 := Combatant.from_bestiary(_db, "CRT-001", 20)
	var b2 := Battle.new(_db, [hero2], foe2)
	b2.rng.seed = 1234
	var ev2 := b2.resolve_round(BattleAction.use_ability("HAB-001"), BattleAction.use_ability("HAB-001"))
	var hero_side := ev2.filter(func(e: Dictionary) -> bool: return bool(e.get("is_player", false)))
	var enemy_side := ev2.filter(func(e: Dictionary) -> bool: return not bool(e.get("is_player", false)))
	_check_true("mesmo codigo dos dois lados: ainda separa jogador de inimigo",
		not hero_side.is_empty() and not enemy_side.is_empty())


# ---------------------------------------------------------------------------
# 2. ElementPalette.play_battle_effect
# ---------------------------------------------------------------------------

func _test_play_battle_effect_shapes() -> void:
	print("\n-- ElementPalette.play_battle_effect")
	var actor := CreatureActor.create(_db.creature("CRT-021"), Vector3.ZERO, 1)
	root.add_child(actor)

	actor.play_battle_effect("damage", "ELE-001", "HAB-001")
	var attack_children := actor.find_children("*", "VFXBattleSwingBB", true, false)
	_check_true("golpe instanciou swing/claw (VFXBattleSwingBB)", attack_children.size() == 1)
	if not attack_children.is_empty():
		var vfx := attack_children[0] as VFXBattleSwingBB
		_check("cor primaria = rampa neutra fixa (sem elemento desde 2026-09)",
			vfx.primary_color, ElementPalette.highlight_color())
		# Duelo pausa a árvore inteira; sem isto o golpe nasce e trava no
		# quadro zero — invisível, porque a forma inteira depende da
		# animação abrir. Foi exatamente o bug relatado: "status anima,
		# golpe não".
		_check("golpe processa com a arvore pausada (PROCESS_MODE_ALWAYS)",
			vfx.process_mode, Node.PROCESS_MODE_ALWAYS)

	actor.play_battle_effect("debuff", "ELE-002", "")
	var shield_children := actor.find_children("*", "VFXBattleShieldBB", true, false)
	_check_true("debuff instanciou shield (VFXBattleShieldBB)", not shield_children.is_empty())
	if not shield_children.is_empty():
		_check("status tambem processa com a arvore pausada",
			(shield_children[0] as Node).process_mode, Node.PROCESS_MODE_ALWAYS)

	_test_buff_element_color(actor)
	_test_beam(actor)
	_test_elemental_hit()

	actor.play_battle_effect("charge", "ELE-003", "")
	_check_true("carga instanciou charge (VFXBattleChargeBB)",
		not actor.find_children("*", "VFXBattleChargeBB", true, false).is_empty())

	# Mesmo código -> mesma CENA, sempre (sorteio ESTÁVEL, não aleatório).
	# `swing` e `claw` compartilham a mesma classe de script (`VFXBattleSwingBB`
	# serve as duas cenas), então só o tipo não prova a escolha — o caminho da
	# cena de origem prova.
	var actor2 := CreatureActor.create(_db.creature("CRT-021"), Vector3(5, 0, 0), 1)
	root.add_child(actor2)
	actor2.play_battle_effect("damage", "ELE-001", "HAB-001")
	var repeat_children := actor2.find_children("*", "VFXBattleSwingBB", true, false)
	_check_true("mesmo codigo de habilidade -> mesma cena de origem (estavel)",
		not attack_children.is_empty() and not repeat_children.is_empty()
		and (attack_children[0] as Node).scene_file_path == (repeat_children[0] as Node).scene_file_path)

	actor.free()
	actor2.free()


## Buff é o único efeito que sai na cor do elemento. A rampa vem do bundle
## pelo autoload achado por CAMINHO — que no modo `--script` não existe, então
## a bancada pendura o próprio `_db` na raiz com o nome que o jogo usa.
func _test_buff_element_color(actor: CreatureActor) -> void:
	_db.name = "Bestiary"
	root.add_child(_db)

	var fire := _buff_on(actor, "ELE-001")
	var water := _buff_on(actor, "ELE-002")
	_check_true("buff instanciou a aura Shatter (StatusFX)", fire != null and water != null)
	if fire == null or water == null:
		return
	_check("buff processa com a arvore pausada", fire.process_mode, Node.PROCESS_MODE_ALWAYS)

	var fire_palette: Dictionary = _db.element("ELE-001")["palette"]
	var water_palette: Dictionary = _db.element("ELE-002")["palette"]
	_check("buff de Fogo: primaria = highlight do bundle",
		fire.get("primary_color"), Color.from_string(str(fire_palette["highlight"]), Color.BLACK))
	_check("buff de Agua: terciaria = aura do bundle",
		water.get("tertiary_color"), Color.from_string(str(water_palette["aura"]), Color.BLACK))

	# O que a TELA mostra é o parâmetro do shader, não a propriedade do script —
	# e os materiais são sub-recurso compartilhado da cena: sem duplicar, o
	# buff de Água (instanciado depois) teria repintado o de Fogo.
	var fire_aura := (fire.get_node("Aura") as GeometryInstance3D).material_override as ShaderMaterial
	var water_aura := (water.get_node("Aura") as GeometryInstance3D).material_override as ShaderMaterial
	_check_true("cada instancia tem o proprio material", fire_aura != water_aura)
	var fire_shown: Color = fire_aura.get_shader_parameter("tertiary_color")
	var water_shown: Color = water_aura.get_shader_parameter("tertiary_color")
	_check("shader do buff de Fogo segue com a cor de Fogo",
		fire_shown, Color.from_string(str(fire_palette["aura"]), Color.BLACK))
	_check("shader do buff de Agua tem a cor de Agua",
		water_shown, Color.from_string(str(water_palette["aura"]), Color.BLACK))

	# Elemento que o bundle não conhece cai na rampa neutra, nunca em erro.
	var unknown := _buff_on(actor, "ELE-999")
	_check("elemento desconhecido -> rampa neutra",
		unknown.get("primary_color") if unknown != null else null, ElementPalette.NEUTRAL_HIGHLIGHT)


## Golpe elementar (`attack2`): o corte do básico tingido, mais o estouro de
## impacto do "Stylized Hit FX". Corpo próprio, pra contar filhos sem o que as
## outras seções deixaram penduradas.
func _test_elemental_hit() -> void:
	var body := CreatureActor.create(_db.creature("CRT-021"), Vector3(-6, 0, 0), 1)
	root.add_child(body)
	var water: Dictionary = _db.element("ELE-002")["palette"]
	var water_aura := Color.from_string(str(water["aura"]), Color.BLACK)

	body.play_battle_effect("damage", "ELE-002", "HAB-004")
	_check_true("golpe BASICO nao estoura impacto",
		body.find_children("*", "VFXImpactBB", true, false).is_empty())

	body.play_battle_effect("impact", "ELE-002", "HAB-004")
	var impacts := body.find_children("*", "VFXImpactBB", true, false)
	_check("golpe elementar instanciou o estouro (VFXImpactBB)", impacts.size(), 1)
	if not impacts.is_empty():
		var impact := impacts[0] as VFXImpactBB
		_check_true("estouro vem de uma das cenas escolhidas do pack",
			impact.scene_file_path in ElementPalette.BATTLE_IMPACT_SCENES)
		_check("estouro processa com a arvore pausada", impact.process_mode, Node.PROCESS_MODE_ALWAYS)
		_check("estouro de Agua: secundaria = aura do bundle", impact.secondary_color, water_aura)
		_check("a LUZ do estouro tambem vem na cor (e ela que tinge chao e alvo)",
			impact.light_color, water_aura)
		var sphere := impact.get_node_or_null("ImpactSphere") as GeometryInstance3D
		_check_true("cena de impacto tem a bola central", sphere != null)
		if sphere != null:
			var sphere_material := sphere.material_override as ShaderMaterial
			var sphere_emission: float = sphere_material.get_shader_parameter("emission")
			_check_true("bola central com freio proprio (o shader dela eleva emission ao quadrado)",
				is_equal_approx(sphere_emission, ElementPalette.BATTLE_IMPACT_SPHERE_EMISSION))
			var shown: Color = sphere_material.get_shader_parameter("secondary_color")
			_check("o shader da bola recebeu a cor", shown, water_aura)

		# Mesma habilidade -> mesma cena, e material próprio por instância.
		body.play_battle_effect("impact", "ELE-001", "HAB-004")
		var both := body.find_children("*", "VFXImpactBB", true, false)
		_check("segundo estouro entrou", both.size(), 2)
		if both.size() == 2:
			_check_true("mesmo codigo de habilidade -> mesma cena de impacto (estavel)",
				(both[0] as Node).scene_file_path == (both[1] as Node).scene_file_path)
			_check("estouro de Fogo nao repintou o de Agua", impact.secondary_color, water_aura)
			var first_shown: Color = (sphere.material_override as ShaderMaterial).get_shader_parameter("secondary_color")
			_check("nem no shader (material proprio por instancia)", first_shown, water_aura)

	# O corte do elementar é o MESMO do básico (swing/claw, mesmo sorteio),
	# só que tingido.
	var neutral_cut: VFXBattleSwingBB = null
	for child in body.find_children("*", "VFXBattleSwingBB", true, false):
		neutral_cut = child as VFXBattleSwingBB
	body.play_battle_effect("damage_elemental", "ELE-002", "HAB-004")
	var cuts := body.find_children("*", "VFXBattleSwingBB", true, false)
	_check("corte elementar instanciou swing/claw", cuts.size(), 2)
	if cuts.size() == 2 and neutral_cut != null:
		var tinted := (cuts[1] if cuts[0] == neutral_cut else cuts[0]) as VFXBattleSwingBB
		_check_true("mesma cena do corte basico (mesmo sorteio estavel)",
			tinted.scene_file_path == neutral_cut.scene_file_path)
		_check("corte elementar na cor do elemento", tinted.secondary_color, water_aura)
		_check("corte basico segue neutro", neutral_cut.secondary_color, ElementPalette.NEUTRAL_MID)

	body.free()


## Feixe do golpe do Despertar (`attack3`): liga DOIS corpos, então o que se
## prende aqui é o que um efeito de corpo só não tem — a âncora no alvo, o
## feixe no atacante, e a limpeza da âncora quando o feixe some (ela mora em
## outro corpo e ficaria órfã).
func _test_beam(actor: CreatureActor) -> void:
	var target := CreatureActor.create(_db.creature("CRT-023"), Vector3(6, 0, 0), 1)
	root.add_child(target)

	actor.play_battle_beam(target, "ELE-001", 0.8)
	var beam: Node3D = null
	for child in actor.get_children():
		if child.scene_file_path == ElementPalette.BATTLE_BEAM_SCENE:
			beam = child as Node3D
	_check_true("attack3 instanciou o feixe no ATACANTE", beam != null)
	if beam == null:
		target.free()
		return
	_check("feixe processa com a arvore pausada (segue o alvo em _physics_process)",
		beam.process_mode, Node.PROCESS_MODE_ALWAYS)
	var anchor := target.get_node_or_null("BeamAnchor") as Node3D
	_check_true("ancora do feixe nasceu no ALVO", anchor != null)
	_check_true("feixe aponta pra ancora", beam.get("end_point") == anchor)
	_check_true("feixe nasce fechado (open_amount 0) e abre por tween",
		is_zero_approx(float(beam.get("open_amount"))))
	_check_true("comprimento = distancia real ate a ancora (senao pisca na abertura)",
		anchor != null and absf(float(beam.get("beam_length"))
			- beam.global_position.distance_to(anchor.global_position)) < 0.01)

	var fire: Dictionary = _db.element("ELE-001")["palette"]
	_check("feixe de Fogo: casca = aura do bundle",
		beam.get("secondary_color"), Color.from_string(str(fire["aura"]), Color.BLACK))
	# O que a tela mostra é o parâmetro do shader, e os materiais são
	# sub-recurso compartilhado: um segundo feixe de outro elemento não pode
	# repintar o primeiro.
	var water_beam := ElementPalette.play_battle_beam(actor, 0.0, 0.4, target, 0.0, "ELE-002", 0.8)
	var fire_outer := (beam.get_node("BeamPivot/BeamScalor/BeamOuter") as GeometryInstance3D).material_override as ShaderMaterial
	var fire_shown: Color = fire_outer.get_shader_parameter("secondary_color")
	_check("segundo feixe (Agua) nao repintou o de Fogo",
		fire_shown, Color.from_string(str(fire["aura"]), Color.BLACK))
	var flash: float = ((beam.get_node("BeamEndPivot/BeamEnd") as GeometryInstance3D)
		.material_override as ShaderMaterial).get_shader_parameter("flash_emission")
	_check_true("clarao do impacto freado (sem glow, o da cena vira disco branco sobre o alvo)",
		is_equal_approx(flash, ElementPalette.BATTLE_BEAM_FLASH_EMISSION))

	# `free()` e não `queue_free()`: a remoção diferida não é observável no
	# mesmo quadro (CLAUDE.md, seção de testes).
	if water_beam != null:
		water_beam.free()
	beam.free()
	_check_true("feixe sumiu -> ancora marcada pra sair do alvo",
		anchor == null or not is_instance_valid(anchor) or anchor.is_queued_for_deletion())
	target.free()


## Dispara um buff e devolve a instância recém-nascida (a última com a cena
## do Shatter como origem).
func _buff_on(actor: CreatureActor, element_code: String) -> Node3D:
	actor.play_battle_effect("buff", element_code, "")
	var found: Node3D = null
	for child in actor.get_children():
		if child.scene_file_path == ElementPalette.BATTLE_BUFF_SCENE:
			found = child as Node3D
	return found


# ---------------------------------------------------------------------------
# 3. EncounterDirector despacha pro corpo certo
# ---------------------------------------------------------------------------

func _test_director_dispatch() -> void:
	print("\n-- EncounterDirector despacha pro corpo certo (VFX e clipe)")

	var hero := Combatant.from_bestiary(_db, "CRT-021", 20)
	var foe := Combatant.from_bestiary(_db, "CRT-023", 20)
	var battle := Battle.new(_db, [hero], foe)
	battle.rng.seed = 1234

	var duel := DuelScreen.new()
	duel.battle = battle

	# `_companion` é tipado `CompanionActor` em produção, não `CreatureActor` —
	# passar o tipo errado por `.set()` não dá erro nenhum, só deixa o campo
	# null em silêncio (reflexão não confere tipo estático). Usar o tipo real
	# aqui é o que prova o despacho de verdade, não um double emprestado.
	var fake_player := Node3D.new()
	root.add_child(fake_player)
	var companion := CompanionActor.create(_db, "CRT-021", fake_player)
	root.add_child(companion)
	# Em jogo, a árvore fica pausada durante o duelo — o `_process` de
	# exploração da companheira (que escolhe o próprio clipe pela velocidade
	# de seguir o jogador) nem roda. Sem essa pausa aqui, ele brigaria com
	# `play_battle_clip` do mesmo jeito que o `BattleStaging` brigaria sem a
	# trava — mesma classe de problema, fonte diferente. `set_process(false)`
	# reproduz a pausa só pro que este teste precisa.
	companion.set_process(false)
	var enemy_actor := CreatureActor.create(_db.creature("CRT-023"), Vector3(3, 0, 0), 1)
	root.add_child(enemy_actor)
	enemy_actor.set_process(false)
	enemy_actor.set_physics_process(false)

	var director := EncounterDirector.new()
	director.set("_duel", duel)
	director.set("_companion", companion)
	director.set("_engaged_actor", enemy_actor)
	# `_staging` fica null de propósito — sem encenação, `_lock_gait` não faz
	# nada (guarda `_staging != null`), e a sequência ainda tem de tocar
	# certo. O contrato COM encenação (a trava de verdade) é assunto de
	# `test_staging.gd`, não daqui.

	# HAB-001 (Brasa, dano) do jogador contra HAB-010 (dano) do inimigo — os
	# DOIS lados atacam na mesma rodada, e dano aparece no ALVO de cada um:
	# o golpe do jogador acerta o inimigo, o contra-ataque do inimigo acerta a
	# própria companheira. Exatamente 1 de cada, nunca os dois no mesmo corpo.
	# A presença do VFX em si já está coberta em `_test_play_battle_effect_shapes`
	# (checada ANTES do compasso). Aqui o `await` cobre a rodada INTEIRA — o
	# VFX e o `_wait()` usam de propósito a MESMA duração (terminam juntos),
	# então checar "o VFX ainda está lá" depois do `await` é medir bem depois
	# dele já ter se apagado sozinho. O que é NOVO aqui, e o que este teste
	# prova, é o CLIPE do corpo — que sobrevive ao `await` porque nada mais o
	# reseta (sem `BattleStaging` nesta bancada).
	var before := battle.log_events.size()
	battle.resolve_round(BattleAction.use_ability("HAB-001"), BattleAction.use_ability("HAB-010"))
	await director._animate_round_events(battle.log_events.slice(before))

	# NÃO dá pra checar `current_animation` aqui: `HitReact` dura 0,6s e o
	# compasso (`BATTLE_ATTACK_LIFETIME`) é 0,8s — o clipe termina sozinho
	# ANTES do fim do `await`, e um `AnimationPlayer` não-looping que chega
	# ao fim limpa `current_animation` pra "" (sem voltar a pose de bind —
	# só para de escrever, o último quadro fica). `Attack` (0,867s) quase
	# sempre sobrevive ao mesmo compasso por pura coincidência de duração;
	# testar por aí seria prender o teste a um acidente de tempo, não ao
	# contrato. O contrato — `_play_body_clip` escolhe o corpo certo — é
	# testado direto, síncrono, abaixo.
	var companion_clip := str((companion.get("_anim") as AnimationPlayer).current_animation)

	# O estouro do golpe elementar vive 1,2 s, mais que o compasso do golpe
	# (0,8 s) — então, ao contrário do corte, ele AINDA está no corpo que
	# apanhou por último quando o `await` volta, e dá pra provar o despacho:
	# no ALVO, e na cor do elemento da HABILIDADE (não de quem usou).
	var round_events := battle.log_events.slice(before)
	var last_damage := {}
	for ev: Dictionary in round_events:
		if str(ev.get("type", "")) == "damage":
			last_damage = ev
	if not last_damage.is_empty():
		var hit_by_player := bool(last_damage.get("is_player", false))
		var struck: Node = enemy_actor if hit_by_player else companion
		var striker: Combatant = hero if hit_by_player else foe
		var used := striker.ability_by_code(str(last_damage.get("ability", "")))
		var expected_element := BestiaryData.ability_element(used)
		var landed := struck.find_children("*", "VFXImpactBB", true, false)
		_check_true("golpe elementar (%s): estouro despachado no ALVO" % str(last_damage.get("ability")),
			not landed.is_empty())
		if not landed.is_empty() and expected_element != "":
			var palette: Dictionary = _db.element(expected_element)["palette"]
			_check("estouro na cor do elemento da HABILIDADE (%s)" % expected_element,
				(landed[-1] as VFXImpactBB).secondary_color,
				Color.from_string(str(palette["aura"]), Color.BLACK))

	director.call("_play_body_clip", true, "Attack")
	_check("_play_body_clip(true, Attack) toca na companheira",
		str((companion.get("_anim") as AnimationPlayer).current_animation), "Attack")
	director.call("_play_body_clip", false, "HitReact")
	_check("_play_body_clip(false, HitReact) toca no inimigo",
		str((enemy_actor.get("_anim") as AnimationPlayer).current_animation), "HitReact")

	# `Idle` é contínuo (`LOOPED_CLIPS`) — ao contrário de `Attack`/`HitReact`,
	# não termina sozinho no meio do compasso seguinte, então serve de linha
	# de base estável pra provar "nada mexeu" através de um `await`.
	director.call("_play_body_clip", true, "Idle")
	companion_clip = str((companion.get("_anim") as AnimationPlayer).current_animation)

	# HAB-020 (buff_attack, em si mesmo) dos DOIS lados — status não mexe no
	# CLIPE do corpo, só na partícula (ver o comentário de `_animate_one_event`
	# sobre por quê). O clipe tem de continuar exatamente o mesmo de antes.
	# O inimigo PRECISA usar algo sem dano aqui: HAB-010 (a mesma habilidade
	# de dano da primeira rodada) geraria um evento "damage" contra a
	# companheira e tocaria HitReact de verdade — não seria bug nenhum, mas
	# quebraria a isolação que este teste quer provar.
	before = battle.log_events.size()
	battle.resolve_round(BattleAction.use_ability("HAB-020"), BattleAction.use_ability("HAB-020"))
	await director._animate_round_events(battle.log_events.slice(before))
	_check("buff nao mexeu no clipe do corpo da companheira",
		str((companion.get("_anim") as AnimationPlayer).current_animation), companion_clip)

	# -----------------------------------------------------------------------
	# 4. Variantes de ataque, Dodge e capture_failed
	# -----------------------------------------------------------------------

	# `_attack_clip_for` é pura: só olha o dicionário de habilidade, nenhum
	# Combatant envolvido. Ausente/desconhecido cai em "Attack", mesmo padrão
	# de fallback silencioso de `BestiaryData.ability_element`.
	_check("_attack_clip_for(attack2) -> Attack2",
		director.call("_attack_clip_for", {"attackVariant": "attack2"}), "Attack2")
	_check("_attack_clip_for(attack3) -> Attack3",
		director.call("_attack_clip_for", {"attackVariant": "attack3"}), "Attack3")
	_check("_attack_clip_for sem campo -> Attack (fallback)",
		director.call("_attack_clip_for", {}), "Attack")
	_check("_attack_clip_for valor desconhecido -> Attack (fallback)",
		director.call("_attack_clip_for", {"attackVariant": "invalido"}), "Attack")

	# `Attack2` (Sword_Dash) e `Dodge` (Shield_Dash) são clipes de verdade na
	# UAL desde 2026-09 — mesma checagem síncrona de `_play_body_clip` que já
	# prova `Attack`/`HitReact` acima.
	director.call("_play_body_clip", true, "Attack2")
	_check("_play_body_clip(true, Attack2) toca na companheira",
		str((companion.get("_anim") as AnimationPlayer).current_animation), "Attack2")
	director.call("_play_body_clip", false, "Dodge")
	_check("_play_body_clip(false, Dodge) toca no inimigo",
		str((enemy_actor.get("_anim") as AnimationPlayer).current_animation), "Dodge")

	# `Attack3` não é clipe único — é a encenação Cast_Enter->Cast->Cast_Exit
	# (`_play_attack3_sequence`). A prova aqui é dos TRÊS nomes de clipe,
	# direto e síncrono, pelo mesmo motivo do comentário mais acima sobre
	# `current_animation` esvaziar sozinho num clipe não-looping curto antes
	# do `await` de um compasso real terminar.
	director.call("_play_body_clip", true, "Cast_Enter")
	_check("_play_body_clip(true, Cast_Enter) toca na companheira",
		str((companion.get("_anim") as AnimationPlayer).current_animation), "Cast_Enter")
	director.call("_play_body_clip", true, "Cast")
	_check("_play_body_clip(true, Cast) toca na companheira",
		str((companion.get("_anim") as AnimationPlayer).current_animation), "Cast")
	director.call("_play_body_clip", true, "Cast_Exit")
	_check("_play_body_clip(true, Cast_Exit) toca na companheira",
		str((companion.get("_anim") as AnimationPlayer).current_animation), "Cast_Exit")

	# "miss": evento sintético (não pela rolagem de acerto real, pra não
	# depender de sorte de RNG). `HAB-024` (Bote) de propósito — é o básico
	# de classe, fixado em `attack` por desenho (animado por Attack1), então
	# o teste não depende de qual habilidade elemental está com qual
	# variante nesta rodada (elas já são `attack2`/`attack3` desde 2026-09).
	# Quem atacou anima essa variante; quem apanharia escapa com `Dodge` — do
	# lado OPOSTO de quem agiu, nunca do atacante. Chamada SEM `await` (fogo
	# e esquece, mesmo padrão de `duel_screen._try_capture`): as duas
	# chamadas a `_play_body_clip` do branch "miss" são síncronas, antes do
	# primeiro `await` da função — não precisam esperar o compasso.
	var miss_event := {"round": 1, "type": "miss", "actor": hero.code, "is_player": true, "ability": "HAB-024"}
	director._animate_one_event(battle, miss_event)
	_check("miss: atacante toca a variante padrao (Attack)",
		str((companion.get("_anim") as AnimationPlayer).current_animation), "Attack")
	_check("miss: Dodge toca no lado que apanharia (inimigo), nao no atacante",
		str((enemy_actor.get("_anim") as AnimationPlayer).current_animation), "Dodge")

	# "capture_failed": `Battle._do_capture` loga este evento com `actor` = a
	# própria criatura selvagem (nunca quem tentou capturar) — é ela que
	# escapa, e `is_player` já vem no lado certo sem precisar negar (mesmo
	# padrão de "faint").
	var capture_failed_event := {"round": 1, "type": "capture_failed", "actor": foe.code, "is_player": false}
	director._animate_one_event(battle, capture_failed_event)
	_check("capture_failed: Dodge toca no selvagem que escapou da captura",
		str((enemy_actor.get("_anim") as AnimationPlayer).current_animation), "Dodge")

	companion.free()
	enemy_actor.free()
	fake_player.free()
	duel.free()


# ---------------------------------------------------------------------------
# relatório
# ---------------------------------------------------------------------------

func _check(label: String, actual: Variant, expected: Variant) -> void:
	_checks += 1
	if actual == expected:
		print("  ok   %s = %s" % [label, str(actual)])
	else:
		_failures += 1
		printerr("  FAIL %s = %s (esperado %s)" % [label, str(actual), str(expected)])


func _check_true(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
