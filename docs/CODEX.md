# OpsToutatis - P0 Manifest

Tu travailles sur OpsToutatis, un module PowerShell d'orchestration d'infrastructure
multi-plateforme. Respecte ABSOLUMENT les règles suivantes sur toute la session :

## LANGUES
- Tous les messages affichés à l'utilisateur final sont en FRANÇAIS.
- Tout le code (noms de fonctions, variables, commentaires techniques, logs bruts) est en ANGLAIS.
- Les fonctions exportées suivent la convention Verbe-OpsNom (ex : Invoke-OpsDeploy, Get-OpsRole).

## COMPATIBILITÉ
- PowerShell 5.1 (Windows 10/Server 2016+) ET PowerShell 7.4+ (Windows + Linux).
- Pas d'opérateur ternaire, pas de ?? , pas de using namespace System.X non portable en 5.1.
- Pas de classes PowerShell sauf nécessité absolue (problèmes de reload en 5.1).
- Code testé mentalement sous cmd.exe, PS 5.1, PS 7 Windows, PS 7 Linux, bash (via pwsh).

## ERGONOMIE
- Toute opération potentiellement destructive DEMANDE CONFIRMATION EXPLICITE
  (l'utilisateur doit retaper un mot clé, pas juste "O").
- Toute fonction expose -WhatIf et -Confirm. Dry-run par défaut sur les rôles.
- Toute variable sensible (mot de passe, clé) est un SecureString. Jamais de string clair.
- Les messages utilisateur expliquent POURQUOI on demande chaque info
  (ex : "Mot de passe DSRM — 14 caractères minimum — sert à restaurer l'AD en mode sans échec").

## LOGS
- Les logs vont dans ./logs/<ISO-timestamp>-<session-id>/ et NE S'AFFICHENT PAS par défaut.
- L'utilisateur voit uniquement les messages pédagogiques et les barres de progression.
- Les secrets sont masqués par regex avant écriture dans les logs.

## IDÉMPOTENCE
- Tout rôle déployable suit le cycle Test → Plan → Apply → Verify → (Rollback si échec).
- Relancer deux fois le même déploiement ne doit jamais casser l'état.

## INTERDICTIONS
- PAS de dépendance à un module propriétaire payant.
- PAS de secret en dur, même pour test.
- PAS d'appel réseau sortant non documenté (liste blanche explicite).
- PAS de code qui "semble fonctionner mais n'est pas testé" — chaque fonction publique a un test Pester.

## LIVRAISON
- Fournis TOUS les fichiers modifiés ou créés en entier (pas de diff partiel).
- Après chaque lot : liste les fichiers touchés, résume les décisions, indique comment tester localement.
- Si une consigne est ambiguë : pose une question avant de coder, ne devine pas.
