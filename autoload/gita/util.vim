let s:V = gita#vital()
let s:Guard = s:V.import('Vim.Guard')
let s:Compat = s:V.import('Vim.Compat')
let s:Prompt = s:V.import('Vim.Prompt')

function! s:diffoff() abort
  if !&diff
    return
  endif
  augroup vim_gita_internal_util_diffthis
    autocmd! * <buffer>
  augroup END
  if maparg('<C-l>', 'n') ==# '<Plug>(gita-C-l)'
    unmap <buffer> <C-l>
  endif
  nunmap <buffer> <Plug>(gita-C-l)
  diffoff
endfunction

function! gita#util#clip(content) abort
  let @" = a:content
  if has('clipboard')
    call setreg(v:register, a:content)
  endif
endfunction

function! gita#util#doautocmd(name, ...) abort
  let pattern = get(a:000, 0, '')
  let expr = empty(pattern)
        \ ? '#' . a:name
        \ : '#' . a:name . '#' . pattern
  let eis = split(&eventignore, ',')
  if index(eis, a:name) >= 0 || index(eis, 'all') >= 0 || !exists(expr)
    " the specified event is ignored or not exists
    return
  endif
  let nomodeline = has('patch-7.4.438') && a:name ==# 'User'
        \ ? '<nomodeline> '
        \ : ''
  execute printf('doautocmd %s%s %s', nomodeline, a:name, pattern)
endfunction

function! gita#util#diffthis() abort
  if maparg('<C-l>', 'n') ==# ''
    nmap <buffer> <C-l> <Plug>(gita-C-l)
  endif
  nnoremap <buffer><silent> <Plug>(gita-C-l)
        \ :<C-u>diffupdate<BAR>redraw<CR>

  augroup vim_gita_internal_util_diffthis
    autocmd! * <buffer>
    autocmd BufWinLeave <buffer> call s:diffoff()
    autocmd BufHidden <buffer>   call s:diffoff()
  augroup END
  diffthis
  keepjump normal! zM
endfunction

function! gita#util#handle_exception() abort
  let known_attention_patterns = [
        \ '^\%(vital: Git[:.]\|vim-gita:\) Cancel: ',
        \ '^\%(vital: Git[:.]\|vim-gita:\) Attention: ',
        \]
  for pattern in known_attention_patterns
    if v:exception =~# pattern
      call s:Prompt.attention(
            \ 'gita:',
            \ substitute(v:exception, pattern, '', ''),
            \)
      return
    endif
  endfor
  let known_warning_patterns = [
        \ '^\%(vital: Git[:.]\|vim-gita:\) \zeWarning: ',
        \ '^\%(vital: Git[:.]\|vim-gita:\) \zeValidationError: ',
        \]
  for pattern in known_warning_patterns
    if v:exception =~# pattern
      call s:Prompt.warn(
            \ 'gita:',
            \ substitute(v:exception, pattern, '', ''),
            \)
      return
    endif
  endfor
  call s:Prompt.error(v:exception)
  call s:Prompt.debug(v:throwpoint)
endfunction

function! gita#util#define_variables(prefix, defaults) abort
  " Note:
  "   Funcref is not supported while the variable must start with a capital
  let prefix = empty(a:prefix)
        \ ? 'g:gita'
        \ : printf('g:gita#%s', a:prefix)
  for [key, value] in items(a:defaults)
    let name = printf('%s#%s', prefix, key)
    if !exists(name)
      execute printf('let %s = %s', name, string(value))
    endif
    unlet value
  endfor
endfunction

function! gita#util#select(selection, ...) abort
  " Original from mattn/emmet-vim
  " https://github.com/mattn/emmet-vim/blob/master/autoload/emmet/util.vim#L75-L79
  let prefer_visual = get(a:000, 0, 0)
  let line_start = get(a:selection, 0, line('.'))
  let line_end = get(a:selection, 1, line_start)
  if line_start == line_end && !prefer_visual
    keepjump call setpos('.', [0, line_start, 1, 0])
  else
    keepjump call setpos('.', [0, line_end, 1, 0])
    keepjump normal! v
    keepjump call setpos('.', [0, line_start, 1, 0])
  endif
endfunction

function! gita#util#matchdict(expr, pattern, scheme) abort
  if a:expr !~# a:pattern
    return {}
  endif
  let t = type(0)
  let m = matchlist(a:expr, a:pattern)
  let object = {}
  for [key, value] in items(a:scheme)
    if type(value) == t
      let object[key] = m[value]
    else
      let object[key] = value
    endif
    unlet value
  endfor
  return object
endfunction
