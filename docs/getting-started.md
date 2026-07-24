# Getting Started

<p class="ebb-lead">
Install EbonBuilds, create your first build, and turn on Autopilot in a few minutes.
</p>

!!! info "Download"
    Grab the latest **`EbonBuilds.zip`** from the
    [releases page](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest)
    before you start.

## Install

1. Download the latest `EbonBuilds.zip` from the [releases page](https://github.com/Lzra2000/ProjectEbonHoldBuildAutomation/releases/latest).
2. Extract it and put the `EbonBuilds` folder into `Interface/AddOns/`.
3. Restart the game or `/reload`.

Requires **ProjectEbonhold** or **ProjectEbonhold Enhanced**. Some features additionally use **Details!** if installed.

## First login

A one-time panel greets you after logging in. It asks the DPS-tracking consent question (tracking and community sharing are off until you say otherwise -- either answer is one checkbox in Settings if you change your mind), and offers What's new and the in-game guide. It shows once per addon version, then stays out of the way.

## Your first build

1. `/ebb` opens the main window. Click **+ New Build**.
2. On the **Build** tab set title, class, and spec. On **Priorities**, give the Echoes you care about rank values -- everything else can stay 0 to start.

    <img src="https://raw.githubusercontent.com/Lzra2000/ProjectEbonHoldBuildAutomation/main/assets/screenshots/editor-priorities.png" alt="Echo priorities editor" width="100%">
3. **Autopilot** tab: pick an intent (Save charges / Balanced / Chase upgrades) rather than tuning thresholds by hand -- the intent presets are the dependable starting point.

    <img src="https://raw.githubusercontent.com/Lzra2000/ProjectEbonHoldBuildAutomation/main/assets/screenshots/editor-autopilot.png" alt="Autopilot intent and thresholds" width="100%">
4. Save, then enable Autopilot from the build overview. From here every echo choice screen is scored and acted on for you, and every decision lands in the **Logbook** with its reasoning.

    <img src="https://raw.githubusercontent.com/Lzra2000/ProjectEbonHoldBuildAutomation/main/assets/screenshots/build-overview.png" alt="Build overview with Autopilot toggle" width="100%">

    <img src="https://raw.githubusercontent.com/Lzra2000/ProjectEbonHoldBuildAutomation/main/assets/screenshots/logbook.png" alt="Logbook: every decision with its reasoning" width="100%">

## Let the data teach it

With Details! installed and tracking consented, the **Stats** views accumulate evidence across runs, and **Recommendations** proposes specific weight changes -- each with its confidence and a link to the exact decisions behind it. Nothing applies itself; you review and apply.

<img src="https://raw.githubusercontent.com/Lzra2000/ProjectEbonHoldBuildAutomation/main/assets/screenshots/stats-recommendations.png" alt="Evidence-backed recommendations" width="100%">
