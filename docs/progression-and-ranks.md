# Civilisation et grades — contrat de l’alpha

Coûts validés après réduction de 20 % : arrondi(80 000 × (niveau cible − 1)^0,85), maximum 40. Chaque niveau exige 72 heures réelles. Les investissements successifs sont payés à l’avance, puis assimilés dans l’ordre, un à la fois par planète. Plusieurs planètes progressent en parallèle. Ferros n’accélère pas l’assimilation. Les niveaux complétés persistent lors d’une capture ; les investissements inachevés sont interrompus sans remboursement. Pas de file gratuite ni d’annulation/remboursement à exploiter.

Le moteur traite la fin d’assimilation dans la même chronologie que les versements, les constructions, les arrivées et les combats. Les recettes de l’ancien niveau sont comptabilisées avant le changement ; le commerce et le recrutement utilisent ensuite le nouveau niveau. Une commande vérifie l’identité, la session, la propriété, le niveau courant, le dernier niveau déjà financé, les fonds et la dette. Les requêtes répétées avec le même identifiant ne paient qu’une fois.

## Score

- Civilisation : 100 × somme des niveaux des mondes actuellement contrôlés.
- Production vérifiable : 20 % de la valeur des unités produites. Référence : soldat 1, scout 4, bombardier 24, destroyer 32. Cette composante est plafonnée à 40 % des points de civilisation pour empêcher une promotion obtenue uniquement par une boucle de production.
- Destructions : valeur entière des pertes infligées, partagée entre les joueurs du camp selon leur contribution aux dégâts spatiaux et terrestres. Les passagers perdus avec leurs transports sont attribués aux forces spatiales qui les ont détruits. Les fractions sont conservées jusqu’au calcul du score affiché.

Les garnisons de départ, les captures et les transferts de troupes ne sont pas des créations d’armées. Les navires déjà livrés et vérifiables dans les commandes industrielles sont repris à l’activation. Le recrutement et les destructions historiques antérieurs à ce suivi ne sont pas devinés à partir des stocks : leur suivi commence à l’activation. Les pertes infligées à ses propres forces ou à un membre de son clan ne donnent aucun point. Le propriétaire réel et les appartenances cachées ne sont pas exposés dans le calcul retourné.

## Grades

| Grade | Score minimum |
| --- | ---: |
| Cadet de Flotte | 0 |
| Enseigne stellaire | 300 |
| Lieutenant orbital | 700 |
| Capitaine de corvette | 1 250 |
| Capitaine de frégate | 1 950 |
| Capitaine stellaire | 2 800 |
| Commandant d’escadre | 3 850 |
| Commodore | 5 100 |
| Contre-amiral | 6 550 |
| Amiral | 8 200 |
| Fleet Admiral | 10 000 |

Fleet Admiral exige également trois mondes actuellement au niveau 15 ou plus et 2 000 points de combat. Trois mondes civ 15 donnent 4 500 points de civilisation ; au plus 1 800 points de production comptent pour ce territoire. Avec 4 000 points de combat et assez de production, ce profil atteint 10 300 points et Fleet Admiral. Deux mondes civ 1/2 donnent 300 points et le premier grade supplémentaire. Les grades reflètent le score et les conditions actuelles ; ils peuvent baisser après perte de territoires. Aucun bonus économique ou militaire caché n’est attaché aux titres.

## Interface et confidentialité

Civilisation regroupe les mondes, niveaux, assimilation active, réserve déjà investie, file et financement de nouveaux niveaux. Le même investissement est disponible dans la section Population & civilisation de Planètes. Le grade apparaît dans la barre supérieure, le compte, le commandement et la page Civilisation, avec l’insigne et le détail des points.

Tables privées civilization_jobs, civilization_commands et player_merit : RLS activée sans droits directs client. Les seules nouvelles RPC authentifiées sont progression_dashboard et invest_civilization, avec wrapper public invoker et contrôles privés. Il n’existe pas d’API cliente pour écrire un score, un grade, une échéance ou des compteurs de mérite.

## Vérifications

28 tests Node réussis, dont migrations exécutées dans Postgres isolé, rattrapage hors connexion, niveaux séquentiels et parallèles, refus des devis périmés / doubles paiements / accès tiers / dette, plafond 40, capture, suivi des productions sans transferts, attribution des pertes et prérequis Fleet Admiral. Migration Supabase validée en transaction annulée. Après le refus initial du contrôle automatique, le propriétaire a explicitement autorisé l’activation en production. Les deux migrations ont été appliquées. Le score affiché additionne les composantes entières affichées, avec conservation des fractions dans les compteurs privés.


### Essais connectés

Fixture QA_Civilization_UI créée avec autorisation explicite et bornée par app_metadata : identifiant de compte, participation et cinq mondes. Un deuxième monde de cette fixture a été attribué au compte QA pour le scénario de première conquête. Aucun monde réel n’a reçu d’investissement de test.

Dans Planètes : achat du niveau 2 à 80 000 Þ, trésorerie 1 000 000 → 920 000, niveau inchangé pendant l’assimilation. Dans Civilisation : financement des niveaux 3 et 4 à 347 737 Þ, trésorerie 572 263, échéances séparées de 72 h. Un investissement indépendant de 80 000 Þ sur le second monde réduit la trésorerie QA à 492 263. Après déplacement des seules échéances QA, le niveau 2 est acquis, le commerce local passe à ×1,05, la file suivante continue et le score passe à 300, Enseigne stellaire, dans le bandeau et la barre supérieure. L’horloge globale de la session n’a pas été avancée.

Affichage du plafond Fleet Admiral vérifié avec des compteurs préparés uniquement sur la fixture : trois mondes civ 15, 4 500 points de civilisation + 1 800 de production après plafond + 4 000 de combat = 10 300. Ce scénario d’affichage ne simule pas de vrais combats sur la partie publique ; l’attribution des combats réels est testée dans Postgres isolé.

Mobile 390 × 844 : document de 375 px, aucun débordement horizontal, file et score lisibles. La sélection d’une planète est conservée par identifiant lors d’un rechargement des données ; les onglets n’attribuent plus une origine à un monde en se basant uniquement sur son ordre de retour.
