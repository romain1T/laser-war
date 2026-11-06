# Règles et état réel

## Validées par le master prompt

- Stratégie spatiale multijoueur asynchrone ; session d'un an ; 12 planètes maximum à terme.
- Race et ressource attachées aux planètes. Aucun choix de race à l'inscription.
- Compte email/mot de passe, pseudo, récupération et avatar.
- Une seule possibilité de nommer la planète de départ ; nom neutre unique Terra_Nullius_<serial>.
- 50 planètes initiales, ajout de 5 mondes à chaque nouvelle participation.
- Monnaie Þ. Autorité serveur et brouillard de guerre dans les réponses de la base.
- Aucun nom d'empire à choisir : le joueur nomme sa planète d'origine.
- Commerce possible avec toute planète, sans restriction de clan ou de propriétaire. Acceptation automatique activée par défaut ; mode manuel pour examiner les demandes avant de les accepter.
- Création ou adhésion à un clan ; chaque planète peut afficher ou masquer individuellement son affiliation.
- Planètes neutres : 5 capacités commerciales qui ne croissent jamais, population et civilisation fixes, garnison de départ de 1 scout et 1 soldat.

## Implémentées dans cette tranche

Authentification via Supabase, première planète après confirmation de l'e-mail, lecture des données possédées et avatar privé. La fondation verrouille la session, crée le profil, la participation et cinq planètes dans la même transaction. La répétition retourne la participation existante sans nouvelle allocation. Le modèle interne conserve la table empires et les anciens noms pour une migration non destructive ; aucun nom d'empire n'est demandé, chargé ni affiché dans l'interface.

Clans : création, adhésion libre, départ, succession du fondateur au membre le plus ancien et dissolution au dernier départ. Un clan par participation dans la session. Nom unique insensible à la casse, 3 à 24 caractères sans crochets. Ce sont les choix techniques de cette première version ; candidatures, invitations, rangs et modération ne sont pas encore développés.

Les tags sont désactivés par défaut. Afficher le tag montre NomPlanète [NomClan] sans modifier le nom enregistré. Quitter un clan masque les tags de toutes ses planètes ; rejoindre un autre clan ne les réactive pas. L'annuaire des clans ne révèle pas leurs membres. Seul le joueur voit son appartenance, son rôle et l'effectif de son propre clan.

La carte utilise une projection serveur : coordonnées publiques, noms et tags déclarés publics pour les mondes taggés. Sans reconnaissance, les autres mondes sans tag deviennent Signal <serial>, quelle que soit leur propriété réelle. Propriétaire, race, ressource, population et forces restent absents des réponses. Les mondes du joueur restent identifiés pour lui.

La préférence commerciale est enregistrée par planète (auto_trade=true par défaut). Les liaisons et revenus sont calculés par le serveur.

Les 54 mondes neutres existants ont reçu 5 capacités, 1 scout et 1 soldat, sans modifier leur population ni leur civilisation. Les nouvelles planètes neutres suivent la même initialisation. Une contrainte maintient les capacités neutres à 5 et un trigger refuse leur croissance démographique ou de civilisation. Les planètes possédées par des joueurs ne sont pas affectées. La résolution des pertes en combat sera définie avec le moteur militaire ; aucun recrutement neutre automatique n'est actif.

Le pseudo est demandé à l'inscription mais son unicité insensible à la casse est réservée à la fondation. Une collision est signalée et un autre pseudo peut être choisi avant de fonder l'empire. À la fondation, le nom de planète est consommé ; aucun renommage direct n'est autorisé.

La session Alpha commence à la migration et se termine un an plus tard. Le serveur refuse les fondations hors de cette période. La fin ne lance pas encore de classement, d'archivage ni de nouvelle session automatique.

## Propositions provisoires

- Les 5 mondes supplémentaires incluent le monde de départ : total 50 + 5 × empires. Pas d'attribution d'un ancien monde neutre.
- Départ : 100 000 Þ, 1 000 000 habitants, civilisation 1, 100 soldats, 0 vaisseau, 0 capacité commerciale, énergie 0/100, Conseil. Aucune croissance passive ni production activée.
- Vael : flottes +15 %, soldats −15 %. Khar : soldats +15 %, flottes −15 %. Elys : équilibrés.
- Aurite : revenus civils et commerce +15 %. Biomasse : soldats +15 %. Ferros : chantiers ×1,15 en vitesse.
- Matelot est le seul grade affiché ; aucune progression n'est encore définie.

Le bonus Aurite est actif pour les revenus civils et le commerce net. Les bonus militaires, industriels et de croissance attendent leurs moteurs.

## Confidentialité actuelle

| Information | Accès |
| --- | --- |
| Nom et dates de session | Joueurs connectés |
| Profil et portrait | Propriétaire uniquement |
| Participation, trésorerie et grade | Propriétaire uniquement |
| Toutes les données de sa planète | Propriétaire uniquement |
| Position d'un monde extérieur | Joueurs de la session via projection serveur |
| Nom et tag d'un monde extérieur | Publics uniquement si tag activé ; sinon signal anonyme |
| Propriétaire et informations stratégiques extérieurs | Jamais retournés dans cette tranche |
| Membres des clans | Relation privée non exposée ; aucune liste publique |

## À décider / développer

Interprétation de « six domaines » dans la page Planètes (la limite d'empire reste 12), valeurs de départ, progression des grades, équations économiques et simulation d'un an. L'arbre Hyperiums est une référence à adapter : bâtiments, noms de races, classes de vaisseaux et protections mentionnées ne constituent pas des règles automatiquement adoptées.

Combats horaires, technologies, énergie utilisable, capitale, reconnaissance, notifications persistantes et forum ne sont pas actifs. Les entrées correspondantes sont annoncées à venir.

## Économie active

Paramètres : voir economy-proposal.md. Revenus aux deux extrémités, bonus locaux. Commerce net décroissant avec la distance : 1 500 − min(distance, 1 000) Þ/capacité/jour avant bonus. Civil : 20 000 Þ/million/jour. Entretien quotidien : soldat 2 Þ, scout 20 Þ, bombardier 60 Þ, chasseur 80 Þ.

Achat jusqu’à 200 capacités selon la courbe validée ; prix serveur et devis périmé refusé. Une demande réserve les deux extrémités pendant 24 heures sans rapporter ; acceptation automatique par défaut, mode manuel par planète. Activer le mode automatique accepte aussi les demandes en attente non expirées. Changer de mode ne ferme pas les liaisons déjà actives. Chaque extrémité peut fermer une liaison.

Versements à 00:00, 08:00 et 16:00 UTC, prorata réel et fractions conservées. L’économie a été activée avec accord explicite du propriétaire le 6 novembre 2026 à 20:53:42 UTC, sans rétroactivité. La trésorerie ne devient pas négative : l’entretien impayé est conservé et remboursé par les revenus suivants.

## Civilisation et présentation commerciale

Départ au niveau 1, plafond 40. Le bonus commercial local validé est 1 + 0,05 × (niveau − 1), appliqué après entretien de distance, puis multiplié par Aurite si présent. Les mondes neutres restent fixes. Les niveaux de civilisation sont publics dans les échanges, avec le nom et les capacités libres ; les données militaires et le propriétaire restent privés.

Les barres distinguent les capacités de notre liaison des capacités libres, pour chaque extrémité. Un petit bloc vaut une unité ; un bloc de couleur différente marqué 10 représente une dizaine. Elles ne montrent pas la répartition des autres relations du partenaire.

Le quatrième mois est une cible indicative pour le niveau 40, sans verrou calendaire. La proposition de progression, ses coûts et simulations sont dans civilization-balance.md ; les commandes d’investissement et l’assimilation ne sont pas encore développées.
