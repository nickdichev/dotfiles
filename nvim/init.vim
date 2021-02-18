call plug#begin('~/.config/nvim/plugged')
  Plug 'neoclide/coc.nvim', {'branch': 'release'}
  Plug 'airblade/vim-gitgutter'
  Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
  Plug 'junegunn/fzf.vim'
  Plug 'tpope/vim-fugitive'
  Plug 'itchyny/lightline.vim'
  Plug 'kana/vim-textobj-user'
  " Languages
  " Elixir
  Plug 'elixir-editors/vim-elixir'
  Plug 'mhinz/vim-mix-format'
  Plug 'amiralies/vim-textobj-elixir'
  " Go
  Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
call plug#end()

" ## General
set encoding=UTF-8
syntax on
set background=dark cursorline
set number relativenumber
set backspace=indent,eol,start confirm
set shiftwidth=2 autoindent smartindent tabstop=2 softtabstop=2 expandtab
set splitbelow splitright
set nobackup nowritebackup
set colorcolumn=120
highlight ColorColumn ctermbg=4 guibg=lightblue
highlight MatchParen cterm=none ctermfg=lightblue ctermbg=none
highlight clear SignColumn

" ## Keybinds
let mapleader=" "

" Handle nvim config
nnoremap <leader>, :vsplit ~/.config/nvim/init.vim<CR>
nnoremap <C-s> :source ~/.config/nvim/init.vim<CR>

" Reize splits
nnoremap <Up> :resize +2<CR>
nnoremap <Down> :resize -2<CR>
nnoremap <Left> :vertical resize +2<CR>
nnoremap <Right> :vertical resize -2<CR>

" Move between splits
nnoremap <leader>h <C-W>h
nnoremap <leader>j <C-W>j
nnoremap <leader>k <C-W>k
nnoremap <leader>l <C-W>l

" Move between buffers
nnoremap <leader>n :bn<CR>
nnoremap <leader>p :bp<CR>

" Shift hunks by line
xnoremap K :move '<-2<CR>gv-gv
xnoremap J :move '>+1<CR>gv-gv

" Fzf
nnoremap <C-p> :GFiles<CR>
nnoremap <C-o> :Files<CR>
nnoremap <C-r> :Rg<CR>

" NetRW
let g:netrw_banner = 0
let g:netrw_liststyle = 3
let g:netrw_browse_split = 4
let g:netrw_altv = 1
let g:netrw_winsize = 25

" ## Plugin Configuration
source ~/.config/nvim/plugins/coc.vim
source ~/.config/nvim/plugins/vim-gitgutter.vim
source ~/.config/nvim/plugins/lightline.vim
source ~/.config/nvim/plugins/vim-mix-format.vim
