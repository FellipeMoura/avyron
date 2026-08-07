# Avyron

Jogo 3D de coleção de criaturas com tema paleontológico, em Godot.

Câmera isométrica ortográfica **travada em 30° de inclinação e 45° de azimute**. Exploração em tempo real, **combate por turnos** (1v1 com troca livre, disputado no mesmo espaço do mapa, sem corte para arena).

## Onde vive o design

Este repositório é o **jogo**. O catálogo de criaturas, a bíblia de design e todos os números de balanceamento vivem em outro lugar:

- **App:** https://bestiary.sysnode.com.br
- **Repo:** https://github.com/FellipeMoura/game

Essa separação é deliberada. Lá o conteúdo é versionado com changelog a cada mudança e escrito por agentes via API; aqui é código e asset.

## `data/bestiary.json` — gerado, não editar à mão

O bundle é produzido pelo repo do bestiário:

```powershell
cd ..\game
pnpm game:export --from https://bestiary.sysnode.com.br --out ..\avyron
```

Ele carrega um `dataVersion` tirado do changelog, então todo build é rastreável até o estado exato do catálogo de onde saiu. Tudo é endereçado por código (`CRT-001`, `ELE-002`, `HAB-014`) — nenhum id numérico atravessa a fronteira, o que mantém o arquivo diffável em pull request e imune a uma reconstrução do banco.

**Editar este arquivo à mão é o erro que o pipeline inteiro existe para evitar.** A próxima exportação sobrescreve. Se um número está errado, corrija no bestiário via API e re-exporte.

O export **aborta sem escrever nada** se alguma criatura estiver sem stats, sem regra de captura ou sem golpes.

## Vocabulário

| Termo | Significa |
|---|---|
| **Loricati** | artrópodes |
| **Theria** | sinapsídeos |
| **Draconis** | sauropsídeos |
| **Aetheris** | era paleozoica |
| **Titanor** | era mesozoica |
| **Novaterra** | era cenozoica |
| **Despertar Ancestral** | transformação temporária em combate |

"Despertar Ancestral" é o único termo válido para a transformação — o bestiário rejeita escritas que usem os termos descontinuados.

## Regras de combate que o código precisa respeitar

```
valor(nível) = floor(base * (1 + growthRate * (nível - 1)))

dano = floor((poder * ataque / defesa) * 0.4 * multElemental * random(0.90, 1.10))
       mínimo 1

carga: recebe dano ×1.0, causa dano ×0.5, escalado por (carga / 50)
       cheia em 100, dura 3 turnos, zera na reversão
```

Ciclo elemental fechado — cada elemento vence exatamente um e perde para exatamente um:

```
Água → Fogo → Natureza → Terra → Gelo → Eletricidade → Água
```

Vantagem 2.0, desvantagem 0.5, todo o resto 1.0 por omissão. As constantes acima também vêm no bundle, em `rules`.

Especificação legível: documentos `combate`, `carga-e-despertar` e `captura` no bestiário.

## Godot

**4.7.x**, build padrão (GDScript, não .NET), renderizador **Forward+**.

A versão está fixada em `project.godot` via `config/features`. Não trocar sem combinar — dois devs em builds diferentes geram diffs fantasma.

### Instalar

Windows 64, build padrão (não .NET):

- **Download direto (4.7.1):** https://downloads.godotengine.org/?version=4.7.1&flavor=stable&slug=win64.exe.zip&platform=windows.64
- **Página oficial** (release notes + hashes): https://godotengine.org/download/windows/

O zip contém dois executáveis — descompacte os dois em `%LOCALAPPDATA%\Programs\Godot\`:

| Executável | Para quê |
|---|---|
| `Godot_v4.7.1-stable_win64.exe` | abrir o editor e dar play |
| `Godot_v4.7.1-stable_win64_console.exe` | rodar os testes `--headless` do bloco abaixo |

Sem instalador — é só extrair. O path `%LOCALAPPDATA%\Programs\Godot\Godot_v4.7.1-stable_win64_console.exe` é o que os comandos de teste esperam no `$godot`.

### Rodar

Na primeira vez você precisa importar o projeto — depois é só abrir do Project Manager.

1. **Abrir o editor.** Duplo clique em `Godot_v4.7.1-stable_win64.exe` (o de cima da tabela acima, sem `_console`). Abre o Project Manager com uma lista de projetos.
2. **Importar este repo.** Botão `Import` → aponte para `c:\code\avyron\project.godot` → `Import & Edit`. Da segunda vez em diante ele já aparece na lista; duplo clique abre.
3. **Play.** `F5` (ou o botão ▶ no canto superior direito) roda a cena principal definida em `project.godot`, que é o mapa. Para rodar o duelo direto, abra `scenes/duel.tscn` na aba de cenas e aperte `F6` (roda **só** a cena atual).

Se pedir para escolher a Main Scene na primeira execução, aponte para `scenes/main.tscn` — está fixado no `project.godot`, mas versões novas do Godot às vezes perguntam mesmo assim.

**Mapa** (`scenes/main.tscn`) — WASD anda, shift corre, **F minera**, câmera isométrica travada seguindo com lookahead. A **criatura ativa** do jogador (starter, `CRT-002` por padrão) anda ao lado, atrás e um pouco à direita, com bob leve — puramente visual, sem colisão nem clique.

Oito criaturas selvagens nascem espalhadas, lidas do bundle: cápsulas escaladas pelo tamanho de jogo e coloridas pelo elemento. Elas patrulham, notam você a 6 m e param para encarar; as agressivas perseguem. **O combate é disparado por clique**: o primeiro clique numa criatura seleciona e abre um painel de identificação (nome, classe, elemento, tamanho); o segundo clique na mesma começa a batalha ali mesmo — a câmera aproxima 12,5% e **inclina para -18°** (era -30°) num único movimento, e o overlay do duelo revela por fade sobre o mundo congelado. Sem corte de cena. Clique fora ou aperte `Esc` para desmarcar; afastar-se demais também desseleciona.

Contato físico não faz mais nada: agressivas continuam perseguindo por pressão, mas quem aperta o gatilho é sempre o jogador.

**Ciclo de vida no mapa** — vencer o combate remove o adversário do mapa e joga um slot de respawn na fila do `CreatureSpawner`. Depois de 20–40s, o slot vira uma criatura nova (espécie e posição sorteadas do pool do bioma). Fuga e derrota do jogador liberam a criatura de origem para ser reengajada. **Captura** remove o adversário sem respawn e o armazena no card do jogador (1 slot por enquanto); o painel de time no canto superior direito atualiza em tempo real.

**Mineração** — pressionar `F` em qualquer ponto do mapa coleta um minério sorteado por peso da tabela do bioma atual (cooldown de 3 s). O painel de inventário fica no canto superior esquerdo e lista os materiais acumulados. Ambos os painéis somem durante o combate e voltam ao fechar.

A tabela de minérios vive em `scripts/data/ore_table.gd` e é hardcoded enquanto o bundle não exporta itens; quando exportar, só essa classe muda. Pool atual do PZ-01:

| Código | Nome | Frequência |
|---|---|---|
| `ORE-001` | Calcário | 35 % |
| `ORE-002` | Sílex | 25 % |
| `ORE-003` | Carvão | 20 % |
| `ORE-004` | Cobre | 12 % |
| `ORE-005` | Ferro | 8 % |

**Duelo** (`scenes/duel.tscn`, também abrível sozinho com `F6`) — sorteia duas criaturas nível 25 e deixa você lutar:

| Tecla | |
|---|---|
| `1`–`6` | usar golpe |
| `E` | Despertar Ancestral (quando a carga enche) |
| `C` / `F` | capturar / fugir |
| `R` | novo duelo |
| `Esc` | voltar ao mapa |

É instrumento de playtest, não a UI do jogo: texto puro, porque o que precisa ser avaliado é o *ritmo* — se cinco rodadas dão espaço tático, se o Despertar chega na hora certa, se a vantagem elemental é sentida.

### Testes

Duas suítes headless, sem dependência de editor:

```powershell
$godot = "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.7.1-stable_win64_console.exe"

& $godot --headless --script res://scripts/dev/test_data.gd     # contrato de dados + fórmulas
& $godot --headless --script res://scripts/dev/test_world.gd    # input, câmera, cena
& $godot --headless --script res://scripts/dev/test_battle.gd   # máquina de turnos
& $godot --headless --script res://scripts/dev/test_playable.gd # a cena rodando de verdade
& $godot --headless --script res://scripts/dev/test_duel_screen.gd  # duelo jogado por tecla
& $godot --headless --script res://scripts/dev/test_encounter.gd    # spawn, encontro, captura, overlay
& $godot --headless --script res://scripts/dev/test_mining.gd       # OreTable, inventário, cooldown
```

`test_playable.gd` é o único que sobe a árvore de cena com física ativa e injeta input. Responde "dá para jogar?" em vez de "as contas fecham?" — e foi ele que pegou o corpo andando de costas, que nenhum teste de lógica isolada veria.

`test_data.gd` é o guarda do contrato com o bestiário: se o formato do bundle mudar, se uma fórmula sair do lugar ou se o export deixar passar uma criatura sem stats, estoura ali em vez de virar bug de runtime. Rode depois de todo `game:export`.

`test_encounter.gd` cobre o loop completo de encontro — spawn → clique → batalha → vitória (remoção + respawn) → captura (remoção sem respawn + card do jogador).

`test_mining.gd` cobre a `OreTable` (distribuição, mapa inexistente, nome por código), o `PlayerInventory` (add, quantity, entries ordenado) e o fluxo no `WorldRoot` (minera, cooldown bloqueia segunda chamada, zerar cooldown libera terceira, painel existe na HUD).

`scripts/dev/setup_project.gd` gerou o input map e a cena inicial. É andaime de bootstrap — daqui em diante a edição normal é pelo editor.

### Sonda de balanceamento

```powershell
& $godot --headless --script res://scripts/dev/balance_probe.gd
& $godot --headless --script res://scripts/dev/balance_probe.gd -- 0.22 3 3.0
```

Simula o elenco inteiro lutando contra si mesmo (2.600 batalhas) e reporta taxa de vitória por criatura, duração média e quanto o Despertar Ancestral realmente vira o jogo. Não falha nem afirma nada — é leitura, para tuning sair de números em vez de impressão.

Os três argumentos opcionais sobrescrevem, nesta ordem: constante de dano, duração do Despertar, escala de enchimento da carga. Servem para medir o efeito de uma mudança **antes** de gravá-la no bestiário.

## Assets 3D

Os modelos servidos pelo app web estão comprimidos com **Draco**, que é otimização de entrega para browser. **Para o jogo, importe o `.glb` mestre sem compressão** — o Godot recomprime no formato dele na importação, e o Draco só adiciona um passo de decodificação e um ponto de falha.

Orçamento por asset, conforme `direcao-3d-arte`:

| Papel | Triângulos | Textura |
|---|---|---|
| Chefe/hero | 5k–8k | 1024² |
| Regular | 2k–4k | 512² |
| Enxame | 500–1.5k | 256² |

Oito loops de animação obrigatórios por criatura a 24 fps: `idle`, `walk`, `run`, `attack_primary`, `attack_secondary`, `hurt`, `death`, `victory`.

Criaturas Loricati usam **rig flutuante** — sem rig locomotor por perna, deslizamento com bob vertical de ~5 cm. Cobre ~60% do elenco atual.

Modelos-fonte ainda não estão versionados aqui: 8–27 MB cada bloqueiam o histórico para sempre. Configurar `git-lfs` antes de commitar o primeiro.

## Convenção de escala

**1 metro real = 1 unidade Godot.** Escala real, sem exagero dramático — um trilobita de 15 cm aparece pequeno e um Arthropleura de 2,5 m aparece grande.
