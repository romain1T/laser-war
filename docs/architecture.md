# Architecture

## Première tranche

- Interface HTML/CSS et modules JavaScript, sans build et sans framework. Les éléments de jeu sont du HTML interactif ; l'illustration n'encode aucune statistique.
- Supabase Auth pour les sessions et mots de passe ; client officiel 2.119.0 épinglé, livré localement. Les jetons de session sont gérés par le SDK ; aucune clé serveur dans le navigateur.
- Postgres : seasons, profiles, empires, planets. RLS sur chaque table exposée. Lecture privée ; aucune écriture directe sur l'état du jeu.
- Point d'entrée RPC public.found_empire en SECURITY INVOKER ; commande privilégiée dans le schéma private non exposé, SECURITY DEFINER à search_path vide avec contrôle auth.uid et email confirmé. EXECUTE refusé à PUBLIC et anon. Les noms sont validés et le verrou de session sérialise les fondations. Unicité saison/joueur comme second garde-fou.
- Storage : bucket avatars privé, WebP uniquement, maximum 2 Mo. Chemin autorisé uid/avatar.webp. L'image d'entrée est convertie en WebP 256 px côté navigateur. Liens signés de courte durée pour son propre portrait.
- Date et allocation décidées dans Postgres, jamais avec l'horloge ou les statistiques transmises par le client.

## Clans et carte

`start_player(username, planet_name)` supprime le besoin d'un nom d'empire. L'ancienne RPC reste compatible et ignore désormais le nom transmis ; les anciennes données et trésoreries sont conservées.

`clans` contient uniquement un identifiant, une session, un nom et une date. `private.clan_memberships` n'est ni exposée dans l'API ni accessible aux rôles clients. Les commandes `manage_clan`, `my_clan` et `set_planet_options` passent par des wrappers SECURITY INVOKER puis des fonctions privées à search_path vide, contrôlant auth.uid et la session active. Un verrou de session sérialise les mutations ; les répétitions de création/adhésion sont idempotentes et un départ précise le clan attendu pour éviter qu'une requête ancienne retire un nouveau clan.

`galaxy_signals` est une projection à liste de champs autorisés : id du signal, désignation, coordonnées, nom de clan public éventuel et indication de son propre monde. Aucun owner/player/clan ID, aucune affiliation masquée ni renseignement stratégique. Le SELECT direct des planètes demeure limité à leur propriétaire. Les tags ne modifient jamais le nom enregistré.

## Découpage suivant

1. Tranche comptes/empire/planète, puis configuration email et tests avec une boîte réelle.
2. Économie avec registre des versements et commandes d'achats idempotentes ; simulations d'équilibrage avant activation.
3. Civilisation, croissance et recherche avec dates serveur, files et rattrapage hors connexion.
4. Carte et reconnaissance via vues/projections retournant exclusivement les données autorisées.
5. Flottes : retrait transactionnel au départ, événements d'arrivée uniques et entretien sans doublon.
6. Combats horaires, débarquement différé, rapports et conquêtes transactionnelles.
7. Clans, diplomatie et contenus avancés. Forum ultérieur.

Les versements économiques utilisent désormais le cron décrit ci-dessous. Les déplacements et combats attendent leurs moteurs.

## Économie alpha

Tables privées economy_clock, trade_links, economy_accruals, economy_ledger et economy_commands, aucun droit direct client. Verrou de session pour achats et réservations, identifiant de commande pour reprise réseau, contrôle de devis dans purchase_capacities. Accrual en secondes, fractions conservées, registre unique par planète et échéance. Cron laser-war-economy chaque minute et rattrapage lors des RPC. Versements à 00, 08 et 16 heures UTC ; entretien impayé conservé en dette. Prévisions et historique réservés au propriétaire. Destinations issues de galaxy_signals sans données stratégiques adverses.


## Progression des mondes et du joueur

Les tables privées civilization_jobs / civilization_commands / player_merit sont protégées par RLS et sans accès direct client. progression_dashboard et invest_civilization exposent uniquement les données propres et des commandes à devis / identifiant de requête. La fin d’assimilation entre dans la chronologie du moteur militaire avant changement des rendements. Les créations d’unités et les pertes sont créditées côté serveur, jamais déduites d’un stock transmis par le client. Le grade en cache est recalculé sur le score et les conditions courantes. Voir progression-and-ranks.md pour les règles détaillées et les essais.
