<p align="center">
  <img src="../../assets/banner.svg" alt="EbonBuilds" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="Checks"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
  <img src="https://img.shields.io/badge/Lua-5.1-8a5fc9" alt="Lua 5.1">
</p>

<p align="center">
  <a href="../../README.md">English</a> | <a href="README.de.md">Deutsch</a> | <a href="README.ru.md">Русский</a> | <b>Português (Brasil)</b> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.pl.md">Polski</a>
</p>

Um addon de World of Warcraft (3.3.5a) para o **ProjectEbonhold** que automatiza as escolhas de echo (Banish / Reroll / Freeze / Select) com base em um build que você define, e se auto-ajusta ao longo do tempo com dados reais de jogo.

Requer **ProjectEbonhold** ou **ProjectEbonhold Enhanced**. Alguns recursos usam adicionalmente o **[Details!](https://www.curseforge.com/wow/addons/details)**, se instalado.


<p align="center">
  <img src="assets/how-it-works.svg" alt="How it works" width="100%">
</p>

## O que ele faz

- **Definir um build**: pesos por echo, bônus de qualidade/família/novidade, slots travados, echoes banidos.
- **Automação**: avalia cada tela de escolha de echo contra o seu build e age (banish/reroll/freeze/select) para você não precisar.
- **Tuning Advisor**: compara seus limiares de Banish/Reroll/Freeze com o que seu build realmente recebe de oferta (não um modelo teórico), sugere valores melhores e pode ajustá-los automaticamente e gradualmente ao longo do tempo.
- **Distribuição de orçamento durante toda a run**: os limiares ficam automaticamente mais rígidos conforme as cargas de Banish/Reroll/Freeze diminuem, para você não gastar suas últimas cargas em ofertas duvidosas.
- **Rastreamento de DPS e taxa de aparição**: com o Details! instalado, rastreia o DPS real por echo ativo; sempre rastreia com que frequência cada echo realmente aparece numa tela de escolha. Ambos podem opcionalmente sincronizar com outros jogadores da mesma classe.
- **Manual Training Mode**: suspenda a automação de um build, escolha manualmente, e o EbonBuilds aprende com suas escolhas, gerando sugestões de peso a partir do que você realmente preferiu.
- **Sugestões de peso e bônus**: dados de DPS e escolhas manuais alimentam sugestões de peso por echo, e (experimentalmente) sugestões de bônus de Qualidade/Família.
- **Export (AI)**: um dump completo em texto simples das configurações do build, todos os echoes disponíveis para sua classe com descrições reais de efeito, e todos os dados de ajuste — feito para ser colado num chat de IA para análise.
- **Tome Atlas**: locais de drop de tomos de echo, coletados pela comunidade.
- **Public Builds**: navegue e importe builds compartilhados por outros jogadores.

Veja [FAQ](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/faq/) / [CHANGELOG.md](../../CHANGELOG.md) para explicações detalhadas de cada recurso e o histórico completo de versões.

## Capturas de tela

O tour segue o fluxo real: configure um build, deixe o Autopilot jogar e aprenda com os dados.

### 1 · Configurar o build

<img src="assets/screenshots/editor-priorities.png" alt="editor-priorities" width="100%">

*Prioridades de echo: valores por rank, políticas e pontuações finais.*

<img src="assets/screenshots/editor-modifiers.png" alt="editor-modifiers" width="100%">

*Modificadores: estratégia de rank, ênfase de função, bônus de echo único.*

<img src="assets/screenshots/editor-autopilot.png" alt="editor-autopilot" width="100%">

*Autopilot: escolha uma intenção e ajuste os limites.*

### 2 · A aba Personagem

<img src="assets/screenshots/character-overview.png" alt="character-overview" width="100%">

*Snapshot do personagem: talentos, glifos e equipamento.*

<img src="assets/screenshots/character-talents.png" alt="character-talents" width="100%">

*Árvores de talentos completas com a alocação do snapshot.*

<img src="assets/screenshots/character-gear.png" alt="character-gear" width="100%">

*Equipamento com afixos por slot e pontuações modeladas.*

### 3 · Deixar rodar

<img src="assets/screenshots/build-overview.png" alt="build-overview" width="100%">

*A visão geral do build: echoes travados, compartilhamento, exportações.*

<img src="assets/screenshots/logbook.png" alt="logbook" width="100%">

*O diário: cada decisão com o motivo e a alternativa.*

### 4 · Aprender com os dados

<img src="assets/screenshots/stats-summary.png" alt="stats-summary" width="100%">

*Resumo estatístico das partidas registradas.*

<img src="assets/screenshots/stats-actions.png" alt="stats-actions" width="100%">

*Como as quatro ações foram realmente usadas.*

<img src="assets/screenshots/stats-recommendations.png" alt="stats-recommendations" width="100%">

*Recomendações baseadas em evidências, com confiança e links.*

<img src="assets/screenshots/missing-echoes.png" alt="missing-echoes" width="100%">

*Echoes ponderados faltantes e suas fontes.*

## Instalação

A raiz deste repositório *é* a pasta do addon (`EbonBuilds.toc`, `core/`, `modules/` ficam no nível superior, não dentro de uma subpasta).

**Via Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Via download do ZIP:** o "Download ZIP" do GitHub nomeia a pasta extraída de acordo com a branch (ex.: `EbonBuilds-main`) — renomeie-a exatamente para `EbonBuilds` antes de colocá-la em `Interface/AddOns/`, para que o nome da pasta corresponda ao `EbonBuilds.toc`.

Depois reinicie o jogo ou dê `/reload`.

## Comandos

Apenas `/ebb` (ou `/ebonbuilds`): abre ou fecha a janela principal. Tudo o que antes era um comando separado agora fica no ícone de engrenagem (Configurações) no cabeçalho da janela, tudo em um só lugar em vez de subcomandos para memorizar: idioma, venda automática, pontos de afixo nas bolsas, log de depuração, Click Trace, os logs de depuração/erros/Click Trace, o Tuning Advisor, o Tome Atlas, a referência de afixos, o guia de comandos, e a exportação EWL e o reset do Manual Training do build ativo.

## Localização

As abas, botões e tooltips do editor de builds estão traduzidos para alemão, espanhol, francês, polonês, português do Brasil e russo. O EbonBuilds escolhe o idioma automaticamente a partir do seu cliente; dá para forçar com `/ebb locale <code>`. Para adicionar um idioma: `sh scripts/new-locale.sh <code>` gera um arquivo inicial pré-preenchido — o restante dos passos está em `CONTRIBUTING.md`. Termos do jogo (Echo, Build, Banish/Reroll/Freeze/Select, Autopilot) ficam em inglês em todos os idiomas.

## Documentação

O [site de documentação](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/) cobre os primeiros passos, cada configuração, o FAQ completo com busca, localização, desenvolvimento e solução de problemas. Sua fonte vive em [`docs/`](../../docs/), é versionada com o código e é publicada no GitHub Pages a cada merge na `main`. Questões de segurança — payloads de sincronização hostis, strings de importação maliciosas, consentimento de compartilhamento de dados — têm seu próprio canal: veja [SECURITY.md](../../SECURITY.md).

## Relatando bugs

Anexe a saída do log de erros ou do log de depuração (Configurações — ícone de engrenagem — Windows & Tools) ao seu relato: é de longe a forma mais rápida de algo ser corrigido em vez de adivinhado.

## Desenvolvimento

- Lua puro, API do WotLK 3.3.5a (Interface 30300). Sem etapa de build — a raiz do repositório *é* a estrutura de pasta que `Interface/AddOns/` espera.
- Uma única vez: `sh scripts/dev-setup.sh` instala as ferramentas (`lua5.1`, `zip`; Debian/Ubuntu — no Windows, via WSL).
- `sh scripts/check.sh` roda as mesmas verificações do CI em um comando: sintaxe, suíte de testes, verificação do `.toc`, checagem de API 3.3.5a, cabeçalhos de arquivo.
- Releases passam por `sh scripts/release.sh <version>`; o tag enviado publica o GitHub Release automaticamente via workflow.
- Guia completo (em inglês): [`CONTRIBUTING.md`](../../CONTRIBUTING.md).

## Licença

Veja [`LICENSE`](../../LICENSE). Uso pessoal e em comunidades de servidores privados é livre; redistribuir versões modificadas sob o nome EbonBuilds, ou uso comercial, exige permissão prévia do detentor dos direitos.
