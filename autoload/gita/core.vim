let s:V = vital#of('vim_gita')
let s:Path = s:V.import('System.Filepath')
let s:Compat = s:V.import('Vim.Compat')
let s:Git = s:V.import('Git')
let s:NAME = '_gita_refinfo'
let s:references = {}

function! s:get_available_refname(refname) abort
  if !has_key(s:references, a:refname)
    return a:refname
  endif
  " find alternative refname
  let l:count = 1
  while has_key(s:references, a:refname . '~' . l:count)
    let l:count += 1
  endwhile
  return a:refname . '~' . l:count
endfunction

function! s:is_expired(expr, refinfo) abort
  let buftype  = s:Compat.getbufvar(a:expr, '&buftype', '')
  if has_key(a:refinfo, 'git') && get(a:refinfo.git, 'is_expired')
    " the git instance is reserved as expired
    return 1
  elseif buftype =~# '^\%(\|nowrite\|acwrite\)$' && bufname(a:expr) !=# a:refinfo.bufname
    " the bufname has changed since detection
    return 1
  elseif buftype =~# '^\%(nofile\|quickfix\|help\)$' && getcwd() !=# a:refinfo.cwd
    " the current working directory has changed since detection
    return 1
  endif
  return 0
endfunction

function! s:get_for_internal(expr, options) abort
  let bufname = bufname(a:expr)
  let refname = matchstr(bufname, '^gita:\%(//\)\?\zs[^:\\/]\+')
  if !has_key(s:references, refname)
    call gita#throw(printf(
          \ 'No repository reference for %s is found.',
          \ refname,
          \))
  endif
  return s:references[refname]
endfunction

function! s:get_for_external(expr, options) abort
  let options = extend({
        \ 'force': 0,
        \}, a:options)
  let refinfo = gita#core#get_refinfo(a:expr)
  if !empty(refinfo) && !options.force && !s:is_expired(a:expr, refinfo)
    return refinfo.git
  endif
  return s:new_for_external(a:expr, a:options)
endfunction

function! s:new_for_external(expr, options) abort
  let options = extend({
        \ 'force': 0,
        \}, a:options)
  let buftype = s:Compat.getbufvar(a:expr, '&buftype', '')
  if buftype =~# '^\%(\|nowrite\|acwrite\)$'
    " file buffer
    let filename = gita#meta#expand(a:expr)
    let git = s:Git.get(filename, options)
    let git = !git.is_enabled && filename !=# resolve(filename)
          \ ? s:Git.get(resolve(filename), options)
          \ : git
  else
    let git = {}
  endif
  " try to find a git repository from cwd if couldn't
  let git = empty(git) || !git.is_enabled
        \ ? s:Git.get(getcwd(), options)
        \ : git
  let git = !git.is_enabled && getcwd() !=# resolve(getcwd())
        \ ? s:Git.get(resolve(getcwd()), options)
        \ : git
  " save git instance to the reference
  if git.is_enabled
    let refname = s:get_available_refname(git.repository_name)
    let s:references[refname] = git
  else
    let refname = ''
  endif
  " save reference info to the buffer if the buffer exists
  " NOTE: bufexists() does not support '%'
  if bufexists(bufnr(a:expr))
    call setbufvar(a:expr, s:NAME, {
          \ 'git': git,
          \ 'refname': refname,
          \ 'bufname': bufname(a:expr),
          \ 'cwd': getcwd(),
          \})
  endif
  return git
endfunction

function! gita#core#get(...) abort
  let expr = get(a:000, 0, '%')
  let options = get(a:000, 1, {})
  if bufname(expr) =~# '^gita:'
    return s:get_for_internal(expr, options)
  else
    return s:get_for_external(expr, options)
  endif
endfunction

function! gita#core#get_or_fail(...) abort
  let git = call('gita#core#get', a:000)
  if git.is_enabled
    return git
  endif
  let expr = get(a:000, 0, '%')
  call gita#throw(join([
        \ 'Attention:',
        \ printf('Git is not available on "%s" buffer.', expand(expr)),
        \ 'Call ":GitaClear" to remove cache if you feel it is incorrect.',
        \]))
endfunction

function! gita#core#expire(...) abort
  let git = call('gita#core#get', a:000)
  let git.is_expired = 1
endfunction

function! gita#core#get_refinfo(...) abort
  let expr = get(a:000, 0, '%')
  let refinfo = s:Compat.getbufvar(expr, s:NAME, {})
  return refinfo
endfunction

function! s:on_BufWritePre() abort
  if empty(&buftype) && gita#core#get().is_enabled
    let b:_gita_internal_modified = &modified
  endif
endfunction

function! s:on_BufWritePost() abort
  if exists('b:_gita_internal_modified')
    if b:_gita_internal_modified && !&modified
      call gita#util#doautocmd('User', 'GitaStatusModified')
    endif
    unlet b:_gita_internal_modified
  endif
endfunction

" Automatically check if files in a git repository has modified
augroup vim_gita_internal_core
  autocmd! *
  autocmd BufWritePre  * call s:on_BufWritePre()
  autocmd BufWritePost * nested call s:on_BufWritePost()
augroup END
