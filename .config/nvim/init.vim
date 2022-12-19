call plug#begin('~/.config/nvim/plugged')
  Plug 'airblade/vim-gitgutter'
  Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
  Plug 'junegunn/fzf.vim'
  Plug 'tpope/vim-fugitive'
  Plug 'tpope/vim-rhubarb'
  Plug 'tpope/vim-eunuch'
  Plug 'tpope/vim-commentary'
  Plug 'kana/vim-textobj-user'
  Plug 'direnv/direnv.vim'
  Plug 'qpkorr/vim-bufkill'
  Plug 'APZelos/blamer.nvim'
  Plug 'vim-test/vim-test'
  Plug 'hoob3rt/lualine.nvim'
  Plug 'kyazdani42/nvim-web-devicons'
  " LSP
  Plug 'neovim/nvim-lspconfig'
  Plug 'hrsh7th/nvim-compe'
  Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
  " Languages
  " Elixir
  " Plug 'elixir-editors/vim-elixir'
  Plug 'amiralies/vim-textobj-elixir'
  Plug 'renderedtext/vim-elixir-alternative-files'
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
set signcolumn=yes
highlight ColorColumn ctermbg=4 guibg=lightblue
highlight MatchParen cterm=none ctermfg=lightblue ctermbg=none
highlight Folded ctermbg=none
highlight clear SignColumn

" Trailing spaces
:set list!
:set list listchars=tab:\|_,trail:·
highlight NonText ctermfg=red ctermbg=none

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
nnoremap <leader>fc :Rg <c-r>=expand("<cword>")<cr><CR>

" Vim-test
nnoremap <leader>tf :TestFile<CR>
nnoremap <leader>tn :TestNearest<CR>
nnoremap <leader>tt :TestLast<CR>
nnoremap <leader>tv :TestVisit<CR>

" Elixir
nnoremap <leader>a :call ElixirAlternateFile()<CR>

" NetRW
let g:netrw_banner = 0
let g:netrw_liststyle = 3
let g:netrw_browse_split = 4
let g:netrw_altv = 1
let g:netrw_winsize = 25

" Scratch
function! Scratch()
  split
  noswapfile hide enew
  setlocal buftype=nofile
  setlocal bufhidden=hide
  "setlocal nobuflisted
  "lcd ~
  file scratch
endfunction

" ## Plugin Configuration
" source ~/.config/nvim/plugins/coc.vim
source ~/.config/nvim/plugins/vim-gitgutter.vim
source ~/.config/nvim/plugins/lightline.vim
source ~/.config/nvim/plugins/vim-mix-format.vim
source ~/.config/nvim/plugins/blamer.vim
source ~/.config/nvim/plugins/vim-test.vim

:lua << EOF
local nvim_lsp = require('lspconfig')

local on_attach = function(client, bufnr)
  local function buf_set_keymap(...) vim.api.nvim_buf_set_keymap(bufnr, ...) end
  local function buf_set_option(...) vim.api.nvim_buf_set_option(bufnr, ...) end

  -- Enable completion triggered by <c-x><c-o>
  buf_set_option('omnifunc', 'v:lua.vim.lsp.omnifunc')

  -- Mappings.
  local opts = { noremap=true, silent=true }

  -- See `:help vim.lsp.*` for documentation on any of the below functions
  buf_set_keymap('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
  buf_set_keymap('n', 'K', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
  buf_set_keymap('n', '<C-k>', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
  buf_set_keymap('n', '<space>D', '<cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
  buf_set_keymap('n', '<space>ca', '<cmd>lua vim.lsp.buf.code_action()<CR>', opts)
  buf_set_keymap('n', '<space>e', '<cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>', opts)
  buf_set_keymap('n', '[e', '<cmd>lua vim.lsp.diagnostic.goto_prev()<CR>', opts)
  buf_set_keymap('n', ']e', '<cmd>lua vim.lsp.diagnostic.goto_next()<CR>', opts)
  buf_set_keymap('n', '<leader>mf', '<cmd>lua vim.lsp.buf.formatting()<CR>', opts)
end

nvim_lsp.elixirls.setup{
  cmd = { '/Users/kamana/.ls/elixir-ls/release/language_server.sh' },
  on_attach = on_attach,
  settings = {
    elixirLS = {
      fetchDeps = false
    }
  }
}

require('nvim-treesitter.configs').setup({
  highlight = {
    enable = true
  },
})

require('compe').setup({
  enabled = true;
  autocomplete = true;
  debug = false;
  min_length = 1;
  preselect = 'enable';
  throttle_time = 80;
  source_timeout = 200;
  incomplete_delay = 400;
  max_abbr_width = 100;
  max_kind_width = 100;
  max_menu_width = 100;
  documentation = true;

  source = {
    path = true;
    nvim_lsp = true;
  };
})

require('lualine').setup({
  options = {
    theme = 'palenight',
    icons_enabled = false
  }
})

local t = function(str)
  return vim.api.nvim_replace_termcodes(str, true, true, true)
end

local check_back_space = function()
    local col = vim.fn.col('.') - 1
    if col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') then
        return true
    else
        return false
    end
end

-- Use (s-)tab to:
--- move to prev/next item in completion menuone
--- jump to prev/next snippet's placeholder
_G.tab_complete = function()
  if vim.fn.pumvisible() == 1 then
    return t "<C-n>"
  elseif check_back_space() then
    return t "<Tab>"
  else
    return vim.fn['compe#complete']()
  end
end
_G.s_tab_complete = function()
  if vim.fn.pumvisible() == 1 then
    return t "<C-p>"
  else
    return t "<S-Tab>"
  end
end

vim.api.nvim_set_keymap("i", "<Tab>", "v:lua.tab_complete()", {expr = true})
vim.api.nvim_set_keymap("s", "<Tab>", "v:lua.tab_complete()", {expr = true})
vim.api.nvim_set_keymap("i", "<S-Tab>", "v:lua.s_tab_complete()", {expr = true})
vim.api.nvim_set_keymap("s", "<S-Tab>", "v:lua.s_tab_complete()", {expr = true})
EOF
