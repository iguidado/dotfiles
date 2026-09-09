# Reprise

> Instantané daté du **2026-09-09**. Ce document dit où en est le dépôt, ce
> qu'il faut savoir avant de relancer un déploiement, et ce qui reste ouvert.
> Le `README.md` explique comment le projet s'utilise ; celui-ci, où il en est.

---

## 1. Vérifier que rien n'a bougé

Quatre commandes, dans cet ordre. Aucune ne modifie quoi que ce soit.

```bash
cd ~/dotfiles

git status --short --branch          # attendu : arbre propre, main = origin/main
ansible-playbook ansible/dotfiles.yml --check   # attendu : rc=0, failed=0
ls -la ~ | grep -c '\-> dotfiles'    # attendu : 6 symlinks
cd Test && vagrant status            # attendu : les trois VMs « shutoff »
```

Le `--check` n'écrit rien : il simule. S'il annonce des fichiers à écarter,
lis la section 2 avant d'exécuter quoi que ce soit pour de vrai.

**Rappel qui vaut pour tout ce dépôt :** `rc=0` ne prouve pas qu'une action a
eu lieu, seulement que rien n'a échoué. Un play qui ne matche aucun hôte sort
en `0`. Regarde toujours le nombre de tâches exécutées, pas seulement le code
de sortie.

---

## 2. Le seul piège à connaître avant le prochain `task install`

Les paquets `Srcs/nvim` et `Srcs/nvim-lazyvim` sont **dans le dépôt mais pas
déployés**. Un déploiement réel voudra lier `~/.config/nvim/` et
`~/.config/nvim-lazyvim/`, qui existent en dur. Le mécanisme de conflit
déplacera donc **9 fichiers** vers `~/.dotfiles-backup/<horodatage>/` avant de
les relier depuis le dépôt (`init.vim`, plus les 8 fichiers du paquet
`nvim-lazyvim` ; le reste de `~/.config/nvim/` n'est pas versionné et ne bouge
pas).

C'est conforme au design et réversible — déplacement, jamais suppression — et
le contenu est identique, puisqu'il vient de ces mêmes fichiers. Mais c'est du
remue-ménage sur une configuration vivante.

Trois options :

```bash
task install                     # accepter le déplacement (réversible)
task install PROFILE=minimal     # ne stowe que stow git vim tmux gdb
ansible-playbook ansible/dotfiles.yml --check   # voir d'abord la liste exacte
```

**Sujet connexe, à traiter avant d'y aller :** `~/.config/nvim-lazyvim` est un
**clone git amont** (LazyVim/starter). Son `.git` survit au déploiement, ses
fichiers suivis deviennent des liens, `git status` les rapporte en
`typechange`, et un `git pull` ou `git restore` lancé là défait silencieusement
le déploiement. La parade est de renommer le clone amont d'abord :

```bash
mv ~/.config/nvim-lazyvim ~/.config/nvim-lazyvim.upstream
```

Détail dans `docs/stow.md`, section « Un package ne cohabite pas avec un clone
git ».

---

## 3. Ce qui est vérifié, et sur quoi

Parcours complet « machine nue → environnement utilisable », **idempotent**
(second passage `changed=0`) :

| Cible | Bootstrap | 2ᵉ passage | Particularité |
|---|---|---|---|
| `web_debian` | `ok=31 changed=7` | `changed=0` | AppImage déballée (pas de FUSE) |
| `web_ubuntu` | `ok=33 changed=9` | `changed=0` | `.vimrc` de la box écarté |
| `mini_alpine` | `ok=35 changed=0` | `changed=0` | repli paquet pour neovim |

Également prouvé :

- **Profils** sur les trois chemins — défaut, `-e dotfiles_profile=`, et
  appartenance à un groupe d'inventaire. Un profil inconnu échoue en `rc=2`.
- **Repli FUSE** : sur Debian sans `fusermount`, `nvim` passe de
  « No suitable fusermount binary » à `NVIM v0.12.5`.
- **Repli paquet** : sur Alpine, l'AppImage glibc est retirée et `apk neovim`
  prend le relais (`NVIM v0.9.2` depuis `/usr/bin/nvim`).
- **Podman rootless** : sur Debian, `podman run --rm docker.io/library/alpine`
  s'exécute en tant qu'utilisateur, sans `sudo`.

---

## 4. Chantiers ouverts

Aucun ne bloque. Par ordre de valeur.

1. **Bibliothèque de profils.** Le mécanisme est prouvé, mais il n'existe que
   `all.yml` (le socle) et `minimal.yml` (l'exemple). Les profils correspondant
   à tes machines réelles restent à écrire.
2. **Alpine ne change pas le shell de connexion.** `usermod` appartient au
   paquet `shadow`, absent par défaut. Le playbook le **signale** correctement
   au lieu de mentir ; l'installer quand le privilège existe le rendrait
   effectif.
3. **La VM Alpine est un mauvais banc d'essai pour le rootless** : cgroup v1 et
   pas de `/dev/net/tun`. `podman run` y échoue pour des raisons de noyau,
   étrangères au playbook. Une box plus récente, ou cgroup v2 au boot.
4. **`container_base.yml` n'est pas dans le cycle `task test`** — son
   provisioner est en `run: never`, à lancer explicitement :
   `vagrant provision --provision-with containers`.
5. **`bootstrap.sh` clone depuis GitHub.** Tester une modification de *dotfile*
   impose donc de pousser d'abord. Les modifications de `bootstrap.sh` et des
   playbooks, elles, sont bien prises en local.
6. **Le plafond de 1,5 Go par VM** (`Test/Vagrantfile`) est un choix non
   mesuré. Il tient, il n'a pas été éprouvé.

---

## 5. Le motif à garder en tête

Presque tous les défauts trouvés dans ce dépôt sont le même : **une commande
qui interroge sa propre configuration ne prouve rien sur la capacité à
s'exécuter.** Cinq occurrences, toutes corrigées :

| Symptôme | Ce qui mentait |
|---|---|
| Play réussi, rien de déployé | `'LINK' in stderr` — test sur chaîne |
| `ok`, shell inchangé | module `user` sans `usermod` (Alpine) |
| Binaire installé, ne démarre pas | AppImage sans FUSE |
| Capacité « présente », inutilisable | AppImage morte masquant le repli paquet |
| `podman info` rc=0, `podman run` échoue | plages `subuid` jamais écrites |

La parade, appliquée partout dans le playbook : **relire l'état réel** —
`stat` sur le disque, `getent passwd`, `grep` dans `/etc/subuid` — plutôt que
de croire le rapport d'un module. Toute nouvelle tâche devrait suivre la même
règle, et tout nouveau message ne devrait affirmer que ce qui a été constaté.
