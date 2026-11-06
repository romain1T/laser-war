# Vérification économique — 6 novembre 2026

Les tests SQL utilisent des transactions annulées : achats idempotents et charge utile inchangée, devis périmés, plafond 200, refus de lecture du registre privé, réservations aux deux extrémités, acceptation manuelle, revenus locaux bilatéraux, bonus Aurite, limites de versement sur plusieurs cycles, rattrapage hors connexion, annulation, expiration et conservation comptable. Le test de dette a révélé un arrondi prématuré : la migration precise_accrual_seconds multiplie maintenant le taux par les secondes avant la division. Tests de dette et de cycles repassés avec succès.

REST réel avec deux comptes jetables : connexion, trois achats concurrents facturés une seule fois, refus d’un devis ancien, réservation manuelle, rejeu de commande, acceptation, revenus pour les deux joueurs et refus d’accès au tableau commercial adverse. Les métadonnées Auth de ces comptes fictifs ont été corrigées avant ces essais (instance et dates de création).

Navigateur : achat de deux capacités pour 666 Þ, solde 99 001 → 98 335 Þ et capacités 3 → 5. Liaison automatique à distance 68, rendement net affiché 1 432 Þ/jour ; autre liaison à distance 709, rendement 791 Þ/jour. Rapport financier civil 20 000, commerce brut 3 000, entretien liaisons 777 et soldats 200 ; net 22 023 Þ/jour. Persistance après rechargement. Mobile 390 × 844, largeur du document 375, aucun débordement horizontal. Viewport rétabli et compte QA déconnecté.

Cron laser-war-economy actif chaque minute, dernières exécutions réussies. Activation réelle autorisée explicitement par le propriétaire à 20:53:42 UTC. Premier versement prévu le 7 novembre à 00:00 UTC (01:00 Paris), uniquement pour le temps écoulé depuis activation. Les frontières de versement ont été simulées en rollback ; aucun faux versement n’a été ajouté au joueur réel.

L’advisor ne signale pas de nouvelle faille : les tables privées à RLS sans politique sont volontairement interdites aux clients. L’avertissement Auth préexistant sur les mots de passe compromis reste inchangé. Quatre tests Node passent ; contrôles de syntaxe app, clans et economy passent.

Déploiement Sites public version 5, source e204c131f3305982cef536fc128ec246532cb4e0. Population, civilisation, production et combats ne sont pas simulés dans cette tranche. La simulation économique sur 365 jours suppose une disponibilité totale des partenaires et ne prédit pas une partie concurrentielle.
