" ~/.config/nvim/init.vim

" 1. Dit à Neovim de chercher les scripts dans le dossier .vim
set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath

" 2. Charge physiquement ton fichier de config classique
source ~/.vimrc
