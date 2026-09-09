# dotfiles

Configurateur d'espace **utilisateur** : GNU stow pose les liens symboliques
depuis le dépôt vers `$HOME`, Ansible orchestre tout ce qui doit exister autour
(présence de stow, de zsh, d'oh-my-zsh, de neovim, mise à l'écart des fichiers
en conflit, shell de connexion).

Le principe qui gouverne tout le reste : **le privilège est une capacité
détectée, jamais un prérequis**. Un compte sans `sudo` doit aboutir à un
environnement fonctionnel, pas à un abandon.

> **Tu reprends le dépôt après une pause ?** Lis
> [`docs/reprise.md`](docs/reprise.md) d'abord : état vérifié, commandes de
> contrôle, et le piège à connaître avant de relancer un déploiement.
> Ce README explique comment le projet s'utilise ; celui-là, où il en est.

---

## 1. Le contrat structurel : `Srcs/`

`Srcs/` est le **stow directory**. Chaque sous-répertoire est un **package**,
c'est-à-dire l'unité de déploiement. Le contenu d'un package **reproduit
l'arborescence relative à `$HOME`** — pas le nom du package, pas une convention
maison : le chemin tel qu'il apparaîtra dans le HOME.

```
Srcs/                            <- stow directory
├── gdb/.gdbinit                 ->  ~/.gdbinit
├── git/.gitconfig               ->  ~/.gitconfig
├── tmux/.tmux.conf              ->  ~/.tmux.conf
├── vim/.vimrc                   ->  ~/.vimrc
├── zsh/.zshrc                   ->  ~/.zshrc
├── stow/.stow-global-ignore     ->  ~/.stow-global-ignore
├── nvim/.config/nvim/init.vim   ->  ~/.config/nvim/init.vim
└── nvim-lazyvim/.config/nvim-lazyvim/…  ->  ~/.config/nvim-lazyvim/…
```

Le nom du package (`nvim`, `zsh`) ne sert **qu'**à sélectionner un périmètre en
ligne de commande. Ce qui décide de la destination, c'est le chemin *sous* le
package : `Srcs/nvim/.config/nvim/init.vim` atterrit dans
`~/.config/nvim/init.vim` parce que le package contient `.config/nvim/`, pas
parce qu'il s'appelle `nvim`.

Pièges à connaître :

- **`--no-folding` est utilisé partout.** Sans lui, stow lie le *répertoire*
  `~/.config/nvim` vers le dépôt dès qu'il est seul à l'occuper (tree folding),
  et le second package qui écrit sous `~/.config` déclenche un dépliage. Avec
  `--no-folding`, les répertoires sont créés en vrai et seuls les fichiers sont
  liés — comportement stable quel que soit l'ordre des packages.
- **Les règles d'exclusion vivent dans le package `stow`**, pas à la racine de
  `Srcs/`. stow ne lit que deux emplacements : `.stow-local-ignore` au sommet
  d'un package, ou `~/.stow-global-ignore`. Un `.stow-local-ignore` posé dans le
  stow directory lui-même (`Srcs/.stow-local-ignore`) est **ignoré en silence**.
  D'où `Srcs/stow/.stow-global-ignore`, déployé vers `~/.stow-global-ignore`
  avant tout le reste par le playbook — sinon la toute première exécution sur
  une machine neuve lierait quand même les secrets.
- Définir `~/.stow-global-ignore` **remplace** la liste d'exclusion intégrée de
  stow ; les défauts utiles y sont donc recopiés à la main.
- `nvim-lazyvim` se déploie dans `~/.config/nvim-lazyvim`, pas dans
  `~/.config/nvim` : les deux configurations cohabitent, la seconde s'ouvre par
  l'alias `lazyvim` (`NVIM_APPNAME`) défini dans `Srcs/zsh/.zshrc`. L'état
  d'exécution de LazyVim (`lazy-lock.json`, `lazyvim.json`) est délibérément
  hors du package : stowé, il salirait le dépôt à chaque `:Lazy update`.

Le reste du dépôt :

| Chemin | Rôle |
|---|---|
| `bootstrap.sh` | Amorçage d'une machine neuve (sh POSIX, aucune dépendance) |
| `ansible/dotfiles.yml` | Le playbook : capacités puis déploiement |
| `ansible/group_vars/` | Table des capacités et profils (données, pas de code) |
| `ansible/tasks/detect_tools.yml` | Moteur de détection, inclus 3 fois |
| `ansible/container_base.yml` | Playbook **privilégié**, hors périmètre userland |
| `ansible.cfg` | Inventaire et interpréteur Python par défaut |
| `Taskfile.yml` | Interface d'usage courant (`task …`) |
| `Test/Vagrantfile` | Trois VMs de vérification |
| `docs/stow.md` | Cours de fond sur stow + Ansible |

---

## 2. Installation sur une machine neuve

```sh
git clone https://github.com/iguidado/dotfiles.git ~/dotfiles
~/dotfiles/bootstrap.sh
```

Si `git` n'est pas là, `bootstrap.sh` sait se débrouiller seul — il est autonome
et clone le dépôt lui-même :

```sh
curl -fsSL https://raw.githubusercontent.com/iguidado/dotfiles/main/bootstrap.sh -o bootstrap.sh
sh bootstrap.sh
```

Ce que le script fait, dans l'ordre :

1. **refuse de tourner en root** — il configure le compte d'un utilisateur
   standard ;
2. **constate** la capacité d'élévation (`sudo -n`, puis `sudo -v` si un mot de
   passe est demandé) et renseigne `$SUDO`. Il n'échoue jamais à cette étape :
   pas de sudo signifie mode userland strict, pas arrêt ;
3. rafraîchit le cache de paquets *si* l'élévation existe ;
4. clone le dépôt dans `$DOTFILES_DIR` ;
5. **garantit ansible** : paquet système si possible, sinon **venv** dans
   `~/.local/share/dotfiles/venv` ;
6. lance `ansible-playbook ansible/dotfiles.yml`, en n'ajoutant `-K` que dans le
   cas précis où stow manque *et* que l'élévation réclame un mot de passe.

Variables d'environnement reconnues : `DEBUG=1` (trace `set -x`),
`DOTFILES_DIR` (défaut `~/dotfiles`), `DOTFILES_REPO`.

### Ce qui se passe sans aucun privilège

C'est la caractéristique distinctive du projet. Chaque besoin est traité comme
une **capacité**, avec des moyens rangés du moins au plus privilégié :

```
capacité déjà présente  ->  moyen userland  ->  paquet système (sudo)  ->  avertissement actionnable
```

Concrètement, sans `sudo` :

- **ansible** : venv utilisateur. Le venv contourne PEP 668
  (« externally-managed-environment »), qui interdit `pip install --user` sur
  Debian 12+ et Ubuntu 24.04 ;
- **oh-my-zsh** : clone git dans `~/.oh-my-zsh` ;
- **neovim** : AppImage déposée en `~/.local/bin/nvim`, mode `0755` ;
- **le déploiement lui-même** : une fois stow présent, plus **aucune** tâche
  n'exige de privilège — ce ne sont que des liens dans `$HOME`.

Ce qui reste hors de portée est **dit**, pas subi : seule la capacité marquée
`required` (stow) arrête le play, tout le reste produit un message qui donne la
commande exacte à passer ou à faire passer par un administrateur. Deux actions
demandent une élévation et dégradent proprement sinon : l'installation d'un
paquet système, et le changement de shell de connexion (qui touche
`/etc/passwd`).

Le playbook va plus loin que « la commande existe » :

- il **relance** la détection après chaque moyen (trois passes), plutôt que de
  croire le rapport du module qui vient de tourner : un paquet peut s'installer
  sans fournir le binaire, une AppImage se télécharger sans démarrer ;
- il **démarre** les AppImages posées (`--version`) : sans FUSE, sur musl
  (Alpine) ou sur une autre architecture, le fichier est là et inutilisable. Le
  message donne le repli `--appimage-extract` ;
- il lit le **PATH d'un shell de connexion** (`-lc`) : `~/.local/bin` n'y est
  ajouté que par `Srcs/zsh/.zshrc`, donc seulement une fois le dotfile déployé
  *et* un shell rouvert. zsh ne lit ni `/etc/profile.d` ni `~/.profile` ;
- il **relit `/etc/passwd`** après le changement de shell : sur Alpine, `usermod`
  appartient au paquet `shadow`, absent par défaut, et le module `user` rapporte
  `ok` sans rien avoir fait.

---

## 3. Usage courant

Toutes les tâches passent par [Task](https://taskfile.dev) et se lancent depuis
la racine du dépôt.

| Tâche | Effet | Privilège |
|---|---|---|
| `task install` | Déploie : dépôt → `$HOME`. Joue le playbook complet. | non par défaut |
| `task uninstall` | Retire les symlinks posés par stow (`stow -D`). | jamais |
| `task adopt` | **Sens inverse** : importe les fichiers de la machine dans `Srcs/`. | jamais |
| `task save` | `git add -A` + commit + push. Capture : `$HOME` → dépôt → origin. | jamais |
| `task status` | `git status --short --branch` : ce qui n'est pas encore sauvegardé. | jamais |
| `task profiles` | Liste les profils déclarés côté ansible. | jamais |
| `task test-up` | `vagrant up --no-provision` (provider libvirt). | — |
| `task test-provision` | `vagrant provision` (dépend de `test-up`). | — |
| `task test-clean` | `vagrant destroy -f`. | — |
| `task test-init` | Réservée, ne fait rien pour l'instant. | — |
| `task` (défaut) | Affiche la liste des tâches. | — |

Variables surchargeables :

```sh
task install PROFILE=minimal      # profil de déploiement
task install BECOME_FLAG=-K       # stow manquant ET sudo à mot de passe
task uninstall PACKAGES=vim       # restreindre le périmètre (défaut : '*')
task save MESSAGE="add: alias git"
```

À savoir avant de les utiliser :

- **`task uninstall` n'est pas un retour à l'état initial.** `stow -D` ne
  supprime que les liens pointant vers `Srcs/`. Tout ce qu'`install` a fait en
  dehors de stow survit : oh-my-zsh, l'AppImage neovim, les paquets système, le
  shell de connexion dans `/etc/passwd`. La tâche affiche en fin de course la
  liste de ce qui reste et la commande pour chaque élément. Les fichiers mis à
  l'écart ne sont pas restaurés non plus.
- **`task adopt` a une sémantique inversée par rapport à tout le reste du
  dépôt.** `stow --adopt` ne fusionne ni ne sauvegarde : pour chaque conflit, il
  **déplace le fichier de la machine par-dessus la version versionnée** dans
  `Srcs/`, puis crée le lien. Le dépôt perd son contenu au profit de la machine,
  et git est le seul filet — d'où le contrôle d'arbre propre avant (modifications
  non commitées *et* fichiers non suivis) et le `git diff --stat` affiché après,
  y compris si stow échoue en cours de route. Relis le diff : `git diff -- Srcs`
  pour garder, `git checkout -- Srcs` pour rejeter (les liens restent en place et
  pointeront alors sur la version restaurée).
- `ansible.cfg` fixe l'inventaire par défaut, donc
  `ansible-playbook ansible/dotfiles.yml` suffit **depuis la racine** du dépôt.
  Ansible ne charge ce fichier que si la commande part de là.

---

## 4. Ajouter un dotfile

1. Choisir le package (un existant, ou un nouveau répertoire sous `Srcs/`).
2. Y **recréer le chemin relatif à `$HOME`**, pas seulement poser le fichier :

   ```sh
   mkdir -p Srcs/monoutil/.config/monoutil
   mv ~/.config/monoutil/config.toml Srcs/monoutil/.config/monoutil/
   ```

   Le fichier doit être **déplacé**, pas copié : un doublon dans `$HOME` devient
   un conflit à la prochaine installation.
3. Vérifier le plan avant d'écrire :

   ```sh
   cd Srcs && stow --no-folding --simulate --verbose=2 monoutil -t ~
   ```
4. Appliquer par `task install` (ou `stow --no-folding monoutil -t ~`).
5. `task save` pour versionner et pousser.

Si le nouveau package doit sortir du périmètre par défaut, ou si un profil
restreint la liste, penser à `dotfiles_stow_packages` (§ 5) : un package absent
de cette liste n'est jamais déployé, sans avertissement.

Rien de secret ne doit entrer dans `Srcs/`. `~/.stow-global-ignore` empêche
seulement le *lien* (clés, `.env`, `.netrc`, `*.pem`…) ; il n'empêche pas le
commit.

---

## 5. Profils et sélection d'outils

Deux tables, en **données** dans `ansible/group_vars/`, à tenir ensemble :

- **`dotfiles_tools`** dit ce qu'on **installe** — une liste de capacités, avec
  les moyens de les obtenir ;
- **`dotfiles_stow_packages`** dit ce qu'on **déploie** — la valeur part telle
  quelle au shell depuis `Srcs/`, donc `'*'` reste un glob et une restriction
  s'écrit en toutes lettres (`'stow git vim tmux gdb'`).

Les tenir séparément est un piège réel : retirer une capacité sans retirer le
package correspondant pose un dotfile qui référence un outil absent —
`Srcs/zsh/.zshrc` fait `source $ZSH/oh-my-zsh.sh`, donc sans oh-my-zsh chaque
ouverture de shell affiche une erreur.

Champs d'une entrée de `dotfiles_tools` :

| Champ | Sens |
|---|---|
| `name` | Étiquette lisible, et clé dans `dotfiles_tool_paths` |
| `check` | Binaire dont la présence atteste la capacité |
| `check_cmd` | Test shell alternatif quand la capacité n'est pas un binaire |
| `appimage` | URL d'une AppImage à déposer (userland) |
| `git` / `git_version` | Dépôt à cloner dans le HOME (userland) |
| `dest` | Destination des moyens userland |
| `package` | Nom du paquet système (exige une élévation) |
| `required` | `true` = l'absence arrête le play ; sinon avertissement |
| `hint` | Message actionnable si la capacité reste absente |

Exemple réel (`ansible/group_vars/all.yml`) : oh-my-zsh n'est pas un binaire, sa
présence se teste par un répertoire et s'obtient par clone.

```yaml
  - name: oh-my-zsh
    check_cmd: "test -d {{ ansible_user_dir }}/.oh-my-zsh"
    git: https://github.com/ohmyzsh/ohmyzsh.git
    git_version: master
    dest: "{{ ansible_user_dir }}/.oh-my-zsh"
    hint: >-
      oh-my-zsh n'a pas pu être cloné (réseau ?). …
```

### Changer de profil

Deux chemins équivalents, tous deux chargent `ansible/group_vars/<profil>.yml` :

```sh
task install PROFILE=minimal
ansible-playbook ansible/dotfiles.yml -e dotfiles_profile=minimal
```

…ou ranger l'hôte dans le groupe d'inventaire homonyme (`[minimal]` dans
`ansible/inventory.ini`), ce qui déclenche le chargement automatique.

`minimal` est le profil d'exemple livré : `stow` seul comme capacité, shell de
connexion laissé tranquille (`dotfiles_set_login_shell: false`), et périmètre
réduit aux packages dont la configuration est autonome. Un profil **remplace**
la table, il ne la fusionne pas : il décrit ce qu'il veut, pas un delta.

Pièges :

- Un profil passé par `-e` ne déclenche **aucun** chargement automatique ; seule
  l'appartenance à un groupe le fait. Le playbook va donc chercher le fichier
  lui-même, et **échoue** sur un profil inconnu plutôt que de repartir en
  silence sur la table par défaut — une faute de frappe (`PROFILE=minimial`)
  déploierait sinon exactement l'inverse de ce qui a été demandé. `task install`
  vérifie la même chose en précondition, avant même de lancer ansible.
- `dotfiles_profile: default` n'a pas de fichier : `group_vars/all.yml` fait foi.
- Les valeurs par défaut sont dans `group_vars/all.yml` et non dans le `vars:`
  du play, précisément pour qu'un profil puisse les surcharger : `vars:` prime
  sur les group_vars, `all` est le groupe de plus basse précédence.

---

## 6. Conflits : rien n'est supprimé

stow refuse de toucher à un fichier régulier et n'a aucun mode interactif
(`--override` ne vaut que pour les liens qu'il gère déjà). Un **seul** fichier
préexistant fait donc échouer le déploiement de **tous** les packages — cas
banal : la box Ubuntu 22.04 livre son propre `~/.vimrc`.

Le playbook simule, recense les conflits dans la sortie de stow, puis **déplace**
les fichiers concernés — `mv`, jamais `rm` :

```
~/.dotfiles-backup/<horodatage>/<chemin relatif à $HOME>
```

L'horodatage est celui de l'exécution (format compact ISO 8601), le répertoire
est en `0700`, et l'arborescence relative est conservée. Le playbook affiche la
liste des fichiers écartés et le chemin de sauvegarde.

Pour récupérer un fichier :

```sh
ls ~/.dotfiles-backup/
mv ~/.dotfiles-backup/20250909T120000/.vimrc ~/.vimrc   # remplace le lien par l'original
```

Points à connaître :

- La sauvegarde est débrayable : `-e dotfiles_backup_conflicts=false` rétablit
  l'arrêt sur conflit.
- Deux formats de message de conflit coexistent selon la version de stow (2.3.x
  et 2.4.x) ; les deux sont reconnus, et toute ligne qu'aucune règle ne sait
  réduire à un chemin est **écartée** — elle ne sera pas sauvegardée, et la
  replanification s'arrêtera dessus plutôt que de déplacer n'importe quoi.
- En `--check`, la mise à l'écart n'a pas lieu : stow signale forcément encore
  les conflits. Le playbook le dit au lieu d'échouer.
- Une assertion croise le nombre de packages planifiés par stow avec le nombre
  demandé. Si stow change sa sortie, le play **échoue bruyamment** au lieu de se
  déclarer en succès sans avoir rien déployé.

---

## 7. Tests

Trois VMs, un même parcours appliqué à l'identique — c'est la seule façon de
vérifier qu'un même bootstrap tient sur trois familles de distributions :

| VM | Box | IP |
|---|---|---|
| `web_ubuntu` | `generic/ubuntu2204` | 192.168.56.10 |
| `mini_alpine` | `generic/alpine319` | 192.168.56.11 |
| `web_debian` | `debian/bookworm64` | 192.168.56.12 |

```sh
task test-up          # vagrant up --no-provision --provider=libvirt
task test-provision   # bootstrap puis playbook
task test-clean       # vagrant destroy -f
```

Le parcours de chaque VM : téléversement du `bootstrap.sh` **local**, exécution
en `privileged: false` (les provisioners shell de Vagrant tournent en root par
défaut, or `bootstrap.sh` refuse explicitement de s'exécuter en root), puis
rejeu du playbook local avec `dotfiles_repo_dir=/home/vagrant/dotfiles` —
`playbook_dir` est un chemin du **contrôleur**, pas de la cible.

**Limite connue :** `bootstrap.sh` clone le dépôt **depuis GitHub**. Le contenu
de `Srcs/` effectivement stowé dans la VM est donc celui de la branche distante.
**Pousse tes changements avant de tester une modification de dotfile.** Les
modifications de `bootstrap.sh` et des playbooks, elles, sont bien prises depuis
le working tree local.

Autres pièges du banc de test :

- Le synced folder est désactivé **volontairement** : sans lui, le `file`
  provisioner est le seul moyen d'exercer le code local.
- Le play cible `hosts: dotfiles`, jamais `all`. L'inventaire que Vagrant génère
  ne range les invités dans **aucun** groupe nommé : `Test/Vagrantfile` doit
  déclarer `ansible.groups` pour reconstruire le groupe, faute de quoi le play
  ne matcherait rien et Vagrant rapporterait un **succès** (play skipped, rc=0)
  sans rien avoir déployé. Toute VM ajoutée doit être inscrite dans `VM_NAMES`.
- `ansible/container_base.yml` est **privilégié et destructeur** (il désinstalle
  `docker.io`/`containerd`/`runc` avant de poser `docker-ce`). Il cible le groupe
  `[containers]`, laissé **vide** dans l'inventaire, et son provisioner Vagrant
  est en `run: "never"` :
  `vagrant provision --provision-with containers`. Tout nouveau playbook doit se
  donner un groupe explicite, sinon il hériterait de `localhost` par
  `ansible.cfg`.

Contrôles locaux sans risque (le déploiement réel pose des liens et déplace des
fichiers du HOME) :

```sh
ansible-playbook ansible/dotfiles.yml --syntax-check
ansible-playbook ansible/dotfiles.yml --check
```

---

Le fond théorique sur stow (tree folding, orphelins, restructuration d'un
package, sécurité) est dans [`docs/stow.md`](docs/stow.md).
