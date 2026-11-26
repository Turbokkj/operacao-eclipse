# OPERAÇÃO ECLIPSE: BATTLE ROYALE

Battle royale 3D **offline** para navegador (Godot 4 · GDScript · WebAssembly · renderizador Compatibility / WebGL 2.0).
Identidade, personagens, mapa, interface e sons são **originais** (nada de Free Fire foi copiado).

> ## Leia primeiro: estado real desta entrega
> O projeto foi submetido a uma verificação estática do código-fonte. A execução no Godot e a exportação Web
> ainda precisam ser confirmadas no ambiente de compilação. Não considere o multiplayer validado até testar
> duas instâncias do jogo conectadas ao servidor de partidas.

## Requisitos
- **Godot 4.3 ou superior** (testado em lugar nenhum ainda; projetado para 4.3) + *export templates* da mesma versão para exportar para Web.
- Python 3 (opcional) para regenerar assets (`numpy`, `Pillow`) e servir a build web.

## Primeira execução
1. Abra a pasta no Godot (`project.godot`). Na primeira vez o editor importa o projeto e cria o cache de classes globais — aguarde terminar.
2. Veja o painel **Saída/Depurador**. Se aparecer algum *Parse Error*, ele indica arquivo e linha; corrija e recarregue.
3. Pressione **F5**. Fluxo: carregamento → login demonstrativo → lobby 3D → partida.
4. (Opcional) Rode os testes automatizados:
   `godot --headless --path . --script res://tests/run_tests.gd` (inclui uma partida simulada só com bots até o fim).
5. Antes de abrir no editor você pode rodar o verificador estático: `python3 tools/check_project.py`.

## Controles
| Ação | PC | Mobile (touch) |
|---|---|---|
| Mover | W A S D | joystick flutuante (lado esquerdo); empurre até a borda para correr |
| Câmera | mouse (clique para capturar) | arrastar no lado direito (ou segurando ATIRAR) |
| Atirar / Mirar | botão esquerdo / direito | botões ATIRAR / MIRAR (liga/desliga) |
| Pular / Agachar | Espaço / C | botões PULAR / AGACHAR |
| Correr | Shift | automático ao empurrar o joystick, ou botão CORRER |
| Coletar / Recarregar | E / R | botões PEGAR / RECARR. |
| Armas | 1 2 3, Q (próxima) | botão TROCAR |
| Curar | 4 bandagem/energético, 5 kit médico | botão CURAR |
| Mochila / Mapa grande / Pausa | Tab / M / Esc | botões MOCHILA e II |

Teclas podem ser remapeadas em **Configurações → Controles**. Nessa mesma aba há o **editor de HUD** (arraste/redimensione os botões touch).

## O que existe (visão geral)
- **Boot/Carregamento**: logotipo, barra de progresso com etapas reais (cada áudio/material carregado conta), mensagens, fade e tratamento de erro; página `web/shell.html` mostra o progresso real do download e erros de WebGL2/navegador.
- **Login demonstrativo** (apelido/convidado + 6 avatares), tudo salvo em `user://` (perfil, personalização, configurações, estatísticas, layout do HUD).
- **Lobby 3D**: palco, skyline + eclipse ao fundo, partículas, luzes, câmera com movimento sutil, personagem com animação de descanso, arrastar para girar, zoom, painéis de **Modos**, **Personagem** (ao vivo), **Inventário/Arsenal** e **Configurações**.
- **Personagens 3D procedurais** (3 modelos-base): esqueleto de 18 ossos + malha com *skinning* (cabeça, rosto com olhos/nariz/boca/orelhas, cabelo, pescoço, tronco, braços, mãos, pernas, pés e roupas) — 6 penteados, 4 rostos, 6 tons de pele, 4 camisetas/jaquetas, 3 calças, 3 calçados, 3 acessórios de cabeça, cores. A aparência escolhida aparece na partida.
- **Animação procedural** (`character_animator.gd`): parado/respirando, andar, correr, 8 direções + lateral, agachar, andar agachado, pular, aterrissar, equipar, interagir, recarregar, atirar (recuo), impacto, eliminado, vitória e descanso do lobby; ciclo de passo guiado pela distância (sem “patinar”) e IK de 2 ossos para segurar a arma.
- **Modo CLÁSSICO** (Mapa 1 — 800×800 m): 1 jogador + até 15 bots, loot, zona segura circular que fecha em 7 fases, dano fora da zona, contagem 3-2-1, vitória/derrota e tela de resultados.
- **Modo TREINAMENTO**: campo com alvos físicos fixos, móveis e pop-up, bots de treino, percurso (muro, caixas, barra baixa, plataforma com escada), rack de armas, acertos/precisão/pontos/cronômetro; tipos Livre, Precisão (60 s) e Contra bots.
- **Mapa**: terreno com colinas + 3 cidades (Nova Aurora — centro urbano; Vale Verde — bairro com relevo, cercas e praça; Porto Ferro — zona industrial com armazéns, contêineres, tanques e guindaste) + construções rurais, estradas, árvores, rochas, arbustos, nuvens. Construções com portas, janelas, paredes, telhados (planos com platibanda e de duas águas), pisos, salas internas, móveis e escadas externas até os telhados.
- **Loot**: distribuição procedural por construção/cidade/riqueza (quantidades mínimas garantidas), itens físicos coletáveis, inventário com capacidade e categorias, raridades com feixe de luz.
- **Bots**: máquina de estados (12 estados), percepção por campo de visão + raio contra o cenário + sons do jogo, navegação em dois níveis (A* em grade + grafo de salas/portas), três perfis (iniciante/intermediário/avançado), mesmas regras do jogador, decisão escalonada e LOD de animação.
- **Combate**: 5 equipamentos fictícios (pistola, SMG, rifle, escopeta, DMR), tiro por *raycast*, dispersão, recuo, recarga, proteção (colete/capacete), cura, mira assistida (4 níveis) e eliminação sem violência gráfica.
- **Áudio** 100 % sintetizado (efeitos, música de menu, ambientes) com barras Geral/Música/Efeitos/Ambiente.
- **Qualidade**: Baixo / Médio / Alto / Automático / Personalizado (escala 3D, sombras, distância de renderização, vegetação, MSAA) + limite de FPS; o modo Automático reduz a qualidade se o FPS cair.

## Estrutura
```
operacao-eclipse/
├── project.godot · export_presets.cfg · icon.svg
├── scenes/          boot · login · lobby · maps/classic_map_01 · maps/training · player · bots   (cenas-raiz; o conteúdo 3D/UI é montado por código)
├── scripts/
│   ├── core/        events, settings_manager, audio_manager, quality_manager, scene_router, boot, material_library, theme_factory
│   ├── save/        save_system (JSON em user://)
│   ├── customization/  cosmetics_db, mesh_kit, character_builder, character_model, character_animator, weapon_models
│   ├── player/ camera/ combat/ inventory/ loot/ bots/ match/ training/
│   ├── map/         map_generator, building_builder, nav_grid, map_props, world_batch, environment_builder, map_data, building_info
│   └── ui/          hud, minimap, touch_controls, hud_editor, settings_menu, lobby, login, results_screen, loading_overlay, ui_kit ...
├── assets/audio/*.pcm · assets/textures/*.tex     (gerados por tools/gen_audio.py e tools/gen_textures.py)
├── web/shell.html      página HTML customizada (progresso real + erros)
├── tools/              check_project.py · gen_audio.py · gen_textures.py · export_web.sh · serve.py
└── tests/run_tests.gd
```
Observações de projeto:
- Personagens, animações, mapa e interface são **gerados por código** (por isso não há pastas de modelos/animações binárias). Os arquivos `.pcm`/`.tex` são lidos diretamente (sem depender do pipeline de importação) e entram na exportação pelo filtro `include_filter` do preset.
- A personalização fica no painel **Personagem** do lobby (`scripts/ui/lobby.gd`), e HUD/Configurações/Resultados são criados em código a partir de `scripts/ui/*`.

## Exportar para Web (HTML5/WebAssembly)
Pelo editor: **Projeto → Exportar → Web** (preset já configurado: single-thread, shell customizado, VRAM compression para desktop e mobile).
Pela linha de comando:
```bash
GODOT=/caminho/do/godot tools/export_web.sh      # importa e exporta para build/web/index.html
python3 tools/serve.py build/web 8060            # servidor local com MIME correto para .wasm
```
Hospede `build/web/` em qualquer servidor HTTPS estático (ative compressão gzip/brotli para `.wasm` e `.pck`). Build single-thread → **não exige** cabeçalhos COOP/COEP. Para mobile use orientação horizontal; a página avisa quando estiver em retrato.


## Multiplayer online (novo)
**Como funciona:** modelo *listen-server*. O jogador "host" da sala roda a partida inteira (mapa, loot, bots, zona, dano); os outros enviam entrada e recebem snapshots (~12/s). O `server/server.js` só faz **matchmaking, salas e repasse de mensagens** (sem dependências, Node 18+). Bots completam as vagas no host.

**No jogo:** Lobby → **ONLINE** → informe o endereço do servidor → 
- **Partida rápida:** fila de ~15 s (ou até 16 jogadores); quem faltar vira bot.
- **Criar sala:** gera um código de 5 letras para os amigos; o dono escolhe vagas, bots e dificuldade e inicia.
- **Entrar com código.**

**Servidor local:** `node server/server.js` (porta 8080) → no jogo use `ws://localhost:8080`. Testes: `node server/test.js` (35 verificações).

### Deploy (2 peças)
1. **Servidor de partidas — NÃO pode ficar na Vercel** (funções serverless não mantêm WebSocket). Use Render/Railway/Fly/VPS. Render: *New → Blueprint* apontando para este repositório (usa `render.yaml`) → você ganha `https://xxx.onrender.com` → o endereço do jogo é `wss://xxx.onrender.com`. (Plano gratuito "dorme": a 1ª conexão pode levar ~1 min.)
2. **Jogo na Vercel:** envie este projeto para um repositório GitHub → *Add New Project* na Vercel → em *Environment Variables* defina `GAME_SERVER_URL=wss://xxx.onrender.com` → *Deploy*. `vercel.json` + `tools/vercel_build.sh` baixam o Godot 4.3 no build e exportam para Web. (Ou, com a CLI: `npx vercel --prod` dentro da pasta.) Se o build falhar, o log mostra os erros do Godot. Também dá para passar `?server=wss://...` na URL.

**Limites assumidos:** movimento confiado ao cliente (sem anti-cheat), sem migração de host (se o host sai, a partida acaba), sem reconexão, páginas `https` exigem `wss://`.

## Ajustes rápidos
- Tamanho do mapa: `MapData.HALF` (`scripts/map/map_data.gd`; padrão 400 → 800×800 m). Células de navegação: `NavGrid.setup(..., 2.5)` em `map_generator.gd`.
- Fases da zona: `ZoneController.PHASES`. Armas: `WeaponDB.WEAPONS`. Itens/raridades: `ItemDB`. Perfis dos bots: `Bot.PROFILES`.
- Perfis gráficos: `QualityManager.PROFILES`. Número de bots e dificuldade: painel **Modos de jogo** do lobby.
- Regerar assets: `python3 tools/gen_audio.py` e `python3 tools/gen_textures.py`.

## Limitações conhecidas e próximos passos
Limitações conhecidas: **nada foi executado no Godot ainda**; não há `AnimationTree` (animação procedural), nem LOD de malhas/occlusion culling/lightmaps/normal maps; não há pontes/rio nem andares internos (telhados via escada externa); o remapeamento cobre só teclado; a qualidade visual dos personagens/prédios é a de malhas procedurais estilizadas (não de arte modelada por artista).
