# Énergie, téléportation et population

Le rendement commercial net après entretien de distance est multiplié par 1,075. Aurite et la civilisation conservent leurs multiplicateurs ; les frais de liaison ne changent pas. Les revenus déjà acquis sont réglés avant ce changement.

## Recherches et énergie

Deux recherches sont achetées une seule fois par participation : recharge d’énergie à 150 000 Þ et téléportation à 300 000 Þ. Elles ne sont pas achetées automatiquement. Les commandes sont sérialisées et idempotentes, avec prix et soldes contrôlés par le serveur.

La recherche Énergie initialise les mondes possédés à 10 charges, dans une réserve initiale de 10. Une charge se régénère en six heures. Les fractions sont conservées hors connexion et abandonnées lorsque la réserve est pleine, afin d’éviter une recharge cachée accumulée au-delà du plafond.

Le stockage augmente par planète jusqu’à 100. La place de rang n coûte `round(5000 × 1,055^(n−11))` Þ, pour n de 11 à 100. Une extension ne donne aucune charge gratuite. Le devis doit correspondre à la capacité actuelle.

## Téléportation

Elle ne transporte que les soldats au sol, jamais les vaisseaux ni les soldats encore embarqués. Les deux planètes doivent appartenir à des joueurs ayant recherché la TP, et au moins une extrémité appartient au joueur qui donne l’ordre. L’extrémité étrangère doit appartenir au même clan ou disposer d’un code valide.

Le coût est arrondi au supérieur : une charge pour cinq soldats, ou pour dix entre deux mondes du même joueur. L’énergie est prélevée sur le monde du joueur impliqué dans le saut : départ pour un envoi, arrivée pour un retour. Les soldats apparaissent immédiatement au sol sous forme de détachements défensifs, en conservant leurs races, leur propriétaire et leur entretien. Aucun mérite de production n’est accordé lors du déplacement.

Les codes sont hachés avec le bcrypt natif de Supabase. Aucun code ni hash n’est renvoyé par les tableaux de bord. Les tentatives incorrectes sont comptées même quand l’accès est refusé ; les limites sont dix par minute et par joueur et vingt par minute sur une planète. Les codes ne sont pas sauvegardés dans le stockage du navigateur ; une reprise demande de les saisir à nouveau.

Une conquête efface le code et impose une connexion au réseau de quatre heures par planète contrôlée. Le stockage physique existant est conservé ; les recherches restent propres au joueur. Les permissions de clan et les recherches des deux propriétaires sont revérifiées à chaque ordre.

## Démographie

Les mondes possédés croissent à une base de 0,5 % par jour, multipliée par 1,2 sous Conseil ou 0,8 sous Tyrannie, puis par `1 + 0,25 × occupation commerciale`. Seules les capacités actives comptent dans l’occupation ; les réservations en attente sont exclues.

Une présence offensive stationnée arrête la croissance sur la planète. Un combat sur l’un des cinq mondes les plus proches la divise par deux. Les neutres ne croissent jamais. La simulation règle l’économie avant chaque changement démographique ; les populations nouvelles affectent donc les revenus futurs et le recrutement, sans revenu rétroactif. Les fractions de population et d’énergie sont conservées entre les traitements.

## Validation

Les tests isolés vérifient les coûts, répétitions, stocks, plafonds, croissance et guerres proches, permissions, codes, TP et conservation des unités. Le simulateur SQL local emploie une fonction de test pour la comparaison des codes ; la disponibilité du bcrypt réel est vérifiée séparément sur Supabase.
