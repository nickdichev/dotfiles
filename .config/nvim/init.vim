call plug#begin('~/.config/nvim/plugged')
  Plug 'neoclide/coc.nvim', {'branch': 'release'}
  Plug 'airblade/vim-gitgutter'
  Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
  Plug 'junegunn/fzf.vim'
  Plug 'tpope/vim-fugitive'
  Plug 'tpope/vim-rhubarb'
  Plug 'tpope/vim-eunuch'
  Plug 'tpope/vim-commentary'
  Plug 'itchyny/lightline.vim'
  Plug 'kana/vim-textobj-user'
  Plug 'direnv/direnv.vim'
  Plug 'qpkorr/vim-bufkill'
  Plug 'APZelos/blamer.nvim'
  Plug 'vim-test/vim-test'
  " Languages
  " Elixir
  Plug 'elixir-editors/vim-elixir'
  Plug 'mhinz/vim-mix-format'
  Plug 'amiralies/vim-textobj-elixir'
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
set scrolloff=5
highlight ColorColumn ctermbg=4 guibg=lightblue
highlight MatchParen cterm=none ctermfg=lightblue ctermbg=none
highlight clear SignColumn

"Kotlin
au BufReadPost *.kt set syntax=kotlin

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

" Allow mousescroll in normal mode
set mouse=ah

" Move between splits
nnoremap <leader>h <C-W>h
nnoremap <leader>j <C-W>j
nnoremap <leader>k <C-W>k
nnoremap <leader>l <C-W>l

" Move between buffers
nnoremap <leader>n :bn<CR>
nnoremap <leader>p :bp<CR>
nnoremap <leader>b :buffers<CR>:buffer<Space>

" Jumplist
nnoremap <leader>o <C-o>
nnoremap <leader>i <C-i>

" Shift hunks by line
xnoremap K :move '<-2<CR>gv-gv
xnoremap J :move '>+1<CR>gv-gv

" Fzf
nnoremap <leader>fg :GFiles<CR>
nnoremap <leader>ff :Files<CR>
nnoremap <leader>fr :Rg<CR>
nnoremap <leader>fb :Buffers<CR>

" Vim-test
nnoremap <leader>tf :TestFile<CR>
nnoremap <leader>tn :TestNearest<CR>
nnoremap <leader>tt :TestLast<CR>
nnoremap <leader>tv :TestVisit<CR>

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
source ~/.config/nvim/plugins/blamer.vim
source ~/.config/nvim/plugins/vim-test.vim
