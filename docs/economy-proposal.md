# Économie alpha — courbe validée

Paramètres validés : revenus aux deux extrémités, chacun avec ses bonus locaux.

## Règles déjà fixées

- Maximum 200 capacités par planète ; chaque liaison utilise des capacités aux deux extrémités.
- Trois versements par jour, montants affichés par jour.
- Commerce avec toute planète ; acceptation automatique par défaut, option manuelle par planète.
- Monde neutre : 5 capacités fixes, population et civilisation fixes, 1 scout et 1 soldat.

## Courbe de coût validée

Référence R = 1 000 Þ par capacité occupée et par jour. Cette valeur sert à mettre les prix à l'échelle ; c’est le revenu net pour une distance de 500.

Pour la n-ième capacité, le coût est arrondi(R × T(n)). Avec x=(n−20)/30 :

- 1 ≤ n ≤ 20 : T(n) = 1/3 jour.
- 20 < n ≤ 50 : T(n) = 1/3 + (15−1/3) × (3x²−2x³).
- 50 < n ≤ 200 : T(n) = 15 + 45 × ((n−50)/150)^1,3.

La courbe est continue avec une pente nulle aux jonctions ; elle reste bornée à 60 jours au rang 200. Pas d'exponentielle. Le rang n désigne la capacité achetée ; au niveau n−1, il s'agit de la prochaine capacité.

| Capacité achetée | Prix marginal Þ | Amortissement marginal de référence (jours) | Investissement cumulé Þ | Amortissement cumulé (jours) |
|---|---:|---:|---:|---:|
| 20 | 333 | 0,33 | 6 660 | 0,33 |
| 50 | 15 000 | 15 | 243 993 | 4,88 |
| 100 | 25 788 | 25,79 | 1 233 937 | 12,34 |
| 150 | 41 564 | 41,56 | 2 912 261 | 19,42 |
| 200 | 60 000 | 60 | 5 451 306 | 27,26 |

L'amortissement cumulé divise le coût de toutes les capacités par le revenu de toutes les capacités occupées. Il ne décrit ni la date réelle du retour sur investissement ni le temps pour construire ce réseau avec des revenus réinvestis. Les capacités sont supposées occupées dès l'achat dans ce tableau.

## Occupation et bonus

À revenu relatif f et occupation u, l'amortissement moyen devient T/(f × u). Une capacité inoccupée ne rapporte rien ; son amortissement est infini tant qu'elle reste inutilisée. Pour Aurite, le bonus local prévu est ×1,15.

| Situation au rang 200 | Amortissement marginal estimé |
|---|---:|
| Référence, 100 % occupé | 60 jours |
| Référence, 50 % occupé | 120 jours |
| Aurite, 100 % occupé | 52,17 jours |
| Revenu ×1,5 et Aurite, 100 % occupé | 34,78 jours |

À la référence, 12 planètes de 200 capacités toutes occupées représentent 2,4 millions de Þ par jour, ou 2,76 millions avec Aurite partout. Cela suppose des partenaires suffisants et ne déduit pas l'entretien. Une liaison interne à deux planètes du joueur consomme bien deux ensembles de capacités ; chaque planète reçoit son revenu local.

Les 54 mondes neutres actuels offrent au maximum 270 capacités d'accueil, partagées entre tous les joueurs. Ils ne peuvent donc pas suffire seuls à remplir douze mondes de 200 capacités. Les liaisons entre joueurs ou entre ses propres mondes seront importantes.

## Revenus et entretien validés

Commerce brut : 1 500 Þ/capacité/jour. Entretien : min(distance, 1 000) Þ/capacité/jour. Net de 1 500 à 500 Þ : il diminue avec la distance. Aurite multiplie ce net par 1,15. Revenus civils : 20 000 Þ par million d’habitants/jour, bonus Aurite de 15 %. Entretien journalier : soldat 2 Þ ; scout 20 Þ ; bombardier 60 Þ ; chasseur 80 Þ. Versements à 00:00, 08:00 et 16:00 UTC. Fractions reportées, calcul au temps réel, aucun revenu avant activation.

## Réinvestissement sur 365 jours

Un monde, 100 000 Þ initiaux, 1 million d’habitants fixes, 100 soldats, aucun vaisseau. Achat maximal à t=0 puis après chaque versement ; pleine occupation immédiate, partenaires disponibles, distance constante, aucun autre achat. Simulation en nombres réels (écart d’arrondi de quelques Þ possible). Ce scénario ne prédit pas les gains réels avec concurrence et capacités limitées.

| Distance | Bonus | Jour rang 50 | Jour rang 100 | Jour rang 200 | Solde jour 365 Þ |
|---|---|---:|---:|---:|---:|
| 100 | 1 | 2.00 | 10.00 | 28.33 | 100977494 |
| 100 | 1.15 | 1.67 | 8.67 | 24.67 | 117391784 |
| 500 | 1 | 2.33 | 13.00 | 37.67 | 71969694 |
| 500 | 1.15 | 2.00 | 11.33 | 33.00 | 84005827 |
| 900 | 1 | 3.33 | 18.67 | 56.67 | 43112494 |
| 900 | 1.15 | 3.00 | 16.33 | 49.33 | 50774814 |
