# Laser War · Alpha 0.1

Jeu de stratégie spatiale asynchrone. Première tranche : authentification Supabase, fondation transactionnelle d'un empire, première planète persistante, portrait privé et interface responsive.

## Lancer

Node.js 22 ou plus. Aucun build requis pour le navigateur : `node scripts/serve.mjs`, puis http://localhost:4173. Le client officiel Supabase 2.119.0 est livré dans `dist/supabase.js`. `pnpm install --frozen-lockfile` installe la même version pour les outils futurs. `node --test tests/*.test.mjs` et `node --check dist/app.js` vérifient le code.

`dist/config.js` ne contient qu'une URL et une clé **publishable** : elles sont publiques par conception. Aucune clé privilégiée n'est nécessaire au client. Pour un autre environnement, utiliser un autre projet Supabase et remplacer cette configuration. Ne jamais utiliser la base de production pour les démonstrations.

## Base de données

Migration SQL versionnée dans `supabase/migrations/`. Déjà appliquée au projet `qidkgtuvcvoztzfmflgw`. Ne pas la rejouer manuellement sur ce projet. `supabase/config.toml` décrit le développement local et ne configure pas automatiquement le projet hébergé. Les tables sont protégées par RLS ; les écritures de jeu passent par `found_empire`. Le client n'envoie ni prix, ni soldes, ni statistiques de départ.

`tests/database.sql` teste l'isolation de deux joueurs, les écritures refusées, l'unicité des pseudos, l'expansion de l'univers et l'idempotence. Les données de test restent dans une transaction annulée. Aucun compte de démonstration permanent n'est livré.

`tests/live-api.mjs` vérifie un compte QA confirmé et jetable via l'API réelle : connexion, trois fondations simultanées, lecture persistante, écritures interdites, stockage privé et déconnexion. Les identifiants sont reçus sur stdin masqué et restent en mémoire. Ce test ne doit être lancé que contre un environnement de test avec un compte explicitement jetable.

## E-mails : configuration hébergée

Dans Supabase → Authentication → URL Configuration, définir Site URL sur `https://laser-war-command.romaint133.chatgpt.site` et autoriser cette même URL et `http://localhost:4173` comme redirections. Conserver la confirmation des e-mails. Le connecteur disponible ne permet pas de modifier cette configuration.

Configurer un SMTP adapté avant d'ouvrir les inscriptions à tous : l'envoi par défaut de Supabase peut être limité aux adresses autorisées de l'organisation et limité en fréquence. La réception réelle des e-mails n'a pas été vérifiée sans accès à une boîte destinataire. L'application gère les erreurs d'envoi et permet de coller le lien original reçu par e-mail, sans visiter une redirection localhost. Elle vérifie le token uniquement auprès du projet Supabase attendu.

L'advisor Auth signale que la protection contre les mots de passe compromis n'est pas activée. La config locale recommande au moins 10 caractères ; la configuration hébergée Auth doit être vérifiée séparément. Voir https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection.

## Hébergement et sources

Le dossier `dist/` est statique et peut être hébergé indépendamment. Le Site privé est déclaré dans `.openai/hosting.json`. GitHub conserve le code, les migrations et la documentation ; l'hébergement Sites utilise une copie de source synchronisée. L'alpha privée n'est pas encore ouverte au public.

Voir [règles](docs/rules.md), [architecture](docs/architecture.md) et [master prompt](docs/master-prompt.md).
