# CLAUDE.md — briefing para sessões do Claude Code

Contexto para trabalhar neste repositório. Complementa o `README.md`, que descreve o que existe e como rodar; aqui está como trabalhar e o que não fazer.

## O que é isto

O **jogo**, em Godot 4.7.x (GDScript, Forward+). Câmera isométrica ortográfica travada em 30°/45°, exploração em tempo real, combate por turnos 1v1 com troca livre disputado no mesmo espaço do mapa.

O **catálogo** — criaturas, habilidades, itens, números de balanceamento — vive no repositório irmão em `../game`, e chega aqui como `data/bestiary.json` via `pnpm game:export`. Este repo é código e asset; aquele é conteúdo.

O bestiário **roda local** desde a versão 0.104. O deploy em produção foi aposentado — ele existia para um Claude web alimentar o catálogo por HTTP, e quem escreve hoje roda na mesma máquina.

## Regras invioláveis

1. **Nenhum número de tuning mora em código.** Dano, carga, captura, preço, taxa de minério, bolsa inicial, margem do comerciante — tudo vem do bundle, que vem do banco. Se você está prestes a escrever uma constante que um designer poderia querer ajustar, ela pertence ao bestiário. As exceções legítimas são constantes de *apresentação* (velocidade de giro da câmera, amplitude de bob) e de *engenharia* (tamanho de chunk, epsilon).

2. **`data/bestiary.json` é gerado. Nunca edite à mão.** A próxima exportação sobrescreve. Número errado se corrige no bestiário e re-exporta.

3. **Depois de criar qualquer `class_name`, rode `--headless --import`.** O cache de classes globais do Godot só é atualizado na importação, e sem isso o parser não conhece a classe nova — o erro é `Identifier "X" not declared in the current scope`, que parece erro de digitação e não é.

4. **A frente de um nó é `-Z`.** Para encarar uma direção: `atan2(-dir.x, -dir.z)`. Usar `atan2(x, z)` alinha `+Z` e o corpo anda de costas — já aconteceu, e foi o teste de cena jogável que pegou.

5. **Encarar e afastar são medidas no plano.** Os corpos apoiam o Y em regras diferentes — `CreatureActor` sobe meia cápsula, `CompanionActor` fica em `GROUND_Y` com o mesh deslocado — então qualquer produto escalar ou distância entre dois deles mede o desnível junto se não achatar antes. O sintoma é um valor quase certo (`dot 0.913` em vez de `1.0`), que lê como imprecisão de giro e é geometria de outra dimensão.

## Como o código se divide

```
scripts/data/     bundle e fórmulas puras (BestiaryData, CombatMath, MiningTable, ItemEffects)
scripts/battle/   máquina de turnos (Battle, Combatant, BattleAction) — sem nós, sem sinais
scripts/world/    mapa, atores, jogador, time, inventário
scripts/ui/       telas e painéis
scripts/dev/      suítes headless e sondas
```

A separação que importa: **`data/` indexa e calcula, não decide.** `BestiaryData` só busca no bundle; `CombatMath`, `MiningTable` e `ItemEffects` só aplicam fórmula. Quem decide é `battle/` e `world/`. Quando surgir um sistema novo com números, ele segue esse par — um índice em `BestiaryData`, uma classe de fórmula ao lado de `CombatMath`. `ItemEffects` é o exemplo mais recente disso.

Cuidado com `effectValue`: é uma coluna só servindo códigos de efeito que a interpretam de formas diferentes — `heal_percent` guarda pontos percentuais (30, 70, 100), `capture_bonus` guarda multiplicador cru (1.5, 2.5, 4.0). Ler o campo sem olhar o `effectCode` ao lado dá um número plausível e errado.

`Battle` é `RefCounted` puro de propósito: sem nós, sem sinais, sem árvore de cena. É o que torna 2.600 batalhas simuláveis em segundos na sonda de balanceamento e o que deixa a apresentação livre para consumir os eventos no ritmo que quiser.

## Testes

Doze suítes headless, todas em `scripts/dev/`. Rodam sem editor. O padrão:

```gdscript
extends SceneTree
func _initialize() -> void:   # monta a cena
func _process(_d) -> bool:    # roda os testes num quadro, devolve true para sair
```

**Rodar os testes no `_initialize` não funciona** para nada que dependa da árvore: um nó adicionado à raiz antes de a árvore estar viva não conta como dentro dela, e `global_position` devolve transform vazio — toda medição vira zero.

**`queue_free()` é diferido.** Teste que remove um nó e confere a remoção no mesmo quadro falha por artefato, não por bug. Confira o estado síncrono (a referência que caiu) ou use `free()` em bancadas que você controla.

**Bancada com `_process` manual precisa de `set_process(false)`.** Senão o motor também chama, e cada passo conta dobrado.

Screenshot de verificação: crie um `scripts/dev/shot_*.gd` descartável, rode com `--resolution 1600x900`, salve em `user://`, **apague o andaime depois**. Teste headless não vê layout.

## Convenções

- **Português** em tudo que o jogador lê e em todo comentário de código. Identificadores em inglês, seguindo o Godot.
- **Escala real: 1 metro = 1 unidade.** Um trilobita de 15 cm é pequeno, um Arthropleura de 2,5 m é grande. Sem exagero dramático.
- **Cápsulas são placeholder**, e o que já é definitivo é tudo o mais — escala, máquina de estados, raio de detecção. Trocar por `.glb` não mexe em lógica.
- **Terminologia travada:** "Despertar Ancestral" é o único termo. *Evolução* e *Forma Ancestral* estão descontinuados e a API do bestiário rejeita com 422.
- Comentário explica **por quê**, não o quê. Os comentários deste repo carregam o histórico das decisões — quando mudar uma, atualize o comentário junto ou ele vira mentira.

## Coisas para NÃO fazer

- Não escrever constante de balanceamento em código (regra 1).
- Não editar `data/bestiary.json` (regra 2).
- Não commitar `.glb`, `.png` ou áudio sem LFS — o `.gitattributes` já cobre, mas confira `git lfs status` se um binário aparecer no diff. Blob commitado direto fica no histórico para sempre.
- Não adicionar tabela ao bestiário sem incluí-la em `packages/db/src/tables.ts` lá — o dump sai sem ela em silêncio.
- Não comparar versão (`0.NN`) como texto: `'0.99' > '0.104'` em ordenação lexicográfica.
- Não deixar andaime de screenshot commitado.

## Onde procurar

- **README.md** — o que existe, como rodar, e o raciocínio de cada sistema
- **ROADMAP.md** — o que está pendente e em que ordem
- **`scripts/data/bestiary_data.gd`** — o contrato com o bundle
- **`scripts/battle/battle.gd`** — a máquina de turnos, e o comentário sobre `replace_active` vs `_do_switch`
- **`scripts/dev/test_data.gd`** — o guarda do contrato; rode depois de todo `game:export`
- **`../game/CLAUDE.md`** — o briefing do bestiário
- **`../game/docs/DATA_WORKFLOW.md`** — como inserir e corrigir dados
