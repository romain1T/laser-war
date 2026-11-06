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

## Limites à ne pas confondre avec une validation

- La réception d'un e-mail de confirmation et de récupération dans une vraie boîte n'est pas vérifiée. SMTP et redirections hébergées nécessitent la configuration décrite dans le README.
- Le compte QA confirme le parcours API après confirmation ; il ne valide pas l'envoi d'e-mails.
- Le navigateur local n'a pas pu joindre le serveur de développement. L'accès au Site privé exige une connexion ChatGPT par son propriétaire ; la vérification visuelle et mobile dépend de cette connexion.
- Les règles de combat, l'économie et la progression ne font pas partie de cette tranche et n'ont pas été simulées.

## Audit

Aucun avertissement RLS ou fonction privilégiée exposée. L'advisor Auth signale la protection contre les mots de passe compromis désactivée. Les index de planètes sont encore signalés inutilisés sur ce petit univers ; ils sont conservés pour les requêtes par propriétaire et session.
