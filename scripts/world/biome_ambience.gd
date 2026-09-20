class_name BiomeAmbience
extends Node

## A luz e a névoa do bioma em que o jogador está, interpoladas na travessia.
##
## Até 2026-09-17 o PZ-01 tinha UM `Environment` para os cinco biomas, e a
## única fragmentação era por ALTURA: névoa densa abaixo da linha d'água, rala
## acima (`MapDressing._apply_pz01_ambience`). Isso resolve "submerso vs.
## emerso" e nada mais — e os dois biomas que mais precisavam de tratamento
## próprio são exatamente os que altura não expressa:
##
##   - **Mar Profundo (BIO-004)** pede escuro, e fica na MESMA cota do mar
##     raso desde que o relevo virou dois níveis fixos (`MapTerrain`, seção
##     "Dois níveis"). Não existe altura que o distinga.
##   - **Plataforma Glacial (BIO-014)** pede frio, e é terra firme — a mesma
##     cota da costa, que pede quente.
##
## `BIOME_PROPS.md` (§6.3) registra isso como a terceira pendência de código
## antes de o acervo de props servir. É a primeira das três a ser feita porque
## é a única que não depende de asset nenhum: numa câmera ortográfica travada,
## prop é uma fração da tela e névoa é a tela inteira.
##
## ## Por que interpolar, e não trocar
##
## A fronteira de bioma é uma linha matemática (`MapBiomes.biome_at`), não uma
## transição de terreno. Trocar o `Environment` no quadro da travessia faria a
## tela inteira piscar num passo — e pior, piscaria de ida e volta se o jogador
## andasse em cima da linha. A interpolação de `TRANSITION_SEC` transforma as
## duas patologias na mesma coisa inofensiva: caminhar pela borda vira um
## gradiente que nunca chega a lugar nenhum.
##
## ## Um Environment, não cinco
##
## Este nó MUTA o `Environment` que o `MapDressing` já criou, em vez de trocar
## o recurso. Um `Environment` por bioma teria de ser trocado inteiro no
## `WorldEnvironment` — o que é justamente o passo que não dá para interpolar.
##
## A mesma razão vale para o sol: `KeyLight` continua sendo a única luz com
## sombra do mapa, e o que muda é a cor/energia dela, não a existência.
## As omnis de preenchimento da costa e da ilha (`_add_fill_light`) NÃO entram
## aqui de propósito — elas são banho local de cor sobre chão emerso, e chão
## emerso não muda de temperatura porque o jogador cruzou uma linha no mar.

## Quanto dura a travessia. Medido contra `PlayerController.WALK_SPEED`
## (3,12 m/s desde 2026-09-17): 2 s são ~6 m de caminhada — menos que meia
## tela na câmera de jogo, o bastante para a mudança ler como "entrei em outro
## lugar" em vez de corte, e curto o bastante para o bioma novo já estar
## estabelecido quando a primeira criatura dele aparece na tela.
const TRANSITION_SEC := 2.0

## O estado que o mapa tinha antes deste arquivo existir — os valores que
## `MapDressing` escreve no `Environment` ao montar, sem bioma nenhum na conta.
##
## LIDO das constantes de lá, não copiado: aquelas constantes carregam o
## histórico de calibragem inteiro (o ambient que clareou e voltou, a névoa
## que afogava coral acima de 0,02), e uma cópia aqui seria um segundo lugar
## para alguém recalibrar só metade.
##
## É a referência de duas formas: o perfil de BIO-001 (mar raso, bioma-base
## do PZ-01 e fallback de `WorldRoot`) e o que qualquer bioma sem entrada em
## `PROFILES` recebe.
const BASE := {
	"bg": MapDressing.PZ01_WATER_BG,
	"ambient": MapDressing.PZ01_AMBIENT,
	"ambient_energy": MapDressing.PZ01_AMBIENT_ENERGY,
	"fog": MapDressing.PZ01_FOG,
	"fog_density": MapDressing.PZ01_FOG_BASE_DENSITY,
	"fog_underwater": MapDressing.PZ01_FOG_UNDERWATER_DENSITY,
	"sun": MapDressing.PZ01_SUN,
	"sun_energy": MapDressing.PZ01_SUN_ENERGY,
}

## Desvios por bioma sobre `BASE`. Chave ausente = valor de `BASE`, e é por
## isso que BIO-001 não aparece: ele É a base.
##
## As intenções vêm do cadastro de cada bioma (ver `BIOME_PROPS.md` §4, que
## cita a descrição do catálogo entre aspas); os números são apresentação, e
## a regra 1 do `CLAUDE.md` os permite aqui pelo mesmo motivo que permite as
## cores de `MapDressing`.
const PROFILES := {
	# "faixa mineral costeira" — é o adro da vila, e o único trecho do mapa
	# com luz quente própria (as omnis de `_add_fill_light`). O perfil só
	# empurra o sol na direção que elas já apontam, para a subida da rampa
	# não ser um degrau de temperatura entre "luz local quente" e "sol
	# neutro do mar".
	"BIO-002": {
		"bg": Color("#0A3348"),
		"ambient": Color("#9C958A"),
		"fog": Color("#2A4E62"),
		"fog_density": 0.005,
		"sun": Color("#FFF6E4"),
		"sun_energy": 1.4,
	},
	# "primeiro grande espetáculo visual do jogo" — o bioma mais denso e o
	# mais claro. Névoa puxada para o turquesa que o kit de coral já tem, e
	# menos murk que o mar raso: o recife tem de ser o trecho em que se
	# enxerga LONGE, senão a densidade de prop que ele carrega se perde na
	# névoa em vez de virar espetáculo.
	"BIO-003": {
		"bg": Color("#08415A"),
		"ambient_energy": 1.4,
		"fog": Color("#1C6E7E"),
		"fog_density": 0.0055,
		"fog_underwater": 0.85,
		"sun": Color("#F2FFF6"),
		"sun_energy": 1.4,
	},
	# "baixa luminosidade, substrato escuro, sensação de vazio e profundidade"
	# — o perfil mais distante da base, e de propósito: é 28% da área do mapa
	# lendo igual ao mar raso até aqui. O escuro vem da COR (névoa e fundo
	# quase pretos), não de apagar a luz: é o que deixa o vazio de props que o
	# bioma vai ter (densidade ×0,35 no orçamento) ler como escuridão, não
	# como cenário faltando.
	#
	# A primeira calibragem (murk 1,6, sol 0,75, ambiente 0,9) acertou o fundo
	# e apagou o corpo: na captura de 2026-09-17 o jogador quase sumia no
	# leito. Personagem e criatura têm de continuar legíveis em qualquer
	# bioma — é o que se clica. Sol e ambiente voltaram para perto da base,
	# que é o que ilumina corpo, e a murk subiu menos.
	"BIO-004": {
		"bg": Color("#020F18"),
		"ambient": Color("#6A767E"),
		"ambient_energy": 1.1,
		"fog": Color("#08192B"),
		"fog_density": 0.012,
		"fog_underwater": 1.25,
		"sun": Color("#A8CCE0"),
		"sun_energy": 1.05,
	},
	# "placas de gelo quebradas [...] aparência ecologicamente empobrecida" —
	# frio se comunica por névoa PÁLIDA e luz alta, não por escuro (esse é o
	# vocabulário do abismo, logo acima). A densidade-base sobe de 0,006 para
	# 0,010 porque o platô é terra firme: acima da linha d'água a névoa de
	# altura quase não acumula, e sem esse empurrão o frio não chegaria à
	# parte do bioma em que o jogador de fato anda.
	"BIO-014": {
		"bg": Color("#0E3A4A"),
		"ambient": Color("#AEBCC4"),
		"ambient_energy": 1.45,
		"fog": Color("#7FA8BE"),
		"fog_density": 0.010,
		"fog_underwater": 0.55,
		"sun": Color("#DCF2FF"),
		"sun_energy": 1.5,
	},
}

var _env: Environment
var _sun: DirectionalLight3D
var _biome_code := ""
## Os dois extremos da interpolação corrente e onde ela está. `_t >= 1.0`
## significa parada — e é o estado em que este nó passa a maior parte do
## tempo, porque travessia de fronteira é evento raro.
var _from := {}
var _to := {}
var _t := 1.0


## Monta o nó e o prende à árvore. `env` e `sun` são os que o `MapDressing`
## acabou de criar/achar; qualquer um pode ser `null` (cena sem `KeyLight`, por
## exemplo) e o nó continua válido — degrada para "não mexe no que não tem",
## mesma tolerância que `_apply_pz01_ambience` já pratica com a luz.
static func create(root: Node3D, env: Environment, sun: DirectionalLight3D) -> BiomeAmbience:
	var node := BiomeAmbience.new()
	node.name = "BiomeAmbience"
	node._env = env
	node._sun = sun
	root.add_child(node)
	return node


## O bioma em que o jogador está agora. Chamada por `WorldRoot._update_biome`,
## que já detecta a travessia — este nó não consulta posição nenhuma, pelo
## mesmo motivo que `MapDressing` não consulta: quem sabe onde o jogador está
## é o mundo, e um segundo lugar perguntando é um segundo lugar para
## discordar.
##
## `instant` é para a abertura: o primeiro bioma não tem de onde vir, e
## interpolá-lo a partir da base faria o mapa abrir com 2 s de correção de cor
## à toa (visível, por exemplo, ao nascer dentro do recife).
func set_biome(biome_code: String, instant := false) -> void:
	if biome_code == _biome_code:
		return
	_biome_code = biome_code
	_to = _profile(biome_code)
	if instant:
		_from = _to
		_t = 1.0
		_apply(_to)
	else:
		_from = _current_values()
		_t = 0.0


func _process(delta: float) -> void:
	if _t >= 1.0:
		return
	_t = minf(1.0, _t + delta / TRANSITION_SEC)
	# `smoothstep` em vez de linear: a rampa linear tem quina nos dois
	# extremos, e quina em mudança de LUZ lê como o corte que a interpolação
	# existe para evitar — só deslocado 2 s para frente.
	var k: float = smoothstep(0.0, 1.0, _t)
	var mixed := {}
	for key in _to:
		var a = _from.get(key, _to[key])
		var b = _to[key]
		mixed[key] = a.lerp(b, k) if a is Color else lerpf(a, b, k)
	_apply(mixed)


## Perfil completo de um bioma: `BASE` com os desvios de `PROFILES` por cima.
## Sempre completo — é o que permite ao `_process` interpolar chave a chave
## sem se perguntar se o bioma de origem declarava aquele campo.
func _profile(biome_code: String) -> Dictionary:
	var values := BASE.duplicate()
	var overrides: Dictionary = PROFILES.get(biome_code, {})
	for key in overrides:
		values[key] = overrides[key]
	return values


## O que está escrito no `Environment`/`KeyLight` NESTE instante — que pode ser
## um ponto no meio de uma interpolação anterior, não um perfil de bioma.
##
## Ler o estado real (em vez de guardar "o último perfil que eu pedi") é o que
## faz a travessia rápida de três biomas em sequência encadear sem saltar: a
## interpolação nova parte de onde a imagem está, não de onde ela teria
## chegado se ninguém a tivesse interrompido.
func _current_values() -> Dictionary:
	if _env == null:
		return _profile(_biome_code)
	return {
		"bg": _env.background_color,
		"ambient": _env.ambient_light_color,
		"ambient_energy": _env.ambient_light_energy,
		"fog": _env.fog_light_color,
		"fog_density": _env.fog_density,
		"fog_underwater": _env.fog_height_density,
		"sun": _sun.light_color if _sun else BASE["sun"],
		"sun_energy": _sun.light_energy if _sun else BASE["sun_energy"],
	}


func _apply(values: Dictionary) -> void:
	if _env:
		_env.background_color = values["bg"]
		_env.ambient_light_color = values["ambient"]
		_env.ambient_light_energy = values["ambient_energy"]
		_env.fog_light_color = values["fog"]
		_env.fog_density = values["fog_density"]
		_env.fog_height_density = values["fog_underwater"]
	if _sun:
		_sun.light_color = values["sun"]
		_sun.light_energy = values["sun_energy"]
