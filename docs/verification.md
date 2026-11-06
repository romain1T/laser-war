# Vérification de la tranche 0.1

## Réussites observées

- Analyse syntaxique des modules JavaScript.
- Tests Node : échappement HTML, validation des noms et validation de l'origine des liens e-mail.
- Postgres : deux identités de test dans une transaction annulée ; isolation des profils/empires/planètes, refus des écritures directes, refus du pseudo dupliqué, retour idempotent et 50 + 5 × 2 mondes.
- API Supabase réelle : connexion d'un compte QA confirmé et jetable, trois fondations concurrentes retournant le même empire, lecture d'un seul empire et d'une seule planète, trésorerie de départ correcte, refus des écritures directes, refus de la lecture anonyme.
- Storage réel : téléversement du portrait, liaison au profil et génération d'un lien signé ; refus d'écrire dans le portrait d'un autre utilisateur. Avatar QA supprimé par l'API après le test.
- Déconnexion réelle du compte QA.
- CI GitHub du commit initial : succès.
- Publication privée Sites : succès.
- Après connexion ChatGPT par le propriétaire : écran de connexion inspecté visuellement, illustration et formulaires correctement affichés. Un compte utilisateur réel a été créé et son adresse confirmée dans Supabase. Le lien de confirmation réutilisé a été refusé ; le message est désormais traduit et explique le retour à la connexion.
- Parcours réel effectué par le propriétaire : inscription, confirmation, connexion, fondation de l'empire et première planète visible. Rechargement du navigateur : empire, planète, race, ressource et trésorerie conservés. Écrans profil et trésorerie contrôlés.
- Affichage mobile contrôlé à 390 × 844 : navigation inférieure, illustration, informations et absence de débordement horizontal détecté. Affichage ordinateur rétabli ensuite.
- Le compte QA, son empire et les cinq mondes qu'il avait générés ont été supprimés avec des gardes sur son identifiant et son marqueur test_only. Aucun compte utilisateur réel n'a été modifié. Les fixtures SQL avaient déjà été annulées par rollback.

## Limites à ne pas confondre avec une validation

- Une confirmation réelle a été observée, mais la récupération du mot de passe par e-mail n'est pas vérifiée. SMTP pour les inscriptions publiques et redirections hébergées nécessitent la configuration décrite dans le README.
- Le compte QA confirme le parcours API après confirmation ; il ne valide pas l'envoi d'e-mails.
- Le navigateur local n'a pas pu joindre le serveur de développement. Le contrôle visuel a été réalisé sur la version privée hébergée, après connexion ChatGPT par son propriétaire.
- Les règles de combat, l'économie et la progression ne font pas partie de cette tranche et n'ont pas été simulées.

## Audit

Aucun avertissement RLS ou fonction privilégiée exposée. L'advisor Auth signale la protection contre les mots de passe compromis désactivée. Les index de planètes sont encore signalés inutilisés sur ce petit univers ; ils sont conservés pour les requêtes par propriétaire et session.
