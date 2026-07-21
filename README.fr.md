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
  <a href="README.md">English</a> | <a href="README.de.md">Deutsch</a> | <a href="README.ru.md">Русский</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.es.md">Español</a> | <b>Français</b> | <a href="README.pl.md">Polski</a>
</p>

Un addon World of Warcraft (3.3.5a) pour **ProjectEbonhold** qui automatise les choix d'écho (Banish / Reroll / Freeze / Select) en fonction d'un build que vous définissez, et qui s'auto-ajuste au fil du temps à partir de données de jeu réelles.

Nécessite **ProjectEbonhold** ou **ProjectEbonhold Enhanced**. Certaines fonctionnalités utilisent en plus **[Details!](https://www.curseforge.com/wow/addons/details)** si installé.


<p align="center">
  <img src="assets/how-it-works.svg" alt="How it works" width="100%">
</p>

## Ce qu'il fait

- **Définir un build** : poids par écho, bonus de qualité/famille/nouveauté, emplacements verrouillés, échos bannis.
- **Automatisation** : évalue chaque écran de choix d'écho par rapport à votre build et agit (banish/reroll/freeze/select) à votre place.
- **Tuning Advisor** : compare vos seuils de Banish/Reroll/Freeze à ce que votre build reçoit réellement en offre (pas un modèle théorique), suggère de meilleures valeurs et peut les ajuster automatiquement et progressivement au fil du temps.
- **Répartition du budget sur toute la run** : les seuils deviennent automatiquement plus stricts à mesure que les charges de Banish/Reroll/Freeze diminuent, pour éviter de gaspiller vos dernières charges sur des offres limites.
- **Suivi du DPS et du taux d'apparition** : avec Details! installé, suit le DPS réel par écho actif ; suit toujours la fréquence à laquelle chaque écho apparaît réellement sur un écran de choix. Les deux peuvent être synchronisés en option avec d'autres joueurs de la même classe.
- **Manual Training Mode** : suspendez l'automatisation d'un build, choisissez manuellement, et EbonBuilds apprend de vos choix, générant des suggestions de poids à partir de ce que vous avez réellement préféré.
- **Suggestions de poids et de bonus** : les données de DPS et les choix manuels alimentent tous deux des suggestions de poids par écho, ainsi que (de façon expérimentale) des suggestions de bonus de Qualité/Famille.
- **Export (AI)** : un export complet en texte brut des paramètres du build, de tous les échos disponibles pour votre classe avec de vraies descriptions d'effet, et de toutes les données de réglage — destiné à être collé dans un chat IA pour analyse.
- **Tome Atlas** : emplacements de drop des tomes d'écho, recueillis par la communauté.
- **Public Builds** : parcourez et importez des builds partagés par d'autres joueurs.

Voir [`FAQ.md`](FAQ.md) pour des explications détaillées de chaque fonctionnalité et l'historique complet des versions.

## Captures d'écran

La visite suit le déroulement réel : configurez un build, laissez Autopilot le jouer, puis apprenez des données.

### 1 · Configurer le build

<img src="assets/screenshots/editor-priorities.png" alt="editor-priorities" width="100%">

*Priorités d'écho : valeurs par rang, politiques et scores finaux.*

<img src="assets/screenshots/editor-modifiers.png" alt="editor-modifiers" width="100%">

*Modificateurs : stratégie de rang, accent de rôle, bonus d'écho unique.*

<img src="assets/screenshots/editor-autopilot.png" alt="editor-autopilot" width="100%">

*Autopilot : choisissez une intention, ajustez les seuils.*

### 2 · L'onglet Personnage

<img src="assets/screenshots/character-overview.png" alt="character-overview" width="100%">

*Instantané du personnage : talents, glyphes et équipement.*

<img src="assets/screenshots/character-talents.png" alt="character-talents" width="100%">

*Arbres de talents complets avec la répartition de l'instantané.*

<img src="assets/screenshots/character-gear.png" alt="character-gear" width="100%">

*Équipement avec affixes par emplacement et scores modélisés.*

### 3 · Le laisser tourner

<img src="assets/screenshots/build-overview.png" alt="build-overview" width="100%">

*La vue d'ensemble du build : échos verrouillés, partage, exports.*

<img src="assets/screenshots/logbook.png" alt="logbook" width="100%">

*Le journal : chaque décision avec sa raison et l'alternative.*

### 4 · Apprendre des données

<img src="assets/screenshots/stats-summary.png" alt="stats-summary" width="100%">

*Résumé statistique des parties enregistrées.*

<img src="assets/screenshots/stats-actions.png" alt="stats-actions" width="100%">

*Comment les quatre actions ont réellement été utilisées.*

<img src="assets/screenshots/stats-recommendations.png" alt="stats-recommendations" width="100%">

*Recommandations fondées sur les données, avec confiance et liens.*

<img src="assets/screenshots/missing-echoes.png" alt="missing-echoes" width="100%">

*Échos pondérés manquants et leurs sources.*

## Installation

La racine de ce dépôt *est* le dossier de l'addon (`EbonBuilds.toc`, `core/`, `modules/` se trouvent au niveau supérieur, pas dans un sous-dossier).

**Via Git :**
```
cd "World of Warcraft/Interface/AddOns"
git clone <this-repo-url> EbonBuilds
```

**Via téléchargement ZIP :** le bouton « Download ZIP » de GitHub nomme le dossier extrait d'après la branche (ex. `EbonBuilds-main`) — renommez-le exactement en `EbonBuilds` avant de le placer dans `Interface/AddOns/`, pour que le nom du dossier corresponde à `EbonBuilds.toc`.

Puis redémarrez le jeu ou faites `/reload`.

## Commandes

Juste `/ebb` (ou `/ebonbuilds`) : ouvre ou ferme la fenêtre principale. Tout ce qui était auparavant une commande séparée se trouve désormais derrière l'icône d'engrenage (Paramètres) dans l'en-tête de la fenêtre, le tout au même endroit plutôt que des sous-commandes à mémoriser : langue, vente automatique, points d'affixe des sacs, journalisation de débogage, Click Trace, les journaux de débogage/erreurs/Click Trace, le Tuning Advisor, le Tome Atlas, la référence des affixes, le guide des commandes, ainsi que l'export EWL et la réinitialisation du Manual Training du build actif.

## Signaler un bug

Joignez la sortie du journal d'erreurs ou du journal de débogage (Paramètres — icône d'engrenage — Windows & Tools) à votre rapport : c'est de loin le moyen le plus rapide pour qu'un problème soit corrigé plutôt que deviné.

## Développement

- Lua pur, API WotLK 3.3.5a (Interface 30300).
- `luac5.1 -p` est utilisé pour vérifier la syntaxe de chaque fichier avant chaque version ; voir `.github/workflows/lua-syntax.yml` pour la même vérification exécutée en CI.
- Aucune étape de build — la racine du dépôt *est* la structure de dossier de l'addon attendue par `Interface/AddOns/`.
