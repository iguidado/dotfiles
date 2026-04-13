" ============================================================================
" CONFIGURATION VIM OPTIMISÉE (VANILLA & PERFORMANCE)
" ============================================================================

" --- INTERFACE ET VISUEL ---
syntax on                   " Active la coloration syntaxique
" set number                  " Affiche les numéros de ligne
set relativenumber          " Numérotation relative (essentiel pour les sauts)
set mouse=                  " Désactive la souris (100% clavier)
set laststatus=2            " Toujours afficher la barre d'état
set showcmd                 " Affiche la commande en cours en bas à droite
set cursorline              " Souligne la ligne actuelle (repère visuel rapide)
set scrolloff=5             " Garde 5 lignes de contexte lors du défilement
set termguicolors           " Active les couleurs 24-bits (pour Retrobox)

" --- COULEURS (Natif Vim 9.0+ / Neovim) ---
set background=dark         " Optimise les couleurs pour fond sombre
silent! colorscheme retrobox " Thème natif inspiré de Gruvbox (robuste et rétro)

" --- GUIDES VISUELS D'INDENTATION ---
set list                    " Affiche les caractères invisibles
" Affiche une flèche pour les tabs et un point pour les espaces en fin de ligne
set listchars=tab:→\ ,trail:·,nbsp:± 
set colorcolumn=80          " Ligne verticale à 80 car. pour limiter la largeur
highlight ColorColumn ctermbg=235 guibg=#32302f " Couleur discrète

" --- INDENTATION ET TABULATIONS ---
filetype plugin indent on   " Détecte le type de fichier pour l'indentation
set expandtab               " Transforme les tabulations en espaces
set tabstop=2               " Largeur visuelle d'une tabulation (gain de place)
set shiftwidth=2            " Taille de l'indentation automatique
set softtabstop=2           " Nombre d'espaces pour une pression sur Tab
set smartindent             " Indentation intelligente selon le code

" --- RECHERCHE ---
set ignorecase              " Recherche insensible à la casse...
set smartcase               " ...sauf si une majuscule est saisie
set incsearch               " Recherche pendant la saisie
set hlsearch                " Surligne les résultats de recherche
" Touche Echap pour nettoyer le surlignage de recherche
nnoremap <esc> :noh<return><esc>

" --- COMPORTEMENT DE SUPPRESSION (BLACK HOLE) ---
" Empêche d'écraser le registre de copie lors d'une suppression ou modification
nnoremap d "_d
vnoremap d "_d
nnoremap D "_D
nnoremap c "_c
vnoremap c "_c
nnoremap C "_C
nnoremap x "_x

" --- EXPLORATEUR DE FICHIERS (NETRW) ---
let g:netrw_banner = 0      " Supprime l'aide inutile en haut
let g:netrw_liststyle = 3   " Vue en arborescence
let g:netrw_winsize = 20    " Prend 20% de l'écran (idéal petit écran)
" Raccourci pour ouvrir/fermer l'explorateur (Leader est \ par défaut)
nnoremap <leader>e :Lexplore<CR>

" --- MAPPINGS CLAVIER FR / SPÉCIFIQUES ---
" Utilisation de la touche 'œ' comme préfixe de gestion de fenêtres (Ctrl+W)
map œ <C-w>
map! œ <C-o>

" --- AUTOMATISATION DÉVELOPPEMENT (Compilation/Exécution) ---
" Appuyer sur F5 pour sauvegarder et lancer le script/programme selon le langage
autocmd FileType python nnoremap <buffer> <F5> :w<CR>:!python3 %<CR>
autocmd FileType c nnoremap <buffer> <F5> :w<CR>:!gcc % -o out && ./out<CR>
autocmd FileType cpp nnoremap <buffer> <F5> :w<CR>:!g++ % -o out && ./out<CR>
autocmd FileType sh nnoremap <buffer> <F5> :w<CR>:!bash %<CR>

" --- DIVERS ---
set noswapfile              " Désactive les fichiers .swp
set clipboard=unnamedplus   " Utilise le presse-papier système par défaut

" Permet de changer de buffer sans sauvegarder (très utile dans Tmux)
set hidden
