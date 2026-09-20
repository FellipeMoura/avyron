# Animações pendentes — briefing para a sessão que for autorar clipes novos no Godot

Esta rodada (2026-09-18) fechou a **decisão de dados e o encaixe de código**: qual golpe
toca qual clipe, e por quê. Não desenhou nenhuma animação nova — hoje toda criatura do
elenco (inclusive trilobita, cefalópode, artrópode...) está reaproveitando três gestos
de personagem HUMANO do pack Quaternius (golpe de espada, bloqueio de escudo, conjuração
de magia), retargetados pro esqueleto compartilhado da mestre. Este documento existe pra
quem for desenhar animação de verdade não ter que reconstruir esse mapa do zero.

Ponteiro rápido: `CLAUDE.md` → "Onde procurar"; `ROADMAP.md` → seção "Arte".

## 1. O vocabulário de clipe hoje

| Clipe | Quando toca | Lado | Fonte física atual (pack Quaternius, humano) |
|---|---|---|---|
| `Idle`/`Walk`/`Run` | escada de marcha por velocidade | quem se move | UAL1, nomes já genéricos |
| `Swim`/`Swim_Idle` | escada de marcha submersa | quem se move | UAL1, idem |
| `Sprint` | degrau de cima da escada seca (≥ `CreatureActor.SPRINT_THRESHOLD`) — hoje só a INVESTIDA do duelo chega lá (ida e volta do golpe `attack`/`attack2`, movida pela `BattleStaging`); submerso a investida é `Swim` | atacante | UAL1, nome já genérico |
| `Attack` | dano/miss de habilidade com `attackVariant: attack` | atacante | UAL1 `Punch_Cross` |
| `Attack2` | dano/miss de habilidade com `attackVariant: attack2` | atacante | UAL2 `Sword_Dash` (golpe de espada, corpo a corpo) |
| `Attack3` (não é 1 clipe — é sequência) | dano/miss com `attackVariant: attack3` | atacante | UAL1 `Cast_Enter`→`Cast`→`Cast_Exit` (conjuração, longo alcance) |
| `HitReact` | dano recebido | alvo | UAL1 `Hit_Chest` |
| `Dodge` | `miss` (quem escaparia) ou `capture_failed` (selvagem que escapou) | alvo | UAL2 `Shield_Dash` (esquiva com escudo) |
| `Death` | `faint` | quem desmaiou | UAL1 `Death01` |

`attackVariant` é o campo do bestiário (`ability_stats.attack_variant`) que decide entre
`Attack`/`Attack2`/`Attack3` — nunca sorteio, nunca hardcode por categoria. Distribuição
atual no elenco (31 habilidades): **15 elementais → `attack2`**, **5 do Despertar →
`attack3`**, os outros 11 (5 básicos de classe + 2 buffs + 2 debuffs + cura + carga) →
`attack` (default; buff/debuff/cura/carga nunca tocam clipe de corpo, só VFX).

## 2. A cadeia completa, ponta a ponta

```
ability_stats.attack_variant (Postgres, avyron-bestiary)
  └─ packages/db/src/schema/enums.ts:21-26        (o comentário mais completo sobre o PORQUÊ)
  └─ AbilityStatsTypes.ts:20-22                    (schema Zod da API)
  └─ export-game-data.mjs:725                      (campo `attackVariant` no bundle)
  └─ avyron/data/bestiary.json                     (bundle espelhado)
  └─ encounter_director.gd:485-492  _attack_clip_for(ability) -> "Attack"/"Attack2"/"Attack3"
  └─ encounter_director.gd:392-442  _animate_one_event()      -> decide o QUANDO (damage/miss/capture_failed/faint)
       ├─ "Attack3" -> _play_attack3_sequence() (500-508): Cast_Enter -> [espera] -> Cast + feixe de energia na cor do elemento (ElementPalette.play_battle_beam) -> [abertura do feixe] -> HitReact se acertou -> [espera] -> Cast_Exit
       └─ senão      -> _charge_out() [BattleStaging corre o atacante até o contato, clipe `Sprint`/`Swim` pela escada] -> efeito de dano (attack: corte neutro; attack2: corte + estouro de impacto na cor do elemento)
                       -> _play_body_clip(lado, variant) (472-477) + HitReact/Dodge no lado oposto -> [espera] -> _charge_back() (volta ao posto)
  └─ CreatureActor.play_battle_clip() (creature_actor.gd:715-716) ou CompanionActor.play_battle_clip() (companion_actor.gd:494-498)
       -> AnimationPlayer.play(clip, 0.2)  (só troca se `has_animation(clip)` e nome diferente do atual)
```

`Battle`/`Combatant`/`BattleAction` (`avyron/scripts/battle/*.gd`) são **RefCounted puro,
zero referência a clipe** — o que expõem é só `Combatant.ability_by_code()`
(`combatant.gd:149-153`) e o evento de log (`Battle._log`, `battle.gd:499-507`, com
`type`/`is_player`/`ability`). Todo o despacho pra animação mora em
`EncounterDirector`. Nada aqui precisa mudar pra sessão de animação nova.

## 3. Onde o clipe físico REALMENTE mora (e a lacuna real)

O único lugar do jogo que carrega arquivo de animação é
`character_rig.gd._build_library` (213-260), que funde `UAL1.glb` + `UAL2.glb`
(`ANIM_LIBRARIES`, linha 83, de `res://models/characters/animations/`) numa biblioteca
única — **compartilhada por humanos E criaturas** (`CreatureActor._build_retargeted_animation`,
`creature_actor.gd:357-383`, chama o mesmo `_build_library`). Não existe biblioteca por
criatura; toda criatura ganha os MESMOS 73 clipes (35 de UAL1 + 38 de UAL2, número travado
em `test_characters.gd:359-362`) por retarget no esqueleto de 55 ossos da mestre.

Do lado do bestiário, `convert-characters.mjs` é quem decide, por nome, qual clipe de
ORIGEM (do pack Quaternius) vira qual nome CANÔNICO — `CLIP_MAP_UAL1` (99-129),
`CLIP_MAP_UAL2` (131-145). É exatamente esse dicionário que trocamos nesta sessão
(`Punch_Jab`→`Sword_Dash` como fonte de `Attack2`, `Melee_Hook` saiu do mapa,
`Shield_Dash`→`Dodge` entrou). **Vasculhei o arquivo inteiro: não há nenhum comentário
ou TODO sobre substituir essas animações humanas por algo mais apropriado a criatura —
o vocabulário atual não é marcado como provisório em lugar nenhum do código.**

A lacuna real: `../mestre/README.md` (o pipeline "base + casca" que gera a MALHA de cada
espécie) documenta bem o contrato de malha/esqueleto (55 ossos, nomes da UAL, `pelvis`,
manequim de 0,93 m em T-pose, "sem clipe no arquivo" — regras em `mestre/README.md:42-47`)
mas **não tem nenhum passo sobre autoria de animação**. Isso é estrutural: o pipeline
inteiro foi desenhado para a criatura chegar SEM clipe e ganhar a biblioteca UAL de
graça, em runtime. Não existe hoje uma ferramenta ou processo pra animar uma casca
isoladamente.

## 4. A decisão aberta pra próxima sessão

Duas rotas, com custo bem diferente:

**(a) Clipe novo, mas ainda compartilhado por todo o elenco.** Troca-se o gesto físico
de `Attack2`/`Attack3`/`Dodge` (reanima-se no esqueleto da mestre, chibi, T-pose,
sem root motion) e aponta-se `convert-characters.mjs` pra essa fonte nova em vez do
Quaternius humano — ou adiciona-se um `UAL3.glb` novo em `ANIM_LIBRARIES`
(`character_rig.gd:83`). Zero mudança de arquitetura: o jogo já é 100% nome-driven,
nunca olha QUEM fez o clipe. É a rota barata, mas todo o elenco (trilobita, lula,
artrópode, molusco...) continua fazendo o MESMO gesto — só deixa de ser
reconhecivelmente "humano brandindo espada".

**(b) Clipe por criatura (ou por família de corpo).** Exige pipeline novo — o fluxo
"base + casca" hoje proíbe isso de propósito (regra "sem clipe no arquivo"). Seria
reabrir algo como o antigo `transfer-clips.mjs` (apagado junto com o pipeline Meshy,
ver `avyron-bestiary/CLAUDE.md:202-203`), mas pra clipe autoral em vez de retarget
1:1. Rota cara, mas resolve de verdade "por que um trilobita empunha espada".

Este documento não escolhe — é decisão de produto. Mas se a escolha for (a), o
trabalho é 100% do lado do bestiário (`convert-characters.mjs` + a animação em si);
nenhuma linha de GDScript muda.

## 5. Testes que travam o vocabulário (atualizar se o NOME de um clipe mudar)

| Arquivo | O que trava |
|---|---|
| `scripts/dev/test_creature_bodies.gd:33-36,43-46` | `EXPECTED_CLIPS`/`DRIFT_CHECKED_CLIPS` — todo corpo definitivo do PZ-01 |
| `scripts/dev/test_dungeon_bodies.gd:26-29` | idem, pro placeholder único (Imp) — **nota: esta lista não tem `Swim_Idle`, diferente das outras duas; ver seção 6** |
| `scripts/dev/test_tripo_shell.gd:26-29` | idem, pra sonda de um `.glb` qualquer (`--shell`) |
| `scripts/dev/test_characters.gd:156,347-376` | contrato do corpo humano; `73` clipes fundidos é literal aqui |
| `scripts/dev/test_battle_effects.gd:172-334` | `_attack_clip_for`/`_play_body_clip`/`_play_attack3_sequence`/Dodge/capture_failed — a suíte que prende `EncounterDirector` |

Só o NOME importa pros testes (`has_animation("Attack2")`, etc.) — trocar o GESTO por
trás do nome (rota "a" da seção 4) não quebra nenhum deles. Trocar o NOME quebraria
todos de uma vez; foi o que aconteceu quando `Attack3` deixou de ser clipe único nesta
sessão, e os cinco foram atualizados juntos.

## 6. Inconsistência encontrada (não fui atrás de causa, só registrando)

`test_dungeon_bodies.gd:26-29` não lista `Swim_Idle` em `EXPECTED_CLIPS`, mas
`test_creature_bodies.gd` e `test_tripo_shell.gd` (que testam o MESMO retarget) listam.
Como o Imp (`Bestiary - Dungeon Monsters` kit) usa a mesma biblioteca fundida (os 73
clipes chegam de qualquer forma), a omissão provavelmente é só o teste do Imp ter
nascido antes da escada de nado existir — não parece intencional, mas não confirmei.

## 7. Ferramentas pra visualizar/testar animação (já existem, prontas pra usar)

- **`scripts/dev/shot_shell.gd`** — roda COM janela (não headless), coloca dois corpos
  lado a lado na câmera isométrica do próprio jogo, toca um clipe (`--clip`, default
  `Idle`) e salva PNG. Exemplo (`mestre/README.md:30`):
  `godot --script res://scripts/dev/shot_shell.gd -- --a /models/dev/manequim-mestre.glb --b /models/CRT-XXX.glb --clip Walk --out screenshot.png`.
  Aceita `--face` (giro) e `--size`.
- **`scripts/dev/test_tripo_shell.gd -- --shell <modelUrl>`** — headless, reporta
  esqueleto/ossos/clipes disponíveis/altura em jogo pra qualquer `.glb`. Rápido pra
  confirmar que um corpo (ou uma UAL nova) está correto antes de gastar tempo com
  screenshot.

## 8. Onde a decisão "qual habilidade usa qual variante" é tomada

`apps/web/src/routes/Abilities.tsx` (bestiário) — página criada nesta sessão
especificamente pra isso: lista toda habilidade com a variante atual e as criaturas
que a usam, com filtro por papel (básico/elemental/buff/despertar). Qualquer habilidade
NOVA que entrar no catálogo precisa de uma decisão consciente de `attackVariant` ali —
hoje o default silencioso é `attack`.

## 9. Documentação que ficou defasada (fora do escopo desta rodada, registrando)

- `avyron/ROADMAP.md`, seção "Arte" (~linha 200-210): ainda descreve o pipeline Meshy
  como o caminho corrente ("Meshy exporta um `.glb` único... `convert-meshy.mjs`
  normaliza...") e diz que "~59 membros do elenco" esperam "export do Meshy" — isso
  precede a migração pro pipeline Tripo/mestre (base + casca, 2026-09-15/17) e o
  fechamento do elenco do PZ-01 em 14. Precisa de uma passada de atualização, fora do
  escopo deste documento.
- `avyron-bestiary/CLAUDE.md`: não menciona `attackVariant` nem o esquema de 4 golpes
  do PZ-01 (2 básicos + 1 buff + 1 despertar) em lugar nenhum — essa regra só existe
  hoje como guarda de código em `export-game-data.mjs:843-871`.
