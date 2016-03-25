function! s:action(candidate, options) abort
  let filenames = gita#meta#get_for(
        \ '^gita-\%(status\|commit\)$', 'filenames', []
        \)
  call gita#content#status#open({
        \ 'filenames': filenames,
        \})
endfunction

function! gita#action#status#define(disable_mapping) abort
  call gita#action#define('status', function('s:action'), {
        \ 'description': 'Open gita-status window',
        \ 'mapping_mode': 'n',
        \ 'options': {},
        \})
  if a:disable_mapping
    return
  endif
  let content_type = gita#meta#get('content_type')
  if content_type ==# 'commit'
    nmap <buffer><nowait> <C-^> <Plug>(gita-status)
  endif
endfunction
