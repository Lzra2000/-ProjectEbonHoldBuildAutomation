<p align="center">
  <img src="../../assets/banner.svg" alt="EbonBuilds — Automatización de ecos para ProjectEbonhold" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="Comprobaciones CI"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Última versión"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-EbonBuilds%20License-4a5568" alt="Licencia"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
</p>

<p align="center">
  <a href="../../README.md">English</a> | <a href="README.de.md">Deutsch</a> | <a href="README.ru.md">Русский</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <b>Español</b> | <a href="README.fr.md">Français</a> | <a href="README.pl.md">Polski</a>
</p>

**EbonBuilds** es un addon de cliente de World of Warcraft **3.3.5a** para jugadores en servidores privados de **[ProjectEbonhold](https://github.com/Lzra2000/ProjectEbonhold)**. Defines un build — pesos de eco, políticas e intención de autopilot — y EbonBuilds puntúa cada pantalla de elección de eco (Banish / Reroll / Freeze / Select) por ti, registra lo ocurrido y convierte datos reales de partida en sugerencias de ajuste revisables.

Pensado para raiders y grinders de ecos de ProjectEbonhold que quieren automatización consistente sin ceder el control: cada acción queda registrada, las recomendaciones requieren tu aprobación y el Manual Training Mode permite que el addon aprenda de elecciones deliberadas.

## Instalación rápida

1. Descarga **`EbonBuilds.zip`** desde la [última versión](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest).
2. Extrae el archivo. La carpeta debe llamarse **`EbonBuilds`** (coincidiendo con `EbonBuilds.toc`).
3. Cópiala a `World of Warcraft/Interface/AddOns/`.
4. Reinicia el juego o ejecuta `/reload`.

**Alternativa por Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation.git EbonBuilds
```

**Requisito del servidor:** ProjectEbonhold incluye su propio addon de servidor. Instala **ProjectEbonhold** o **ProjectEbonhold Enhanced** en el cliente según lo proporcione tu servidor — EbonBuilds depende de él para tableros de eco, datos de afijos y varias funciones de integración. Sin él, EbonBuilds no funcionará.

**Opcional:** **[Details!](https://www.curseforge.com/wow/addons/details)** habilita sugerencias de peso basadas en DPS y estadísticas más completas. El registro de DPS en combate en el Logbook (v3.84+) funciona sin Details! cuando está activado en Ajustes.

Abre el addon con **`/ebb`** o **`/ebonbuilds`**.

## Funciones

| Área | Qué obtienes |
| --- | --- |
| **Autopilot** | Presets de intención (Save charges / Balanced / Chase upgrades), puntuación por eco, seguimiento de freeze persistente en la partida y un **Logbook** centrado en decisiones con razonamiento y uso de cargas. |
| **Builds** | Pesos por eco (incl. rangos por calidad), ranuras bloqueadas/prohibidas, instantáneas de personaje (talentos, glifos, equipo), Tuning Advisor, Manual Training Mode, exportación EchoWishlist (`EWL1`) y volcados de **Export (AI)** en texto plano. |
| **Public Builds** | Explora builds de la comunidad, inspecciona prioridades e instantáneas, vota, importa y (si el servidor lo admite) guarda o aplica **server loadouts**. |
| **Affixes** | Panel de referencia de afijos, puntos de afijo en bolsas (bolsas predeterminadas, Bagnon, Combuctor) y modelado de equipo en la pestaña Personaje. |
| **DPS y estadísticas** | Muestras opcionales de DPS en combate adjuntas a partidas y visibles en el Logbook; seguimiento de DPS respaldado por Details! y sincronización de tasa de aparición cuando está instalado y con consentimiento. Espacio de estadísticas con Summary, Actions, Echoes y Recommendations respaldadas por evidencia. |
| **Locales** | UI del editor de builds en alemán, español, francés, polaco, portugués brasileño y ruso — detectada automáticamente del cliente o anulada desde Ajustes. |

Otras herramientas destacadas: **Tome Atlas** (ubicaciones de drop de la comunidad), **Missing Echoes** (ecos ponderados que aún no has aprendido), **budget pacing** en toda la partida y auto-venta opcional al vender.

<p align="center">
  <img src="../../assets/how-it-works.svg" alt="Define un build, Autopilot actúa en pantallas de elección, se registran datos, el Tuning Advisor sugiere ajustes y el ciclo se repite" width="100%">
</p>

## Capturas de pantalla

| Editor de build — prioridades | Vista general del build y Autopilot |
| --- | --- |
| <img src="../../assets/screenshots/editor-priorities.png" alt="Editor de prioridades de eco" width="100%"> | <img src="../../assets/screenshots/build-overview.png" alt="Vista general del build" width="100%"> |

| Logbook | Estadísticas — recomendaciones |
| --- | --- |
| <img src="../../assets/screenshots/logbook.png" alt="Logbook de decisiones" width="100%"> | <img src="../../assets/screenshots/stats-recommendations.png" alt="Recomendaciones respaldadas por evidencia" width="100%"> |

Más capturas y un recorrido completo de la UI están en [`assets/screenshots/`](../../assets/screenshots/) y en el [sitio de documentación](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/getting-started/).

## Documentación y soporte

| Recurso | Enlace |
| --- | --- |
| Documentación (Primeros pasos, Ajustes, FAQ) | [lzra2000.github.io/ProjectEbonHoldBuildAutomation](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/) |
| FAQ | [FAQ](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/faq/) |
| Versiones y changelog | [Releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases) · [`CHANGELOG.md`](../../CHANGELOG.md) |
| Informes de errores y solicitudes de funciones | [Issues](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues) |
| Seguridad | [`SECURITY.md`](../../SECURITY.md) |

Al informar errores, adjunta la salida de **Ajustes → Windows & tools → Error log** o **Debug log** — es la vía más rápida para una corrección.

## Desarrollo

Las contribuciones son bienvenidas. Consulta [`CONTRIBUTING.md`](../../CONTRIBUTING.md) para la configuración, convenciones y la lista de verificación pre-PR.

Para comprobaciones locales, paridad con CI y depuración de ejecuciones fallidas de Actions, consulta **[`docs/dev-testing.md`](../../docs/dev-testing.md)**. Puntos de entrada rápidos:

```sh
sh scripts/dev-setup.sh    # toolchain única (Debian/Ubuntu; usa WSL en Windows)
sh scripts/check.sh        # bucle local rápido (sintaxis, tests, .toc, lint API 3.3.5a)
sh scripts/check.sh --full # suite completa que ejecuta CI antes del merge
sh scripts/build-dist.sh   # produce dist/EbonBuilds.zip
```

La raíz del repositorio es la carpeta del addon (`EbonBuilds.toc`, `core/`, `modules/` en el nivel superior). Las etiquetas de release activan [`.github/workflows/release.yml`](../../.github/workflows/release.yml), que publica `EbonBuilds.zip` en GitHub Releases.

## Licencia

Consulta [`LICENSE`](../../LICENSE). El uso personal y en comunidades de servidores privados está permitido para releases oficiales sin modificar. Redistribuir versiones modificadas bajo el nombre EbonBuilds, o uso comercial, requiere permiso previo del titular de los derechos de autor.
