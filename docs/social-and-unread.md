# Forum, correspondance et indicateurs de lecture

Les nouvelles participations reçoivent 150 000 Þ. La migration modifie uniquement la valeur par défaut ; aucun solde existant n’est réécrit. Les trois pictogrammes de population fournis sont livrés en WebP et sélectionnés selon la race.

Chaque planète peut changer de politique une fois toutes les 72 heures. Le premier changement est libre. Un trigger impose le délai côté serveur, conserve l’horodatage pendant une conquête et ne relance pas le délai lors d’une répétition idempotente.

## Échanges

- Forum public de la session : création de discussions et réponses en texte brut.
- Forum de clan : lecture, publication et accusé de lecture autorisés selon l’appartenance actuelle. Quitter le clan retire l’accès ; sa dissolution supprime son forum.
- Grade, pseudo, portrait et signature de 280 caractères maximum sur les publications. Les portraits restent dans le bucket privé ; une politique permet leur affichage aux joueurs actifs par URL signée courte. Aucun accès anonyme.
- Correspondance privée entre deux participations. Destinataire recherché par pseudo ou nom de planète, jusqu’à quinze résultats. Le serveur résout le propriétaire au moment du premier envoi.
- Dans une conversation adressée à une planète, l’expéditeur voit le nom de la planète à la place de l’identité du destinataire, y compris sur ses réponses. La conversation reste avec le destinataire initial après un changement de propriétaire. Une signature volontairement écrite dans le corps peut évidemment révéler son identité.
- Titres de 3 à 120 caractères, corps de 1 à 5 000 caractères, limite de vingt publications par minute et par joueur. Le rendu échappe tous les contenus et n’interprète aucun HTML.
- Les listes et historiques sont paginés par cinquante. Les commandes conservent un identifiant de requête et une charge utile immuable ; une reprise permet de confirmer un envoi dont la réponse réseau a été perdue.

## Lecture

Les curseurs sont enregistrés par participation dans le schéma privé : revenus, notifications, forum public, clan précis, discussion et conversation. Les identifiants séquentiels sont transmis en chaînes pour préserver la précision.

Le bandeau signale les nouvelles recettes, opérations, publications et lettres. Une ouverture conserve les éléments récents en gras sur le rendu courant puis accuse réception de son instantané. Une actualisation affiche leur état lu. Un message arrivé après cet instantané reste non lu. Les lettres ne sont lues qu’en ouvrant leur conversation. L’indicateur est actualisé toutes les trente secondes lorsque le jeu est visible, sans remplacer les formulaires en cours de saisie.

## Vérification

`node --test tests/*.test.mjs` couvre notamment les accès intercomptes, l’exclusion des anciens membres, l’anonymat des adresses planétaires, les répétitions, les curseurs bornés, l’échappement et les 72 heures de délai.

`tests/live-social.mjs` accepte uniquement trois fixtures QA nommées et marquées par un même `qa_run`, via stdin masqué. Il vérifie Auth, upload et signature de portrait, réponses publiques, forum de clan, correspondance et lectures persistantes contre les vraies API. Les données QA sont supprimées après les essais navigateur.
