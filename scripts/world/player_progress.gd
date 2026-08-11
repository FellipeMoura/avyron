class_name PlayerProgress
extends Node

## Conquistas permanentes do jogador, persistidas em disco.
##
## Registrado como autoload `Progress`, junto de `Bestiary` — nome diferente
## do `class_name` de propósito, mesmo truque de `BestiaryData`/`Bestiary`:
## um script não pode nomear a própria classe igual ao autoload dela ("hides
## an autoload singleton").
##
## Hoje só guarda Glifos (documento `glifos-e-portais`) — o resto do estado
## do jogador (time, bolsa, relicário) ainda vive só em memória, então não há
## nada mais para agrupar aqui ainda. O formato (`ConfigFile`, uma seção por
## categoria de progresso) é o que permite crescer sem reescrever isto
## quando esse save maior existir: uma seção nova, não um arquivo novo.

const SAVE_PATH := "user://progress.cfg"
const SECTION := "progress"
const KEY_GLYPHS := "glyphs"

var _glyphs: Array = []
var _cfg := ConfigFile.new()
var _save_path := SAVE_PATH


func _ready() -> void:
	_load()


## Só para `test_glyphs.gd`: isola os testes do save real do jogador. Nunca
## chamado em jogo — o autoload usa `SAVE_PATH` sempre.
func use_path_for_test(path: String) -> void:
	_save_path = path


func has_glyph(code: String) -> bool:
	return _glyphs.has(code)


## Concede o Glifo e grava em disco na hora — não há "salvar jogo" separado
## ainda, e um Glifo perdido por não ter salvo seria pior que gravar cedo
## demais. Devolve `true` só quando concedido agora, `false` quando o
## jogador já tinha — é o que deixa quem chama decidir se anuncia ou fica
## quieto (refazer a arena não deve reanunciar nem duplicar nada).
func grant_glyph(code: String) -> bool:
	if code == "" or has_glyph(code):
		return false
	_glyphs.append(code)
	_save()
	return true


func glyphs() -> Array:
	return _glyphs.duplicate()


func _load() -> void:
	if _cfg.load(_save_path) != OK:
		return  # sem save ainda — estado normal na primeira execução
	var raw: Variant = _cfg.get_value(SECTION, KEY_GLYPHS, [])
	if raw is Array:
		_glyphs = raw


func _save() -> void:
	_cfg.set_value(SECTION, KEY_GLYPHS, _glyphs)
	var err := _cfg.save(_save_path)
	if err != OK:
		push_error("PlayerProgress: falha ao gravar %s (erro %d)" % [_save_path, err])
