local addonName, EbonBuilds = ...

-- EbonBuilds: modules/i18n/locales/ptBR.lua
-- Brazilian Portuguese translation. "build" and "echo" stay as loanwords,
-- automation actions (Banish/Reroll/Freeze/Select) and Autopilot stay in
-- English, matching the existing README.pt-BR.md convention.

EbonBuilds.Locale.Register("ptBR", {
    -- Build editor tabs
    ["Build"] = "Build",
    ["Priorities"] = "Prioridades",
    ["Modifiers"] = "Modificadores",
    ["Autopilot"] = "Autopilot",
    ["Identity, class, locked Echoes, and sharing."] = "Identidade, classe, echoes travados e compartilhamento.",
    ["Set rank-specific Echo values and protect must-keep Echoes."] = "Defina valores de echo por rank e proteja echoes indispensáveis.",
    ["Adjust rank, family, and unique-Echo strategy."] = "Ajuste a estratégia de rank, família e echo único.",
    ["Choose an automation intent and tune its decisions."] = "Escolha uma intenção de automação e ajuste suas decisões.",

    -- Build editor bottom bar
    ["Save build"] = "Salvar build",
    ["Validate active fields and save build details, Echo values, bonuses, and visibility."] =
        "Valida os campos ativos e salva os detalhes do build, valores de echo, bônus e visibilidade.",
    ["Cancel"] = "Cancelar",
    ["Cancel editing"] = "Cancelar edição",
    ["Discard all unsaved build details, Echo values, modifiers, protection rules, and Autopilot tuning."] =
        "Descarta todos os detalhes do build não salvos, valores de echo, modificadores, regras de proteção e ajustes do Autopilot.",
    ["Export"] = "Exportar",
    ["Export build"] = "Exportar build",
    ["Create a compact string that another EbonBuilds user can import."] =
        "Cria uma string compacta que outro usuário do EbonBuilds pode importar.",
    ["AI report"] = "Relatório de IA",
    ["AI tuning report"] = "Relatório de ajuste para IA",
    ["Create a readable report of weights, bonuses, thresholds, and tuning data for analysis. It cannot be imported back."] =
        "Cria um relatório legível de pesos, bônus, limites e dados de ajuste para análise. Não pode ser reimportado.",
    ["Unsaved changes"] = "Alterações não salvas",
    ["All changes saved"] = "Todas as alterações salvas",
    [" · Autopilot uses last saved settings"] = " · Autopilot usa as últimas configurações salvas",

    -- /ebb locale command
    ["Character"] = "Personagem",
    ["Live gear, full talent trees, and glyphs; adopt them into the build."] = "Equipamento atual, árvores de talentos completas e glifos; adote-os no build.",
})
