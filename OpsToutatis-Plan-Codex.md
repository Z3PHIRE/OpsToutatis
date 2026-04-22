# OpsToutatis — Plan de déploiement Codex

**Auteur :** Anthony
**Projet :** OpsToutatis — module PowerShell cross-plateforme d'orchestration d'infrastructure
**Public cible de l'outil :** équipes IT / admins devant déployer rapidement des rôles serveurs (AD, DNS, RDS, Linux…) avec une TUI pédagogique

---

## Comment utiliser ce plan

1. Lis le **Préambule (P0)** : c'est le manifeste du projet. Tu le colleras **au début de chaque session Codex** (ou tu en feras un fichier `CODEX.md` commité à la racine du dépôt, que Codex ira lire).
2. Avance prompt par prompt (P1 → P13). **Ne passe au suivant que lorsque les critères d'acceptation du précédent sont verts** (tests Pester OK, import du module OK, PR reviewée).
3. Chaque prompt est autonome : il est rédigé pour être compréhensible même sans la mémoire des autres. C'est voulu — Codex oublie vite.
4. Les **garde-fous** (🛑) sont non-négociables : si Codex les enfreint, rejette sa sortie et relance-le en lui rappelant la règle violée.

---

## P0 — Préambule / Manifeste (à coller en tête de chaque prompt)

```text
Tu travailles sur OpsToutatis, un module PowerShell d'orchestration d'infrastructure
multi-plateforme. Respecte ABSOLUMENT les règles suivantes sur toute la session :

LANGUES
- Tous les messages affichés à l'utilisateur final sont en FRANÇAIS.
- Tout le code (noms de fonctions, variables, commentaires techniques, logs bruts) est en ANGLAIS.
- Les fonctions exportées suivent la convention Verbe-OpsNom (ex : Invoke-OpsDeploy, Get-OpsRole).

COMPATIBILITÉ
- PowerShell 5.1 (Windows 10/Server 2016+) ET PowerShell 7.4+ (Windows + Linux).
- Pas d'opérateur ternaire, pas de ?? , pas de using namespace System.X non portable en 5.1.
- Pas de classes PowerShell sauf nécessité absolue (problèmes de reload en 5.1).
- Code testé mentalement sous cmd.exe, PS 5.1, PS 7 Windows, PS 7 Linux, bash (via pwsh).

ERGONOMIE
- Toute opération potentiellement destructive DEMANDE CONFIRMATION EXPLICITE
  (l'utilisateur doit retaper un mot clé, pas juste "O").
- Toute fonction expose -WhatIf et -Confirm. Dry-run par défaut sur les rôles.
- Toute variable sensible (mot de passe, clé) est un SecureString. Jamais de string clair.
- Les messages utilisateur expliquent POURQUOI on demande chaque info
  (ex : "Mot de passe DSRM — 14 caractères minimum — sert à restaurer l'AD en mode sans échec").

LOGS
- Les logs vont dans ./logs/<ISO-timestamp>-<session-id>/ et NE S'AFFICHENT PAS par défaut.
- L'utilisateur voit uniquement les messages pédagogiques et les barres de progression.
- Les secrets sont masqués par regex avant écriture dans les logs.

IDÉMPOTENCE
- Tout rôle déployable suit le cycle Test → Plan → Apply → Verify → (Rollback si échec).
- Relancer deux fois le même déploiement ne doit jamais casser l'état.

INTERDICTIONS
- PAS de dépendance à un module propriétaire payant.
- PAS de secret en dur, même pour test.
- PAS d'appel réseau sortant non documenté (liste blanche explicite).
- PAS de code qui "semble fonctionner mais n'est pas testé" — chaque fonction publique a un test Pester.

LIVRAISON
- Fournis TOUS les fichiers modifiés ou créés en entier (pas de diff partiel).
- Après chaque lot : liste les fichiers touchés, résume les décisions, indique comment tester localement.
- Si une consigne est ambiguë : pose une question avant de coder, ne devine pas.
```

---

## P1 — Squelette du module & bootstrap d'installation

**🎯 Objectif**
Poser les fondations du dépôt : arborescence, manifest, loader, scripts d'installation one-liner (Windows + Linux), CI minimale, licence, README.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Tâche 1 — Initialise le squelette du projet OpsToutatis.

Arborescence attendue :
  /OpsToutatis.psd1          (manifest du module)
  /OpsToutatis.psm1          (loader : dot-source récursif de src/)
  /src/
    /Public/                 (fonctions exportées, une par fichier)
    /Private/                (helpers internes)
    /Roles/                  (plugins de rôles, vide pour l'instant)
    /UI/                     (moteur TUI, vide pour l'instant)
    /Transport/              (abstraction local/WinRM/SSH, vide)
  /tests/                    (Pester 5)
  /scripts/
    install.ps1              (bootstrap Windows : iex (irm ...))
    install.sh               (bootstrap Linux : curl ... | bash)
  /docs/
    CODEX.md                 (copie du manifeste P0)
    CONTRIBUTING.md
  /.github/workflows/ci.yml  (Pester sur Windows + Linux)
  /CHANGELOG.md
  /LICENSE                   (MIT)
  /README.md
  /.editorconfig
  /.gitignore

Exigences précises :
1. Le manifest déclare PowerShellVersion = '5.1' et une FunctionsToExport vide pour l'instant.
2. Le loader (OpsToutatis.psm1) parcourt src/Public et src/Private, dot-source chaque .ps1,
   et exporte uniquement les fonctions présentes dans src/Public.
3. install.ps1 : télécharge la dernière release GitHub, extrait dans
   $env:USERPROFILE\Documents\PowerShell\Modules\OpsToutatis\, puis affiche en français
   un message de succès expliquant comment lancer Start-OpsToutatis.
4. install.sh : équivalent pour Linux, extrait dans ~/.local/share/powershell/Modules/OpsToutatis/,
   vérifie que pwsh est installé (sinon message d'erreur pédagogique en français).
5. CI : workflow GitHub Actions qui tourne Pester sur windows-latest ET ubuntu-latest avec pwsh.

🛑 GARDE-FOUS
- AUCUNE fonction métier dans cette étape. Juste la structure.
- Le module DOIT s'importer sans warning ni erreur avec `Import-Module ./OpsToutatis.psd1`
  en PS 5.1 ET en PS 7.
- install.ps1 ne doit PAS exécuter de code téléchargé non vérifié : il utilise une release
  GitHub taguée, pas la branche main.
- Pas de stockage de secrets. Pas de télémétrie.

✅ CRITÈRES D'ACCEPTATION
- `Import-Module ./OpsToutatis.psd1 -Force` fonctionne sur Windows PS 5.1.
- `Import-Module ./OpsToutatis.psd1 -Force` fonctionne sur Linux pwsh 7.4.
- Le workflow CI passe au vert.
- Le README montre l'usage one-liner Windows ET Linux.

Fournis tous les fichiers ci-dessus intégralement.
```

---

## P2 — Moteur de session & de logs

**🎯 Objectif**
Chaque exécution d'OpsToutatis ouvre une **session** horodatée qui capture tout : choix, actions, erreurs — sans polluer la sortie utilisateur.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P1 a posé le squelette du module OpsToutatis. Le dossier src/Private est vide.

Tâche 2 — Implémente le moteur de session et de logs.

Crée dans src/Private/ :
  Session.ps1    → New-OpsSession, Get-OpsSession, Close-OpsSession
  Logger.ps1     → Write-OpsLog (niveaux : Debug/Info/Warn/Error/Action/Decision)
  Redaction.ps1  → Format-OpsRedactedString (masque secrets)

Comportement attendu :
1. New-OpsSession crée ./logs/<YYYYMMDD-HHMMSS>-<8charsRandom>/
   contenant : session.log, actions.log, decisions.log, errors.log, transcript.log.
2. Un script:OpsCurrentSession stocke la session active. Get-OpsSession la retourne.
3. Write-OpsLog -Level Info -Message '...' écrit dans session.log. Les niveaux Action et Decision
   vont ADDITIONNELLEMENT dans actions.log et decisions.log.
4. AUCUN log n'est affiché à la console par défaut. Un switch -PassThru permet d'écrire en console
   (réservé au mode debug interactif).
5. Format-OpsRedactedString prend une string et masque : motifs ressemblant à des mots de passe,
   tokens (bearer, eyJ...), clés privées (-----BEGIN), chaînes après "password=", "pwd=", "-ascredential".
   Retourne la string avec ces zones remplacées par "***REDACTED***".
6. Tout Write-OpsLog passe automatiquement le message dans Format-OpsRedactedString avant écriture.
7. Close-OpsSession écrit un résumé (nb actions, nb décisions, nb erreurs, durée) dans session.log.

Dans src/Public/ crée :
  Start-OpsToutatis.ps1 → fonction d'entrée qui appelle New-OpsSession et affiche un simple
  "Bienvenue dans OpsToutatis. Session ouverte : <id>. Logs : <chemin>".

Tests Pester à fournir dans tests/ :
- Session crée bien le dossier attendu.
- Logs ne s'affichent pas en console sans -PassThru.
- Un mot de passe passé à Write-OpsLog n'apparaît jamais en clair dans les fichiers.
- Close-OpsSession écrit bien le résumé.

🛑 GARDE-FOUS
- AUCUN Write-Host dans le logger. Utilise Out-File / Add-Content.
- Format-OpsRedactedString doit avoir au moins 8 tests unitaires couvrant des cas piégeux
  (mot "password" dans une phrase normale ne doit PAS casser le texte entier ; masquer uniquement la valeur).
- Pas de dépendance à un package externe pour la redaction. Regex maison.

✅ CRITÈRES D'ACCEPTATION
- Start-OpsToutatis crée un dossier de session et n'affiche AUCUN log technique.
- Tous les tests Pester passent sur PS 5.1 et PS 7.
- Zéro secret n'apparaît en clair dans les logs de test.
```

---

## P3 — Configuration & inventaire

**🎯 Objectif**
Formaliser comment on décrit un parc de serveurs (inventory) et ce qu'on veut déployer (playbook).

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P1 (squelette) + P2 (sessions/logs) sont en place.

Tâche 3 — Implémente le système d'inventaire et de playbooks.

Format inventaire (PSD1, plus natif PS que YAML) :
  @{
    Hosts = @(
      @{ Name='DC01'; Address='192.168.1.10'; Transport='WinRM'; OS='WindowsServer2022'; CredentialRef='corp-admin' }
      @{ Name='WEB01'; Address='192.168.1.20'; Transport='SSH';   OS='Ubuntu2404';        CredentialRef='web-root' }
    )
    Groups = @{
      DomainControllers = @('DC01')
      WebServers        = @('WEB01')
    }
  }

Format playbook (PSD1) :
  @{
    Name = 'corp-baseline'
    Description = 'Déploiement socle domaine + web'
    Targets = @(
      @{ Host='DC01'; Roles = @('ADDS-Forest','DNS-Primary') }
      @{ Host='WEB01'; Roles = @('Linux-Nginx') }
    )
    Options = @{ ParallelHosts = 3; StopOnFirstError = $false }
  }

Crée dans src/Public/ :
  Import-OpsInventory.ps1  (parse et valide un inventaire)
  Import-OpsPlaybook.ps1   (parse et valide un playbook)
  Test-OpsInventory.ps1    (validation schéma : champs obligatoires, types, IP valide, OS supporté)
  Test-OpsPlaybook.ps1     (tous les Host référencés existent dans l'inventaire courant, rôles existants)

Crée dans src/Private/ :
  Schema.ps1 → Test-OpsSchema : moteur de validation interne (pas de dépendance externe).

Gestion des credentials :
- Jamais dans l'inventaire. Les CredentialRef sont des clés vers SecretManagement.
- Ajoute Set-OpsCredential et Get-OpsCredential qui wrappent Get-Secret / Set-Secret
  avec un coffre par défaut 'OpsToutatisVault' (créé si absent).

Tests Pester :
- Inventaire valide : Import + Test passent.
- Inventaire avec IP invalide : Test retourne une erreur claire en français.
- Playbook référençant un Host absent : Test retourne erreur claire.
- Set/Get-OpsCredential round-trip fonctionne.

🛑 GARDE-FOUS
- ZÉRO credential dans les fichiers d'inventaire/playbook. Si Codex ajoute un champ
  "Password" dans le schéma, c'est à rejeter.
- Les messages d'erreur de validation sont en français, pointent la ligne / clé fautive,
  et expliquent la correction attendue.
- Si SecretManagement n'est pas installé, Set-OpsCredential affiche un message pédagogique
  expliquant comment l'installer, ne plante pas.

✅ CRITÈRES D'ACCEPTATION
- Un inventaire et un playbook d'exemple sont fournis dans examples/.
- Test-OpsPlaybook détecte au moins 6 classes d'erreurs (fichier absent, syntax error, clé
  manquante, type invalide, référence inexistante, OS non supporté).
- Round-trip SecretManagement fonctionne sous Windows ET Linux.
```

---

## P4 — Moteur TUI cross-plateforme

**🎯 Objectif**
Le cœur visuel. Rendu ANSI maison, composants réutilisables, fallback non-interactif.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P1-P3 posent module + logs + inventaire. On n'a encore RIEN de visuel.

Tâche 4 — Implémente le moteur TUI dans src/UI/.

Principes :
- Rendu en séquences ANSI pures (ESC[...m, ESC[...H). Pas de dépendance Terminal.Gui, Spectre.Console.
- Détection capabilities : $Host.UI.SupportsVirtualTerminal, $env:NO_COLOR, $Host.Name, TTY vs non-TTY.
- Fallback automatique en mode "plain" (prompts texte séquentiels) si non-interactif.
- Redessin ciblé (pas de Clear-Host brutal à chaque frame).

Composants à livrer :
  src/UI/Theme.ps1        → palette de couleurs nommées (variables script:OpsTheme)
  src/UI/Render.ps1       → Write-OpsUI, Write-OpsBox (bordures), Write-OpsBanner
  src/UI/Menu.ps1         → Show-OpsMenu (flèches haut/bas, Enter)
  src/UI/Checklist.ps1    → Show-OpsChecklist (espace pour cocher, Enter pour valider)
  src/UI/Form.ps1         → Show-OpsForm (champs avec label, aide pédagogique, validation live)
  src/UI/Progress.ps1     → Show-OpsProgress (barre + sous-étape + % global multi-serveur)
  src/UI/Schema.ps1       → Show-OpsTopology (rendu ASCII d'un graphe de serveurs)

Spécificités du formulaire pédagogique (Show-OpsForm) :
- Chaque champ déclare : Name, Label, HelpText (explique À QUOI sert la variable),
  Type (String/SecureString/Int/Choice), Validation (regex ou scriptblock), DefaultValue.
- Exemple d'appel pour un mot de passe DSRM :
    @{ Name='DSRMPassword'; Label='Mot de passe DSRM'; Type='SecureString';
       HelpText='Sert à restaurer AD en mode sans échec. 14 caractères minimum, complexité forte.';
       Validation={ param($v) (ConvertFrom-SecureString $v -AsPlainText).Length -ge 14 } }
- Affiche sous chaque champ l'aide et l'exigence de validation EN FRANÇAIS.
- Si validation échoue : message rouge sous le champ, pas de plantage.

Checklist multi-sélection (Show-OpsChecklist) :
- Input : array d'items @{ Id=...; Label=...; Description=...; DefaultChecked=$false }
- Output : array des Id cochés.
- Support PageUp/PageDown, Home/End, flèches.
- En mode plain : affiche la liste numérotée, demande "1,3,5" en une ligne.

Tests Pester :
- Test de non-régression du rendu en mode plain (capture de Out-String, comparaison golden file).
- Test de fallback : forcer $Host.UI.SupportsVirtualTerminal=$false doit basculer en plain.

🛑 GARDE-FOUS
- AUCUN Clear-Host dans une boucle de rendu (fait clignoter sur SSH lent).
- Pas de caractères Unicode hors BMP (certains terminaux Windows historiques pètent).
- Un switch -Ascii global force caractères ASCII uniquement (bordures +, -, |).
- Le moteur TUI ne DOIT PAS bloquer si stdin n'est pas un TTY (ex : pipeline CI) — il bascule
  automatiquement en mode non-interactif et lit depuis les defaults ou les paramètres.
- Aucun appel réseau dans le moteur UI.

✅ CRITÈRES D'ACCEPTATION
- Démo Show-OpsMenu, Show-OpsChecklist, Show-OpsForm visibles via un script examples/ui-demo.ps1.
- Rendu lisible dans : cmd.exe, Windows Terminal, ConEmu, GNOME Terminal, Alacritty, iTerm2.
- Aucun blocage en mode non-interactif.
- Zéro secret lu par Show-OpsForm n'apparaît en logs (redaction P2 appliquée).
```

---

## P5 — Abstraction de transport (Local / WinRM / SSH)

**🎯 Objectif**
Exécuter une commande ou un script sur n'importe quelle cible de manière uniforme.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P1-P4 livrés. On peut parler à l'utilisateur mais pas encore aux serveurs distants.

Tâche 5 — Implémente la couche transport dans src/Transport/.

Fichiers :
  src/Transport/TransportBase.ps1    → contrat (pseudo-interface via convention)
  src/Transport/LocalTransport.ps1
  src/Transport/WinRMTransport.ps1
  src/Transport/SSHTransport.ps1
  src/Public/Invoke-OpsRemote.ps1    → façade unifiée
  src/Public/Test-OpsTarget.ps1      → test de connectivité + auth
  src/Public/Get-OpsTargetInfo.ps1   → OS détaillé, version, hostname, arch

Contrat de transport (chaque transport expose) :
  function Invoke-<X>Command($Target, $ScriptBlock, $ArgumentList, $TimeoutSec)
  function Send-<X>File($Target, $LocalPath, $RemotePath)
  function Receive-<X>File($Target, $RemotePath, $LocalPath)
  function Test-<X>Connection($Target)

Invoke-OpsRemote choisit le transport d'après $Target.Transport :
- 'Local'  → exécute directement.
- 'WinRM'  → Invoke-Command -ComputerName -Credential (CredSSP / Kerberos / NTLM).
- 'SSH'    → New-PSSession -HostName ... -UserName ... (PS 7) ou bascule vers ssh.exe + pwsh si PS 5.1.

Credentials :
- Récupérés via Get-OpsCredential (P3). Jamais demandés inline dans Invoke-OpsRemote.
- SSH : support clé privée référencée par chemin dans l'inventaire OU agent SSH.

Détection OS après connexion :
- Windows : Get-CimInstance Win32_OperatingSystem.
- Linux : cat /etc/os-release.
- Retour normalisé : @{ Family='Windows'|'Linux'; Distribution='WindowsServer2022'|'Ubuntu2404'|...;
  Version='10.0.20348'; Architecture='x64' }.

Pré-vols obligatoires dans Test-OpsTarget :
1. Ping / TCP reachability.
2. Port du transport ouvert (5985/5986 WinRM, 22 SSH).
3. Auth réussit.
4. Élévation / sudo disponible.
5. Espace disque > 1 Go sur le disque système.
Chaque étape a un message pédagogique en français.

Tests Pester :
- Mocks des transports distants (pas de test live obligatoire).
- LocalTransport : tests réels (on exécute localement).
- Test-OpsTarget sur localhost en Local doit passer les 5 pré-vols.

🛑 GARDE-FOUS
- AUCUN credential en clair en paramètre. Toujours PSCredential ou SecureString.
- Timeout par défaut raisonnable (120s pour command, 600s pour transfer), toujours surchargeable.
- Pas de stockage de ConnectionString / session ouverte longue durée sans nettoyage.
  Chaque fonction referme sa session distante dans un finally.
- Si un transport échoue, le message d'erreur indique la cause probable EN FRANÇAIS
  (ex : "Port 5985 fermé — activez WinRM avec Enable-PSRemoting côté cible").

✅ CRITÈRES D'ACCEPTATION
- Démo : Test-OpsTarget sur un Windows distant et un Linux distant renvoient les mêmes champs.
- Invoke-OpsRemote exécute "{ hostname }" sur les deux familles avec un code identique côté appelant.
- Aucun handle de session qui fuit (vérifiable via Get-PSSession après usage).
```

---

## P6 — Architecture de plugins de rôles

**🎯 Objectif**
Définir le contrat que chaque "rôle déployable" doit respecter, et le moteur qui les orchestre.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P1-P5 livrés. On peut exécuter des commandes distantes. Il est temps de structurer
ce qu'on déploie.

Tâche 6 — Implémente le framework de rôles dans src/Roles/ et le moteur d'orchestration.

Chaque rôle est un DOSSIER dans src/Roles/, nommé d'après son Id (ex : ADDS-Forest/).
Structure d'un rôle :
  src/Roles/<RoleId>/
    role.psd1            (manifest du rôle)
    Test.ps1             (function Test-<RoleId>Role)
    Plan.ps1             (function Get-<RoleId>Plan)
    Apply.ps1            (function Invoke-<RoleId>Apply)
    Verify.ps1           (function Test-<RoleId>Applied)
    Rollback.ps1         (function Invoke-<RoleId>Rollback, optionnel)
    Parameters.ps1       (function Get-<RoleId>ParameterSchema, pour Show-OpsForm)

Manifest role.psd1 :
  @{
    Id = 'ADDS-Forest'
    DisplayName = 'Active Directory — Nouvelle forêt'
    Category = 'Windows/Directory'
    SupportedOS = @('WindowsServer2016','WindowsServer2019','WindowsServer2022','WindowsServer2025')
    Requires = @()             # autres rôles prérequis
    Conflicts = @('ADDS-AdditionalDC')
    RiskLevel = 'High'         # Low / Medium / High
    DestructivePotential = $true
    EstimatedDurationMin = 15
  }

Cycle de déploiement orchestré par Invoke-OpsDeploy (à créer dans src/Public/) :
  1. Pre-check : Test.ps1 → retourne Current state.
  2. Plan : Plan.ps1 prend (Current, DesiredParameters) → retourne liste d'Actions typées
     (ex : InstallFeature, SetRegistry, CreateADObject) avec pour chacune un label français.
  3. Présentation : le plan est AFFICHÉ à l'utilisateur dans la TUI avant Apply.
     Si RiskLevel=High, demande confirmation explicite (retaper le DisplayName du rôle).
  4. Apply : Apply.ps1 exécute les Actions une par une, Write-OpsLog -Level Action pour chacune.
  5. Verify : Verify.ps1 valide que Desired state est atteint. Si non → déclenche Rollback si présent.

Mode -WhatIf natif :
- Invoke-OpsDeploy -WhatIf s'arrête après Plan et affiche le plan sans l'exécuter.
- Toujours passer par -WhatIf en premier est la pratique recommandée, documentée dans le README.

Crée un rôle FACTICE exemple src/Roles/Demo-Hello/ qui installe un fichier hello.txt sur la cible.
C'est le "hello world" des rôles, utilisé par les tests.

Crée Get-OpsRole, Show-OpsRoleCatalog (liste filtrable par Category / SupportedOS).

Tests Pester :
- Invoke-OpsDeploy avec le rôle Demo-Hello en local : cycle complet OK.
- Relance identique → idempotent (Verify détecte déjà-appliqué, skip Apply).
- Rôle avec RiskLevel=High sans confirmation → refus net.

🛑 GARDE-FOUS
- Aucune action d'Apply sans Plan préalable affiché.
- Apply ne peut jamais sauter Verify.
- Un rôle sans Test.ps1, Plan.ps1, Apply.ps1, Verify.ps1 doit être rejeté au chargement
  avec un message clair.
- Pas de rôle qui s'auto-installe des dépendances externes sans validation utilisateur.

✅ CRITÈRES D'ACCEPTATION
- Démo : Invoke-OpsDeploy -Role Demo-Hello -Target DC01 -WhatIf affiche un plan lisible.
- Sans -WhatIf : applique, vérifie, log action dans actions.log.
- 2e exécution : "État déjà conforme" sans re-exécution.
```

#---------------------------------------------------------------------------------------------------------------#
#-------------------------------------#### je me suis arrêter là ####-------------------------------------------#
#---------------------------------------------------------------------------------------------------------------#

---

## P7 — Rôles Windows Server fondamentaux

**🎯 Objectif**
Les rôles du quotidien : AD, DNS, DHCP, File Server, IIS.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P6 livre le framework de rôles + le rôle Demo-Hello.

Tâche 7 — Implémente les rôles Windows Server fondamentaux dans src/Roles/.

Rôles à livrer (chacun avec ses 5 fichiers : Test/Plan/Apply/Verify/Parameters + role.psd1) :

1. ADDS-Forest
   - Paramètres : DomainName (FQDN), NetBIOSName, DSRMPassword (SecureString),
     ForestFunctionalLevel, SiteName, InstallDNS (bool).
   - Test : détecte si la machine est déjà un DC.
   - Plan : Install-WindowsFeature AD-Domain-Services + Install-ADDSForest ...
   - Apply : utilise Install-ADDSForest avec SkipPreChecks:$false, redémarrage géré.
   - Verify : Get-ADDomain répond, DNS résout le nouveau FQDN.
   - Rollback : documente qu'un rollback forêt est manuel.

2. ADDS-AdditionalDC (joindre un DC à une forêt existante)

3. DNS-Primary (zone primaire autonome, hors AD-integrated)

4. DHCP-Scope
   - Paramètres : ScopeName, StartRange, EndRange, SubnetMask, Router, DnsServers, LeaseDurationHours.
   - Refus si le service DHCP n'est pas autorisé dans l'AD (pour éviter scopes rogue).

5. FileServer-Share
   - Paramètres : ShareName, Path, FullAccessPrincipals, ReadAccessPrincipals.
   - Crée le dossier, les ACL NTFS ET les permissions de partage.

6. IIS-SiteBasic
   - Paramètres : SiteName, BindingPort, PhysicalPath, AppPoolName.

Tests Pester pour chaque rôle :
- Test-RoleParameterSchema : Get-<X>ParameterSchema retourne un schéma valide pour Show-OpsForm.
- Plan unitaire (mock des cmdlets Install-WindowsFeature) : plan généré contient les bonnes actions.
- Verify sur un mock d'état appliqué retourne $true.

🛑 GARDE-FOUS
- AUCUN rôle ne cache un redémarrage silencieux. Chaque redémarrage est annoncé à l'utilisateur
  avec fenêtre de confirmation et proposition de planifier.
- DSRMPassword : SecureString obligatoire, validation de complexité en Plan (pas en Apply).
- ADDS-Forest refuse de s'exécuter sur un Windows non-serveur (Windows 10/11).
- FileServer-Share refuse des chemins dans C:\Windows, C:\Program Files.
- Chaque rôle expose SupportedOS correctement — tester avec une OS non supportée retourne
  un message français explicite.

✅ CRITÈRES D'ACCEPTATION
- Show-OpsRoleCatalog -Category 'Windows/*' liste bien les 6 rôles.
- Un playbook d'exemple examples/playbook-baseline-ad.psd1 fait :
  DC01 = ADDS-Forest + DNS-Primary ; FS01 = FileServer-Share.
- Invoke-OpsDeploy -Playbook <ce fichier> -WhatIf produit un plan complet lisible.
```

---

## P8 — Rôles Windows Server avancés

**🎯 Objectif**
Monter en gamme : RDS farm, clustering, certificats, Hyper-V, WSUS.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P7 livre les rôles basiques. Le framework sait gérer des rôles simples.

Tâche 8 — Implémente les rôles Windows Server avancés.

Rôles à livrer :

1. RDS-Farm (déploiement multi-composants)
   - Paramètres : BrokerHost, SessionHosts[], GatewayHost (optionnel), LicensingMode,
     CollectionName, CollectionDescription, CollectionUserGroups[].
   - Le Plan décompose en sous-actions : install RDCB, install RDSH sur chaque host,
     install RDGW, créer la collection.
   - Gère les dépendances : Broker AVANT Session Hosts, SHs AVANT création collection.
   - Supporte l'ajout de nouveaux SessionHosts à une collection existante (idempotent).

2. FailoverCluster-Basic (2 à 8 noeuds)

3. ADCS-EnterpriseCA (Autorité de certification Entreprise, racine ou subordonnée)

4. HyperV-Host (activation rôle + configuration réseau virtuel externe/interne/privé)

5. WSUS-Server (installation + configuration produits + plannings de synchronisation)

Exigence transversale : RÉSOLUTION DE DÉPENDANCES MULTI-HÔTES.
Ajoute dans src/Private/ un résolveur :
  Get-OpsDeploymentOrder : prend un playbook, retourne une liste d'étapes ordonnées.
  Respecte les Requires (global) ET les dépendances internes multi-hôtes d'un même rôle
  (RDS-Farm : Broker avant SH).

Tests Pester :
- RDS-Farm avec 1 broker + 3 SH : ordre de déploiement correct.
- Cycle détecté → erreur claire en français avec le cycle affiché.

🛑 GARDE-FOUS
- Ces rôles sont à RiskLevel=High ou Medium. Confirmations renforcées.
- Aucun téléchargement de binaire externe sans checksum dans le code.
- ADCS : refuse de s'installer sur un domain controller (best practice).
- HyperV : refuse si virtualisation imbriquée non disponible ET la cible est une VM
  (à moins que -Force soit passé, avec warning).

✅ CRITÈRES D'ACCEPTATION
- Un playbook examples/playbook-rds-farm.psd1 déploie (en WhatIf) un broker + 2 SH + 1 GW.
- Le plan affiché indique clairement l'ordre : "Étape 1/7 : Installation Broker sur BROKER01"…
- Le résolveur détecte bien un cycle artificiel dans un playbook de test.
```

---

## P9 — Gestion des objets Active Directory

**🎯 Objectif**
Une fois l'AD déployé, peupler : OU, utilisateurs (batch + template), groupes, GPO de base.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P7 a livré ADDS-Forest. On peut désormais créer des AD. Il faut pouvoir les peupler.

Tâche 9 — Implémente les rôles de peuplement AD dans src/Roles/.

Rôles :

1. AD-OU-Structure
   - Paramètres : OUTree (structure hiérarchique déclarative).
   - Exemple :
       @{ Name='Corp'; Children=@(
         @{ Name='Users'; Children=@(@{Name='Paris'},@{Name='Marseille'}) },
         @{ Name='Groups' },
         @{ Name='Servers' }
       )}
   - Idempotent : n'écrase pas l'existant, complète.

2. AD-Users-FromCSV
   - Paramètres : CsvPath, DefaultPasswordPolicy, TargetOU, UserTemplate.
   - CSV colonnes attendues : SamAccountName, GivenName, Surname, Department, Title, Manager, Email.
   - Mots de passe initiaux générés (14 chars, complexité forte) et exportés dans un CSV
     chiffré dans ./logs/<session>/credentials.csv.enc (chiffré DPAPI Windows ou équivalent Linux).
   - Chaque utilisateur : ChangePasswordAtLogon=$true par défaut.
   - Validation pré-création : politique de mot de passe du domaine respectée.

3. AD-Users-Interactive
   - Lance Show-OpsForm (P4) pour saisir un utilisateur. L'aide pédagogique explique
     chaque champ (SamAccountName : max 20 chars, pas d'espaces ; UPN : format prenom.nom@domaine…).

4. AD-Groups-Bulk
   - Création de groupes en masse avec imbrication (GG → DL → U).

5. AD-GPO-Baseline
   - Crée des GPO de base (mot de passe, verrouillage, désactivation SMBv1, audit logon).
   - Fournit un template modifiable en examples/gpo-baseline.psd1.

Exigence transversale : REPORTING.
Après exécution, génère dans le dossier de session un rapport HTML
(report.html) listant : utilisateurs créés, OU créées, groupes, GPO, erreurs.

Tests Pester :
- Mocks de ActiveDirectory module.
- CSV avec lignes invalides → lignes rejetées listées dans le rapport, pas de plantage.

🛑 GARDE-FOUS
- AUCUN mot de passe utilisateur en clair dans les logs. Rapport chiffré uniquement.
- Refuse de créer un utilisateur si le domaine n'est pas joignable ou pas un DC.
- AD-Users-FromCSV refuse un CSV > 1000 lignes sans flag -Confirm explicite
  (protection contre import accidentel massif).
- Validation des caractères interdits dans SamAccountName AVANT toute tentative de création.

✅ CRITÈRES D'ACCEPTATION
- Un CSV d'exemple examples/users-sample.csv de 10 utilisateurs est fourni.
- Invoke-OpsDeploy -Role AD-Users-FromCSV -WhatIf liste les 10 créations prévues.
- report.html est propre, en français, ouvre sans JS.
```

---

## P10 — Rôles Linux

**🎯 Objectif**
Ne pas faire d'OpsToutatis un outil Windows-only. Couvrir les rôles Linux clés.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P1-P9 sont livrés. Côté Linux, seul le transport SSH existe (P5).

Tâche 10 — Implémente les rôles Linux dans src/Roles/.

Rôles :

1. Linux-Baseline
   - Update/upgrade système, fuseau horaire, NTP (systemd-timesyncd ou chrony), hostname,
     SSH hardening (désactivation root login par mot de passe, KexAlgorithms/Ciphers modernes),
     fail2ban, unattended-upgrades (Debian/Ubuntu) ou dnf-automatic (RHEL/Rocky).
   - Idempotent.

2. Linux-Firewall
   - UFW sur Debian/Ubuntu, firewalld sur RHEL/Rocky.
   - Paramètres : Rules[] (port, protocol, source, action), DefaultInbound, DefaultOutbound.

3. Linux-Nginx
   - Installation + 1 à N vhosts avec TLS Let's Encrypt optionnel (certbot).
   - Refuse Let's Encrypt si port 80 non joignable depuis internet (check préalable).

4. Linux-Samba-AD
   - Samba en mode Active Directory Domain Controller (alternative open source à ADDS).
   - Paramètres similaires à ADDS-Forest.

5. Linux-Docker-Host
   - Installation Docker CE selon distro officielle, ajout utilisateur au groupe docker,
     Docker Compose v2, paramétrage daemon.json (storage-driver, log rotation).

6. Linux-BIND9
   - Serveur DNS autoritatif avec zones déclaratives.

Détection distro obligatoire :
- Debian / Ubuntu : apt, /etc/debian_version.
- RHEL / Rocky / AlmaLinux : dnf, /etc/redhat-release.
- Fallback : message d'erreur français expliquant que la distro n'est pas supportée et
  listant les distros supportées.

Tests Pester :
- Mocks de ssh pour simuler les distros.
- Chaque rôle testé sur 2 distros au moins.

🛑 GARDE-FOUS
- AUCUN sudo sans mot de passe supposé. Si sudo passwordless n'est pas dispo :
  message pédagogique expliquant comment configurer.
- Linux-Baseline ne doit jamais verrouiller le user courant hors de SSH
  (test : après hardening, re-connexion SSH doit marcher, sinon rollback auto).
- Firewall : règle "autoriser SSH depuis ma source actuelle" TOUJOURS ajoutée en premier.
  Sinon on se coupe la branche.
- Docker : refuse l'installation si une autre version (docker.io, snap) est déjà présente —
  demande désinstallation manuelle explicite.

✅ CRITÈRES D'ACCEPTATION
- Un playbook examples/playbook-linux-web.psd1 déploie Baseline + Firewall + Nginx sur
  une Ubuntu 24.04 et une Rocky 9 (WhatIf OK pour les deux).
- Hardening SSH ne casse pas la session qui l'applique.
```

---

## P11 — Audit & analyse de failles

**🎯 Objectif**
Avant ou après déploiement, l'outil audite et suggère. Lecture seule stricte.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P1-P10 livrés. On peut déployer. On ne sait pas encore auditer.

Tâche 11 — Implémente le module d'audit dans src/Audit/ et expose des "rôles lecteur".

Ce ne sont PAS des rôles qui modifient l'état — ce sont des audits (pattern Test+Report seulement).
Convention : préfixe Audit- dans l'Id. Ils exposent Test.ps1 + Report.ps1 (pas d'Apply).

Audits à livrer :

1. Audit-ADHealth
   - Comptes utilisateurs : PasswordNeverExpires, PasswordNotRequired, ServicePrincipalNames
     sur utilisateurs sensibles, comptes inactifs > 90j, admins sans MFA / sans smart card.
   - Délégations : Unconstrained Delegation, Constrained Delegation vers services critiques.
   - Groupes privilégiés : membres récents de Domain Admins / Enterprise Admins.
   - Politiques : longueur mdp, lockout, âge max, SMBv1 activé.
   - Règles inspirées publiquement des bonnes pratiques MS (pas de copie de base PingCastle).

2. Audit-DNS
   - Récursion ouverte à internet, transferts de zone autorisés à n'importe qui,
     zones avec scavenging désactivé, enregistrements orphelins.

3. Audit-Windows-Server
   - SMBv1, TLS 1.0/1.1, LLMNR, NetBIOS, PowerShell v2, Wdigest, LAPS absent.
   - Niveau de patch (dernière KB vs aujourd'hui).

4. Audit-Linux-Server
   - SSH root password auth, algorithmes obsolètes, firewall absent, ports exposés
     non attendus, paquets en retard de mise à jour, logs auth.log avec tentatives bruteforce récentes.

5. Audit-NetworkExposure
   - Depuis un hôte tiers : test passif (no portscan agressif) des ports les plus sensibles
     (3389, 445, 22, 5985, 5986) vers une liste d'IPs cibles.
   - Opt-in explicite obligatoire.

Rapport :
- Format HTML unique : ./logs/<session>/audit-report.html.
- Sections par audit, sévérité (Info/Low/Medium/High/Critical), recommandation en français,
  commande ou rôle OpsToutatis suggéré pour corriger.
- Export JSON machine-readable pour intégration CI.

Intégration TUI :
- Après un déploiement AD ou DNS, OpsToutatis propose de lancer Audit-ADHealth / Audit-DNS.
  L'utilisateur coche ce qu'il veut via Show-OpsChecklist.

Tests Pester :
- Mocks de Get-ADUser / Get-DnsServerZone etc.
- Chaque audit produit un score et au moins 3 findings sur un mock "parc pourri".

🛑 GARDE-FOUS
- LECTURE SEULE STRICTE. Zéro Set-* / New-* / Remove-* dans les scripts d'audit.
- Le rapport dit explicitement "aucune modification n'a été appliquée".
- Audit-NetworkExposure refuse d'être lancé sans flag -IAccept ET sans inventaire déclarant
  les cibles comme autorisées.
- Aucun appel à un service externe (pas de scan cloud VirusTotal etc.) sans whitelisting.

✅ CRITÈRES D'ACCEPTATION
- Audit-ADHealth sur un lab vide produit un rapport HTML lisible.
- Chaque finding est reliable à une action corrective (texte ou rôle OpsToutatis).
- Rapport JSON validable contre un schéma fourni dans docs/schemas/.
```

---

## P12 — Découverte & schéma de topologie

**🎯 Objectif**
L'utilisateur donne une liste d'IPs (ou passe par SSH) → OpsToutatis découvre et dessine.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P1-P11 livrés. OpsToutatis gère individuellement chaque serveur. Il manque la vue d'ensemble.

Tâche 12 — Implémente la découverte de topologie et son rendu.

Fichiers :
  src/Public/Invoke-OpsDiscovery.ps1
  src/Public/Show-OpsTopology.ps1      (utilise src/UI/Schema.ps1 de P4)
  src/Public/Export-OpsTopology.ps1    (export Mermaid + DOT)

Invoke-OpsDiscovery :
- Input : inventaire (P3) OU liste d'IPs avec credentials.
- Pour chaque hôte joignable :
  - Get-OpsTargetInfo (P5) → OS, version.
  - Si Windows : détection rôles installés (Get-WindowsFeature filtrée), hostname, domaine,
    DNS primaire, IP, gateway, trusts AD si DC.
  - Si Linux : détection services actifs (nginx, bind9, samba, docker, postgres, etc.),
    hostname, IP, gateway, /etc/resolv.conf.
- Résultat : objet OpsTopology @{ Nodes = [...]; Edges = [...] }.
  - Edges déduites : même domaine AD, même réseau /24, lien DNS → forwarder déclaré,
    lien SSH déclaré dans inventaire.

Rendu ASCII dans la TUI (Show-OpsTopology) :
- Placement automatique simple (grid par groupe).
- Boîtes nommées (Hostname, IP, rôles courts).
- Liaisons dessinées avec caractères --- | + (ou Unicode selon -Ascii P4).
- Navigation : flèches pour déplacer un focus, Enter pour ouvrir un détail.

Exports :
- Mermaid flowchart → docs/topology-<session>.mmd (se rend sur GitHub/GitLab).
- Graphviz DOT → optionnel.

Tests Pester :
- Discovery sur 3 nœuds mockés → topology avec bonnes edges.
- Export Mermaid produit un document mermaid valide (syntaxe vérifiable).

🛑 GARDE-FOUS
- SCAN PASSIF. Pas de nmap, pas de portscan au-delà des ports déjà listés comme transport
  dans l'inventaire.
- Discovery n'écrit RIEN sur les cibles.
- Si une cible ne répond pas : elle apparaît dans la topologie en "Unreachable", pas d'erreur fatale.
- Pas d'inférence "magique" non documentée. Chaque edge déduite est étiquetée avec sa raison
  (ex : "même domaine AD : corp.local").

✅ CRITÈRES D'ACCEPTATION
- Invoke-OpsDiscovery -Inventory examples/inventory-lab.psd1 produit un OpsTopology complet.
- Show-OpsTopology affiche un schéma ASCII lisible dans Windows Terminal, cmd.exe et bash.
- Export Mermaid s'ouvre proprement via un viewer.
```

---

## P13 — Orchestration multi-serveur, packaging final, documentation

**🎯 Objectif**
Ficeler l'expérience utilisateur de bout en bout, publier, documenter.

**📝 Prompt Codex**

```text
[Coller P0 d'abord]

Contexte : P1-P12 livrés. Il reste à assembler l'expérience et à publier.

Tâche 13 — Orchestration multi-serveur + packaging.

Partie A — Orchestration complète via TUI.
Crée src/Public/Start-OpsToutatis.ps1 (refonte) qui propose un parcours guidé :
  1. Écran d'accueil : bannière ASCII OpsToutatis, version, session ouverte.
  2. Menu principal (Show-OpsMenu) : Déployer / Découvrir / Auditer / Gérer credentials / Quitter.
  3. Parcours "Déployer" :
     3a. Charger un inventaire existant OU en créer un inline.
     3b. Show-OpsChecklist : sélection des hôtes cibles.
     3c. Pour chaque hôte : Show-OpsChecklist des rôles compatibles (filtré par OS détecté).
     3d. Show-OpsForm pour les paramètres de chaque rôle sélectionné.
     3e. Récap du plan global (liste ordonnée multi-hôtes).
     3f. Confirmation explicite.
     3g. Exécution avec Show-OpsProgress global + progress par hôte (parallélisme contrôlé,
         ThrottleLimit dans Options du playbook).
     3h. Écran récap final : OK / KO par hôte, chemin du rapport, proposition de lancer
         un audit pertinent (Audit-ADHealth si ADDS déployé, etc.).

Parallélisme :
- PS 7 : ForEach-Object -Parallel.
- PS 5.1 : runspaces via RunspacePool.
- Un échec sur un hôte ne bloque pas les autres si StopOnFirstError=$false.
- Les sorties des runspaces sont agrégées dans le logger sans collision (lock par fichier).

Partie B — Packaging & publication.
- Workflow GitHub Actions : tag v*.*.* → build → test matrix (Windows+Linux) → publish PowerShell Gallery (manuel via approval) + Release GitHub avec zip.
- install.ps1 / install.sh mis à jour pour taper dernière release taguée.
- Script scripts/Bump-Version.ps1 qui met à jour .psd1 et CHANGELOG.

Partie C — Documentation.
- docs/README.md (landing)
- docs/getting-started.md (install + premier déploiement en 5 min)
- docs/concepts.md (session, rôle, playbook, transport, audit)
- docs/roles/*.md (un par rôle, généré partiellement automatiquement depuis role.psd1 + Parameters.ps1)
- docs/cookbook/*.md (recettes : "Déployer une forêt AD + DNS + premier file server", "Farm RDS 2 hôtes", "LAMP Linux")
- docs/troubleshooting.md (erreurs fréquentes et leur diagnostic en français)
- docs/security.md (modèle de sécurité, stockage secrets, logs, redaction)

Partie D — Tests end-to-end.
- tests/e2e/scenario-ad-baseline.tests.ps1 : playbook complet en WhatIf, vérifie plan cohérent.
- tests/e2e/scenario-linux-web.tests.ps1 : idem côté Linux.
- CI exécute les e2e en WhatIf uniquement (pas de lab réel requis).

🛑 GARDE-FOUS
- Parallélisme : limite par défaut ThrottleLimit=5. Ne pas DoS un lab involontairement.
- Publication PowerShell Gallery : étape manuelle (approval workflow), jamais auto sur push.
- Documentation : AUCUN placeholder type "TODO écrire cette section". Tout est complet
  ou la section est retirée.
- Start-OpsToutatis en mode non-interactif (CI) accepte -Playbook <path> et bypass la TUI.

✅ CRITÈRES D'ACCEPTATION
- Démo vidéo (ou screencast scripté) de bout en bout : install → déploiement AD complet en WhatIf
  → audit → topologie → rapport.
- Version 1.0.0 tagguée et publiée en Release GitHub.
- Documentation navigable, aucun lien cassé.
- Tous les tests Pester (unit + e2e) verts sur Windows et Linux.
```

---

## Checklist de pilotage (pour toi, pas pour Codex)

| Step | Objet | Estimé | Bloquant pour |
|------|-------|--------|---------------|
| P1 | Squelette | 1 session | Tous |
| P2 | Sessions & logs | 1 session | P6+ |
| P3 | Inventory & secrets | 1 session | P5+ |
| P4 | Moteur TUI | 2 sessions | P13 |
| P5 | Transports | 2 sessions | P7+ |
| P6 | Framework rôles | 1 session | P7-P11 |
| P7 | Rôles Win basiques | 2 sessions | P9 |
| P8 | Rôles Win avancés | 2 sessions | — |
| P9 | Peuplement AD | 1 session | — |
| P10 | Rôles Linux | 2 sessions | — |
| P11 | Audit | 2 sessions | — |
| P12 | Topologie | 1 session | — |
| P13 | Finition & release | 2 sessions | — |

## Règles d'or pour piloter Codex

1. **Colle P0 à chaque nouveau prompt.** Codex oublie ton contexte entre sessions.
2. **Ne laisse jamais Codex sauter Plan avant Apply** — c'est le point central du framework.
3. **Si Codex propose d'ajouter une dépendance externe** (module, package), refuse par défaut
   et demande la justification. Chaque dépendance est une surface d'attaque.
4. **Refuse toute suggestion de stocker un credential en dur**, même "pour tester".
5. **Ne valide un prompt que si tous les critères d'acceptation sont cochés** — même si
   Codex dit "c'est bon". Réexécute les tests toi-même.
6. **En cas de régression entre deux steps**, reviens au step précédent, ne tente pas
   de patcher au vol en ajoutant du scope au step courant.

---

*Document prêt à être haché en morceaux et donné à Codex prompt par prompt. Bonne construction.*
