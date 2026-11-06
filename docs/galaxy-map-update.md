# Carte galactique — halos et informations publiques

Chaque clan reçoit à sa création une couleur aléatoire lumineuse, stockée dans clans.color. Les clans déjà présents reçoivent aussi une couleur lors de la migration. Cette couleur ne change pas à la lecture ou au rechargement. Les commandes clients ne peuvent pas la modifier. Les couleurs ne sont pas garanties uniques entre clans.

galaxy_map expose race, ressource, civilisation et couleur du tag public, avec l’apparence et la projection existante. Un monde dont le tag est désactivé ne renvoie ni nom ni couleur de clan, même pour un autre membre du même clan. Propriétaire, population et forces restent absents. La projection galaxy_signals historique est conservée.

Les mondes taggés affichent un anneau coloré et un halo animé. Le niveau de civilisation apparaît au-dessus de chaque planète, taggée ou non. Le panneau de sélection affiche race, ressource et niveau de civilisation avec les insignes fournis. Le fond est calculé en SVG/CSS : quatre bras spiraux, poussières et étoiles, rotation lente et scintillement. Les planètes et coordonnées restent fixes. Aucun asset supplémentaire ni dépendance n’est requis. Le réglage prefers-reduced-motion désactive les animations.

Tests SQL en rollback : couleur aléatoire valide et persistante, couleur identique pour deux mondes d’un clan, refus des modifications directes, invisibilité du clan masqué et civilisation visible sur un monde non taggé. Test Node : niveaux sur chaque monde, anneau uniquement avec tag, informations du panneau, couleur non injectable et fond déterministe. Sept tests Node passent.
