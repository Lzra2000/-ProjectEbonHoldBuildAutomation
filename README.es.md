<p align="center">
  <img src="assets/banner.svg" alt="EbonBuilds" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="Checks"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
  <img src="https://img.shields.io/badge/Lua-5.1-8a5fc9" alt="Lua 5.1">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.de.md">Deutsch</a> | <a href="README.ru.md">Русский</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <b>Español</b> | <a href="README.fr.md">Français</a> | <a href="README.pl.md">Polski</a>
</p>

Un addon de World of Warcraft (3.3.5a) para **ProjectEbonhold** que automatiza las elecciones de eco (Banish / Reroll / Freeze / Select) según un build que defines, y se autoajusta con el tiempo a partir de datos reales de juego.

Requiere **ProjectEbonhold** o **ProjectEbonhold Enhanced**. Algunas funciones usan además **[Details!](https://www.curseforge.com/wow/addons/details)** si está instalado.


<p align="center">
  <img src="assets/how-it-works.svg" alt="How it works" width="100%">
</p>

## Qué hace

- **Definir un build**: pesos por eco, bonificaciones de calidad/familia/novedad, ranuras bloqueadas, ecos prohibidos.
- **Automatización**: evalúa cada pantalla de elección de eco contra tu build y actúa (banish/reroll/freeze/select) para que no tengas que hacerlo tú.
- **Tuning Advisor**: compara tus umbrales de Banish/Reroll/Freeze con lo que tu build realmente recibe de oferta (no un modelo teórico), sugiere mejores valores y puede ajustarlos automáticamente y de forma gradual con el tiempo.
- **Reparto de presupuesto durante toda la partida**: los umbrales se vuelven automáticamente más estrictos a medida que se agotan las cargas de Banish/Reroll/Freeze, para que no gastes tus últimas cargas en ofertas dudosas.
- **Seguimiento de DPS y tasa de aparición**: con Details! instalado, rastrea el DPS real por eco activo; siempre rastrea con qué frecuencia aparece cada eco en una pantalla de elección. Ambos se pueden sincronizar opcionalmente con otros jugadores de la misma clase.
- **Manual Training Mode**: suspende la automatización de un build, elige manualmente, y EbonBuilds aprende de tus elecciones, generando sugerencias de peso a partir de lo que realmente preferiste.
- **Sugerencias de peso y bonificación**: los datos de DPS y las elecciones manuales alimentan sugerencias de peso por eco, y (de forma experimental) sugerencias de bonificación de Calidad/Familia.
- **Export (AI)**: un volcado completo en texto plano de la configuración del build, todos los ecos disponibles para tu clase con descripciones reales de efecto, y todos los datos de ajuste — pensado para pegarlo en un chat de IA para su análisis.
- **Tome Atlas**: ubicaciones de drop de tomos de eco, recopiladas por la comunidad.
- **Public Builds**: explora e importa builds compartidos por otros jugadores.

Consulta [`FAQ.md`](FAQ.md) para explicaciones detalladas de cada función y el historial completo de versiones.

## Capturas de pantalla

El recorrido sigue el flujo real: configura un build, deja que Autopilot lo juegue y aprende de los datos.

### 1 · Configurar el build

<img src="assets/screenshots/editor-priorities.png" alt="editor-priorities" width="100%">

*Prioridades de eco: valores por rango, políticas y puntuaciones finales.*

<img src="assets/screenshots/editor-modifiers.png" alt="editor-modifiers" width="100%">

*Modificadores: estrategia de rango, énfasis de rol, bonificación de eco único.*

<img src="assets/screenshots/editor-autopilot.png" alt="editor-autopilot" width="100%">

*Autopilot: elige una intención y ajusta los umbrales.*

### 2 · La pestaña Personaje

<img src="assets/screenshots/character-overview.png" alt="character-overview" width="100%">

*Instantánea del personaje: talentos, glifos y equipo.*

<img src="assets/screenshots/character-talents.png" alt="character-talents" width="100%">

*Árboles de talentos completos con la asignación de la instantánea.*

<img src="assets/screenshots/character-gear.png" alt="character-gear" width="100%">

*Equipo con afijos por ranura y puntuaciones modeladas.*

### 3 · Ejecutarlo

<img src="assets/screenshots/build-overview.png" alt="build-overview" width="100%">

*La vista general del build: ecos bloqueados, compartir, exportar.*

<img src="assets/screenshots/logbook.png" alt="logbook" width="100%">

*El registro: cada decisión con su razonamiento y alternativa.*

### 4 · Aprender de los datos

<img src="assets/screenshots/stats-summary.png" alt="stats-summary" width="100%">

*Resumen estadístico de las partidas registradas.*

<img src="assets/screenshots/stats-actions.png" alt="stats-actions" width="100%">

*Cómo se usaron realmente las cuatro acciones.*

<img src="assets/screenshots/stats-recommendations.png" alt="stats-recommendations" width="100%">

*Recomendaciones basadas en evidencia, con confianza y enlaces.*

<img src="assets/screenshots/missing-echoes.png" alt="missing-echoes" width="100%">

*Ecos ponderados que faltan y dónde se consiguen.*

## Instalación

La raíz de este repositorio *es* la carpeta del addon (`EbonBuilds.toc`, `core/`, `modules/` están en el nivel superior, no dentro de una subcarpeta).

**Vía Git:**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Vía descarga de ZIP:** el "Download ZIP" de GitHub nombra la carpeta extraída según la rama (p. ej. `EbonBuilds-main`) — renómbrala exactamente a `EbonBuilds` antes de colocarla en `Interface/AddOns/`, para que el nombre de la carpeta coincida con `EbonBuilds.toc`.

Luego reinicia el juego o haz `/reload`.

## Comandos

Solo `/ebb` (o `/ebonbuilds`): abre o cierra la ventana principal. Todo lo que antes era un comando aparte ahora está en el icono de engranaje (Ajustes) en la cabecera de la ventana, todo en un solo lugar en vez de subcomandos que memorizar: idioma, venta automática, puntos de afijo en las bolsas, registro de depuración, Click Trace, los registros de depuración/errores/Click Trace, el Tuning Advisor, el Tome Atlas, la referencia de afijos, la guía de comandos, y la exportación EWL y el reinicio del Manual Training del build activo.

## Reportar errores

Adjunta la salida del registro de errores o del registro de depuración (Ajustes — icono de engranaje — Windows & Tools) a tu reporte: es la forma más rápida de que algo se arregle en lugar de adivinarse.

## Desarrollo

- Lua puro, API de WotLK 3.3.5a (Interface 30300).
- `luac5.1 -p` se usa para comprobar la sintaxis de cada archivo antes de cada versión; consulta `.github/workflows/lua-syntax.yml` para la misma comprobación ejecutándose en CI.
- Sin paso de compilación — la raíz del repositorio *es* la estructura de carpeta del addon que espera `Interface/AddOns/`.
