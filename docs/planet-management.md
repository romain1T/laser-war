# Page Planètes — gestion compacte

Navigation : Civilisation reste dans le bandeau supérieur, avec son insigne sur mobile ; l’entrée du menu latéral et le bloc commandant/session redondant sont supprimés. Le pied de page conserve la marque, sans message de sauvegarde.

L’en-tête planétaire rassemble race, ressource, civilisation et population compacte (1 800 000 → 1.8M), avec le nombre exact en infobulle. Le texte narratif générique disparaît.

Quatre encarts :

- Politique & civilisation : choix Conseil/Tyrannie et investissement de civilisation, deux modules de même niveau visuel. Les bonus de recrutement sont actifs ; la croissance démographique reste annoncée à venir.
- Économie & commerce : capacités utilisées et libres dans les mêmes blocs jaunes / orange / verts que Commerce ; achat immédiat via la commande existante, avec devis et protections de reprise réseau.
- Garnison : Soldat, Scout, Bombardier, Destroyer, avec effectifs distincts et accès aux forces.
- Énergie : réserve locale uniquement. Le renommage reste disponible une fois après capture, dans son formulaire conditionnel ; aucun statut « Utilisé » n’est affiché.

Destroyer est le nouveau libellé du vaisseau spatial auparavant affiché Chasseur. Les clés internes fighter/fighters, les unités existantes, prix, transports et statistiques sont conservés pour compatibilité ; aucun quatrième type de vaisseau n’est ajouté.

planet_overview ne retourne que les capacités des mondes possédés et la courbe publique de prix. set_governance vérifie session, propriétaire, mode attendu et identifiant de requête. Les événements dus sont traités avant le changement ; les bonus horaires futurs suivent la nouvelle politique. Aucun changement de régime n’est lancé automatiquement. Les accès directs en écriture restent interdits.

Vérifications initiales : 30 tests Node, dont changement Conseil/Tyrannie avec recrutement Biomasse 1,38 → 2,07, conservation des fractions, répétition idempotente, devis politique périmé, refus de propriété étrangère et d’accès anonyme, achat de capacités et population 1.8M. Migration validée en rollback puis appliquée. Les avis Supabase restent ceux des tables privées volontairement fermées et de l’avertissement Auth préexistant sur les mots de passe compromis.
