<p align="center">
  <img src="../../assets/banner.svg" alt="EbonBuilds — Automação de echoes para ProjectEbonhold" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="Verificações CI"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Última versão"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-EbonBuilds%20License-4a5568" alt="Licença"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
</p>

<p align="center">
  <a href="../../README.md">English</a> | <a href="README.de.md">Deutsch</a> | <a href="README.ru.md">Русский</a> | <b>Português (Brasil)</b> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.pl.md">Polski</a>
</p>

**EbonBuilds** é um addon de cliente World of Warcraft **3.3.5a** para jogadores em servidores privados do **[ProjectEbonhold](https://github.com/Lzra2000/ProjectEbonhold)**. Você define um build — pesos de echo, políticas e intenção do autopilot — e o EbonBuilds pontua cada tela de escolha de echo (Banish / Reroll / Freeze / Select) por você, registra o que aconteceu e transforma dados reais de run em sugestões de ajuste revisáveis.

Feito para raiders e grinders de echo do ProjectEbonhold que querem automação consistente sem abrir mão do controle: cada ação é registrada, recomendações exigem sua aprovação, e o Manual Training Mode permite que o addon aprenda com escolhas deliberadas.

## Instalação rápida

1. Baixe **`EbonBuilds.zip`** na [última versão](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest).
2. Extraia o arquivo. A pasta deve se chamar **`EbonBuilds`** (correspondendo a `EbonBuilds.toc`).
3. Copie para `World of Warcraft/Interface/AddOns/`.
4. Reinicie o jogo ou execute `/reload`.

**Alternativa via Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation.git EbonBuilds
```

**Requisito do servidor:** o ProjectEbonhold inclui seu próprio addon de servidor. Instale **ProjectEbonhold** ou **ProjectEbonhold Enhanced** no cliente conforme fornecido pelo seu servidor — o EbonBuilds depende dele para quadros de echo, dados de affixes e vários recursos de integração. Sem ele, o EbonBuilds não funcionará.

**Opcional:** **[Details!](https://www.curseforge.com/wow/addons/details)** habilita sugestões de peso baseadas em DPS e estatísticas mais ricas. O registro de DPS em combate no Logbook (v3.84+) funciona sem Details! quando ativado em Configurações.

Abra o addon com **`/ebb`** ou **`/ebonbuilds`**.

## Recursos

| Área | O que você obtém |
| --- | --- |
| **Autopilot** | Presets de intenção (Save charges / Balanced / Chase upgrades), pontuação por echo, rastreamento de freeze persistente na run e um **Logbook** focado em decisões com raciocínio e uso de cargas. |
| **Builds** | Pesos por echo (incl. ranks por qualidade), slots travados/banidos, snapshots de personagem (talentos, glifos, equipamento), Tuning Advisor, Manual Training Mode, exportação EchoWishlist (`EWL1`) e dumps de **Export (AI)** em texto simples. |
| **Public Builds** | Navegue builds da comunidade, inspecione prioridades e snapshots, vote, importe e (quando o servidor suportar) salve ou aplique **server loadouts**. |
| **Affixes** | Painel de referência de affixes, pontos de affix na bolsa (bolsas padrão, Bagnon, Combuctor) e modelagem de equipamento na aba Personagem. |
| **DPS e estatísticas** | Amostras opcionais de DPS em combate anexadas às runs e exibidas no Logbook; rastreamento de DPS via Details! e sync de taxa de aparição quando instalado e com consentimento. Espaço de estatísticas com Summary, Actions, Echoes e Recommendations respaldadas por evidências. |
| **Locales** | UI do editor de builds em alemão, espanhol, francês, polonês, português brasileiro e russo — detectada automaticamente do cliente ou substituída em Configurações. |

Outras ferramentas: **Tome Atlas** (locais de drop da comunidade), **Missing Echoes** (echoes ponderados que você ainda não aprendeu), **budget pacing** durante toda a run e auto-venda opcional ao vender.

<p align="center">
  <img src="../../assets/how-it-works.svg" alt="Defina um build, o Autopilot age nas telas de escolha, dados são rastreados, o Tuning Advisor sugere ajustes, e o ciclo se repete" width="100%">
</p>

## Capturas de tela

| Editor de build — prioridades | Visão geral do build e Autopilot |
| --- | --- |
| <img src="../../assets/screenshots/editor-priorities.png" alt="Editor de prioridades de echo" width="100%"> | <img src="../../assets/screenshots/build-overview.png" alt="Visão geral do build" width="100%"> |

| Logbook | Estatísticas — recomendações |
| --- | --- |
| <img src="../../assets/screenshots/logbook.png" alt="Logbook de decisões" width="100%"> | <img src="../../assets/screenshots/stats-recommendations.png" alt="Recomendações respaldadas por evidências" width="100%"> |

Mais capturas e um tour completo da UI estão em [`assets/screenshots/`](../../assets/screenshots/) e no [site de documentação](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/getting-started/).

## Documentação e suporte

| Recurso | Link |
| --- | --- |
| Documentação (Primeiros passos, Configurações, FAQ) | [lzra2000.github.io/ProjectEbonHoldBuildAutomation](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/) |
| FAQ | [FAQ](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/faq/) |
| Versões e changelog | [Releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases) · [`CHANGELOG.md`](../../CHANGELOG.md) |
| Relatos de bugs e pedidos de recursos | [Issues](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues) |
| Segurança | [`SECURITY.md`](../../SECURITY.md) |

Ao relatar bugs, anexe a saída de **Configurações → Windows & tools → Error log** ou **Debug log** — é o caminho mais rápido para uma correção.

## Desenvolvimento

Contribuições são bem-vindas. Veja [`CONTRIBUTING.md`](../../CONTRIBUTING.md) para configuração, convenções e checklist pré-PR.

Para verificações locais, paridade com CI e depuração de execuções falhas do Actions, consulte **[`docs/dev-testing.md`](../../docs/dev-testing.md)**. Pontos de entrada rápidos:

```sh
sh scripts/dev-setup.sh    # toolchain única (Debian/Ubuntu; use WSL no Windows)
sh scripts/check.sh        # loop local rápido (sintaxe, testes, .toc, lint API 3.3.5a)
sh scripts/check.sh --full # suite completa executada pelo CI antes do merge
sh scripts/build-dist.sh   # produz dist/EbonBuilds.zip
```

A raiz do repositório é a pasta do addon (`EbonBuilds.toc`, `core/`, `modules/` no nível superior). Tags de release disparam [`.github/workflows/release.yml`](../../.github/workflows/release.yml), que publica `EbonBuilds.zip` no GitHub Releases.

## Licença

Consulte [`LICENSE`](../../LICENSE). Uso pessoal e em comunidades de servidores privados é permitido para releases oficiais não modificados. Redistribuir versões modificadas sob o nome EbonBuilds, ou uso comercial, requer permissão prévia do detentor dos direitos autorais.
