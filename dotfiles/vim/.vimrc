" ============================================================================
" ~/.vimrc - 由 linux-tune 管理（不依赖任何插件）
" ============================================================================
set nocompatible
filetype plugin indent on

" ---- 显示 ----
syntax on
set number relativenumber
set cursorline
set showmatch
set wildmenu
set wildmode=longest:full,full
set laststatus=2
set ruler
set scrolloff=5
set sidescrolloff=5
set display+=lastline
set termguicolors
set background=dark

" ---- 缩进 ----
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
set autoindent
set smartindent
set shiftround
autocmd FileType python,json,yaml,javascript,typescript,css,html setlocal shiftwidth=2 tabstop=2 softtabstop=2
autocmd FileType make setlocal noexpandtab

" ---- 搜索 ----
set incsearch
set hlsearch
set ignorecase
set smartcase
nnoremap <silent> <leader>h :nohlsearch<CR>

" ---- 编辑 ----
set backspace=indent,eol,start
set clipboard=unnamedplus
set undofile
set undodir=~/.vim/undo
set noswapfile
set mouse=a
set pastetoggle=<F2>

" ---- 中文 ----
set fileencodings=utf-8,gbk,gb18030,latin1
set fileencoding=utf-8
set encoding=utf-8
set langmenu=zh_CN.UTF-8

" ---- 快捷键 ----
let mapleader=" "
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>s :wq<CR>
inoremap jk <Esc>
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" ---- 自动命令 ----
autocmd BufWritePre * :%s/\s\+$//e
autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g`\"" | endif
