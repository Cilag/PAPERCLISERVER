Mission de conseil en virtualisation pour le client AIRSOLID (projet MSPR Ynov M1). Cadre la mission et confie l'exécution technique selon ton rôle (le Tech Lead organise les spécialistes et consolide).

## Contexte client AIRSOLID
- Distribution d'équipements aérauliques / climatisation, ~80 personnes
- Aucune équipe IT interne (ancien responsable parti)
- UN SEUL serveur physique (2012) : Active Directory + ERP web + partages fichiers
- Panne récente de 48h → activité commerciale et expéditions bloquées
- Déploiement Microsoft 365 en cours ; entrepôt secondaire prévu sous 12 mois
- Aucune politique de sauvegarde ; commerciaux nomades + postes atelier SAV
- Direction : sortir de la dépendance au serveur unique ("Plus jamais 48h sans ERP"), flux EDI sécurisé à prévoir

## Livrable attendu — repo /home/guigui/work/mspr-airsolid, dossier airsolid/
UN jeu de fichiers cohérent (pas de versions multiples du même fichier) :
- airsolid/README.md (sommaire du cas)
- airsolid/01-contexte-besoin.md (besoin reformulé)
- airsolid/02-architecture-proposee.md (archi virtualisée cible + schémas mermaid)
- airsolid/03-mise-en-oeuvre.md (hyperviseur, VMs, réseau, stockage, AD, Hyper-V)
- airsolid/04-objectifs-pedagogiques.md (les 8 objectifs OFFICIELS ci-dessous, dans CET ordre, chacun expliqué et appliqué à AIRSOLID)
- airsolid/05-evolutions-entretien-2.md (placeholder pour l'entretien 2)
- airsolid/assets/ (schémas éventuels)

## Les 8 objectifs pédagogiques OFFICIELS (titres exacts à respecter dans 04)
1. Proxmox / XCP-ng — hyperviseur type 1 adapté au besoin
2. Ressources & sécurité — dimensionnement, isolation, accès, tiers
3. Hybride on-prem / cloud — local / SaaS / hébergement externe
4. Supervision — suivi des VMs / services critiques
5. Sauvegardes & PRA — stratégie, tests de restauration
6. VDI & profils — accès distant / postes centralisés si pertinent
7. Hyper-V & résilience — lien atelier « résilience Windows » + ce cas
8. PRA / PCO — plan de continuité documenté

## Exigences de cohérence
- Le livrable final sur la branche main doit former UN dossier airsolid/ cohérent (pas 4 versions du même fichier sur des branches différentes).
- Chaque fichier a UN seul propriétaire pendant la rédaction ; l'intégration finale produit une version unique.
- 04-objectifs-pedagogiques.md doit suivre EXACTEMENT les 8 titres officiels ci-dessus.
