let SessionLoad = 1
let s:so_save = &g:so | let s:siso_save = &g:siso | setg so=0 siso=0 | setl so=-1 siso=-1
let v:this_session=expand("<sfile>:p")
doautoall SessionLoadPre
silent only
silent tabonly
cd ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
let s:shortmess_save = &shortmess
set shortmess+=aoO
badd +1 ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/completion.lua
badd +11 ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/type.lua
badd +5 lua/minecraft-dev/init.lua
badd +1 todo/todo1.md
badd +6 ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/config.lua
argglobal
%argdel
edit ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/config.lua
let s:save_splitbelow = &splitbelow
let s:save_splitright = &splitright
set splitbelow splitright
wincmd _ | wincmd |
vsplit
1wincmd h
wincmd _ | wincmd |
split
1wincmd k
wincmd w
wincmd w
wincmd _ | wincmd |
split
1wincmd k
wincmd w
let &splitbelow = s:save_splitbelow
let &splitright = s:save_splitright
wincmd t
let s:save_winminheight = &winminheight
let s:save_winminwidth = &winminwidth
set winminheight=0
set winheight=1
set winminwidth=0
set winwidth=1
exe '1resize ' . ((&lines * 29 + 30) / 60)
exe 'vert 1resize ' . ((&columns * 113 + 113) / 227)
exe '2resize ' . ((&lines * 28 + 30) / 60)
exe 'vert 2resize ' . ((&columns * 113 + 113) / 227)
exe '3resize ' . ((&lines * 29 + 30) / 60)
exe 'vert 3resize ' . ((&columns * 113 + 113) / 227)
exe '4resize ' . ((&lines * 28 + 30) / 60)
exe 'vert 4resize ' . ((&columns * 113 + 113) / 227)
argglobal
balt lua/minecraft-dev/init.lua
setlocal foldmethod=manual
setlocal foldexpr=v:lua.vim.treesitter.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
silent! normal! zE
sil! 3,5fold
let &fdl = &fdl
let s:l = 7 - ((6 * winheight(0) + 14) / 28)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 7
normal! 08|
wincmd w
argglobal
if bufexists(fnamemodify("~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/completion.lua", ":p")) | buffer ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/completion.lua | else | edit ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/completion.lua | endif
if &buftype ==# 'terminal'
  silent file ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/completion.lua
endif
balt ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/type.lua
setlocal foldmethod=manual
setlocal foldexpr=v:lua.vim.treesitter.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
silent! normal! zE
sil! 13,19fold
sil! 10,21fold
sil! 28,30fold
sil! 27,31fold
sil! 26,33fold
let &fdl = &fdl
let s:l = 33 - ((25 * winheight(0) + 13) / 27)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 33
normal! 02|
wincmd w
argglobal
if bufexists(fnamemodify("todo/todo1.md", ":p")) | buffer todo/todo1.md | else | edit todo/todo1.md | endif
if &buftype ==# 'terminal'
  silent file todo/todo1.md
endif
balt lua/minecraft-dev/init.lua
setlocal foldmethod=manual
setlocal foldexpr=0
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
silent! normal! zE
sil! 3,4fold
sil! 2,6fold
sil! 1,8fold
let &fdl = &fdl
let s:l = 6 - ((5 * winheight(0) + 14) / 28)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 6
normal! 0
wincmd w
argglobal
if bufexists(fnamemodify("lua/minecraft-dev/init.lua", ":p")) | buffer lua/minecraft-dev/init.lua | else | edit lua/minecraft-dev/init.lua | endif
if &buftype ==# 'terminal'
  silent file lua/minecraft-dev/init.lua
endif
balt ~/CodeProject/luaPro/nvim-plug/minecraft-dev.nvim/lua/minecraft-dev/type.lua
setlocal foldmethod=manual
setlocal foldexpr=v:lua.vim.treesitter.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
silent! normal! zE
sil! 6,10fold
sil! 14,16fold
sil! 13,17fold
sil! 12,20fold
let &fdl = &fdl
let s:l = 5 - ((4 * winheight(0) + 13) / 27)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 5
normal! 058|
wincmd w
4wincmd w
exe '1resize ' . ((&lines * 29 + 30) / 60)
exe 'vert 1resize ' . ((&columns * 113 + 113) / 227)
exe '2resize ' . ((&lines * 28 + 30) / 60)
exe 'vert 2resize ' . ((&columns * 113 + 113) / 227)
exe '3resize ' . ((&lines * 29 + 30) / 60)
exe 'vert 3resize ' . ((&columns * 113 + 113) / 227)
exe '4resize ' . ((&lines * 28 + 30) / 60)
exe 'vert 4resize ' . ((&columns * 113 + 113) / 227)
tabnext 1
if exists('s:wipebuf') && len(win_findbuf(s:wipebuf)) == 0 && getbufvar(s:wipebuf, '&buftype') isnot# 'terminal'
  silent exe 'bwipe ' . s:wipebuf
endif
unlet! s:wipebuf
set winheight=1 winwidth=20
let &shortmess = s:shortmess_save
let &winminheight = s:save_winminheight
let &winminwidth = s:save_winminwidth
let s:sx = expand("<sfile>:p:r")."x.vim"
if filereadable(s:sx)
  exe "source " . fnameescape(s:sx)
endif
let &g:so = s:so_save | let &g:siso = s:siso_save
set hlsearch
doautoall SessionLoadPost
unlet SessionLoad
" vim: set ft=vim :
