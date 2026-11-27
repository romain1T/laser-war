# Arbre technologique — équilibrage alpha

Catalogue faisant autorité : `config/technology-catalog.json`, répliqué dans la migration de recherche. Les coûts et prérequis sont calculés côté serveur.

| Technologie | Coût initial Þ | Durée initiale h | Niveaux | Laboratoire | Prérequis |
|---|---:|---:|---:|---|---|
| Recharge d’énergie | 150 000 | 12 | 1 | Tous | — |
| Téléportation | 300 000 | 24 | 1 | Tous | energy 1 |
| Téléportation améliorée | 250 000 | 24 | 3 | Tous | teleport 1 |
| Magmas énergétiques | 200 000 | 18 | 4 | Tous | energy 1 |
| Voyage amélioré | 500 000 | 48 | 3 | Tous | — |
| Infiltration | 150 000 | 12 | 1 | Tous | — |
| Malléabilité génétique I | 200 000 | 18 | 1 | Tous | infiltration 1 |
| Malléabilité génétique II | 300 000 | 24 | 1 | elys | genetics_1 1 |
| Duplication mentale | 450 000 | 36 | 1 | vael | genetics_1 1 |
| Contrôle mental | 700 000 | 48 | 1 | khar | genetics_1 1 |
| Infiltration avancée | 350 000 | 24 | 33 | Tous | genetics_1 1 |
| Productivité ouvrière I | 150 000 | 12 | 1 | Tous | — |
| Productivité ouvrière II | 300 000 | 24 | 1 | Tous | workers_1 1 |
| Cybernétique I | 600 000 | 48 | 1 | Tous | workers_2 1 |
| Cybernétique II | 1 200 000 | 72 | 1 | Tous | cybernetics_1 1 |
| Exploitation Aurite | 400 000 | 24 | 35 | aurite | workers_1 1 |
| Exploitation Ferros | 400 000 | 24 | 35 | ferros | workers_1 1 |
| Exploitation Biomasse | 400 000 | 24 | 35 | biomasse | workers_1 1 |
| Bouclier entropique | 750 000 | 48 | 1 | Tous | — |
| Bombardement massif | 600 000 | 36 | 1 | Tous | — |
| Tranchées stellaires | 300 000 | 24 | 1 | Tous | energy 1 |
| Vaisseaux Elys | 250 000 | 18 | 100 | elys | — |
| Armées Elys | 250 000 | 18 | 100 | elys | — |
| Vaisseaux Vael | 250 000 | 18 | 100 | vael | — |
| Armées Vael | 250 000 | 18 | 100 | vael | — |
| Vaisseaux Khar | 250 000 | 18 | 100 | khar | — |
| Armées Khar | 250 000 | 18 | 100 | khar | — |
| Relativité universelle | 250 000 | 24 | 1 | Tous | — |
| Scan : Tranchées | 200 000 | 18 | 1 | Tous | relativity 1 |
| Scan : Flottes | 200 000 | 18 | 1 | Tous | relativity 1 |
| Scan : Armées au sol | 200 000 | 18 | 1 | Tous | relativity 1 |
| Scan : Commerce | 200 000 | 18 | 1 | Tous | relativity 1 |
| Porte stellaire massive | 2 000 000 | 120 | 1 | Tous | energy_magma 2, travel 1 |
| Confinement de trou noir 1 | 2 000 000 | 48 | 1 | Tous | energy_magma 2 |
| Confinement de trou noir 2 | 4 000 000 | 96 | 1 | elys | black_hole_1 1 |
| Confinement de trou noir 3 | 6 000 000 | 144 | 1 | vael | black_hole_2 1 |
| Confinement de trou noir 4 | 8 000 000 | 192 | 1 | khar | black_hole_3 1 |
| Trou noir offensif | 15 000 000 | 240 | 1 | Tous | black_hole_4 1 |
| Onde énergétique | 1 500 000 | 96 | 1 | Tous | energy_magma 4 |

Les familles répétables multiplient le coût par `cost_growth^(niveau−1)` et la durée par `time_growth^(niveau−1)`, arrondis au supérieur. Les quatre étapes du trou noir font exactement 2 + 4 + 6 + 8 = 20 millions Þ ; le confinement offensif est une recherche supplémentaire.

## Décisions validées

- TP existante conservée au niveau amélioré III ; nouveaux chercheurs : capacité 1/2, puis 2/4, 3/6 et 5/10. Raccordement après conquête : 2 h par monde déjà possédé.
- Infiltration : cinq points/jour ; entretien 1 000 Þ/jour × civ cible, réduit de 90 % à l’arrêt. Aucun trait racial intrinsèque.
- Captivité : plafond partagé 35 % joueur / 70 % neutre ; pertes au plafond de 0,5 % population/jour et un niveau de civ/30 jours.
- Le seuil de 90 % donne une autorisation TP sans révéler ni déchiffrer les codes.
- Les anciens niveaux TP et réserves sont conservés. Aucun achat ni lancement d’arme automatique.

## Choix de mise en œuvre

- Une recherche par planète ; acquis au joueur, projets inachevés annulés/remboursés après conquête.
- Les champs de protectorat sont inactifs par défaut : le jeu ne définit pas encore de période de protection automatique. Lorsqu’un statut existe, limite d’infiltration à 60 %, quinze jours avant création d’une porte après sa sortie, Conseil après capture clandestine.
- Le texte importé `N+7B` est interprété comme `N+7` pour les technologies d’infiltration avancée.
- Les anciens noms Agro/Minero/Techno sont adaptés aux ressources Aurite/Ferros/Biomasse.
- Bombardement massif alpha : 50 habitants, 0,02 capacité et 0,01 usine par bombardier/h ; dégâts espacés par les tranchées, fractions conservées.
- Les cohortes conservent leurs niveaux par moyenne pondérée. Aucun surclassement rétroactif.
- Les codes des réseaux et de TP restent hachés ; aucune clé secrète n’est renvoyée aux clients.
- Les planètes détruites restent des tombes techniques pour absorber les arrivées, sans apparaître comme destinations vivantes. Les anciens vols redirigés sans historique de lancement fiable ne subissent pas de destruction rétroactive.

## Vérification

Tests existants conservés, scénarios de recherche et d’effets dans `tests/research-tree.test.mjs`. Les anciens tests TP utilisent une fixture explicite d’acquis historiques ; les nouveaux scénarios testent la capacité de base et les délais. Tests destructifs uniquement en base isolée ou transactions annulées.
