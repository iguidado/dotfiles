#!/bin/sh

set -x

check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "❌ Erreur : Ce script ne doit pas être exécuté en tant que root."
        echo "Il est conçu pour configurer l'environnement d'un utilisateur standard."
        exit 1
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

pkg_install() {
    os=$(detect_os)
     case "$os" in
        ubuntu|debian) sudo apt-get install -y "$1" ;;
        alpine) sudo apk add "$1" ;;
        *) echo "OS non supporté : $os"
           exit 1
           ;;
     esac
}

prepare_os() {
    os=$(detect_os)
    case "$os" in
        ubuntu|debian)
            sudo apt-get update -qq
            ;;
        alpine)
            sudo apk update
            ;;
        *)
            echo "OS non supporté : $os"
            exit 1
            ;;
    esac
}

install_sudo() {
    if command -v sudo >/dev/null 2>&1; then
        echo "sudo is already installed."
    else
        os=$(detect_os)
        case "$os" in
            ubuntu|debian)
                su -c "apt install sudo -y"
                ;;
            *)
                echo "Unsupported OS: $os"
                exit 1
                ;;
        esac
    fi
    if ! groups "$USER" | grep -q "\bsudo\b"; then
        echo "Adding $USER to sudo group..."
        su -c "usermod -aG sudo \"$USER\""
        echo "Please log out and log back in for the changes to take effect."
        echo "You can also log again with 'su - $USER' to apply the new group membership immediately."  
        echo "You can then re-run this script to continue the installation process after logging back in."
        exit 0
    fi
}

# Install python
install_python_and_pip() {
    if command -v python3 >/dev/null 2>&1 && command -v pip3 >/dev/null 2>&1; then
        echo "Python et pip déjà installés."
        return
    fi
    os=$(detect_os)
    case "$os" in
        ubuntu|debian)
            sudo apt-get install -y python3 python3-pip
            ;;
        *)
            echo "OS non supporté : $os"
            exit 1
            ;;
    esac
}


# Only calld by install_ansible there is no failsafe if function is called directly
install_ansible_via_pip() {
    if ! command -v pip3 >/dev/null 2>&1; then
        echo "pip is not installed. Installing pip first..."
        install_python_and_pip
    fi
    echo "Installing Ansible via pip..."
    pip3 install --user ansible
}


install_ansible() {
    if command -v ansible >/dev/null 2>&1; then
        echo "Ansible is already installed."
    else
        os=$(detect_os)
        echo "Installing Ansible..."
            case "$os" in
                ubuntu|debian)
                    sudo apt install ansible -y
                    ;;
                *)
                    echo "Unsupported OS: $os"
                    echo "Attempting to install Ansible via pip..."
                    install_ansible_via_pip
                    ;;
            esac
    fi
}


install_docker() {
    # Start by removin any old versions of Docker that might be installed
    sudo apt remove docker.io docker-compose docker-doc podman-docker containerd runc
    return
# Install Docker

}


install_git() {
    if command -v git >/dev/null 2>&1; then
        echo "Git is already installed."
    else
        os=$(detect_os)
        case "$os" in
            ubuntu|debian)
                sudo apt install git -y
                ;;
            *)
                echo "Unsupported OS: $os"
                exit 1
                ;;
        esac
    fi
}

clone_dotfiles() {
    if [ -d "$HOME/dotfiles" ]; then
        echo "Dotfiles repository already exists."
    else
        git clone https://github.com/iguidado/dotfiles.git $HOME/dotfiles
    fi
}

run_playbook() {
    ansible-playbook -i "localhost," -c local $HOME/dotfiles/playbook.yml "$@"
}


main() {
    check_root
    install_sudo
    prepare_os
    install_ansible
    install_git
    clone_dotfiles
    #run_playbook "$@"
}

main "$@"
