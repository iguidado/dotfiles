#!/bin/sh
#
# Bootstrap d'un espace utilisateur.
#
# PRINCIPE : le privilège est une CAPACITÉ DÉTECTÉE, jamais un prérequis.
# Le script constate ce dont le compte dispose, tente la configuration système
# lorsque l'élévation est possible, puis compose avec ce qu'il a effectivement
# obtenu pour réunir les capacités nécessaires (ansible ici, stow côté
# playbook). Un compte sans sudo doit aboutir à un environnement fonctionnel,
# pas à un abandon.
#
# Variables d'environnement :
#   DEBUG=1         active la trace d'exécution
#   DOTFILES_DIR    emplacement du dépôt        (défaut : ~/dotfiles)
#   DOTFILES_REPO   URL de clonage

set -eu

if [ "${DEBUG:-0}" = "1" ]; then
    set -x
fi

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/iguidado/dotfiles.git}"
ANSIBLE_VENV="$HOME/.local/share/dotfiles/venv"

# Préfixe d'élévation, déterminé par detect_privilege.
# Vide = mode userland strict.
SUDO=""

log() { echo "==> $*"; }
warn() { echo "/!\\ $*" >&2; }
die() {
    echo "XX  $*" >&2
    exit 1
}

check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        die "Ce script ne doit pas être exécuté en tant que root : il configure l'environnement d'un utilisateur standard."
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Constate la capacité d'élévation. N'échoue jamais : renseigne $SUDO et rend
# la main, c'est à l'appelant de composer avec le résultat.
detect_privilege() {
    if ! command -v sudo >/dev/null 2>&1; then
        warn "sudo absent : mode userland strict."
        SUDO=""
        return 0
    fi

    if sudo -n true >/dev/null 2>&1; then
        log "Élévation disponible sans mot de passe."
        SUDO="sudo"
        return 0
    fi

    log "sudo est présent mais demande une authentification."
    if sudo -v; then
        log "Élévation accordée."
        SUDO="sudo"
    else
        warn "Élévation indisponible : poursuite en mode userland strict."
        SUDO=""
    fi
    return 0
}

# Installe un paquet système. Retourne 1 si l'élévation manque ou si l'OS est
# inconnu, pour que l'appelant puisse basculer sur un repli userland.
pkg_install() {
    if [ -z "$SUDO" ]; then
        return 1
    fi
    case "$(detect_os)" in
        ubuntu | debian) $SUDO apt-get install -y "$1" ;;
        alpine) $SUDO apk add "$1" ;;
        *) return 1 ;;
    esac
}

prepare_os() {
    if [ -z "$SUDO" ]; then
        log "Sans élévation : mise à jour du cache de paquets ignorée."
        return 0
    fi
    case "$(detect_os)" in
        ubuntu | debian) $SUDO apt-get update -qq ;;
        alpine) $SUDO apk update ;;
        *) warn "OS non reconnu : mise à jour du cache ignorée." ;;
    esac
}

# Repli sans privilège. Un venv contourne PEP 668
# (« externally-managed-environment »), qui interdit `pip install --user` sur
# Debian 12+ et Ubuntu 24.04 — l'ancien repli de ce script.
install_ansible_userland() {
    if ! command -v python3 >/dev/null 2>&1; then
        die "python3 est absent et ne peut pas être installé sans privilège."
    fi
    if ! python3 -m venv --help >/dev/null 2>&1; then
        die "Le module venv est indisponible (paquet python3-venv). Sans privilège, ansible ne peut pas être installé : demande son installation à un administrateur."
    fi

    mkdir -p "$(dirname "$ANSIBLE_VENV")"
    [ -d "$ANSIBLE_VENV" ] || python3 -m venv "$ANSIBLE_VENV"
    "$ANSIBLE_VENV/bin/pip" install --quiet --upgrade pip
    "$ANSIBLE_VENV/bin/pip" install --quiet ansible

    PATH="$ANSIBLE_VENV/bin:$PATH"
    export PATH
    log "ansible installé dans $ANSIBLE_VENV"
}

ensure_ansible() {
    if command -v ansible-playbook >/dev/null 2>&1; then
        log "ansible déjà disponible."
        return 0
    fi

    log "ansible absent : tentative d'installation système."
    if pkg_install ansible && command -v ansible-playbook >/dev/null 2>&1; then
        return 0
    fi

    log "Installation système impossible : repli sur un venv utilisateur."
    install_ansible_userland
}

ensure_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    log "git absent : tentative d'installation système."
    pkg_install git
}

clone_dotfiles() {
    if [ -d "$DOTFILES_DIR/.git" ]; then
        log "Dépôt déjà présent : $DOTFILES_DIR"
        return 0
    fi
    if [ -e "$DOTFILES_DIR" ]; then
        die "$DOTFILES_DIR existe mais n'est pas un dépôt git."
    fi

    ensure_git || die "git est absent et ne peut pas être installé sans privilège. Fais-le installer, ou copie le dépôt à la main dans $DOTFILES_DIR."

    log "Clonage du dépôt dans $DOTFILES_DIR"
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
}

# Composition finale : le playbook n'a besoin d'élévation que pour installer
# stow, et uniquement s'il manque. On ne demande donc `-K` que dans ce cas
# précis, et seulement si l'élévation réclame effectivement un mot de passe.
run_playbook() {
    if ! command -v stow >/dev/null 2>&1 && [ -n "$SUDO" ]; then
        if ! sudo -n true >/dev/null 2>&1; then
            log "stow absent : le playbook sera lancé avec élévation."
            set -- -K "$@"
        fi
    fi

    ansible-playbook "$DOTFILES_DIR/ansible/dotfiles.yml" \
        -i "$DOTFILES_DIR/ansible/inventory.ini" "$@"
}

main() {
    check_root
    detect_privilege
    prepare_os
    clone_dotfiles
    ensure_ansible
    run_playbook "$@"
    log "Terminé."
}

main "$@"
