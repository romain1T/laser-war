> Mise à jour : les règles de déplacements, N/A, siège, conquête et fortification sont remplacées par [Batailles et transit](battles-and-transit.md).

# Armées et flottes — alpha

## Règles validées

Recrutement automatique horaire, désactivable par planète ; affichage journalier. Base : 1,5 soldat/jour par million d’habitants × niveau de civilisation. Conseil ×0,8 ; Tyrannie ×1,2 ; Biomasse ×1,15. Les fractions sont conservées, y compris pendant l’arrêt. Garnison plafonnée pour le recrutement à population / 1 000 (plancher 1). Les arrivées de troupes ne sont pas plafonnées. Pas de consommation de population. Pas de recrutement neutre.

Chaque planète dispose initialement de cinq usines. Une usine produit un vaisseau à la fois. Scout : 2 000 Þ, 2 heures, aucun transport. Bombardier : 12 000 Þ, 8 heures, 10 soldats. Destroyer : 16 000 Þ, 10 heures, 10 soldats. Paiement à la commande, pas de réservation de monnaie ni de création anticipée d’unités. Ferros divise toutes les durées industrielles par 1,15.

Sixième usine : 25 000 Þ, 24 heures. Rang n : prix arrondi supérieur de 25 000 × (n/6)^1,6 ; durée 24 × [1 + 0,08 × (n − 6)] h avant Ferros. Un chantier d’usine à la fois par planète, indépendant des lignes de vaisseaux, plafond 200. La production de vaisseaux est limitée aux usines libres, sans file invisible.

## Déplacements et comptabilité

Une flotte est assemblée à partir des vaisseaux en réserve. Aucun vaisseau n’est ajouté par cette opération. Les unités restent attachées à leur participation d’origine et à leur race de production. Dix soldats par bombardier ou destroyer. Le chargement retire les soldats de leur garnison ou d’un détachement au sol appartenant au même joueur, sur la même planète.

Trajet : max(60 secondes, plafond(distance / √2 000 000 × 691 200 secondes)). Une diagonale de l’univers 1 000 × 1 000 vaut huit jours. Défense ou attaque ; attaque de son propre monde refusée. Les 15 destinations les plus proches sont proposées ; la recherche par nom porte sur l’ensemble des désignations publiques de la carte. La mission ne révèle pas le propriétaire réel de la destination.

Le départ retire immédiatement la flotte de son monde stationné. Les soldats déjà au sol peuvent être laissés en garnison dans un détachement séparé. À l’arrivée, les passagers restent embarqués une heure au minimum, puis débarquent au premier combat horaire suivant. Le déchargement manuel anticipé est refusé. La flotte peut repartir avant de débarquer. Les soldats au sol sont réembarquables dans les transports du joueur présents sur place. La dissolution, réservée à un monde contrôlé, rend toutes les unités aux réserves.

Tous les soldats et vaisseaux sont entretenus par leur propriétaire, en garnison, en orbite ou en voyage. L’économie comptabilise le temps avant chaque événement militaire et conserve les fractions existantes. Les coûts des forces expéditionnaires sont affichés séparément dans Revenus et attribués dans le grand livre à leur planète de ravitaillement d’origine, même si celle-ci est perdue. Les constructions inachevées sont annulées sans remboursement lors d’une capture.

## Combats : valeurs provisoires de l’alpha

Les forces défensives constituent un camp, les forces offensives un autre. Tous les dégâts d’une heure utilisent la même photographie initiale, sans avantage de l’ordre de traitement.

| Unité | Puissance spatiale | Résistance spatiale | Frappe terrestre/h |
| --- | ---: | ---: | ---: |
| Scout | 1 | 2 | 0 |
| Bombardier | 0 | 10 | 2 |
| Destroyer | 8 | 12 | 0 |

Un soldat a une puissance et résistance terrestres de 1. Dégâts par heure : 12 % de la puissance adverse ; au sol s’ajoutent les frappes des bombardiers. Répartition proportionnelle entre unités, pertes entières et fractions de dégâts conservées. Les bonus raciaux Vael / Khar s’appliquent aux puissances correspondantes ; Elys reste équilibré. Les passagers meurent à proportion des transports détruits et ne combattent pas avant débarquement.

Après élimination de tous les défenseurs au sol et en orbite, le groupe attaquant ayant le plus de soldats débarqués prend le contrôle si sa limite de douze mondes n’est pas atteinte. Une égalité est départagée de façon stable par identifiant de participation. Les forces attaquantes survivantes passent en défense. Race, ressource, population, civilisation et usines sont conservées ; le tag de clan est masqué et un renommage unique est ouvert. Aucune croissance neutre n’est ajoutée par le moteur.

## Confidentialité

Les tables militaires sont privées, RLS activée et aucun accès direct accordé. Deux RPC publiques authentifiées : military_dashboard et military_command ; les fonctions privilégiées et le temps simulable restent dans private et sont inaccessibles aux clients. Le serveur vérifie propriétaire, quantités, capacités, fonds, disponibilités, session et unicité de requête.

Les rapports montrent les pertes propres et les forces spatiales opposées. Les forces terrestres opposées restent absentes tant que le joueur n’a pas de troupes débarquées. Les rapports d’arrivée ne révèlent aucune garnison ennemie. L’onglet Planètes affiche uniquement les propres forces du joueur sur des mondes extérieurs, en défense ou en attaque. Le propriétaire réel n’est pas retourné dans ces positions extérieures.

## Vérification

La suite Node exécute aussi les migrations et le moteur dans un Postgres WASM isolé (PGlite), avec services Auth, Storage et Cron minimaux pour tester les contrats SQL. Les tâches Cron réelles et l’authentification GoTrue ne sont pas simulées par cette suite. Installation reproductible via pnpm-lock.yaml ; node --test tests/*.test.mjs. Validation Supabase de la migration en transaction annulée réussie. Après un refus initial du contrôle automatique, le propriétaire a explicitement autorisé l’activation du moteur militaire en production. Migration appliquée avec succès. Contrôle authentifié Supabase : une seule planète propre visible, cinq usines et 1,2 soldat/jour pour la fixture Conseil sans Biomasse. Les tables privées sans politiques restent volontairement inaccessibles ; l’avertissement préexistant sur la protection des mots de passe compromis ne résulte pas de cette migration.


### Essais connectés

QA_Military_Alpha / Beta ont été créés avec autorisation explicite, cinq mondes chacun, identifiants et liste de mondes enregistrés dans app_metadata pour borner le nettoyage. Production d’un scout et d’une usine via le navigateur : débit de 27 000 Þ, puis 6 usines et livraison du scout. Constitution de deux flottes, chargement de dix soldats chacune, retrait des réserves, départ en défense vers le monde QA Beta et attaque d’un neutre de la fixture. Le menu contient 15 destinations ; recherche de Signal 287 en dehors de ce groupe réussie. La présence extérieure est visible dans Planètes. Arrivée, combat puis capture de Signal 283 : rapports affichés avec pertes et unités restantes, cinq usines conservées et renommage ouvert. Les échéances et les deux tours de combat ont été accélérés uniquement sur les données QA, sans avancer l’horloge de toute la session. Le recrutement a été arrêté et réactivé dans l’interface (0 puis 1,2 par jour). Les deux derniers passages Cron observés sont réussis.

Contrôle mobile à 390 × 844 : document de 375 px, aucune surlargeur, chantiers sur une colonne. La barre de navigation mobile défile horizontalement pour conserver des cibles lisibles avec le nouvel onglet. Les devis périmés des usines sont désormais refusés ; un nom absent ne peut pas consommer le renommage d’une capture. Suite locale : 17 tests réussis.
