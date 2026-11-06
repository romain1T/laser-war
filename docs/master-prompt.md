Tu es mon partenaire de conception et de développement. Je souhaite créer un jeu de stratégie spatiale multijoueur asynchrone, jouable dans un navigateur, avec une interface immersive et richement illustrée.
Le projet sera versionné sur GitHub et utilisera Supabase pour l’authentification, la base de données, le stockage des avatars et illustrations, et la synchronisation des données. Je n’ai pas encore de nom de domaine ou de serveur.
1. Concept général
Chaque joueur dirige un empire spatial. Il commence avec une planète et peut posséder jusqu’à douze planètes.
Le jeu repose sur :
Le développement économique et démographique des planètes.
Les relations commerciales entre systèmes.
La recherche technologique.
La constitution et le déplacement de flottes.
La reconnaissance et la conquête.
Les clans et la diplomatie.
Une session dure un an. La progression doit permettre de jouer régulièrement sans exiger une présence permanente.
Nous construirons le projet progressivement, page par page. Le forum sera développé plus tard.
2. Univers et direction artistique
L’univers est entièrement science-fiction, avec une identité originale et cohérente :
Empires interstellaires, stations orbitales et mégastructures.
Planètes spectaculaires et civilisations extraterrestres.
Architecture monumentale, technologies avancées et énergie mystérieuse.
Esthétique illustrée 2D/2.5D, détaillée, avec une influence manga/shōnen.
Espace profond, lumières atmosphériques, hologrammes et contrastes marqués.
Je veux une véritable interface de jeu intégrée à cet univers. Les illustrations doivent être les protagonistes des écrans.
Évite le rendu SaaS/dashboard, les empilements de cartes génériques et les grandes surfaces vides sans intention artistique.
Les textes, statistiques, boutons, progressions et infobulles doivent rester de vrais éléments HTML interactifs. Une illustration ne doit jamais servir de faux écran fonctionnel.
Prévois une composition immersive sur ordinateur et une expérience réellement adaptée au mobile. Les animations doivent rester discrètes et respecter prefers-reduced-motion.
Les assets définitifs pourront être fournis progressivement. Organise leur intégration proprement, avec des correspondances fiables et des fallbacks. N’invente pas une bibliothèque d’illustrations déjà disponible.
3. Comptes et identité des joueurs
Prévoir :
Inscription avec nom d’utilisateur, e-mail et mot de passe.
Connexion, déconnexion et récupération du mot de passe.
Profil avec avatar téléversable.
Grade actuel.
Création ou adhésion à un clan.
Le joueur ne choisit pas de race à l’inscription. Les races sont une caractéristique des planètes, au même titre que leurs ressources.
Les grades s’inspirent d’une marine militaire spatiale à la star wars, de Matelot jusqu’à Jedi Amiral. Propose une progression cohérente, en distinguant clairement les règles proposées des règles validées.
Une barre supérieure compacte affiche :
[Grade] [Nom du joueur] | [Trésorerie] | Notifications et Alertes | Flottes en transit | Civilisation | Aide | Forum
La trésorerie ouvre la page des revenus. Le forum reste clairement indiqué comme indisponible tant qu’il n’est pas développé.
4. Planètes, races et ressources
Chaque planète possède notamment :
Un nom.
Une race.
Une ressource principale.
Une population et sa croissance.
Un niveau de civilisation.
Une capacité commerciale.
Une garnison et des vaisseaux.
Une gouvernance.
Des infrastructures.
Une réserve d’énergie locale.
Les races et ressources restent attachées à la planète après sa capture.
Prévoir trois races, avec des noms et une identité visuelle science-fiction à proposer :
Race spécialisée dans les combats spatiaux : puissance des flottes +15 % mais puissance des soldats -15%
Race spécialisée dans les combats terrestres : puissance terrestre +15 % mais puissance des flottes -15%
Race polyvalente : puissances spatiale et terrestre équilibrée
Prévoir trois ressources, également à renommer pour cet univers :
Ressource économique : commerce et revenus civils locaux +15 %.
Ressource biologique : production automatique de soldats +15 %.
Ressource industrielle : vitesse des chantiers +15 %, soit une durée divisée par 1,15.
Chaque race et chaque ressource dispose d’un pictogramme. À terme, chaque combinaison race × ressource pourra avoir sa propre illustration.

Prévoit de base 50 planetes dans l’univers. A chaque création de compte, 5 planetes supplémentaires doivent apparaitre dans l’univers.
Nom et propriété
Les terres sans propriétaire humain utilisent un nom procédural de type Terra_Nullius_1234, avec des identifiants uniques.
Le joueur peut renommer une planète :
Une fois lors de la création du compte pour sa première planète.
Une fois après chaque capture autorisant ce choix.
Une fois ce choix consommé, le renommage n’est plus proposé.
Le joueur peut choisir d’afficher publiquement ou de masquer l’affiliation de chaque planète à son clan.
Brouillard de guerre
L’exploration doit conserver un véritable effet de surprise.
Avant une reconnaissance autorisée, ne révèle pas pour une planète extérieure :
Son propriétaire réel.
Son caractère neutre, habité ou hostile.
Les forces présentes.
Ses informations stratégiques cachées.
Cette confidentialité doit être appliquée côté serveur et dans les données retournées, pas uniquement par un masquage visuel.
Définis explicitement quelles informations sont publiques, découvertes ou confidentielles.
5. Économie et commerce
La monnaie utilise le symbole Þ, jamais l’euro. Les montants doivent se compter naturellement en milliers et en millions.
Les revenus sont distribués trois fois par jour, mais les écrans présentent des montants par jour. Les détails des cycles de versement sont expliqués dans l’aide, sans vocabulaire technique envahissant dans l’interface.
Le commerce fonctionne avec des capacités partagées entre les liaisons :
Chaque liaison consomme des capacités aux deux extrémités.
Une capacité déjà occupée ne peut pas être réutilisée.
L’affichage 77/77 signifie 77 capacités occupées sur 77, donc aucune disponible.
La distance influence la rentabilité.
Chaque planète est limitée à 200 capacités commerciales.
La page Commerce permet de sélectionner une planète pour piloter ses liaisons individuellement.
Coût des capacités
Je veux une courbe cohérente sur une session d’un an :
Les premières capacités doivent être rapidement rentables.
Jusqu’à la vingtième, l’ordre de grandeur visé est un versement de revenus pour amortir une capacité exploitée.
Autour de la cinquantième, l’amortissement marginal de référence vise environ 15 jours.
Ensuite, le délai continue d’augmenter progressivement, sans rendre les dernières capacités absurdes ou inutilisables avant la fin de session.
Propose une formule continue et une simulation aux seuils 20, 50, 100, 150 et 200. Distingue bien rentabilité de la prochaine capacité et rentabilité de l’investissement cumulé.
N’utilise pas une exponentielle incontrôlée simplement pour atteindre un exemple chiffré.
Le revenu réel dépend de l’occupation, des distances et des bonus. Un réseau très développé peut viser plusieurs millions de Þ par jour ; l’équilibrage précis doit être démontré par des simulations.
Page Revenus
Afficher :
La trésorerie disponible.
Pour chaque planète : revenus civils, revenus commerciaux, entretien militaire, entretien des flottes et éventuels coûts industriels réellement implémentés.
Le solde quotidien de chaque planète et de l’empire.
Les dépenses doivent être comptabilisées une seule fois, y compris pour les unités en transit.
6. Civilisation, population et gouvernance
L’investissement dans la civilisation n’accorde pas immédiatement un niveau.
100 000 Þ nécessitent trois jours d’assimilation pour produire un niveau supplémentaire.
Prévoir :
Une réserve d’investissements en attente.
La progression d’assimilation.
Le délai estimé avant le prochain niveau.
Des investissements successifs mis en file.
Une progression hors connexion cohérente.
La page Civilisation rassemble les planètes possédées et permet d’investir rapidement dans chacune.
Deux gouvernances :
Conseil : croissance démographique +20 %, production de soldats −20 %.
Tyrannie : croissance démographique −20 %, production de soldats +20 %.
Les limites de population, de recrutement et leurs interactions doivent être explicites et testées.
7. Capitale impériale et énergie
Le joueur peut désigner une planète comme capitale impériale, équivalent d’un Haut Lieu.
Elle bénéficie de :
Revenus locaux +20 %.
Production automatique de soldats +20 %.
Après une désignation, il est impossible de changer de capitale pendant 15 jours. Afficher le statut et le délai restant.
Chaque planète possède également une énergie locale, distincte de la monnaie :
Réserve actuelle et maximale.
Régénération.
Consommation par les pouvoirs actifs.
Infrastructures de production et de stockage.
Le système énergétique devient utilisable après une recherche dédiée.

8. Flottes et déplacements
Il n’existe qu’un type de batiments, les Chantiers spatiaux, ou sont produits trois types de vaisseaux : Vaisseau scout, pas cher a produire, petite capacité d’attaque, pas de transport de troupes.
Vaisseau bombardier : Plus cher a produire, permet d’emporter 10 soldats par vaisseau, bombarde les unités ennemies au sol mais ne peut attaquer les vaisseaux ennemis
Vaisseau de chasse : Assez cher a produire, permet d’emporter 10 soldats par vaisseau, efficace contre les vaisseau ennemis dans le ciel, pas de bombardement terrestre
Prévoir :
Flottes composées de vaisseaux, avec transport de troupes.
Départ, origine, destination, mission et heure d’arrivée.
Liste des flottes en transit avec compte à rebours.
défense et attaque.
Résolution des arrivées même lorsque le joueur est déconnecté.
Maintien des coûts d’entretien pendant le déplacement.
Lorsqu’un joueur arrive sur une planete, que ce soit en attaque ou en defense, ses soldats ne débarquent sur le sol que un ticket de combat (une heure) aprés leur heure d’arrivée. Chaque heure, la bataille avance, et en fonction des troupes et vaisseaux en conflit, un rapport de bataille est donné dans alertes et notifications, et les troupes restantes sont affichées. Quand on a seulement des vaisseaux, on ne peut pas voir les troupes au sol des autres joueurs. Si deux joueurs arrivent en defense sur une planete et qu’un autre joueur est en attaque, les deux joueurs en defense sont en équipe et combatte l’ennemi et vise versa etc.

Les unités doivent quitter leur origine au départ et ne jamais être dupliquées.
La plus longue traversée de la carte doit viser huit jours maximum à vitesse de base.
Les technologies de déplacement avancées doivent rester encadrées pour préserver l’intérêt des distances.
Les règles de combat détaillées pourront être affinées ensemble. Ne transforme pas une proposition non validée en règle définitive sans l’indiquer.
9. Technologies
The technology tree shows all the technologies that you can research to increase your power at Hyperiums.
Each technology takes time and money to be researched. Only one research at a time can be done by one planet. Once a technology has been found out, it is owned by you, as player, not by the planet which worked on it; thus, even if you lose all your planets, you do not lose your technologies.
Note that some technologies can only be researched by a specific population race.

The tech tree is always accessible by clicking on the yellow tree on the top left.

Infiltration technologies

All infiltration technologies bring cost reductions, for infiltrating and for fighting enemy infiltrations.

Genetic malleability level 1: Decreases the infiltration costs by 40% for target planets up to civilization level 6; decreases the counter-infiltration costs by 7%.

Genetic malleability level 2: Decreases the infiltration costs by 40% for target planets up to civilization level 7; decreases the counter-infiltration costs by 15%. Researchable only by the Human race.

Mind duplication: Decreases the infiltration costs by 40% for target planets up to civilization level 9; decreases the counter-infiltration costs by 25%. Researchable only by the Azterk race.

Mind control: Decreases the infiltration costs by 40% for target planets up to civilization level 11; decreases the counter-infiltration costs by 35%. Researchable only by the Xillor race.

Infiltration tech. level N: Decreases the infiltration costs by 40% for target planets up to civilization level N+7B.


Exploitation technologies

All exploitation technologies bring a 30% cost reduction for building new exploitations on your planets,up to a certain civilization level, as follows.

Workers productivity level 1: concerns any planet up to civilization level 4.

Workers productivity level 2: concerns any planet up to civilization level 5.

Cybernetics technologies level 1: concerns any planet up to civilization level 7.

Cybernetics technologies level 2: concerns any planet up to civilization level 9.

Agro exploit. level N: concerns Agro exploitations only, up to civilization level N+5. Researchable on Agro planets only.

Minero exploit. level N: concerns Minero exploitations only, up to civilization level N+5. Researchable on Minero planets only.

Techno exploit. level N: concerns Techno exploitations only, up to civilization level N+5. Researchable on Techno planets only.


War technologies

Fundamental technologies bring the possibility to build scouts, and opens the way to all the war and scanning technology tree.

The Camouflage capability is brought to your fleets and your armies by the Entropic shield technology. As long as they are camouflaged, the other players can not detect the owner of your military units, wherever they are. This technology can be used, for example, for anonymous attacks. While camouflaged, your fleets and armies are 25% less powerful at fight.
If you take a planet with camouflaged armies, you gain anonymous control of the planet for 21 days.

Switching up or down the camouflage of a stationed fleet or army makes it unavailable for 1 hour (N/A 1), unless it was already unavailable.

Cryogenic travel: allows construction of Destroyers and opens the way to research the Cruisers and Bombers technology.

Improved targetting systems: allows construction of Cruisers

Space/ground missiles: allows construction of bombers. Bombers are used to carry armies and to bomb the enemy planets. When the "massive bombing" mode is activated, they can destroy the population, exploitations and factories of the target planets, but they become easy targets for enemy ships (especially scouts).

The Stasis field is a powerful defensive technology brought by the Hypermathematics tech research. Once raised on your planet, the stasis field slows down, by a factor of 3 (on average), any battle that may start in the future on or around the planet.
As a downside, Stasis decreases the efficiency of factories by 66%.
The Stasis field can not be raised:
- if enemy ships are already present and surpass the defending ships' AvgP by 1% or more;
- if the planet was taken over less than 24 hours ago.
Raising a Stasis field spends 2 energy units, after what its upkeep cost is 1 energy unit per hour, with an additional cost of 1 energy unit per hour if a battle is raging and the attacking forces are in superiority.

Energy magmas bring the possibility to increase the energy storage capacity of your planets. Once a research level completed, you can increase the storage capacity of your planets on a per planet basis; the increase cost depends on the current storage capacity of each planet.

Black hole confinement: four levels must be researched before you get access to this ultimate weapon, which gives you the possibility to completely annihilate one of your planets and everything surrounding it (including all stationed ships and ships that have left the planet less than 2 hours ago, except those gone through Hypergate). Three of these levels are race specific.
The upkeep cost of a black hole is 1 energy unit per hour. Its preparation takes 48 hours. Once prepared, it can be activated (resulting in instantaneous annihilation of the planet) or cancelled at any time. The use of black holes is only allowed on dictatorial planets.
Annihilating a planet this way increases the delay to get a new planet from Hyperiums by 7 (cumulative) days for the player who activated it.
Any fleet moving to a black holed planet will be absorbed (destroyed) at arrival.
Planets that have left the Protectorate status within the past 15 days are not allowed to prepare a Black hole.

The offensive black hole is a special kind of black hole that not only destroys the planet where it is activated, but also dooms all other planets of the solar system to be absorbed (destroyed) within a time depending on the distance from the black hole (from 16 to 31 days); its preparation takes 96 hours and can not be hidden from the neighbouring planets.

Teleportation allows instant teleportation of armies:
- from any planet to any other planet of the galaxy (at the condition that one of them belongs to you),
- from any of your own planets to your starbase(s).
Teleportation costs one energy unit per army in general, or one energy unit for 2 armies when teleporting between two of your own planets, or to one of your starbases.

The different research levels of this technology (Improved teleportation level 1, 2, 3) bring greater teleportation capacity for the same energy consumption.

Note that, after you have taken over a planet, teleportation is not immediately available; your new planet must be connected to your teleportation network, which takes 4 hours per controlled planet.

Human/Azterk/Xillor ships level N: increases the fire power of the ships of the concerned race by up to 30%, depending on the average ships tech level of each side of the battle:
- if side A has an average tech level N, and side B has an average tech level N+D, all ships of side B get a power bonus of 3xD%, where 3xD can not be greater than 30.
- example 1: the attacking side has an average tech level of 10, the defending side has an average tech level of 17 => all defending ships get a power bonus of 21%.
- example 2: the attacking side has an average tech level of 100, the defending side has an average tech level of 60 => all attacking ships get a power bonus of 30%.

Only the ships built after the tech level N has been researched will benefit from this tech level. When merging fleets of different tech levels, an average tech level is computed for the whole.

Human/Azterk/Xillor armies level N: increases the fire power of the armies of the concerned race by up to 30%, depending on the average armies tech level of each side of the battle. The algorithm is the same as for the ships (see above).
As for ships, only the armies generated after the tech level N has been researched will be of tech level N.

Scanning technologies

Scanning technologies give the possibility to get instant information about any other planet of the same Supercluster within a distance of 50. All scans take 4 hours to complete and cost 80,000.
There are three different scanning modes:
- basic scan: the target planet is warned and knows which planet did it; it costs 1 unit of energy.
- anonymous scan: the target planet is just warned that a scan occured, but is unable to know which planet did it; it costs 2 units of energy. Approximately 5% of the anonymous scans actually fail to be anonymous and act as basic scans.
- stealth scan: the target planet is not informed that a scan occured; it costs 4 units of energy. Approximately 5% of the stealth scans actually fail to be stealth, and act as anonymous scans.

Universal relativity concept: opens the way to the research of all scanning technologies.

Stasis field scan detects if the stasis field is enabled on the target planet.

Fleets scan gives an approximate report of the overall power of all space ships around target planet.

Ground armies scan gives an approximate report of the overall power of all ground armies on the target planet.

Trading scan gives information on the most important trading relations of the target planet.

Hypertravel

The Hypertravel technology gives your fleets the possibility to "jump" from one point to any another point of the galaxy for a small and constant travel time.

An Hyperjump is done between two Hypergates connected to the same Hypernetwork. When setting up your Hypergate, you provide the name and the password of the network you want it to be connected to (if such a network does not exist, your own network will be initiated). The connection time depends on the number of planets already connected or being connecting to the network (it can take several days in a huge network composed of hundreds of planets).

Once your Hypergate connected, you can send your fleets from this gate to any other gate of the network. The travel time is 10 hours, whatever the real distance between the two gates and whatever the size of the fleet. If a gate closes or disconnects from the network while some fleets are jumping to this gate, these fleets will be randomly dispersed in the galaxy.

If you take a planet with an Hypergate connected to a network, you can use it to send your fleets to any other gate of this network.

The upkeep cost of an Hypergate is 1 energy unit per hour.
Planets that have left the Protectorate status within the past 15 days are not allowed to build an Hypergate.

Other technologies

Improved cryogenic technologies
Allows massive migration of populations between two planets of the same race, via dedicated space ships (the player does not have to build these ships). Starting a migration can be done from the planet overview page.
- Both planets must be of the same race and controlled by the player.
- The population of the origin planet must be greater than 5000M.
- The population of the destination planet can be larger than the population of the origin planet, but in this case the migration speed is reduced.
- If both planets are in the same Supercluster, the origin planet's population can not be leeched lower than half (50%) of the destination planet's population size; if the planets are not in the same Supercluster, this limit raises to 75%.
- The migration is stopped or can not be initiated when one of the two planets is under blockade.
- The migration is suspended during the player's vacation mode.
- If the population of the origin planet is larger than the population of the destination planet, some of its civilization level is also transferred in the process.
- If the destination planet is a Protectorate, its population can not increase through migration above 5000.0 x civilization level.

Energy Blast
With this advanced technology, you can disrupt and remove the energy on neighbouring planets, and destroy their fortifications. Depending on the quantity of energy you can spend, the Energy Blast will impact all planets within a certain distance from your own planet.
For instance, a Blast of 40 energy impacts all planets of the local solar system; a 80 energy Blast impacts all planets within distance 1, and 160 energy units are needed to Blast at distance 2, and so on...
Blasted planets have their energy storage emptied and their fortifications destroyed down to the 13% bonus level.
If a black hole is ready on a blasted planet, it is instantly cancelled (while blacks holes in preparation are not impacted). 
10. Pages principales
Prévoir une architecture permettant de développer progressivement :
Centre de commandement : écran immersif servant de point d’entrée.
Planètes : sélection jusqu’à six domaines, grande illustration et gestion locale.
Commerce : gestion des liaisons par planète.
Carte galactique : exploration et informations soumises au brouillard de guerre.
Armées et flottes : production, missions et déplacements.
Technologies : prérequis, coûts, délais et effets.
Compte et clan.
Revenus.
Civilisation.
Aide : règles détaillées et à jour.
Forum, dans une phase ultérieure.
Pour la page Planètes, regrouper les commandes en sections lisibles : population/civilisation, économie/commerce, garnison/gouvernance, énergie et capitale/identité.
10. Architecture GitHub et Supabase
Je veux une base adaptée à un véritable multijoueur, pas un jeu dont le navigateur peut modifier librement les résultats.
GitHub
Code source, historique et documentation dans le dépôt.
Changements progressifs et vérifiables.
Branches de travail et pull requests avec description et validation.
CI pour les vérifications pertinentes.
Aucun secret dans le dépôt.
Supabase
Utiliser les services appropriés pour :
Authentification.
Base Postgres.
Avatars et assets téléversés.
Politiques RLS et contrôle des accès.
Fonctions serveur et traitements planifiés nécessaires au jeu.
Le serveur doit être l’autorité pour :
La trésorerie.
Les achats et investissements.
La propriété des planètes.
Les recherches.
Les recrutements.
Les départs et arrivées de flottes.
Les combats et conquêtes.
Les versements économiques.
Les délais et dates de fin de session.
Ne fais jamais confiance à l’horloge du navigateur, aux coûts transmis par le client ou à un état de partie complet envoyé comme vérité.
Les commandes économiques et militaires doivent être transactionnelles et protégées contre les doubles exécutions, les requêtes simultanées et les répétitions réseau.
Prévoir des migrations versionnées, des données de démonstration séparées des vraies parties et une gestion claire des environnements de développement et de production.
Les clés privilégiées restent exclusivement côté serveur. Les informations cachées par le brouillard de guerre ne doivent pas être accessibles via des requêtes directes du client.
11. Méthode de travail
Commence par inspecter le dépôt GitHub et la configuration Supabase disponibles.
Ensuite :
Résume ta compréhension du jeu.
Distingue les règles fixées, les propositions d’équilibrage et les points restant à décider.
Propose une architecture concise et un découpage en étapes.
Mets en place une première tranche fonctionnelle : inscription/connexion, création de l’empire et de sa première planète, sauvegarde serveur et première page Planètes.
Poursuis progressivement avec des fonctionnalités réellement reliées à la base.
Avance de manière autonome sur les choix techniques courants. Pose uniquement les questions qui bloquent réellement une décision structurante.
Ne réinitialise pas les données existantes et n’applique pas de migration destructive sans autorisation.
Chaque fonctionnalité annoncée comme terminée doit être vérifiée de bout en bout : interface, commande serveur, base et retour visible.
Garde la documentation des règles cohérente avec le comportement réel. Signale clairement les simulations, éléments provisoires et fonctionnalités restant à connecter.
L’objectif est de construire progressivement un jeu spatial multijoueur solide, agréable à jouer et visuellement spectaculaire, en conservant la simplicité d’utilisation d’un jeu de stratégie asynchrone.

