" Basic Settings
set number
set relativenumber
set expandtab
set tabstop=2
set shiftwidth=2
set smartindent
set ignorecase
set smartcase
set termguicolors
set updatetime=300
set signcolumn=yes

" Key mappings
let mapleader = " "
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>e :Explore<CR>

" Load Lua plugins
lua require('plugins')

" Theme settings
colorscheme habamax  " Fallback theme

" Telescope mappings (if installed)
nnoremap <leader>ff <cmd>Telescope find_files<cr>
nnoremap <leader>fg <cmd>Telescope live_grep<cr>
nnoremap <leader>fb <cmd>Telescope buffers<cr>

" Load Claude
lua require('claude').setup()
