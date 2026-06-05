# GNU Stow + Ansible — Gestion de dotfiles

> **Utilisation hors ligne** — document autonome, aucune ressource externe requise  
> **Environnement cible** : Debian/Ubuntu (WSL2, VM Vagrant, dual-boot)  
> **Références** : [GNU Stow Manual](https://www.gnu.org/software/stow/manual/stow.html) · [dotfiles.github.io](https://dotfiles.github.io/utilities/) · [Ansible docs](https://docs.ansible.com)

---

## Prérequis

| Outil | Version minimale | Vérification |
|---|---|---|
| GNU Stow | 2.3.x | `stow --version` |
| Ansible | 2.14+ | `ansible --version` |
| Git | Quelconque | `git --version` |
| Python 3 | 3.8+ | `python3 --version` |

```bash
sudo apt update && sudo apt install -y stow git ansible
```

> **Note WSL2** — les symlinks POSIX fonctionnent dans le filesystem Linux (`/home/...`). Ne jamais placer le stow directory sous `/mnt/c/` : le filesystem NTFS gère incorrectement les symlinks POSIX et cassera Stow silencieusement, sans erreur visible.

---

## 1. GNU Stow : fondamentaux

### 1.1 Pourquoi ça existe

Le problème structurel des dotfiles : ils sont éparpillés dans `$HOME`, à des profondeurs variables, avec des permissions parfois critiques (`.ssh/`, `.gnupg/`). Les solutions naïves créent toutes de la dette technique :

| Approche | Problème |
|---|---|
| `cp` manuel vers repo | Pas de suivi des modifications en place — le repo diverge silencieusement |
| `$HOME` sous Git direct | Tout `$HOME` apparaît dans le working tree ; risque de commit accidentel |
| Scripts de symlinks artisanaux | Fragiles, non-idempotents, non-maintenables au fil des machines |
| Outils dédiés (chezmoi, yadm) | Abstraction supplémentaire, courbe d'apprentissage, lock-in |

GNU Stow est un **symlink farm manager** : il lit une arborescence source et crée dans un répertoire cible un symlink pour chaque fichier, en reconstituant la hiérarchie. L'outil est stable depuis 1993 (Thomas Bushnell, GNU), packagé dans toutes les distros, modèle mental simple — c'est sa force principale.

**Ce que Stow ne fait pas** : pas de templating par machine, pas de chiffrement, pas de gestion des secrets. Pour ces besoins, voir `chezmoi` ou `ansible-vault` en complément.

---

### 1.2 Anatomie : stow directory, target, packages

**Trois concepts clés :**

```
stow directory  ~/.dotfiles/        ← là où vivent les fichiers sources
target          ~/                  ← là où stow crée les symlinks (par défaut: parent du stow dir)
package         ~/.dotfiles/bash/   ← unité atomique de déploiement
```

Un **package** est un sous-répertoire du stow directory. Sa structure interne doit **mirroiter exactement** la structure du target relatif à `$HOME`. Stow traverse le package et pour chaque fichier, crée le symlink correspondant dans le target.

**Exemple concret :**

```
~/.dotfiles/
└── bash/                         ← package "bash"
    ├── .bashrc                   ← sera symlinké → ~/.bashrc
    ├── .bash_profile             ← sera symlinké → ~/.bash_profile
    └── .config/
        └── bash/
            └── aliases           ← sera symlinké → ~/.config/bash/aliases
```

Résultat après `stow --dir ~/.dotfiles --target ~ bash` :

```
~/.bashrc               → ~/.dotfiles/bash/.bashrc
~/.bash_profile         → ~/.dotfiles/bash/.bash_profile
~/.config/bash/aliases  → ~/.dotfiles/bash/.config/bash/aliases
```

> **Convention** : toujours spécifier `--dir` et `--target` explicitement dans les scripts et playbooks Ansible. Ne pas dépendre du répertoire courant — c'est une source de bugs silencieux.

---

### 1.3 L'algorithme tree folding

C'est le comportement le plus important à comprendre pour éviter les conflits. Il est actif par défaut.

**Principe :** Stow cherche à créer le minimum de symlinks. Si un sous-répertoire du package **n'existe pas encore dans le target**, Stow crée un symlink vers ce répertoire **entier** plutôt que de créer le répertoire et des symlinks individuels.

**Exemple — premier package :**

```bash
# État initial : ~/.config/ n'existe pas

stow --dir ~/.dotfiles --target ~ nvim
# Package nvim/ contient : .config/nvim/init.vim

# Résultat :
~/.config  →  ~/.dotfiles/nvim/.config   ← symlink vers le DOSSIER ENTIER (folded)
```

**Exemple — second package touchant le même dossier :**

```bash
stow --dir ~/.dotfiles --target ~ tmux
# Package tmux/ contient : .config/tmux/tmux.conf

# ~/.config/ existe déjà, mais c'est un symlink → Stow "déplie" (unfolds)
# Crée le vrai répertoire ~/.config/
# Crée ~/.config/nvim → ~/.dotfiles/nvim/.config/nvim
# Crée ~/.config/tmux → ~/.dotfiles/tmux/.config/tmux
```

**Pourquoi c'est dangereux :**

Si `~/.config/` contient des fichiers **non gérés par Stow** (créés par une application installée, comme Firefox ou VSCode), le dépliage échoue avec une erreur CONFLICT. L'ordre de stow des packages devient significatif, ce qui est une dépendance fragile et non-déclarative.

Cas pire : Stow a créé `~/.config → ~/.dotfiles/nvim/.config` (symlink vers dossier). Une application crée ensuite `~/.config/some-app/` en suivant ce symlink. Elle écrit donc dans `~/.dotfiles/nvim/.config/some-app/` — des fichiers tiers polluent silencieusement le dépôt dotfiles.

**La solution : `--no-folding`**

```bash
stow --no-folding --dir ~/.dotfiles --target ~ nvim
```

Avec `--no-folding`, Stow crée **toujours de vrais répertoires** dans le target et ne symlinke que les fichiers (jamais les dossiers). Comportement prévisible, indépendant de l'état initial.

> **Règle** : utiliser `--no-folding` systématiquement dans tous les contextes automatisés (scripts, Ansible, CI). Le folding est commode en interactif ponctuel, mais il est une source de bugs en production.

---

### 1.4 Comment ça casse

**Cas 1 : Conflit — fichier existant non géré par Stow**

```
WARNING! stowing bash would cause conflicts:
  * existing target is not owned by stow: .bashrc
All operations aborted.
```

Stow refuse d'écraser tout fichier existant non géré par lui. Résolution :

```bash
mv ~/.bashrc ~/.bashrc.bak          # sauvegarder
stow --no-folding bash              # stow sans conflit
# fusionner manuellement le contenu si nécessaire
cat ~/.bashrc.bak >> ~/.dotfiles/bash/.bashrc
```

**Cas 2 : `--adopt` — la fausse bonne idée**

```bash
stow --adopt bash   # DANGER : ne jamais utiliser en contexte automatisé
```

`--adopt` déplace le fichier existant dans le stow directory et crée le symlink. En apparence pratique pour migrer une machine existante, c'est dangereux : il modifie le dépôt dotfiles sans commit Git et peut introduire des fichiers locaux contenant des secrets dans le repo.

**Règle absolue** : si `--adopt` est utilisé manuellement, faire `git diff` immédiatement après et committer de façon sélective.

**Cas 3 : Orphan symlinks**

Si un fichier source est supprimé du package (ou que le package est renommé/réorganisé), le symlink dans `$HOME` continue d'exister mais pointe dans le vide. `ls -la` l'affiche en rouge dans la plupart des terminaux.

```bash
# Détection
find ~ -maxdepth 3 -xtype l 2>/dev/null
# L'utilitaire officiel de Stow :
chkstow -b    # vérifie les bad links dans le target

# Nettoyage : unstow puis restow après correction
stow -D --dir ~/.dotfiles --target ~ bash
# corriger la structure du package
stow --no-folding --dir ~/.dotfiles --target ~ bash
```

**Cas 4 : Conflit multi-stow directory**

Stow peut gérer plusieurs stow directories (ex: perso + entreprise). Dans ce cas, le "tree splitting" des symlinks de folding peut échouer si un symlink existant pointe vers un autre stow directory. Symptôme : `ERROR: stow_contents() called with non-directory path`.

Solution : `--no-folding` élimine ce problème puisqu'il n'y a jamais de symlinks vers des dossiers.

---

### 1.5 Fichiers de configuration Stow

**`.stow-local-ignore`** — patterns à exclure du stow

Placé dans le stow directory (global) ou dans un package spécifique (local). Syntaxe : expressions régulières Perl, une par ligne. Stow a une liste par défaut incluant déjà `\.git`, `README.*`, `LICENSE`, `CVS`, etc.

Exemple dans `~/.dotfiles/.stow-local-ignore` :

```
# Secrets et clés — ne jamais stower
.*\.key
.*\.pem
.*\.token
.*_rsa$
.*_ed25519$
\.env$
\.envrc$

# Fichiers temporaires
.*\.swp
.*\.swo
.*~
.*\.bak
\.DS_Store

# VCS (complémentaire à la liste par défaut)
\.gitignore
\.gitmodules
```

**`.stowrc`** — options par défaut pour la session interactive

Placé dans `~/.dotfiles/.stowrc` ou `~/.stowrc`. Exemple :

```
--no-folding
--target=/home/user
--dir=/home/user/.dotfiles
```

> **Portée** : `.stowrc` s'applique à la session interactive. Dans les playbooks Ansible, les options doivent toujours être passées explicitement — ne jamais dépendre de `.stowrc` dans un contexte automatisé.

---

### 1.6 Commandes de référence

| Commande | Effet |
|---|---|
| `stow <pkg>` | Crée les symlinks du package |
| `stow -D <pkg>` | Supprime les symlinks (unstow) |
| `stow -R <pkg>` | Unstow + stow (restow) |
| `stow -n <pkg>` | Simulation / dry-run (ne modifie rien) |
| `stow -v <pkg>` | Verbose — sortie sur **stderr** |
| `stow -nv <pkg>` | Simulation verbose ← **toujours exécuter avant le premier stow** |
| `stow --no-folding <pkg>` | Désactive le tree folding |
| `stow --adopt <pkg>` | Absorbe les fichiers existants dans le stow dir ← **dangereux** |
| `stow --dir=PATH --target=PATH <pkg>` | Chemins explicites (recommandé dans les scripts) |
| `chkstow -b` | Vérifie les symlinks orphelins dans le target |

Plusieurs packages en une commande :

```bash
stow --no-folding --dir ~/.dotfiles --target ~ bash git vim
```

---

## 2. Structure du dépôt dotfiles

### 2.1 Arborescence recommandée

```
~/.dotfiles/
│
├── .stow-local-ignore          ← patterns globaux à exclure
├── .stowrc                     ← options interactives par défaut (jamais requis par Ansible)
├── README.md
│
├── bash/                       ← package bash
│   ├── .bashrc
│   └── .bash_profile
│
├── git/                        ← package git
│   └── .gitconfig
│
├── vim/                        ← package vim
│   ├── .vimrc
│   └── .vim/
│       └── autoload/
│           └── plug.vim
│
├── tmux/                       ← package tmux
│   └── .tmux.conf
│
├── ssh/                        ← package ssh — ATTENTION permissions critiques
│   └── .ssh/
│       └── config              ← 0600 OBLIGATOIRE (SSH refuse si permissions trop larges)
│
└── ansible/                    ← automatisation — voir section 4
    ├── playbook.yml
    ├── inventory
    └── roles/
        └── dotfiles/
```

### 2.2 Règles de structure

**Granularité** : un package par programme. Permet de stow/unstow par programme et d'exprimer des listes de packages par profil (workstation, serveur, VM) sans modifier le dépôt.

Ne pas créer un package `all` contenant tout — ça annule l'intérêt de la granularité et empêche les déploiements sélectifs.

**Chemin miroir obligatoire** : si un fichier doit atterrir à `~/.config/nvim/init.vim`, la structure dans le package doit être `nvim/.config/nvim/init.vim`. Toute déviation casse le mapping.

**Fichiers à ne jamais stower dans un repo public** :
- Tout fichier contenant un token, clé, password, secret
- `.ssh/known_hosts` (empreintes machine, informations réseau)
- `.gitconfig` si il contient un token PAT ou une identité réelle

---

## 3. Usage direct de Stow

### 3.1 Initialisation depuis zéro

```bash
mkdir -p ~/.dotfiles
cd ~/.dotfiles

# Créer les packages en déplaçant les fichiers existants
mkdir bash git

mv ~/.bashrc    bash/
mv ~/.gitconfig git/

# Simulation : vérifier l'effet avant d'appliquer
stow --no-folding --simulate --verbose --dir ~/.dotfiles --target ~ bash git

# Si pas d'output stderr → les symlinks seraient créés sans conflit
# Si WARNING/CONFLICT → résoudre avant de continuer

# Application
stow --no-folding --verbose --dir ~/.dotfiles --target ~ bash git
```

### 3.2 Vérification de l'état

```bash
# Symlinks présents dans $HOME
ls -la ~ | grep ' -> '

# Vérification ciblée
readlink -f ~/.bashrc          # doit pointer vers ~/.dotfiles/bash/.bashrc

# Symlinks orphelins
find ~ -maxdepth 3 -xtype l 2>/dev/null
```

### 3.3 Ajouter un fichier à un package existant

```bash
mv ~/.vimrc ~/.dotfiles/vim/.vimrc

# Restow pour que le nouveau symlink soit créé
stow -R --no-folding --dir ~/.dotfiles --target ~ vim
```

### 3.4 Initialisation depuis une machine avec dotfiles existants (`--adopt` contrôlé)

Procédure pour absorber des dotfiles existants de façon auditée :

```bash
cd ~/.dotfiles
git status          # doit être CLEAN avant --adopt

# Simulation d'adoption
stow --adopt --simulate --verbose --dir ~/.dotfiles --target ~ bash

# Application
stow --adopt --no-folding --dir ~/.dotfiles --target ~ bash

# Audit obligatoire
git diff            # voir ce qui a été modifié dans le stow dir
git add -p          # review sélective, fichier par fichier
git commit -m "chore(dotfiles): adopt existing configs from $(hostname)"
```

---

## 4. Rôle Ansible : déploiement automatisé

### 4.1 Arborescence du rôle

```
ansible/
├── playbook.yml
├── inventory
└── roles/
    └── dotfiles/
        ├── defaults/
        │   └── main.yml        ← variables surchargeables (priorité basse)
        ├── tasks/
        │   ├── main.yml        ← orchestrateur d'import
        │   ├── install.yml     ← installation de stow
        │   ├── clone.yml       ← récupération du dépôt
        │   └── stow.yml        ← application des packages
        └── meta/
            └── main.yml        ← métadonnées du rôle
```

---

### 4.2 `defaults/main.yml`

```yaml
---
# --- Source du dépôt dotfiles ---

# Option A : URL distante (requiert accès réseau)
dotfiles_repo: ""
dotfiles_branch: "main"

# Option B : chemin local (offline, pour tests locaux ou Vagrant)
dotfiles_local_src: ""

# --- Chemins ---

# Stow directory : là où le dépôt sera cloné / copié
dotfiles_dir: "{{ ansible_env.HOME }}/.dotfiles"

# Target directory : là où les symlinks seront créés
dotfiles_target_dir: "{{ ansible_env.HOME }}"

# --- Packages à déployer ---
# Surcharger dans le playbook ou group_vars selon le profil machine
dotfiles_packages: []
# dotfiles_packages:
#   - bash
#   - git
#   - vim

# --- Options stow ---

# Désactiver le tree folding (recommandé)
dotfiles_stow_no_folding: true

# Utiliser --restow (unstow + stow) plutôt que stow simple
# À activer explicitement lors d'une réorganisation de packages
dotfiles_stow_restow: false
```

---

### 4.3 `tasks/install.yml`

```yaml
---
- name: "dotfiles | install | install GNU Stow"
  ansible.builtin.apt:
    name: stow
    state: present
    update_cache: false   # déléguer la mise à jour du cache apt à un rôle common en amont
  become: true
```

> `update_cache: false` : éviter les doubles mises à jour de cache si un rôle `common` ou `apt` gère déjà ce point en amont. Dans un playbook autonome, passer à `true`.

---

### 4.4 `tasks/clone.yml`

```yaml
---
- name: "dotfiles | clone | assert source is defined"
  ansible.builtin.assert:
    that:
      - dotfiles_repo != "" or dotfiles_local_src != ""
    fail_msg: >
      Ni dotfiles_repo ni dotfiles_local_src n'est défini.
      Définir au moins l'une des deux variables.
    quiet: true

- name: "dotfiles | clone | ensure dotfiles directory exists"
  ansible.builtin.file:
    path: "{{ dotfiles_dir }}"
    state: directory
    mode: "0750"

# -------------------------
# Option A : clone distant
# -------------------------
- name: "dotfiles | clone | clone repository from remote"
  ansible.builtin.git:
    repo: "{{ dotfiles_repo }}"
    dest: "{{ dotfiles_dir }}"
    version: "{{ dotfiles_branch }}"
    update: true
    force: false      # ne jamais écraser les modifications locales non commitées
  when: dotfiles_repo != ""

# -------------------------
# Option B : copie locale (offline / Vagrant)
# -------------------------
- name: "dotfiles | clone | copy dotfiles from local source (offline)"
  ansible.builtin.copy:
    src: "{{ dotfiles_local_src }}/"
    dest: "{{ dotfiles_dir }}/"
    mode: preserve
  when: dotfiles_local_src != ""
  # Note : ansible.posix.synchronize (rsync) est plus efficace pour les mises à jour
  # incrémentales, mais nécessite rsync sur les deux hôtes. ansible.builtin.copy
  # est suffisant pour un usage initial ou hors ligne.
```

---

### 4.5 `tasks/stow.yml`

```yaml
---
# Étape 1 : simulation — détecte les conflits AVANT toute modification
# Stow envoie sa sortie verbose sur stderr
# rc != 0 signifie conflit détecté → le play s'arrête (fail fast)
- name: "dotfiles | stow | dry-run — detect conflicts"
  ansible.builtin.command:
    cmd: >-
      stow
      {{ '--no-folding' if dotfiles_stow_no_folding else '' }}
      --simulate
      --verbose
      --dir={{ dotfiles_dir }}
      --target={{ dotfiles_target_dir }}
      {{ item }}
  loop: "{{ dotfiles_packages }}"
  register: stow_simulate
  changed_when: false       # dry-run : jamais de changement d'état
  failed_when: stow_simulate.rc != 0

# Étape 2 : application
# --verbose sort les opérations (LINK/UNLINK) sur stderr
# Si les symlinks sont déjà corrects : stow est silencieux → stderr vide → changed=false
- name: "dotfiles | stow | apply packages"
  ansible.builtin.command:
    cmd: >-
      stow
      {{ '--no-folding' if dotfiles_stow_no_folding else '' }}
      {{ '--restow' if dotfiles_stow_restow else '' }}
      --verbose
      --dir={{ dotfiles_dir }}
      --target={{ dotfiles_target_dir }}
      {{ item }}
  loop: "{{ dotfiles_packages }}"
  register: stow_result
  changed_when: stow_result.stderr | length > 0   # verbose → stderr
  failed_when: stow_result.rc != 0
```

---

### 4.6 `tasks/main.yml`

```yaml
---
- name: "dotfiles | install stow"
  ansible.builtin.import_tasks: install.yml
  tags: [dotfiles, install]

- name: "dotfiles | provision dotfiles sources"
  ansible.builtin.import_tasks: clone.yml
  tags: [dotfiles, clone]

- name: "dotfiles | apply stow packages"
  ansible.builtin.import_tasks: stow.yml
  when: dotfiles_packages | length > 0
  tags: [dotfiles, stow]
```

---

### 4.7 `meta/main.yml`

```yaml
---
galaxy_info:
  role_name: dotfiles
  author: "{{ lookup('env', 'USER') }}"
  description: "Déploiement de dotfiles via GNU Stow"
  min_ansible_version: "2.14"
  platforms:
    - name: Debian
      versions:
        - bookworm
        - trixie
    - name: Ubuntu
      versions:
        - jammy
        - noble

dependencies: []
```

---

### 4.8 Playbook et inventaire

**`playbook.yml`** :

```yaml
---
- name: "Deploy dotfiles via GNU Stow"
  hosts: localhost
  connection: local
  gather_facts: true          # requis pour ansible_env.HOME et ansible_user_id

  vars:
    # Chemin relatif au playbook — s'adapte à la position dans le repo
    dotfiles_local_src: "{{ playbook_dir }}/../../"

    dotfiles_packages:
      - bash
      - git
      - vim

    dotfiles_stow_no_folding: true
    dotfiles_stow_restow: false

  roles:
    - role: dotfiles
```

**`inventory`** :

```ini
[local]
localhost ansible_connection=local
```

**Exécution standard :**

```bash
cd ~/.dotfiles/ansible
ansible-playbook -i inventory playbook.yml
```

**Depuis Vagrant (utilisateur différent) :**

```bash
ansible-playbook -i inventory playbook.yml \
  -e "dotfiles_target_dir=/home/vagrant"
```

> La valeur de `ansible_user_id` est résolue automatiquement lors du `gather_facts`. Il n'est pas nécessaire de la passer manuellement sauf si la cible est un utilisateur différent de celui qui lance Ansible.

**Exécution en dry-run complet :**

```bash
ansible-playbook -i inventory playbook.yml --check --diff
```

---

## 5. Idempotence : analyse critique

### 5.1 Comportement de stow selon l'état du target

| État du target | `stow pkg` | `stow --restow pkg` |
|---|---|---|
| Symlinks inexistants | Crée (stderr non-vide → changed) | Crée (stderr non-vide → changed) |
| Symlinks corrects déjà présents | **Ne fait rien** (stderr vide → unchanged) | Supprime et recrée (stderr non-vide → **toujours changed**) |
| Fichier non-stow existant | Erreur CONFLICT (rc != 0) | Erreur CONFLICT (rc != 0) |
| Symlink orphelin | Erreur | Supprime et recrée |

### 5.2 Pourquoi `changed_when: stow_result.stderr | length > 0`

La doc GNU Stow l'indique explicitement : `--verbose` envoie sa sortie sur **stderr**, pas stdout. Chaque opération effective (LINK, UNLINK) produit une ligne sur stderr. Si les symlinks sont déjà dans l'état attendu, stow n'émet rien — stderr est vide.

Conséquence :

- **`stow` sans `--restow`** : idempotent. Si les symlinks existent déjà, la tâche est `ok` (stderr vide).
- **`stow --restow`** : non-idempotent au sens Ansible. Il supprime et recrée les symlinks même s'ils sont corrects, produisant toujours de l'output sur stderr. À réserver aux réorganisations de packages.

`dotfiles_stow_restow: false` par défaut est donc le bon réglage pour l'idempotence quotidienne.

### 5.3 La simulation comme garde-fou (fail fast)

La tâche de simulation (étape 1 de `stow.yml`) a `failed_when: stow_simulate.rc != 0`. Si un conflit est détecté, Ansible s'arrête immédiatement avant d'appliquer quoi que ce soit. C'est un pattern **fail fast** qui protège contre les états partiels où certains packages seraient stowés et d'autres non.

---

## 6. Cas d'usage avancés

### 6.1 Profils multi-environnement

Pour des machines avec des ensembles de packages différents (workstation, serveur, VM), définir les packages dans les `group_vars` ou en surcharge directe dans le playbook.

**Approche `group_vars` :**

Structure d'inventaire étendue :

```ini
[workstation]
localhost ansible_connection=local

[server]
192.168.56.10 ansible_user=vagrant
```

```yaml
# group_vars/workstation.yml
dotfiles_packages:
  - bash
  - git
  - vim
  - tmux
  - ssh

# group_vars/server.yml
dotfiles_packages:
  - bash
  - git
  - vim
```

**Packages conditionnels dans `defaults/main.yml` :**

```yaml
# Packages supplémentaires surchargeables par profil
dotfiles_packages_extra: []
```

Tâche additionnelle dans `stow.yml` :

```yaml
- name: "dotfiles | stow | apply extra packages"
  ansible.builtin.command:
    cmd: >-
      stow
      {{ '--no-folding' if dotfiles_stow_no_folding else '' }}
      --verbose
      --dir={{ dotfiles_dir }}
      --target={{ dotfiles_target_dir }}
      {{ item }}
  loop: "{{ dotfiles_packages_extra }}"
  when: dotfiles_packages_extra | length > 0
  register: stow_extra
  changed_when: stow_extra.stderr | length > 0
  failed_when: stow_extra.rc != 0
```

---

### 6.2 Fichiers sensibles et permissions

Stow crée des **symlinks**, pas des copies. Les permissions qui comptent sont celles du **fichier source dans le stow directory**, pas du symlink lui-même.

**Problème SSH** : `ssh` refuse de démarrer si `.ssh/config` ou `.ssh/` ont des permissions trop larges. Cette vérification opère sur le fichier résolu (source), pas le symlink.

```bash
# Dans le stow directory, avant de committer
chmod 700 ~/.dotfiles/ssh/.ssh
chmod 600 ~/.dotfiles/ssh/.ssh/config
```

Enforcer via Ansible post-stow :

```yaml
- name: "dotfiles | permissions | enforce ssh directory permissions"
  ansible.builtin.file:
    path: "{{ dotfiles_dir }}/ssh/.ssh"
    mode: "0700"
    state: directory
  when: "'ssh' in dotfiles_packages"

- name: "dotfiles | permissions | enforce ssh config permissions"
  ansible.builtin.file:
    path: "{{ dotfiles_dir }}/ssh/.ssh/config"
    mode: "0600"
    state: file
  when: "'ssh' in dotfiles_packages"
```

**Fichiers sensibles dans un package séparé non versionné :**

```
~/.dotfiles/
├── ssh-private/          ← package séparé, HORS GIT
│   └── .ssh/
│       ├── id_ed25519
│       └── id_ed25519.pub
```

```gitignore
# ~/.dotfiles/.gitignore
ssh-private/
```

Ce package est déployé localement mais ne rejoint jamais le dépôt distant.

---

### 6.3 Restructurer un package existant

Quand un package est réorganisé (fichier déplacé dans la hiérarchie, renommé), l'ancien symlink devient orphelin. Procédure :

```bash
# 1. Unstow proprement avant de modifier la structure
stow -D --no-folding --dir ~/.dotfiles --target ~ vim

# 2. Modifier la structure du package
mv ~/.dotfiles/vim/.vimrc ~/.dotfiles/vim/.config/vim/init.vim

# 3. Restow
stow --no-folding --dir ~/.dotfiles --target ~ vim

# 4. Vérifier les orphelins résiduels
find ~ -maxdepth 3 -xtype l 2>/dev/null
```

Dans Ansible, activer `dotfiles_stow_restow: true` ponctuellement lors d'une migration :

```bash
ansible-playbook -i inventory playbook.yml -e "dotfiles_stow_restow=true"
```

---

## 7. Sécurité

### 7.1 Surface d'attaque

**Symlinks comme vecteur de divulgation** : un symlink dans `$HOME` est lisible par tout processus tournant en tant que cet utilisateur. `.gitconfig` contient souvent des tokens PAT. `.ssh/config` expose la topologie réseau et les clés utilisées par hôte.

**Dépôt public = exposition garantie** : si le dépôt dotfiles est public, tout ce qui s'y trouve est indexé par GitHub (et potentiellement par des scrapers de secrets).

**Historique Git** : supprimer un secret d'un commit ne le retire pas de l'historique. `git log --all --full-history -- "path/to/secret"` révèle les versions passées.

### 7.2 Checklist sécurité dotfiles

- [ ] Dépôt en **privé** si les configs contiennent des informations système (hostname, IPs, chemins réseaux)
- [ ] Fichiers contenant des secrets dans un **package séparé hors versioning** (`.gitignore`)
- [ ] `.stow-local-ignore` inclut les patterns `*.key`, `*.pem`, `*_rsa`, `*_ed25519`, `.env`
- [ ] Permissions forcées post-stow : `.ssh/config` → `0600`, `.ssh/` → `0700`
- [ ] `git log --all --full-history -- "**/*.key"` après migration initiale
- [ ] Pas de `.netrc`, token API, ou password en clair dans les dotfiles versionnés
- [ ] Si besoin de secrets versionnés : utiliser `ansible-vault` ou [age](https://age-encryption.org/)

### 7.3 `.stow-local-ignore` de sécurité (complet)

```
# Clés et secrets
.*\.key$
.*\.pem$
.*\.token$
.*\.secret$
.*_rsa$
.*_dsa$
.*_ecdsa$
.*_ed25519$
\.env$
\.envrc$
\.netrc$

# Fichiers temporaires et logs
.*\.log$
.*\.pid$
.*\.lock$
.*\.swp$
.*\.swo$
.*~$
.*\.bak$
\.DS_Store$

# VCS (complémentaire à la liste par défaut de stow)
\.gitignore$
\.gitmodules$
\.gitattributes$

# SSH — config seulement, jamais les clés
# (mettre les clés dans ssh-private/ exclu du repo)
```

---

## 8. Exercices

### Exercice 1 — Initialisation manuelle

**Objectif** : créer un stow directory avec deux packages, vérifier l'état des symlinks.

**Critère de validation** :

```bash
ls -la ~ | grep ' -> ' | grep '\.dotfiles'
# Résultat attendu : au moins deux lignes
readlink ~/.bashrc    # → /home/<user>/.dotfiles/bash/.bashrc
readlink ~/.gitconfig # → /home/<user>/.dotfiles/git/.gitconfig
```

**Attendu** :

1. Créer `~/.dotfiles/bash/` et y déplacer `.bashrc`
2. Créer `~/.dotfiles/git/` et y déplacer `.gitconfig`
3. Simuler : `stow --no-folding -nv --dir ~/.dotfiles --target ~ bash git`
4. Appliquer : `stow --no-folding -v --dir ~/.dotfiles --target ~ bash git`
5. Valider avec les commandes ci-dessus

---

### Exercice 2 — Rôle Ansible en local

**Objectif** : déployer les deux packages via le rôle Ansible, vérifier l'idempotence.

**Critère de validation** :

```bash
# Première exécution
ansible-playbook -i inventory playbook.yml
# → Au moins 2 tâches en CHANGED (stow apply)

# Deuxième exécution
ansible-playbook -i inventory playbook.yml
# → 0 tâches CHANGED (idempotence confirmée)
```

---

### Exercice 3 — Conflit volontaire

**Objectif** : provoquer un conflit et le résoudre sans `--adopt`.

**Procédure** :

1. Créer `~/.testrc` avec `echo "test" > ~/.testrc`
2. Créer le package `mkdir -p ~/.dotfiles/test && echo "stow" > ~/.dotfiles/test/.testrc`
3. Tenter `stow --no-folding --dir ~/.dotfiles --target ~ test` → observer l'erreur
4. Résoudre : sauvegarder et supprimer `~/.testrc`, re-stow
5. Nettoyer : `stow -D --dir ~/.dotfiles --target ~ test`

**Critère de validation** :

```bash
readlink ~/.testrc
# → /home/<user>/.dotfiles/test/.testrc
```

---

### Exercice 4 — Orphan symlinks

**Objectif** : produire un orphan symlink, le détecter, le nettoyer.

**Procédure** :

1. Stow un package test (ex: créer `~/.dotfiles/orphan/.orphanrc`, stow)
2. Supprimer le fichier source : `rm ~/.dotfiles/orphan/.orphanrc`
3. Détecter le symlink orphelin : `find ~ -maxdepth 2 -xtype l 2>/dev/null`
4. Nettoyer : `stow -D --dir ~/.dotfiles --target ~ orphan`
5. Vérifier : `find ~ -maxdepth 2 -xtype l 2>/dev/null` → aucun résultat

---

### Exercice 5 — Profil multi-machine (Ansible)

**Objectif** : déployer des ensembles de packages différents selon un groupe d'inventaire.

**Critère de validation** : modifier l'inventaire pour simuler deux hôtes (`workstation` et `server`), définir des `group_vars` distincts, et vérifier que les packages stowés diffèrent bien entre les deux.

---

## Références

| Ressource | URL |
|---|---|
| GNU Stow Manual (officiel) | https://www.gnu.org/software/stow/manual/stow.html |
| Stow Invoking options | https://www.gnu.org/software/stow/manual/html_node/Invoking-Stow.html |
| dotfiles.github.io — comparatif outils | https://dotfiles.github.io/utilities/ |
| Ansible — module `command` | https://docs.ansible.com/ansible/latest/collections/ansible/builtin/command_module.html |
| Ansible — module `git` | https://docs.ansible.com/ansible/latest/collections/ansible/builtin/git_module.html |
| Ansible — module `copy` | https://docs.ansible.com/ansible/latest/collections/ansible/builtin/copy_module.html |
| chkstow (utilitaire Stow) | inclus dans le paquet `stow` — `man chkstow` |
| age encryption | https://age-encryption.org |
