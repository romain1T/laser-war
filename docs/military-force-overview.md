# Vue des forces et pictogrammes

Les flottes constituées stationnées participent déjà au même combat spatial que les vaisseaux en réserve. Les soldats embarqués ne tirent pas au sol avant leur débarquement ; les troupes N/A conservent les restrictions militaires existantes.

Armées & flottes utilise une projection locale distincte des planètes contrôlées. Le sélecteur ajoute les mondes où le joueur a au moins une unité physiquement stationnée. Rouge : présence offensive ; vert : présence défensive ; rouge et libellé explicite si les deux missions coexistent. Les mondes possédés restent dans la liste même sans unités.

Le total des forces propres présentes additionne les réserves, les troupes au sol, les passagers et les vaisseaux des flottes stationnées, une seule fois. Les unités en transit et celles des autres joueurs sont exclues de ce total. Les réserves utilisables et les commandes industrielles restent séparées ; les commandes planétaires ne sont proposées que pour un monde contrôlé. La liste des flottes est filtrée sur la planète sélectionnée.

Sur un monde contrôlé ou physiquement occupé par ses forces, le joueur voit les forces étrangères stationnées, leurs noms de flotte, races, missions et unités, réparties entre défense et attaque. Cela inclut les effectifs terrestres conformément à la demande explicite de visibilité locale. Aucun identifiant de propriétaire, route de ravitaillement, origine, destination ou force distante étrangère n'est fourni. Un simple survol en transit n'accorde aucune reconnaissance. La visibilité disparaît au départ de la dernière unité du joueur d'un monde étranger.

Commandement présente jusqu'à quatre flottes en transit et les positions extérieures, leurs caractéristiques planétaires, les forces des deux camps et la posture du joueur. Un clic sur une position sélectionne directement cette planète dans Armées & flottes. Les noms des extrémités d'un transit sont accompagnés de l'illustration planétaire correspondante.

Les neuf PNG de vaisseaux fournis sont encodés en WebP transparent de 256 px sans modification des originaux. La race de chaque flotte détermine son illustration ; la race locale détermine les pictogrammes des réserves et chantiers. Les soldats utilisent le portrait de race. Les vues de composition conservent les effectifs en réserve et ne permettent pas d'utiliser une seconde fois une unité déjà affectée.

Validation : tests SQL des totaux avant et après assemblage, exclusion des transits, portée de reconnaissance, départ de la dernière unité, séparation des planètes possédées/occupées, champs confidentiels absents, postures mixtes, droits des fonctions et rendu des neuf assets ; contrôles navigateur sur fixtures jetables autorisées.
