# BIO-002 — Costa Primordial: pré-requisitos de implementação

> **Correção de nomenclatura (2026-08-31):** este documento e a imagem abaixo
> nasceram rotulados "BIO-001". Conferido contra o catálogo do
> `avyron-bestiary`: **BIO-001 é "Mar raso"** (o bioma-fallback, sem forma
> própria) e **BIO-002 é "Costa Primordial"** — o bioma que esta referência e
> os 9 assets Meshy de 2026-08-30 (pasta `models/biomes/assets_BIO-001/` no
> `avyron`) de fato descrevem. O nome do arquivo, da imagem e da pasta de
> assets ficou desalinhado do código do catálogo; corrigido aqui, pendente na
> pasta (ver seção 5).

Referência visual alvo (adicionada em 2026-08-31):

![Referência alvo — arquipélago de basalto](refs/bio-002-target.png)

Visão geral do mapa PZ-01 inteiro (adicionada em 2026-08-31), que situa esta
referência dentro da composição macro do mapa — ver
[pz01-plano-refinamento.md](pz01-plano-refinamento.md) para a leitura completa:

![Visão geral do PZ-01](refs/pz01-overview-target.png)

> **Status:** as decisões da Fase 0 (câmera, fonte de asset, orçamento de
> geografia) foram tomadas — ver seção 6. Este documento descreve o que seria
> necessário implementar para alcançar a imagem acima em Godot,
> **desconsiderando deliberadamente** o estado atual do projeto (heightfield
> procedural, ausência de água) — ver `AUDITORIA.md`/histórico de sessão para
> o gap contra o que já existe. O plano de execução, com dono por tarefa, é
> [pz01-plano-refinamento.md](pz01-plano-refinamento.md).

## 1. O que a referência mostra

Leitura da imagem, decomposta por sistema:

- **Geometria:** ilhas feitas de colunas de basalto hexagonais empilhadas —
  prismas verticais, topos planos em alturas ligeiramente diferentes entre
  colunas vizinhas (columnar jointing). Não é relevo contínuo/suave; é uma
  superfície "quebrada" em unidades discretas.
- **Cobertura:** as colunas ocupam quase 100% da área seca — não há chão liso
  visível entre elas, só a própria rocha até encontrar a água.
- **Vegetação:** musgo/líquen verde em manchas irregulares, concentrado nos
  topos e reentrâncias mais protegidas, nunca uniforme.
- **Água:** gradiente de cor por profundidade (turquesa claro raso → mais
  escuro/saturado fundo), espuma branca exatamente na linha onde a rocha
  encontra a água, sem transição abrupta.
- **Feição especial:** um atol/piscina de maré no canto inferior direito —
  anel de pedra clara cercando uma poça rasa de água mais clara que o mar ao
  redor.
- **Luz:** difusa, uniforme, sem sol direto aparente, mas com **AO forte**
  nas fendas entre colunas e nas bases — é o que dá volume, não uma sombra
  projetada de uma fonte direcional única.
- **Câmera:** quase nadir (perto de 90° de inclinação) — praticamente uma
  vista de mapa/battlemap de RPG de mesa, não uma perspectiva de jogo em
  tempo real.
- **Escala aparente:** dezenas de colunas por ilha, ilhas de tamanhos bem
  variados (de 3 colunas até formações de 40+).

## 2. Câmera — resolvido

O jogo usa câmera ortográfica isométrica clássica: `pitch = -30°`,
`yaw = 45°` (`iso_camera.gd`, `PITCH_DEGREES`) — o mesmo ângulo que a
silhueta de corte de cada criatura do bestiário assume. **Corrigido em
2026-08-31:** o código tinha divergido para -60° ("diorama visto de cima"),
contradizendo o próprio contrato de silhueta documentado na classe; voltou
para -30°, verificado em `test_world.gd`/`test_playable.gd`.

A referência (`bio-002-target.png`) está em ângulo quase nadir — mais
vertical que os -30° do jogo. **Não perseguimos esse enquadramento 1:1**: a
imagem vale como referência de **material/paleta/mood/composição de ilha**,
não de câmera. A composição (quantas colunas cabem no quadro, quão "cheio" o
mapa parece) é validada na câmera real do jogo, -30°/45°.

## 3. Pré-requisitos, por sistema

### 3.1 Kit de assets — colunas de basalto

Não existe hoje um kit modelado para isso (o kit atual, tema
deserto/ruína, não serve — ver seção 5). Do zero, o kit mínimo é:

- **Coluna unitária**, 2–3 variações de altura/proporção e 1–2 variações de
  desgaste do topo (plano, ligeiramente inclinado, rachado).
- **Cluster pré-montado pequeno** (3–8 colunas), útil para preencher bordas
  e ilhas menores sem instanciar peça por peça.
- **Cluster pré-montado grande** (15–40 colunas), para as ilhas centrais de
  maior leitura.
- **Variante com musgo**, mesma geometria, textura com manchas verdes —
  para não depender só de shader para a cor.
- **Peça de atol/piscina de maré** — anel de pedra + fundo raso, feição
  única (provavelmente landmark, não instanciada em série).

Textura: base rocha cinza/marrom escura, normal map para o relevo das
juntas hexagonais, AO map (ou AO gerado em bake), e a variante com musgo
citada acima. Um único material triplanar reutilizável entre todas as
peças do kit é preferível a um material por peça — mantém a paleta
consistente.

### 3.2 Composição do terreno — kit-bash, não heightfield puro

Um heightfield com ruído (o método atual) fisicamente não produz colunas
discretas — é geometria contínua e suave por construção. Para chegar na
referência, a composição precisa inverter a lógica:

- O terreno-base vira **raso/submerso** por padrão (leito do mar).
- As "ilhas" nascem de **instanciar o kit de colunas em massa**, densamente
  o bastante para não sobrar gap de chão liso visível — não landmarks
  isolados espalhados por cima de um relevo que já teria a forma da ilha.
- Precisa de alguma ferramenta/processo de povoamento (script de
  posicionamento por máscara/região, ou autoria manual por ilha) capaz de
  gerar essa densidade sem virar trabalho manual peça-a-peça por hora.

### 3.3 Água — superfície dedicada

Hoje isso **não existe em nenhuma forma** no projeto (nem placeholder) — é
o sistema com maior distância entre "zero" e "pronto". Do zero, precisa de:

- Um plano de água em `y` fixo, com shader próprio (não reaproveitar o
  shader do chão).
- Gradiente de cor por profundidade (comparando a altura do fundo do
  terreno sob cada ponto da água, ou por uma textura de profundidade).
- Espuma na linha de encontro com a rocha (detecção de proximidade com o
  terreno emerso — via textura de intersecção/depth-fade, técnica comum de
  água estilizada).
- Opcional, mas presente na referência: leve variação/ondulação de
  superfície (não precisa ser física, só leitura visual).

### 3.4 Shader/material de rocha

Mesmo com o kit de colunas cobrindo a maior parte da área, qualquer chão
residual (sob a água rasa, nas bordas) precisa de textura real — rocha +
musgo triplanar, não cor lisa por ruído (método atual). Isso é o material
do item 3.1 aplicado também ao terreno-base, para as duas superfícies
lerem como a mesma família visual.

### 3.5 Iluminação

A referência lê como luz difusa/ambiente forte com AO marcado, não sol
direcional duro. Implica:
- Ambient occlusion real (SSAO ou AO map bakeado nas peças do kit — o
  AO map é mais barato e mais controlável para um jogo estilizado).
- Luz ambiente/preenchimento mais contida do que "lisa" — o volume vem do
  AO, não da quantidade de luz.

### 3.6 Escala e densidade

A referência mostra dezenas de colunas por ilha e várias ilhas no quadro.
Em unidades de jogo (1m = 1 unidade, regra do projeto), isso define o
diâmetro típico de uma coluna (provavelmente 0,8–1,5 m de diâmetro por
coluna, para dezenas caberem numa ilha de poucos metros) — vale validar
esse número contra o zoom da câmera de jogo antes de modelar, para não
gerar peças fora de escala.

## 4. Pipeline de conteúdo

Seguindo a convenção do projeto (`CLAUDE.md`, regra 1 e a divisão de
responsabilidade entre `avyron` e `avyron-bestiary`): os `.glb` do kit de
colunas são conteúdo, não código — nasceriam no `avyron-bestiary` e
chegariam aqui via `pnpm game:export`, do mesmo jeito que o kit aquático
(`models/biomes/aquatic/`) chegou. O posicionamento/composição de cada
ilha, por outro lado, é layout de cena (`MapDressing`/equivalente), e isso
sim é código deste repositório.

## 5. Sobre o material atual (pasta `assets_BIO-001`, Meshy)

Os 9 assets adicionados em 2026-08-30 (`Ancient Coin Hoard`, `Cracked Earth`,
`Cracked Stone Platform`, `Golden Island`, `Layered Stone Formation` ×2,
`Oasis Pool`, `Rocky Outcrop`, `Rocky Plateau`) **são** o material desta
referência — não um kit trocado por engano, como uma leitura anterior deste
documento concluiu antes da correção da seção acima. O que ficou errado foi
só o rótulo: a pasta se chama `models/biomes/assets_BIO-001/`, mas o
conteúdo dela é de BIO-002 (Costa Primordial) — batizada com o código errado
desde que foi criada. Renomear a pasta (e o que a referencia em
`map_dressing.gd`) é tarefa mecânica da Fase 3 do plano de execução, não
bloqueia o uso do material como está.

## 6. Pendência técnica — resolvida na Fase 1 (2026-08-31)

Uma leitura anterior deste documento apontava que `MapTerrain._reef_profile`
(a colina que lia como "bloco rochoso" no relevo) não coincidia com o
território real de BIO-002 no catálogo, e tratava isso como um desalinhamento
a corrigir. A leitura estava certa sobre o desalinhamento, mas errada sobre
qual bioma estava envolvido: `_reef_profile` **nunca representou BIO-002** —
sempre foi a forma reservada para BIO-003 (Jardins Recifais), só que com uma
posição solta, de concept art anterior à partição de bioma. O território real
de BIO-002 (a costa, `on_coast`) sempre foi só o retângulo+círculo de
`_coast_profile`, que já batiam com `RGN-001`/`RGN-006` desde antes desta
rodada.

A correção, feita na Fase 1 do plano de execução: `REEF_CENTER` migrou para
o círculo real de `RGN-002` (BIO-003), `_glacial_profile` virou retângulo
(era círculo) para bater com `RGN-004` (BIO-014), e `_abyss_profile` ganhou
um portão em `z` para não invadir mais o platô seco da costa. Nenhum dos três
precisou mexer no território de BIO-002 em si — ele já estava certo.

## 7. Decisões tomadas (Fase 0)

1. **Câmera:** -30°/45°, sem perseguir o nadir da referência — seção 2.
2. **Fonte do kit:** Meshy AI. Para BIO-002 especificamente, os 9 assets já
   prontos (seção 5) são o material a integrar agora — não serão
   regenerados. Para o próximo bioma, o pipeline é protótipo 2D via ChatGPT
   → conversão 3D no Meshy; escrever o prompt do protótipo é tarefa
   colaborativa (ver plano de execução).
3. **Densidade/instanciamento:** decidido junto da Fase 1 do plano de
   execução, não aqui — depende de quanto do kit atual (8 peças) cobre a
   área real de BIO-002 antes de decidir se falta gerar mais.
4. **Orçamento de geografia macro:** aprovado. Sequência: remodelar a
   geografia macro do mapa inteiro primeiro (todos os biomas, só valor,
   sem campo novo no catálogo) → aplicar os assets de BIO-002 → gerar o
   próximo bioma. Detalhado no plano de execução.
