# Batailles et transit

Règles actives du 7 novembre 2026. Elles remplacent les passages correspondants du document militaire alpha.

- Voyage : plafond de `3 600 + distance / √2 000 000 × 601 200` secondes, soit une heure à distance nulle et sept jours sur la diagonale de l'univers. Les vols déjà partis gardent leur échéance jusqu'à leur prochaine redirection.
- Redirection à tout instant en transit : interpolation de la position atteinte sur le segment, nouveau segment vers la destination et nouveau devis de durée. La mission reste inchangée. Une capture inverse toutes les missions en transit vers ce monde.
- Arrivée : une heure N/A pour vaisseaux et soldats. Les vaisseaux combattent pendant N/A mais ne peuvent charger, débarquer, repartir ou être dissous. Aucun mécanisme de fusion ne permet de contourner ce délai.
- Téléportation : soldats au sol uniquement, arrivée immédiate avec une heure N/A. Ces soldats subissent les tirs mais ne tirent pas, ne comptent ni pour la supériorité terrestre ni pour empêcher/prendre une planète, et ne peuvent charger ou se téléporter. L'énergie récupère maintenant une charge par heure après recherche.
- Changement de mission : attaque impose au moins une heure N/A ; défense ajoute une heure, jusqu'à quatre heures restantes. Toute capture ajoute une heure aux forces présentes.
- Mode paranoïaque par planète : un renfort défensif n'appartenant ni au propriétaire ni à son clan passe en attaque à l'arrivée.
- Photographie commune et dégâts simultanés par heure : espace 12 %, sol 4 %, fractions conservées. Les passagers sont répartis entre bombardiers et destroyers ; les pertes de transports entraînent des pertes proportionnelles de passagers.
- Les bombardiers appuient le sol seulement si leur camp a au moins trois fois la puissance spatiale adverse. Au moins 100 vaisseaux offensifs dans cette situation bloquent toutes les liaisons du monde aux deux extrémités. Reprise deux heures après la levée ; les accruals sont découpés à cette échéance exacte.
- Supériorité au sol : les attaquants disponibles dépassent les défenseurs disponibles. Le recrutement et les chantiers industriels sont suspendus ; les durées restantes sont conservées. Fermeture, refus et réduction des liaisons sont verrouillés côté serveur, quelle que soit l'extrémité sélectionnée.
- Conquête : plus aucun défenseur terrestre disponible. Le joueur ayant le plus de soldats offensifs disponibles devient propriétaire, même si des défenseurs orbitaux ou terrestres N/A subsistent. Ces forces conservent leur propriétaire. Usines et capacités sont conservées ; chantiers industriels annulés et intégralement remboursés à leur commanditaire ; assimilations perdues sans remboursement ; Tyrannie devient Conseil. Les participants reçoivent l'identité du conquérant sauf prise camouflée.
- Après capture : nom public `Signal XX`, une possibilité de renommage ; connexion TP après quatre heures pour chaque monde déjà contrôlé, avant la nouvelle conquête.
- Fortification : zéro jusqu'au septième jour, puis `0,6 × ((jours − 7) / 53)^1,6` jusqu'au jour 60. Ensuite `0,6 + 0,35 × (1 − ((150 − jours) / 90)^2)` jusqu'au jour 150, plafond 95 %. Bonus défensif aux combats terrestres et au tir terrestre contre l'espace. Une conquête militaire remet l'ancienneté à zéro.

Les infiltrations, Hypergates et la recherche de camouflage restent de futurs modules. Un indicateur interne de camouflage prépare l'anonymat de 21 jours et supprime la notification nominative ; aucune commande cliente ne permet d'activer gratuitement ce pouvoir.

Sécurité : commandes authentifiées, contrôles de propriété, verrou de session et identifiants de requête idempotents. Positions de transit et forces ne sont retournées qu'à leur propriétaire. Fonctions internes révoquées aux clients. Les noms publics n'exposent pas l'identité des propriétaires.

Validation : tests de transit, redirection, N/A, téléportation, énergie horaire, paranoïa, inversion, dégâts, blocus, reprise commerciale, siège, files industrielles, conquête, remboursement, gouvernement, réseau TP, fortifications et noms publics ; régressions militaires, économie, civilisation et communications.
