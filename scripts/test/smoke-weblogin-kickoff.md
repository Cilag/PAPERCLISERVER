Mission de développement web pour un client interne (smoke-test de l'organisation 3 équipes). Cadre la mission et confie l'exécution technique selon ton rôle : le Tech Lead délègue EN PARALLÈLE au Web Lead (code) et à l'Infra Lead (hébergement), puis le Web Lead pilote en direct la boucle d'audit avec le Cybersecurity Lead jusqu'à une note ≥ 8/10.

## Contexte client
- Petit outil interne : une **page de connexion** (login) + une **API d'authentification** minimale.
- Objectif : valider de bout en bout la chaîne Dev → audit Cyber noté /10 → correction → re-audit, et un déploiement simple.
- Périmètre VOLONTAIREMENT petit (c'est un test de la mécanique d'équipe, pas un vrai produit) : pas de base de données lourde, pas de design élaboré. Reste frugal.

## Livrable attendu — repo /home/guigui/work/smoke-weblogin
UN jeu de fichiers cohérent, ownership non-chevauchant :
- `app/backend/` (Backend Engineer) — API `POST /login` (email + mot de passe), vérif des identifiants, réponse 200/401. Validation côté serveur.
- `app/frontend/` (Frontend Engineer) — formulaire de login minimal qui appelle l'API. Validation côté client.
- `app/tests/` (Fullstack/QA) — quelques tests (login OK / mauvais mot de passe / entrée invalide).
- `docs/security/audit-vN.md` (Cybersecurity Lead) — rapport + **note /10** par itération.
- Hébergement minimal (Infra Lead) — un déploiement conteneurisé simple (ex. un `Dockerfile` + `docker-compose.yml` ou équivalent léger). Pas de Terraform cloud complet pour ce test.

## Boucle qualité attendue (LE cœur du test)
1. Le Web Lead découpe en ownership non-chevauchant, fait coder Frontend/Backend/QA, exige `eslint`/`tsc`/tests verts en local.
2. Quand le code est prêt, le **Web Lead crée une sous-issue d'audit assignée directement au Cybersecurity Lead** (team-to-team, PAS via le Tech Lead).
3. Le Cyber Lead audite **tooling-first** (semgrep/gitleaks/npm audit), consolide une **note /10** (barème : Critical −4, High −2, Medium −0.5, Low −0.1 ; plancher 0) dans `docs/security/audit-v1.md`.
4. Si la note < 8 → findings renvoyés au Web Lead → correction par le specialist owner → **re-audit incrémental** (diff seulement) → `audit-v2.md`, etc. Max 3 itérations puis escalade au Tech Lead.
5. Une fois ≥ 8/10, l'Infra Lead déploie sur l'hébergement préparé, le Tech Lead consolide et rapporte au CEO.

## Exigences
- Ownership : un fichier = un seul propriétaire. La Cyber **n'édite jamais** le code applicatif (elle audite et renvoie des findings ; le Dev corrige).
- Lecture scopée : chaque spécialiste ne lit que les fichiers de sa sous-issue + le brief.
- Le livrable final sur `main` doit être UN dossier cohérent (pas plusieurs versions du même fichier sur des branches divergentes).

## Critères de succès du smoke-test (pour l'évaluation humaine après coup)
- [ ] Le Tech Lead a créé DEUX sous-issues en parallèle (Web Lead + Infra Lead), pas tout fait lui-même (pas de « L2=0 »).
- [ ] Le Web Lead a délégué à Frontend/Backend/QA avec des fichiers distincts.
- [ ] Une sous-issue d'audit Web Lead → Cybersecurity Lead existe (handoff direct).
- [ ] `docs/security/audit-v1.md` contient une note /10 et un tableau de findings.
- [ ] Si v1 < 8 : au moins une itération de correction + `audit-v2.md` montrant une note qui remonte.
- [ ] Note finale ≥ 8/10 (ou escalade documentée au Tech Lead après 3 tours).
- [ ] Un hébergement minimal (Dockerfile/compose) est présent.
