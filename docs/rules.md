# Règles et état réel

## Validées par le master prompt

- Stratégie spatiale multijoueur asynchrone ; session d'un an ; 12 planètes maximum à terme.
- Race et ressource attachées aux planètes. Aucun choix de race à l'inscription.
- Compte email/mot de passe, pseudo, récupération et avatar.
- Une seule possibilité de nommer la planète de départ ; nom neutre unique Terra_Nullius_<serial>.
- 50 planètes initiales, ajout de 5 mondes à chaque nouvelle participation.
- Monnaie Þ. Autorité serveur et brouillard de guerre dans les réponses de la base.

## Implémentées dans cette tranche

Authentification via Supabase, création de l'empire après confirmation de l'e-mail, lecture des données possédées uniquement et avatar privé. La fondation verrouille la session, crée le profil, l'empire et cinq planètes dans la même transaction. La répétition retourne l'empire existant sans nouvelle allocation. Les autres mondes ne sont pas lisibles par le client, même en interrogeant directement PostgREST.

Le pseudo est demandé à l'inscription mais son unicité insensible à la casse est réservée à la fondation. Une collision est signalée et un autre pseudo peut être choisi avant de fonder l'empire. À la fondation, le nom de planète est consommé ; aucun renommage direct n'est autorisé.

La session Alpha commence à la migration et se termine un an plus tard. Le serveur refuse les fondations hors de cette période. La fin ne lance pas encore de classement, d'archivage ni de nouvelle session automatique.

## Propositions provisoires

- Les 5 mondes supplémentaires incluent le monde de départ : total 50 + 5 × empires. Pas d'attribution d'un ancien monde neutre.
- Départ : 100 000 Þ, 1 000 000 habitants, civilisation 1, 100 soldats, 0 vaisseau, 0 capacité commerciale, énergie 0/100, Conseil. Aucune croissance passive ni production activée.
- Vael : flottes +15 %, soldats −15 %. Khar : soldats +15 %, flottes −15 %. Elys : équilibrés.
- Aurite : revenus civils et commerce +15 %. Biomasse : soldats +15 %. Ferros : chantiers ×1,15 en vitesse.
- Matelot est le seul grade affiché ; aucune progression n'est encore définie.

Ces bonus sont des descriptions de règles futures. Ils ne déclenchent aucun calcul inexistant.

## Confidentialité actuelle

| Information | Accès |
| --- | --- |
| Nom et dates de session | Joueurs connectés |
| Profil et portrait | Propriétaire uniquement |
| Empire, trésorerie et grade | Propriétaire uniquement |
| Toutes les données de sa planète | Propriétaire uniquement |
| Coordonnées et données d'un monde extérieur | Aucun accès client dans cette tranche |
| Carte et informations reconnues | À développer via une projection serveur dédiée |

## À décider / développer

Interprétation de « six domaines » dans la page Planètes (la limite d'empire reste 12), valeurs de départ, progression des grades, équations économiques et simulation d'un an. L'arbre Hyperiums est une référence à adapter : bâtiments, noms de races, classes de vaisseaux et protections mentionnées ne constituent pas des règles automatiquement adoptées.

Économie, simulation hors connexion, combats horaires, technologies, énergie utilisable, capitale, clans, commerce, carte, notifications persistantes et forum ne sont pas actifs. Les entrées correspondantes sont annoncées à venir.
