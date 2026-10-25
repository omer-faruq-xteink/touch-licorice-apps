-- merchant_l10n/fr.lua — French. Keys must match the English source exactly.
return {
    -- Menu / general UI
    ["Merchant"] = "Marchand",
    ["Play"] = "Jouer",
    ["Open merchant game"] = "Ouvrir le jeu du marchand",
    ["Theme: %1"] = "Univers : %1",
    ["The new theme starts with your next new game; the current run keeps its theme."]
        = "Le nouvel univers s'applique à la prochaine nouvelle partie ; la partie en cours garde le sien.",
    ["Day %1 / %2          %3"] = "Jour %1 / %2          %3",
    ["Cash %1     Bank %2     Debt %3"] = "Liquide %1     Banque %2     Dette %3",
    ["Health %1     %2 %3     %4 %5/%6"] = "Santé %1     %2 %3     %4 %5/%6",
    ["(none)"] = "(aucun)",
    ["  [you hold %1]"] = "  [vous avez %1]",
    ["Buy"] = "Acheter",
    ["Sell"] = "Vendre",
    ["New game"] = "Nouvelle partie",
    ["Close"] = "Fermer",
    ["Cancel"] = "Annuler",
    ["Stay"] = "Rester",
    ["No thanks"] = "Non merci",
    ["Buy what?"] = "Acheter quoi ?",
    ["Sell what?"] = "Vendre quoi ?",
    ["Buy %1"] = "Acheter : %1",
    ["Sell %1"] = "Vendre : %1",
    ["%1 each · cash %2 · room %3"] = "%1 l'unité · liquide %2 · place %3",
    ["%1 each · you hold %2"] = "%1 l'unité · vous avez %2",
    ["(no buyers)"] = "(pas d'acheteurs)",
    ["Nothing is for sale here."] = "Rien n'est à vendre ici.",
    ["You have nothing to sell."] = "Vous n'avez rien à vendre.",
    ["You can't afford any, or you have no room left."]
        = "Vous n'avez pas les moyens, ou plus de place.",
    ["Couldn't buy."] = "Achat impossible.",
    ["Couldn't sell."] = "Vente impossible.",
    ["Pay back"] = "Rembourser",
    ["Borrow"] = "Emprunter",
    ["Deposit"] = "Déposer",
    ["Withdraw"] = "Retirer",
    ["Nothing to do here right now."] = "Rien à faire ici pour le moment.",
    ["Up to %1"] = "Jusqu'à %1",
    ["30 days are up."] = "Les 30 jours sont écoulés.",
    ["%1\n\nFinal net worth: %2\nBest ever: %3"] = "%1\n\nFortune finale : %2\nRecord : %3",
    ["Start a new game? Current progress is lost."]
        = "Commencer une nouvelle partie ? La progression actuelle sera perdue.",

    -- Shared game rules
    ["That isn't sold here."] = "Cela ne se vend pas ici.",
    ["You can't afford that many."] = "Vous n'avez pas les moyens d'en acheter autant.",
    ["Nobody here is buying that."] = "Personne n'achète cela ici.",
    ["You don't have that many."] = "Vous n'en avez pas autant.",
    ["There's nothing to buy."] = "Il n'y a rien à acheter.",
    ["You can't afford it."] = "Vous n'en avez pas les moyens.",
    ["Fight"] = "Combattre",
    ["Flee"] = "Fuir",

    -- Theme: Silk Road caravan
    ["Silk Road caravan"] = "Caravane de la route de la soie",
    ["%1 silver"] = "%1 pièces d'argent",
    ["Bazaar — buy low, sell high:"] = "Bazar — achetez bas, vendez haut :",
    ["Travel"] = "Voyager",
    ["Set out for where?"] = "Partir vers où ?",
    ["Moneylender"] = "Usurier",
    ["Moneylender — you owe %1"] = "Usurier — vous devez %1",
    ["Guild bank"] = "Caisse de la guilde",
    ["Guild bank — balance %1"] = "Caisse de la guilde — solde %1",
    ["Guards"] = "Gardes",
    ["Load"] = "Charge",
    ["Saffron"] = "Safran",
    ["Silk"] = "Soie",
    ["Frankincense"] = "Encens",
    ["Cinnamon"] = "Cannelle",
    ["Pepper"] = "Poivre",
    ["Salt"] = "Sel",
    ["Constantinople"] = "Constantinople",
    ["Baghdad"] = "Bagdad",
    ["Samarkand"] = "Samarcande",
    ["Bukhara"] = "Boukhara",
    ["Kashgar"] = "Kachgar",
    ["Chang'an"] = "Chang'an",
    ["Nobles are paying outrageous prices for %1!"]
        = "Les nobles paient des prix fous pour %1 !",
    ["A caravan has flooded the bazaar with cheap %1!"]
        = "Une caravane a inondé le bazar de %1 bon marché !",
    ["You found a purse with %1 by the roadside!"]
        = "Vous avez trouvé une bourse de %1 au bord du chemin !",
    ["Pickpockets in the bazaar! Lost %1."]
        = "Des pickpockets dans le bazar ! Vous perdez %1.",
    ["You found %1 %2 abandoned by the trail!"]
        = "Vous avez trouvé %1 %2 abandonnés le long de la piste !",
    ["A mercenary offers to guard your caravan for %1. Hire him?"]
        = "Un mercenaire propose de garder votre caravane pour %1. L'engager ?",
    ["The mercenary joins your caravan."] = "Le mercenaire rejoint votre caravane.",
    ["A drover offers extra camels (+%1 load) for %2. Buy them?"]
        = "Un chamelier propose des chameaux supplémentaires (+%1 de charge) pour %2. Les acheter ?",
    ["Your caravan can now carry %1 more."]
        = "Votre caravane peut maintenant porter %1 de plus.",
    ["Your camels can't carry any more."]
        = "Vos chameaux ne peuvent pas porter davantage.",
    ["Bandits (%1) are raiding your caravan!\nHealth %2 · Guards %3"]
        = "Des bandits (%1) attaquent votre caravane !\nSanté %2 · Gardes %3",
    ["You have no guards to fight them!"]
        = "Vous n'avez pas de gardes pour les combattre !",
    ["Your guards struck one down!"] = "Vos gardes en ont abattu un !",
    ["Your guards missed!"] = "Vos gardes ont manqué leur coup !",
    ["The bandits scatter — you seize %1 from their camp!"]
        = "Les bandits se dispersent — vous saisissez %1 dans leur camp !",
    ["They fought back! Health -%1 (%2 left)."]
        = "Ils ont riposté ! Santé -%1 (%2 restants).",
    ["You escaped through a mountain pass!"]
        = "Vous vous êtes échappé par un col de montagne !",
    ["They caught up with you! Health -%1 (%2 left)."]
        = "Ils vous ont rattrapé ! Santé -%1 (%2 restants).",
    ["The bandits overran your caravan."] = "Les bandits ont submergé votre caravane.",

    -- Theme: Star trader
    ["Star trader"] = "Marchand des étoiles",
    ["%1 cr"] = "%1 cr",
    ["Trade terminal — buy low, sell high:"]
        = "Terminal de commerce — achetez bas, vendez haut :",
    ["Warp"] = "Saut",
    ["Warp to where?"] = "Sauter vers où ?",
    ["The Syndicate"] = "Le Syndicat",
    ["The Syndicate — you owe %1"] = "Le Syndicat — vous devez %1",
    ["Galactic bank"] = "Banque galactique",
    ["Galactic bank — balance %1"] = "Banque galactique — solde %1",
    ["Turrets"] = "Tourelles",
    ["Cargo"] = "Cargaison",
    ["Antimatter"] = "Antimatière",
    ["Quantum cores"] = "Cœurs quantiques",
    ["Med-nanites"] = "Nanites médicaux",
    ["Robot parts"] = "Pièces de robot",
    ["Fuel cells"] = "Piles à combustible",
    ["Scrap alloy"] = "Alliage de récupération",
    ["Terra Station"] = "Station Terra",
    ["Luna Port"] = "Port Luna",
    ["Mars Colony"] = "Colonie de Mars",
    ["Ceres Belt"] = "Ceinture de Cérès",
    ["Europa Dock"] = "Dock d'Europe",
    ["Titan Refinery"] = "Raffinerie de Titan",
    ["A colony shortage — %1 sells at outrageous prices!"]
        = "Pénurie dans la colonie — %1 se vend à des prix fous !",
    ["A freighter dumped cheap %1 on the market!"]
        = "Un cargo a déversé du %1 bon marché sur le marché !",
    ["You salvaged a credit chip worth %1!"]
        = "Vous avez récupéré une puce de crédit d'une valeur de %1 !",
    ["A dock hustler scammed you! Lost %1."]
        = "Un arnaqueur du dock vous a escroqué ! Vous perdez %1.",
    ["You salvaged %1 %2 from drifting wreckage!"]
        = "Vous avez récupéré %1 %2 dans une épave à la dérive !",
    ["A shipwright offers a laser turret for %1. Install it?"]
        = "Un charpentier spatial propose une tourelle laser pour %1. L'installer ?",
    ["Laser turret installed."] = "Tourelle laser installée.",
    ["A dockhand offers spare cargo pods (+%1 space) for %2. Buy them?"]
        = "Un docker propose des modules de fret (+%1 de place) pour %2. Les acheter ?",
    ["Your hold now fits %1 more."] = "Votre soute peut désormais contenir %1 de plus.",
    ["Your cargo hold is full."] = "Votre soute est pleine.",
    ["Pirate ships (%1) are closing in!\nHull %2 · Turrets %3"]
        = "Des vaisseaux pirates (%1) approchent !\nCoque %2 · Tourelles %3",
    ["Evade"] = "Esquiver",
    ["You have no turrets to fight with!"]
        = "Vous n'avez pas de tourelles pour combattre !",
    ["Direct hit — one pirate is down!"] = "Coup au but — un pirate en moins !",
    ["Your shots went wide!"] = "Vos tirs sont passés à côté !",
    ["The pirates are destroyed — you salvage %1!"]
        = "Les pirates sont détruits — vous récupérez %1 !",
    ["They returned fire! Hull -%1 (%2 left)."]
        = "Ils ont riposté ! Coque -%1 (%2 restants).",
    ["You lost them in an asteroid field!"]
        = "Vous les avez semés dans un champ d'astéroïdes !",
    ["They kept pace! Hull -%1 (%2 left)."]
        = "Ils n'ont pas lâché prise ! Coque -%1 (%2 restants).",
    ["Your ship was destroyed by pirates."]
        = "Votre vaisseau a été détruit par les pirates.",

    -- Theme: Clipper captain
    ["Clipper captain"] = "Capitaine de clipper",
    ["Harbor market — buy low, sell high:"]
        = "Marché du port — achetez bas, vendez haut :",
    ["Set sail"] = "Appareiller",
    ["Set sail for where?"] = "Appareiller vers où ?",
    ["Bank"] = "Banque",
    ["Bank — balance %1"] = "Banque — solde %1",
    ["Cannons"] = "Canons",
    ["Hold"] = "Cale",
    ["Porcelain"] = "Porcelaine",
    ["Tea"] = "Thé",
    ["Spices"] = "Épices",
    ["Rum"] = "Rhum",
    ["Hemp"] = "Chanvre",
    ["Canton"] = "Canton",
    ["Singapore"] = "Singapour",
    ["Batavia"] = "Batavia",
    ["Nagasaki"] = "Nagasaki",
    ["Merchants are bidding wildly for %1!"]
        = "Les marchands enchérissent follement sur %1 !",
    ["The docks are flooded with cheap %1!"]
        = "Les quais regorgent de %1 bon marché !",
    ["You found %1 washed up in a sea chest!"]
        = "Vous avez trouvé %1 dans un coffre échoué !",
    ["Dock thieves got into your cabin! Lost %1."]
        = "Des voleurs du port sont entrés dans votre cabine ! Vous perdez %1.",
    ["You fished %1 %2 out of the surf!"]
        = "Vous avez repêché %1 %2 dans les vagues !",
    ["A gunsmith offers a ship's cannon for %1. Buy it?"]
        = "Un armurier propose un canon de marine pour %1. L'acheter ?",
    ["The cannon is bolted to your deck."] = "Le canon est fixé à votre pont.",
    ["A shipwright offers to refit your hold (+%1 space) for %2. Do it?"]
        = "Un charpentier de marine propose d'agrandir votre cale (+%1 de place) pour %2. Accepter ?",
    ["Your hold now stows %1 more."] = "Votre cale peut désormais arrimer %1 de plus.",
    ["Your hold is packed to the beams."] = "Votre cale est pleine à craquer.",
    ["Pirate junks (%1) are bearing down on you!\nHull %2 · Cannons %3"]
        = "Des jonques pirates (%1) fondent sur vous !\nCoque %2 · Canons %3",
    ["You have no cannons to fight with!"]
        = "Vous n'avez pas de canons pour combattre !",
    ["A broadside — one junk is sinking!"] = "Une bordée — une jonque coule !",
    ["Your broadside missed!"] = "Votre bordée a manqué sa cible !",
    ["The pirates strike their colors — you seize %1 in booty!"]
        = "Les pirates amènent leur pavillon — vous saisissez %1 de butin !",
    ["They raked your decks! Hull -%1 (%2 left)."]
        = "Ils ont balayé votre pont ! Coque -%1 (%2 restants).",
    ["You slipped away into a fog bank!"]
        = "Vous vous êtes éclipsé dans un banc de brume !",
    ["They stayed on your tail! Hull -%1 (%2 left)."]
        = "Ils sont restés dans votre sillage ! Coque -%1 (%2 restants).",
    ["Your ship was taken by pirates."] = "Votre navire a été pris par les pirates.",

    -- Theme: Antique dealer
    ["Antique dealer"] = "Antiquaire",
    ["Today's finds — buy low, sell high:"]
        = "Trouvailles du jour — achetez bas, vendez haut :",
    ["Move on"] = "Continuer",
    ["Head to which quarter?"] = "Vers quel quartier ?",
    ["Pawnbroker"] = "Prêteur sur gages",
    ["Pawnbroker — you owe %1"] = "Prêteur sur gages — vous devez %1",
    ["Experts"] = "Experts",
    ["Bag"] = "Sacoche",
    ["Illuminated manuscripts"] = "Manuscrits enluminés",
    ["Pocket watches"] = "Montres de gousset",
    ["Old etchings"] = "Gravures anciennes",
    ["First editions"] = "Éditions originales",
    ["Vintage maps"] = "Cartes anciennes",
    ["Old postcards"] = "Cartes postales anciennes",
    ["Grand Bazaar"] = "Grand Bazar",
    ["Old Town"] = "Vieille Ville",
    ["University Quarter"] = "Quartier de l'Université",
    ["Harbor District"] = "Quartier du Port",
    ["Riverside Market"] = "Marché des Quais",
    ["Flea Market"] = "Marché aux Puces",
    ["Collectors are in a frenzy over %1!"]
        = "Les collectionneurs s'arrachent %1 !",
    ["An estate sale flooded the stalls with cheap %1!"]
        = "Une succession a inondé les étals de %1 bon marché !",
    ["You found %1 tucked inside an old book!"]
        = "Vous avez trouvé %1 glissé dans un vieux livre !",
    ["A pickpocket worked the market crowd! Lost %1."]
        = "Un pickpocket a sévi dans la foule du marché ! Vous perdez %1.",
    ["You spotted %1 %2 in a junk pile!"]
        = "Vous avez repéré %1 %2 dans un tas de bric-à-brac !",
    ["A retired appraiser offers his expertise for %1. Hire him?"]
        = "Un expert à la retraite propose ses services pour %1. L'engager ?",
    ["The appraiser joins your rounds."] = "L'expert vous accompagne dans vos tournées.",
    ["A leatherworker offers a bigger satchel (+%1 room) for %2. Buy it?"]
        = "Un maroquinier propose une sacoche plus grande (+%1 de place) pour %2. L'acheter ?",
    ["Your bag now holds %1 more."] = "Votre sacoche contient désormais %1 de plus.",
    ["Your bag is stuffed full."] = "Votre sacoche est pleine à craquer.",
    ["Forgers (%1) are trying to swindle you!\nNerve %2 · Experts %3"]
        = "Des faussaires (%1) tentent de vous escroquer !\nSang-froid %2 · Experts %3",
    ["Call their bluff"] = "Démasquer le bluff",
    ["Walk away"] = "S'éloigner",
    ["You have no expert to spot the fakes!"]
        = "Vous n'avez aucun expert pour repérer les faux !",
    ["Your expert exposed one of them!"] = "Votre expert en a démasqué un !",
    ["Their forgery fooled your expert!"] = "Leur faux a trompé votre expert !",
    ["The forgers flee — the crowd rewards you with %1 in trade!"]
        = "Les faussaires s'enfuient — la foule vous récompense de %1 en affaires !",
    ["They rattled you badly! Nerve -%1 (%2 left)."]
        = "Ils vous ont sérieusement ébranlé ! Sang-froid -%1 (%2 restants).",
    ["You slipped away into the crowd!"]
        = "Vous vous êtes fondu dans la foule !",
    ["They followed you, jeering! Nerve -%1 (%2 left)."]
        = "Ils vous ont suivi en vous raillant ! Sang-froid -%1 (%2 restants).",
    ["The forgers ruined your reputation and your nerve."]
        = "Les faussaires ont ruiné votre réputation et votre sang-froid.",
}
