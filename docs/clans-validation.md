# Clans, identité planétaire et carte

## Vérifications serveur

Tests SQL réussis dans une transaction annulée avec trois identités : première planète sans nom d'empire, absence de duplication, options par défaut, création et adhésion idempotentes, refus d'un second clan, validation du nom, départ, succession, dissolution, tags masqués au départ et rejet d'un départ ancien après changement de clan.

Confidentialité vérifiée sous les rôles clients : impossibilité de lire directement les appartenances privées, de lire la planète complète d'un autre joueur ou de modifier ses options. La projection de carte montre la signature publique uniquement quand le tag est activé ; sinon le monde extérieur reste un signal anonyme.

Tests Node réussis pour la validation sans nom d'empire et les libellés de clan sans modification du nom enregistré. Les modules app, clans et galaxy passent l'analyse syntaxique.

Le verrou de session et l'unicité clan/participation assurent que les répétitions réseau ne créent ni second clan ni seconde adhésion. Le départ précise le clan attendu afin de ne pas quitter un nouveau clan à la suite d'une vieille requête.

## Parcours réels vérifiés

L'API REST a été testée avec deux comptes confirmés jetables : connexion, trois départs de participation concurrents, trois créations de clan concurrentes, adhésions répétées, projection publique ou masquée, refus de modifier une planète adverse, préférence commerciale conservée, succession et déconnexion.

Dans le navigateur, le premier compte QA a créé un clan, activé le tag de sa planète et désactivé l'acceptation commerciale automatique. Le libellé de planète et la carte ont affiché le tag après la réponse serveur. Le rechargement a conservé le clan, le tag et la préférence. Le second compte QA a rejoint le clan via l'annuaire (effectif passé à deux), puis l'a quitté via l'interface. Les sessions QA ont été déconnectées.

Carte inspectée sur ordinateur et à 390 × 844 sur mobile : navigation inférieure à cinq entrées, panneau de signal, sélection et carte défilable ; aucun débordement horizontal du document détecté. Le viewport a été rétabli après le test.

Nettoyage terminé : comptes QA, clan QA, participations QA et leurs dix mondes supprimés avec gardes sur les identifiants, marqueurs test_only/fixture et absence de propriétaire ou membre réel dans les fixtures. Contrôle final : zéro compte QA, 55 mondes et une planète possédée. Les données du joueur existant ont été préservées.

## Audit et limites

La table privée des appartenances a RLS activé et aucun droit client ; son absence de politique est un refus total intentionnel, signalé comme information par l'advisor. Le contrôle des mots de passe compromis reste l'avertissement Auth préexistant.

Le commerce automatique est une préférence serveur par planète, activée par défaut. Les demandes, liaisons, capacités occupées et revenus ne sont pas encore implémentés. Les règles validées sont conservées dans docs/rules.md.

La carte affiche les positions, les mondes possédés et les tags publics. Elle ne réalise aucune reconnaissance et ne divulgue ni propriétaire extérieur ni données militaires ou économiques.
