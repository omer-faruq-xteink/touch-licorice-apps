--[[
    slidepuzzle_i18n.lua
    Lightweight, self-contained translation table for the Slide puzzle
    plugin. We keep our own strings (instead of relying on KOReader's
    gettext catalog) so the plugin can ship with translations without
    needing to ship a .po/.mo file.

    To add a new language:
      1. Add an entry to `M.SUPPORTED` below with the locale code and a
         human-readable native name.
      2. Add a translation table for that code under `translations`,
         providing a value for every English key already present in the
         "en" reference table at the top.
      3. Reload the plugin (or restart KOReader). The new language will
         show up under "Settings → Language".

    Notes:
      - Keys are the English source strings used throughout the plugin.
      - When a key has no translation in the active language we fall
         back to the English source string, so partial translations are
         safe.
      - For shorter strings used as table column headers in the Stats
         dialog (e.g. "Size", "Time", "Moves", "Plays"), translators
         should prefer compact words/abbreviations to keep the columns
         aligned in monospace.
--]]

local M = {}

-- List of available choices in the Language sub-menu. The first entry
-- is always the magic "default" value which means "follow KOReader's
-- UI language if it is supported, otherwise English".
M.LANGS = {
    { code = "default", name = "Default" },
    { code = "en",      name = "English" },
    { code = "pt",      name = "Português" },
    { code = "es",      name = "Español" },
    { code = "fr",      name = "Français" },
    { code = "de",      name = "Deutsch" },
    { code = "ko",      name = "한국어" },
    { code = "tr",      name = "Türkçe" },
}

-- Quick lookup of which short locale codes we ship a translation for.
local SUPPORTED = {
    en = true, pt = true, es = true, fr = true,
    de = true, ko = true, tr = true,
}

-- Reference English strings. Other languages translate against these
-- exact keys; missing keys simply fall through to English.
local en = {
    -- Menu
    ["Slide puzzle"] = "Slide puzzle",
    ["Play"] = "Play",
    ["Settings"] = "Settings",
    ["Always start a new puzzle on open"] = "Always start a new puzzle on open",
    ["Reset best results"] = "Reset best results",
    ["Reset all best results?"] = "Reset all best results?",
    ["Reset"] = "Reset",
    ["Best results cleared."] = "Best results cleared.",
    ["Font"] = "Font",
    ["Font size"] = "Font size",
    ["Font size: %1"] = "Font size: %1",
    ["Auto"] = "Auto",
    ["OK"] = "OK",
    ["Language"] = "Language",
    ["Default"] = "Default",
    ["Select font"] = "Select font",
    -- Header / messages
    ["%1x%1 Puzzle    Moves: %2    Time: %3"] = "%1x%1 Puzzle    Moves: %2    Time: %3",
    ["Best: %1    Fewest moves: %2"] = "Best: %1    Fewest moves: %2",
    ["Best: not set yet"] = "Best: not set yet",
    ["Solved! Tap \"New\" to play again."] = "Solved! Tap \"New\" to play again.",
    ["Tap a tile next to the gap, or swipe to slide."] = "Tap a tile next to the gap, or swipe to slide.",
    ["Solved in %1 moves and %2."] = "Solved in %1 moves and %2.",
    ["Only tiles next to the gap can move."] = "Only tiles next to the gap can move.",
    ["New puzzle — good luck!"] = "New puzzle — good luck!",
    ["You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3"] = "You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3",
    -- Buttons
    ["New"] = "New",
    ["Size"] = "Size",
    ["Stats"] = "Stats",
    ["Close"] = "Close",
    ["Cancel"] = "Cancel",
    ["Select board size"] = "Select board size",
    ["%1 × %1"] = "%1 × %1",
    -- Stats dialog
    ["Records:"] = "Records:",
    ["No games played yet."] = "No games played yet.",
    ["col_size"] = "Size",
    ["col_time"] = "Time",
    ["col_moves"] = "Moves",
    ["col_plays"] = "Plays",
}

local pt = {
    ["Slide puzzle"] = "Quebra-cabeças deslizante",
    ["Play"] = "Jogar",
    ["Settings"] = "Configurações",
    ["Always start a new puzzle on open"] = "Sempre iniciar novo ao abrir",
    ["Reset best results"] = "Redefinir melhores resultados",
    ["Reset all best results?"] = "Redefinir todos os melhores resultados?",
    ["Reset"] = "Redefinir",
    ["Best results cleared."] = "Melhores resultados apagados.",
    ["Font"] = "Fonte",
    ["Font size"] = "Tamanho da fonte",
    ["Font size: %1"] = "Tamanho da fonte: %1",
    ["Auto"] = "Auto",
    ["OK"] = "OK",
    ["Language"] = "Idioma",
    ["Default"] = "Padrão",
    ["Select font"] = "Selecionar fonte",
    ["%1x%1 Puzzle    Moves: %2    Time: %3"] = "Quebra %1x%1    Mov.: %2    Tempo: %3",
    ["Best: %1    Fewest moves: %2"] = "Melhor: %1    Menos movimentos: %2",
    ["Best: not set yet"] = "Melhor: ainda não definido",
    ["Solved! Tap \"New\" to play again."] = "Resolvido! Toque em \"Novo\" para jogar de novo.",
    ["Tap a tile next to the gap, or swipe to slide."] = "Toque numa peça ao lado do espaço ou deslize.",
    ["Solved in %1 moves and %2."] = "Resolvido em %1 movimentos e %2.",
    ["Only tiles next to the gap can move."] = "Só peças ao lado do espaço podem mover.",
    ["New puzzle — good luck!"] = "Novo quebra-cabeça — boa sorte!",
    ["You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3"] = "Você resolveu o quebra-cabeça %1x%1!\nMovimentos: %2\nTempo: %3",
    ["New"] = "Novo",
    ["Size"] = "Tamanho",
    ["Stats"] = "Recordes",
    ["Close"] = "Fechar",
    ["Cancel"] = "Cancelar",
    ["Select board size"] = "Escolha o tamanho do tabuleiro",
    ["%1 × %1"] = "%1 × %1",
    ["Records:"] = "Recordes:",
    ["No games played yet."] = "Nenhum jogo registrado ainda.",
    ["col_size"] = "Tam.",
    ["col_time"] = "Tempo",
    ["col_moves"] = "Mov.",
    ["col_plays"] = "Jogos",
}

local es = {
    ["Slide puzzle"] = "Rompecabezas deslizante",
    ["Play"] = "Jugar",
    ["Settings"] = "Ajustes",
    ["Always start a new puzzle on open"] = "Empezar siempre nuevo al abrir",
    ["Reset best results"] = "Restablecer mejores resultados",
    ["Reset all best results?"] = "¿Restablecer todos los mejores resultados?",
    ["Reset"] = "Restablecer",
    ["Best results cleared."] = "Mejores resultados borrados.",
    ["Font"] = "Fuente",
    ["Font size"] = "Tamaño de fuente",
    ["Font size: %1"] = "Tamaño de fuente: %1",
    ["Auto"] = "Auto",
    ["OK"] = "OK",
    ["Language"] = "Idioma",
    ["Default"] = "Predeterminado",
    ["Select font"] = "Seleccionar fuente",
    ["%1x%1 Puzzle    Moves: %2    Time: %3"] = "Puzzle %1x%1    Mov.: %2    Tiempo: %3",
    ["Best: %1    Fewest moves: %2"] = "Mejor: %1    Menos movimientos: %2",
    ["Best: not set yet"] = "Mejor: aún no establecido",
    ["Solved! Tap \"New\" to play again."] = "¡Resuelto! Toca \"Nuevo\" para jugar otra vez.",
    ["Tap a tile next to the gap, or swipe to slide."] = "Toca una pieza junto al hueco o desliza.",
    ["Solved in %1 moves and %2."] = "Resuelto en %1 movimientos y %2.",
    ["Only tiles next to the gap can move."] = "Solo se mueven las piezas junto al hueco.",
    ["New puzzle — good luck!"] = "¡Nuevo rompecabezas — suerte!",
    ["You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3"] = "¡Resolviste el rompecabezas %1x%1!\nMovimientos: %2\nTiempo: %3",
    ["New"] = "Nuevo",
    ["Size"] = "Tamaño",
    ["Stats"] = "Récords",
    ["Close"] = "Cerrar",
    ["Cancel"] = "Cancelar",
    ["Select board size"] = "Selecciona el tamaño del tablero",
    ["%1 × %1"] = "%1 × %1",
    ["Records:"] = "Récords:",
    ["No games played yet."] = "Aún no hay partidas jugadas.",
    ["col_size"] = "Tam.",
    ["col_time"] = "Tiempo",
    ["col_moves"] = "Mov.",
    ["col_plays"] = "Partidas",
}

local fr = {
    ["Slide puzzle"] = "Taquin",
    ["Play"] = "Jouer",
    ["Settings"] = "Paramètres",
    ["Always start a new puzzle on open"] = "Toujours commencer un nouveau taquin",
    ["Reset best results"] = "Réinitialiser les meilleurs résultats",
    ["Reset all best results?"] = "Réinitialiser tous les meilleurs résultats ?",
    ["Reset"] = "Réinitialiser",
    ["Best results cleared."] = "Meilleurs résultats effacés.",
    ["Font"] = "Police",
    ["Font size"] = "Taille de police",
    ["Font size: %1"] = "Taille de police : %1",
    ["Auto"] = "Auto",
    ["OK"] = "OK",
    ["Language"] = "Langue",
    ["Default"] = "Par défaut",
    ["Select font"] = "Choisir la police",
    ["%1x%1 Puzzle    Moves: %2    Time: %3"] = "Taquin %1x%1    Coups : %2    Temps : %3",
    ["Best: %1    Fewest moves: %2"] = "Meilleur : %1    Moins de coups : %2",
    ["Best: not set yet"] = "Meilleur : non défini",
    ["Solved! Tap \"New\" to play again."] = "Résolu ! Touchez « Nouveau » pour rejouer.",
    ["Tap a tile next to the gap, or swipe to slide."] = "Touchez une pièce près du vide ou glissez.",
    ["Solved in %1 moves and %2."] = "Résolu en %1 coups et %2.",
    ["Only tiles next to the gap can move."] = "Seules les pièces près du vide bougent.",
    ["New puzzle — good luck!"] = "Nouveau taquin — bonne chance !",
    ["You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3"] = "Taquin %1x%1 résolu !\nCoups : %2\nTemps : %3",
    ["New"] = "Nouveau",
    ["Size"] = "Taille",
    ["Stats"] = "Records",
    ["Close"] = "Fermer",
    ["Cancel"] = "Annuler",
    ["Select board size"] = "Choisir la taille du plateau",
    ["%1 × %1"] = "%1 × %1",
    ["Records:"] = "Records :",
    ["No games played yet."] = "Aucune partie jouée pour l'instant.",
    ["col_size"] = "Taille",
    ["col_time"] = "Temps",
    ["col_moves"] = "Coups",
    ["col_plays"] = "Parties",
}

local de = {
    ["Slide puzzle"] = "Schiebepuzzle",
    ["Play"] = "Spielen",
    ["Settings"] = "Einstellungen",
    ["Always start a new puzzle on open"] = "Beim Öffnen immer neu starten",
    ["Reset best results"] = "Bestleistungen zurücksetzen",
    ["Reset all best results?"] = "Alle Bestleistungen zurücksetzen?",
    ["Reset"] = "Zurücksetzen",
    ["Best results cleared."] = "Bestleistungen gelöscht.",
    ["Font"] = "Schrift",
    ["Font size"] = "Schriftgröße",
    ["Font size: %1"] = "Schriftgröße: %1",
    ["Auto"] = "Auto",
    ["OK"] = "OK",
    ["Language"] = "Sprache",
    ["Default"] = "Standard",
    ["Select font"] = "Schrift auswählen",
    ["%1x%1 Puzzle    Moves: %2    Time: %3"] = "%1x%1-Puzzle    Züge: %2    Zeit: %3",
    ["Best: %1    Fewest moves: %2"] = "Beste Zeit: %1    Wenigste Züge: %2",
    ["Best: not set yet"] = "Beste: noch keine",
    ["Solved! Tap \"New\" to play again."] = "Gelöst! Tippe „Neu\", um erneut zu spielen.",
    ["Tap a tile next to the gap, or swipe to slide."] = "Tippe eine Kachel am Loch an oder wische.",
    ["Solved in %1 moves and %2."] = "Gelöst in %1 Zügen und %2.",
    ["Only tiles next to the gap can move."] = "Nur Kacheln neben dem Loch bewegen sich.",
    ["New puzzle — good luck!"] = "Neues Puzzle — viel Glück!",
    ["You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3"] = "Du hast das %1x%1-Puzzle gelöst!\nZüge: %2\nZeit: %3",
    ["New"] = "Neu",
    ["Size"] = "Größe",
    ["Stats"] = "Rekorde",
    ["Close"] = "Schließen",
    ["Cancel"] = "Abbrechen",
    ["Select board size"] = "Spielfeldgröße wählen",
    ["%1 × %1"] = "%1 × %1",
    ["Records:"] = "Rekorde:",
    ["No games played yet."] = "Noch keine Spiele gespielt.",
    ["col_size"] = "Größe",
    ["col_time"] = "Zeit",
    ["col_moves"] = "Züge",
    ["col_plays"] = "Spiele",
}

local ko = {
    ["Slide puzzle"] = "슬라이드 퍼즐",
    ["Play"] = "플레이",
    ["Settings"] = "설정",
    ["Always start a new puzzle on open"] = "열 때 항상 새로 시작",
    ["Reset best results"] = "최고 기록 초기화",
    ["Reset all best results?"] = "모든 최고 기록을 초기화할까요?",
    ["Reset"] = "초기화",
    ["Best results cleared."] = "최고 기록을 지웠습니다.",
    ["Font"] = "글꼴",
    ["Font size"] = "글꼴 크기",
    ["Font size: %1"] = "글꼴 크기: %1",
    ["Auto"] = "자동",
    ["OK"] = "확인",
    ["Language"] = "언어",
    ["Default"] = "기본",
    ["Select font"] = "글꼴 선택",
    ["%1x%1 Puzzle    Moves: %2    Time: %3"] = "%1x%1 퍼즐    이동: %2    시간: %3",
    ["Best: %1    Fewest moves: %2"] = "최고: %1    최소 이동: %2",
    ["Best: not set yet"] = "최고: 아직 없음",
    ["Solved! Tap \"New\" to play again."] = "완성! \"새로\"를 눌러 다시 시작하세요.",
    ["Tap a tile next to the gap, or swipe to slide."] = "빈칸 옆 조각을 누르거나 쓸어주세요.",
    ["Solved in %1 moves and %2."] = "%1번의 이동과 %2 만에 완성.",
    ["Only tiles next to the gap can move."] = "빈칸 옆 조각만 움직일 수 있습니다.",
    ["New puzzle — good luck!"] = "새 퍼즐 — 행운을!",
    ["You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3"] = "%1x%1 퍼즐을 풀었습니다!\n이동: %2\n시간: %3",
    ["New"] = "새로",
    ["Size"] = "크기",
    ["Stats"] = "기록",
    ["Close"] = "닫기",
    ["Cancel"] = "취소",
    ["Select board size"] = "보드 크기 선택",
    ["%1 × %1"] = "%1 × %1",
    ["Records:"] = "기록:",
    ["No games played yet."] = "아직 플레이한 게임이 없습니다.",
    ["col_size"] = "크기",
    ["col_time"] = "시간",
    ["col_moves"] = "이동",
    ["col_plays"] = "게임",
}

local tr = {
    ["Slide puzzle"] = "Kaydırmalı bulmaca",
    ["Play"] = "Oyna",
    ["Settings"] = "Ayarlar",
    ["Always start a new puzzle on open"] = "Açılınca her zaman yeni başlat",
    ["Reset best results"] = "En iyi sonuçları sıfırla",
    ["Reset all best results?"] = "Tüm en iyi sonuçlar sıfırlansın mı?",
    ["Reset"] = "Sıfırla",
    ["Best results cleared."] = "En iyi sonuçlar silindi.",
    ["Font"] = "Yazı tipi",
    ["Font size"] = "Yazı boyutu",
    ["Font size: %1"] = "Yazı boyutu: %1",
    ["Auto"] = "Otomatik",
    ["OK"] = "Tamam",
    ["Language"] = "Dil",
    ["Default"] = "Varsayılan",
    ["Select font"] = "Yazı tipi seç",
    ["%1x%1 Puzzle    Moves: %2    Time: %3"] = "%1x%1 Bulmaca    Hamle: %2    Süre: %3",
    ["Best: %1    Fewest moves: %2"] = "En iyi: %1    En az hamle: %2",
    ["Best: not set yet"] = "En iyi: henüz yok",
    ["Solved! Tap \"New\" to play again."] = "Çözüldü! Tekrar oynamak için \"Yeni\"ye dokunun.",
    ["Tap a tile next to the gap, or swipe to slide."] = "Boşluğun yanındaki parçaya dokunun ya da kaydırın.",
    ["Solved in %1 moves and %2."] = "%1 hamle ve %2 sürede çözüldü.",
    ["Only tiles next to the gap can move."] = "Sadece boşluğun yanındaki parçalar oynayabilir.",
    ["New puzzle — good luck!"] = "Yeni bulmaca — bol şans!",
    ["You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3"] = "%1x%1 bulmacayı çözdünüz!\nHamle: %2\nSüre: %3",
    ["New"] = "Yeni",
    ["Size"] = "Boyut",
    ["Stats"] = "Rekorlar",
    ["Close"] = "Kapat",
    ["Cancel"] = "İptal",
    ["Select board size"] = "Tahta boyutunu seçin",
    ["%1 × %1"] = "%1 × %1",
    ["Records:"] = "Rekorlar:",
    ["No games played yet."] = "Henüz hiç oyun oynanmadı.",
    ["col_size"] = "Boyut",
    ["col_time"] = "Süre",
    ["col_moves"] = "Hamle",
    ["col_plays"] = "Oyun",
}

local translations = {
    en = en,
    pt = pt,
    es = es,
    fr = fr,
    de = de,
    ko = ko,
    tr = tr,
}

-- Active locale code, set via M.setActive(). Defaults to English so
-- t() works even before the plugin has wired up the user's choice.
M.active = "en"

-- Auto-detect: pick the supported language that matches KOReader's UI
-- language (matching by short locale prefix), falling back to English.
function M.detectAuto()
    local lang
    if rawget(_G, "G_reader_settings") then
        lang = G_reader_settings:readSetting("language")
    end
    if type(lang) ~= "string" or lang == "" then
        return "en"
    end
    local short = lang:match("^([^_%-]+)")
    if short then short = short:lower() end
    if short and SUPPORTED[short] then
        return short
    end
    return "en"
end

-- Resolve a stored choice (which may be "default", an empty value, or a
-- supported locale code) into the actual locale code we should use.
function M.resolveChoice(stored_choice)
    if stored_choice == nil or stored_choice == "" or stored_choice == "default" then
        return M.detectAuto()
    end
    if SUPPORTED[stored_choice] then
        return stored_choice
    end
    return "en"
end

function M.setActive(stored_choice)
    M.choice = stored_choice or "default"
    M.active = M.resolveChoice(M.choice)
end

function M.getChoice()
    return M.choice or "default"
end

-- Look up a translation for the given English source string.
function M.t(key)
    local tab = translations[M.active]
    if tab then
        local v = tab[key]
        if v then return v end
    end
    -- Always fall through to English source.
    return en[key] or key
end

return M
