#!/bin/sh

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
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
            sudo apt-get update -qq
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
                    sudo apt update && sudo apt install ansible -y
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
    return
# Install Docker

}

main() {
    install_ansible
    #clone_dotfiles
    #run_playbook "$@"
}

main "$@"