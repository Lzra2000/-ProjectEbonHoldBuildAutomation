<p align="center">
  <img src="../../assets/banner.svg" alt="EbonBuilds — Automatisation d'échos pour ProjectEbonhold" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml"><img src="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/actions/workflows/lua-syntax.yml/badge.svg" alt="Vérifications CI"></a>
  <a href="https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest"><img src="https://img.shields.io/github/v/release/Lzra2000/ProjectEbonHoldBuildAutomation?label=release&color=2a6e5a" alt="Dernière version"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-EbonBuilds%20License-4a5568" alt="Licence"></a>
  <img src="https://img.shields.io/badge/WoW-3.3.5a%20(12340)-4a7ab5" alt="WoW 3.3.5a">
</p>

<p align="center">
  <a href="../../README.md">English</a> | <a href="README.de.md">Deutsch</a> | <a href="README.ru.md">Русский</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.es.md">Español</a> | <b>Français</b> | <a href="README.pl.md">Polski</a>
</p>

**EbonBuilds** est un addon client World of Warcraft **3.3.5a** pour les joueurs sur les serveurs privés **[ProjectEbonhold](https://github.com/Lzra2000/ProjectEbonhold)**. Vous définissez un build — poids d'écho, politiques et intention d'autopilot — et EbonBuilds évalue chaque écran de choix d'écho (Banish / Reroll / Freeze / Select) à votre place, enregistre ce qui s'est passé et transforme les données réelles de run en suggestions de réglage consultables.

Conçu pour les raiders et farmers d'échos ProjectEbonhold qui veulent une automatisation cohérente sans abandonner le contrôle : chaque action est journalisée, les recommandations nécessitent votre approbation, et le Manual Training Mode permet à l'addon d'apprendre de vos choix délibérés.

## Installation rapide

1. Téléchargez **`EbonBuilds.zip`** depuis la [dernière version](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest).
2. Extrayez l'archive. Le dossier doit s'appeler **`EbonBuilds`** (correspondant à `EbonBuilds.toc`).
3. Copiez-le dans `World of Warcraft/Interface/AddOns/`.
4. Redémarrez le jeu ou exécutez `/reload`.

**Alternative via Git :**
```
cd "World of Warcraft/Interface/AddOns"
git clone https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation.git EbonBuilds
```

**Prérequis serveur :** ProjectEbonhold fournit son propre addon serveur. Installez **ProjectEbonhold** ou **ProjectEbonhold Enhanced** sur le client comme indiqué par votre serveur — EbonBuilds en dépend pour les tableaux d'échos, les données d'affixes et plusieurs fonctionnalités d'intégration. Sans lui, EbonBuilds ne fonctionnera pas.

**Optionnel :** **[Details!](https://www.curseforge.com/wow/addons/details)** active les suggestions de poids basées sur le DPS et des statistiques plus riches. L'enregistrement du DPS en combat dans le Logbook (v3.84+) fonctionne sans Details! lorsqu'il est activé dans les Paramètres.

Ouvrez l'addon avec **`/ebb`** ou **`/ebonbuilds`**.

## Fonctionnalités

| Domaine | Ce que vous obtenez |
| --- | --- |
| **Autopilot** | Préréglages d'intention (Save charges / Balanced / Chase upgrades), scoring par écho, suivi de freeze persistant sur la run et un **Logbook** centré sur les décisions avec raisonnement et usage des charges. |
| **Builds** | Poids par écho (y compris par rang de qualité), emplacements verrouillés/bannis, instantanés de personnage (talents, glyphes, équipement), Tuning Advisor, Manual Training Mode, export EchoWishlist (`EWL1`) et dumps **Export (AI)** en texte brut. |
| **Public Builds** | Parcourez les builds communautaires, inspectez priorités et instantanés, votez, importez et (si le serveur le prend en charge) enregistrez ou appliquez des **server loadouts**. |
| **Affixes** | Panneau de référence des affixes, points d'affixe sur les sacs (sacs par défaut, Bagnon, Combuctor) et modélisation d'équipement dans l'onglet Personnage. |
| **DPS & statistiques** | Échantillons de DPS en combat optionnels attachés aux runs et visibles dans le Logbook ; suivi DPS via Details! et sync du taux d'apparition si installé et consenti. Espace statistiques avec Summary, Actions, Echoes et Recommendations fondées sur des preuves. |
| **Locales** | UI de l'éditeur de build en allemand, espagnol, français, polonais, portugais brésilien et russe — détectée automatiquement depuis le client ou modifiable via les Paramètres. |

Autres outils notables : **Tome Atlas** (emplacements de drop communautaires), **Missing Echoes** (échos pondérés que vous n'avez pas encore appris), **budget pacing** sur toute la run et auto-vente optionnelle chez le vendeur.

<p align="center">
  <img src="../../assets/how-it-works.svg" alt="Définir un build, Autopilot agit sur les écrans de choix, les données sont suivies, le Tuning Advisor suggère des ajustements, et la boucle recommence" width="100%">
</p>

## Captures d'écran

| Éditeur de build — priorités | Vue d'ensemble du build & Autopilot |
| --- | --- |
| <img src="../../assets/screenshots/editor-priorities.png" alt="Éditeur de priorités d'écho" width="100%"> | <img src="../../assets/screenshots/build-overview.png" alt="Vue d'ensemble du build" width="100%"> |

| Logbook | Statistiques — recommandations |
| --- | --- |
| <img src="../../assets/screenshots/logbook.png" alt="Logbook de décisions" width="100%"> | <img src="../../assets/screenshots/stats-recommendations.png" alt="Recommandations fondées sur des preuves" width="100%"> |

Plus de captures et une visite complète de l'UI se trouvent dans [`assets/screenshots/`](../../assets/screenshots/) et sur le [site de documentation](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/getting-started/).

## Documentation & support

| Ressource | Lien |
| --- | --- |
| Documentation (Premiers pas, Paramètres, FAQ) | [lzra2000.github.io/ProjectEbonHoldBuildAutomation](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/) |
| FAQ | [FAQ](https://lzra2000.github.io/ProjectEbonHoldBuildAutomation/faq/) |
| Versions & changelog | [Releases](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases) · [`CHANGELOG.md`](../../CHANGELOG.md) |
| Rapports de bugs & demandes de fonctionnalités | [Issues](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/issues) |
| Sécurité | [`SECURITY.md`](../../SECURITY.md) |

Lors du signalement de bugs, joignez la sortie de **Paramètres → Windows & tools → Error log** ou **Debug log** — c'est le chemin le plus rapide vers une correction.

## Développement

Les contributions sont les bienvenues. Consultez [`CONTRIBUTING.md`](../../CONTRIBUTING.md) pour la configuration, les conventions et la checklist pré-PR.

Pour les vérifications locales, la parité CI et le débogage des exécutions Actions en échec, consultez **[`docs/dev-testing.md`](../../docs/dev-testing.md)**. Points d'entrée rapides :

```sh
sh scripts/dev-setup.sh    # toolchain unique (Debian/Ubuntu ; utilisez WSL sous Windows)
sh scripts/check.sh        # boucle locale rapide (syntaxe, tests, .toc, lint API 3.3.5a)
sh scripts/check.sh --full # suite complète exécutée par CI avant merge
sh scripts/build-dist.sh   # produit dist/EbonBuilds.zip
```

La racine du dépôt est le dossier de l'addon (`EbonBuilds.toc`, `core/`, `modules/` au niveau supérieur). Les tags de release déclenchent [`.github/workflows/release.yml`](../../.github/workflows/release.yml), qui publie `EbonBuilds.zip` sur GitHub Releases.

## Licence

Consultez [`LICENSE`](../../LICENSE). L'usage personnel et en communauté de serveurs privés est autorisé pour les releases officielles non modifiées. La redistribution de versions modifiées sous le nom EbonBuilds, ou l'usage commercial, nécessite l'autorisation préalable du titulaire des droits.
