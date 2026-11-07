# Civilisation et cohérence économique — alpha validée

## Règles actives

Toutes les planètes commencent au niveau 1 ; maximum 40. Bonus commercial local : 1 + 0,05 × (niveau − 1), soit ×2,95 au niveau 40. Il multiplie le rendement après entretien de distance, puis Aurite multiplie le résultat par 1,15. Les revenus civils et les coûts d’entretien des unités ne sont pas multipliés par la civilisation.

Pour q capacités et une distance d : net commercial = q × (1 500 − min(d,1 000)) × bonus de civilisation × bonus Aurite. Chaque extrémité utilise ses propres bonus. Une planète neutre conserve sa civilisation fixe.

## Progression et file d’assimilation

Le quatrième mois est un objectif, sans verrou de calendrier. Règle validée reprenant les trois jours d’assimilation du master prompt : chaque niveau exige trois jours réels, séquentiels, sans accélération payante. Passer de 1 à 40 demande au minimum 117 jours d’assimilation si tous les investissements sont disponibles immédiatement. L’investissement n’accorde pas instantanément le niveau. Les neutres ne progressent pas.

Coût pour atteindre le niveau n : arrondi(80 000 × (n − 1)^0,85). Le niveau 2 coûte 80 000 Þ ; toute la courbe a été réduite de 20 % à la demande du créateur. Pas de remise rétroactive ni de coût relatif au revenu du joueur. Coût total 1 → 40 : 38 860 220 Þ ; dernier niveau : 1 800 922 Þ. Le bonus marginal reste +5 points du rendement niveau 1 : les prix croissent sans emballement exponentiel des revenus.

| Niveau atteint | Coût du niveau Þ | Bonus commercial | Assimilation cumulée minimale |
|---|---:|---:|---:|
| 2 | 80000 | ×1.05 | 3 jours |
| 10 | 517841 | ×1.45 | 27 jours |
| 20 | 977306 | ×1.95 | 57 jours |
| 30 | 1400001 | ×2.45 | 87 jours |
| 40 | 1800922 | ×2.95 | 117 jours |

Le dernier niveau ajoute 10 000 Þ/jour à un monde de 200 capacités occupées à distance 500, avant Aurite. Son amortissement marginal de référence est donc de 180.1 jours. Un niveau 40 obtenu au jour 117 peut encore être amorti avant la fin d’une session d’un an dans ce scénario ; une occupation faible ou une longue distance peut le rendre non rentable. Le coût total des seuls niveaux de civilisation pour douze mondes atteint 466 322 640 Þ.

## Sensibilité et budgets

Scénarios avec N mondes possédant déjà chacun 200 capacités toutes occupées et leurs partenaires disponibles. Le réseau et les conquêtes sont supposés préfinancés : ces résultats sont optimistes et ne prédisent pas une nouvelle partie. Un seul monde cible monte en civilisation ; les autres restent niveau 1. Population fixe de 1 million et 100 soldats par monde. Trésorerie initiale de 100 000 Þ. Versements trois fois par jour. 55 % du revenu net est alloué à la civilisation du monde cible ; 45 % est réservé aux autres besoins. Aucune conquête, file industrielle ou recherche n’est simulée.

| Mondes financés | Distance | Budget civilisation | Jour niveau 20 | Jour niveau 40 | Niveau au jour 365 |
|---|---:|---:|---:|---:|---:|
| 1 | 500 | 55 % | 63.67 | 166.33 | 40 |
| 4 | 500 | 55 % | 57 | 117 | 40 |
| 12 | 500 | 55 % | 57 | 117 | 40 |
| 12 | 100 | 55 % | 57 | 117 | 40 |
| 12 | 900 | 55 % | 57 | 117 | 40 |
| 12 | 500 | 100 % | 57 | 117 | 40 |

L’assimilation fournit un plancher temporel, l’argent fournit une contrainte supplémentaire. Développer les autres mondes, une flotte ou des technologies entre en concurrence avec cet investissement. Un joueur concentrant tous ses revenus constitue un scénario de contrôle, pas le budget recommandé.

## Cadre pour les prochains systèmes

- Les revenus affichés déduisent une seule fois les entretiens : distance, soldats et vaisseaux. Les achats et recherches sont des investissements ponctuels, pas un deuxième prélèvement journalier.
- Préserver une enveloppe de départ indicative de 55 % pour civilisation/infrastructures, 30 % pour acquisition/remplacement militaire et 15 % pour recherche. Ces parts servent aux simulations et ne sont pas des taxes en jeu. L’entretien d’une flotte construite réduit les revenus nets avant cette répartition.
- Prix militaires validés : scout 2 000 Þ, bombardier 12 000 Þ, chasseur 16 000 Þ. Entretien quotidien : 20 / 60 / 80 Þ. Le recrutement automatique n’a pas de prix d’achat ; son entretien est de 2 Þ/soldat/jour. Voir military-alpha.md pour les temps et les capacités de transport.
- Une technologie donnant un bonus économique se juge sur son gain marginal, pas sur le revenu total de la planète. Cible d’amortissement de travail : 10–20 jours pour le début, 30–60 jours pour la fin, avec durée et prérequis. Aucun cumul exponentiel implicite : documenter si les bonus s’additionnent ou se multiplient.
- Pour les futurs ajustements de chantiers et recherches : simuler 1, 4 et 12 mondes, occupation 25/50/100 %, distances proches/moyennes/lointaines, ressources, civ 1/10/20/40, budgets militaires et pertes. Les limites de partenaires et délais de conquête doivent entrer dans une simulation de partie complète.

Les investissements sont financés immédiatement et assimilés en file, sans remboursement. Chaque planète progresse indépendamment. Les niveaux déjà acquis sont conservés après capture ; les programmes inachevés sont interrompus. Ferros ne réduit pas les trois jours d’assimilation. Les simulations ci-dessus ne promettent pas d’atteindre le niveau 40 au jour 117. Les technologies et la croissance démographique restent à développer.
