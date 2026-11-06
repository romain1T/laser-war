# Proposition d'équilibrage commercial

Document de simulation : aucune formule ci-dessous n'est activée dans le jeu. La répartition des revenus entre les deux extrémités reste à valider.

## Règles déjà fixées

- Maximum 200 capacités par planète ; chaque liaison utilise des capacités aux deux extrémités.
- Trois versements par jour, montants affichés par jour.
- Commerce avec toute planète ; acceptation automatique par défaut, option manuelle par planète.
- Monde neutre : 5 capacités fixes, population et civilisation fixes, 1 scout et 1 soldat.

## Courbe de coût proposée

Référence R = 1 000 Þ par capacité occupée et par jour. Cette valeur sert à mettre les prix à l'échelle ; ce n'est pas encore un revenu validé.

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

À la référence, 12 planètes de 200 capacités toutes occupées représentent 2,4 millions de Þ par jour, ou 2,76 millions avec Aurite partout. Cela suppose des partenaires suffisants et ne déduit pas l'entretien. Une liaison interne à deux planètes du joueur consomme bien deux ensembles de capacités ; la répartition de ses revenus reste à décider.

Les 54 mondes neutres actuels offrent au maximum 270 capacités d'accueil, partagées entre tous les joueurs. Ils ne peuvent donc pas suffire seuls à remplir douze mondes de 200 capacités. Les liaisons entre joueurs ou entre ses propres mondes seront importantes.

## Décisions encore nécessaires

Répartition bilatérale des revenus, formule de distance, revenus civils et entretien des unités. Une simulation de réinvestissement sur 365 jours sera ajoutée quand ces paramètres seront validés. Aucun solde ni versement n'est appliqué au compte existant.
