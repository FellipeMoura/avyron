extends SceneTree

## Ferramenta de conversão — não é suíte de teste (não faz parte do `--script
## res://scripts/dev/test_*.gd` de ninguém), fica no repo pela mesma razão
## dos `convert-*.mjs` do bestiário: reproduzir a saída sem depender de
## lembrar o passo a passo.
##
## Ponte entre o "Easy Animated Pack" (Quaternius, CC0 — só .fbx/.obj/.blend,
## sem glTF pronto) e `convert-placeholders.mjs`, que só sabe ler .gltf/.glb
## via gltf-transform (nenhuma lib Node do bestiário lê .fbx). Só o Godot lê
## o .fbx aqui: renomeia os clipes pro vocabulário canônico do jogo e
## reexporta como .glb normal, que dali em diante é só mais um arquivo pro
## pipeline de sempre.
##
##     godot --headless --script res://scripts/dev/convert_easy_pack.gd
##
## Fonte: `res://models/_convert_easy/` — cópia solta dos `.fbx` do pack
## (`new-assets/Easy Animated Pack - Jan 2019/FBX/`), criada à mão antes de
## rodar e apagada depois (o `.fbx` não é asset de jogo, só material de
## conversão). Saída: `../../avyron-bestiary/placeholder_models/EasyAnimated/
## glTF/` — o MESMO layout `<Group>/glTF/*.{gltf,glb}` que
## `convert-placeholders.mjs` já escaneia. `CLIP_MAP` é específico deste
## pack; um pack novo copia a forma, não reusa a tabela.

const SRC_DIR := "res://models/_convert_easy/"
const OUT_DIR := "C:/Users/Fellipe/code/games/avyron-bestiary/placeholder_models/EasyAnimated/glTF/"

## Nome de origem (formato "XxxArmature|Xxx_Clipe" do importador de FBX) →
## vocabulário canônico do jogo. `Wasp_Flying` vira `Idle` pelo mesmo motivo
## de `Flying_Idle` em `convert-placeholders.mjs`: é a pose de loop do
## voador, mesmo sem ele ter um "Idle" parado de verdade.
const CLIP_MAP := {
	"Frog_Attack": "Attack", "Frog_Death": "Death", "Frog_Idle": "Idle", "Frog_Jump": "Jump",
	"Spider_Attack": "Attack", "Spider_Death": "Death", "Spider_Idle": "Idle",
	"Spider_Jump": "Jump", "Spider_Walk": "Walk",
	"Rat_Attack": "Attack", "Rat_Death": "Death", "Rat_Idle": "Idle",
	"Rat_Jump": "Jump", "Rat_Run": "Run", "Rat_Walk": "Walk",
	"Snake_Attack": "Attack", "Snake_Idle": "Idle", "Snake_Jump": "Jump", "Snake_Walk": "Walk",
	"Wasp_Attack": "Attack", "Wasp_Death": "Death", "Wasp_Flying": "Idle",
}

var _converted := 0
var _failed := 0


func _initialize() -> void:
	var dir := DirAccess.open(SRC_DIR)
	if dir == null:
		printerr("FALHA: nao achei ", SRC_DIR)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.get_extension().to_lower() == "fbx":
			_convert(file.get_basename())
		file = dir.get_next()
	dir.list_dir_end()

	print("\ndone: %d convertidos, %d falharam" % [_converted, _failed])
	quit(1 if _failed > 0 else 0)


func _convert(base_name: String) -> void:
	print("== ", base_name, " ==")
	var packed := load(SRC_DIR + base_name + ".fbx") as PackedScene
	if packed == null:
		printerr("  FALHA ao carregar")
		_failed += 1
		return
	var instance := packed.instantiate()

	var anim := _find_animation_player(instance)
	if anim == null:
		printerr("  FALHA: sem AnimationPlayer")
		instance.free()
		_failed += 1
		return

	_rename_clips(anim, base_name)

	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := gltf_doc.append_from_scene(instance, gltf_state)
	if err != OK:
		printerr("  FALHA append_from_scene: ", err)
		instance.free()
		_failed += 1
		return

	var out_path := OUT_DIR + base_name + ".glb"
	err = gltf_doc.write_to_filesystem(gltf_state, out_path)
	instance.free()
	if err != OK:
		printerr("  FALHA write_to_filesystem: ", err)
		_failed += 1
		return

	print("  OK -> ", out_path)
	_converted += 1


## Renomeia dentro da MESMA `AnimationLibrary` (não pode criar uma segunda com
## o mesmo nome de chave) — remove a entrada velha e adiciona a nova com o
## mesmo recurso `Animation`, então a trilha (que aponta pro esqueleto por
## caminho relativo, não por nome de clipe) não precisa de nenhum ajuste.
func _rename_clips(anim: AnimationPlayer, base_name: String) -> void:
	var lib := anim.get_animation_library("")
	if lib == null:
		printerr("  AVISO: sem AnimationLibrary padrao")
		return
	for full_name in anim.get_animation_list():
		var source := String(full_name).get_slice("|", 1) if String(full_name).contains("|") else String(full_name)
		var canonical: Variant = CLIP_MAP.get(source)
		if canonical == null:
			print("  [sem mapa, mantido: ", full_name, "]")
			continue
		var resource := lib.get_animation(full_name)
		lib.remove_animation(full_name)
		lib.add_animation(StringName(canonical), resource)
		print("  %s -> %s" % [full_name, canonical])


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
