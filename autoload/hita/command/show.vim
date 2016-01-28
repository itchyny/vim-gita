let s:V = hita#vital()
let s:Dict = s:V.import('Data.Dict')
let s:Path = s:V.import('System.Filepath')
let s:ArgumentParser = s:V.import('ArgumentParser')
let s:WORKTREE = '@'

function! s:pick_available_options(options) abort
  let options = s:Dict.pick(a:options, [])
  return options
endfunction
function! s:get_ancestor_content(hita, commit, filename, options) abort
  let [lhs, rhs] = hita#variable#split_range(a:commit)
  let lhs = empty(lhs) ? 'HEAD' : lhs
  let rhs = empty(rhs) ? 'HEAD' : rhs
  let result = hita#operation#exec(a:hita, 'merge-base', {
        \ 'commit1': lhs,
        \ 'commit2': rhs,
        \})
  if result.status
    call hita#throw(printf(
          \ 'A common ancestor of %s and %s could not be found.',
          \ lhs, rhs,
          \))
  endif
  return s:get_revision_content(a:hita, result.stdout, a:filename, a:options)
endfunction
function! s:get_revision_content(hita, commit, filename, options) abort
  let options = s:pick_available_options(a:options)
  if empty(a:filename)
    let options['object'] = a:commit
  else
    let options['object'] = printf('%s:%s',
          \ a:commit,
          \ a:hita.get_relative_path(a:filename),
          \)
  endif
  let result = hita#operation#exec(a:hita, 'show', options)
  if result.status
    call hita#throw(result.stdout)
  endif
  return split(result.stdout, '\r\?\n')
endfunction
function! s:get_diff_content(hita, content, filename, options) abort
  let tempfile1 = tempname()
  let tempfile2 = tempname()
  try
    " save contents to temporary files
    call writefile(
          \ s:get_revision_content(a:hita, '', a:filename, a:options),
          \ tempfile1,
          \)
    call writefile(a:content, tempfile2)
    " create a diff between index_content and content
    let result = hita#command#diff#call({
          \ 'unified': '0',
          \ 'no-index': 1,
          \ 'filenames': [tempfile1, tempfile2],
          \})
    if empty(result) || empty(result.content)
      " fail or no differences
      return ''
    endif
    " replace tempfile1/tempfile2 to a:filename
    let raw_content = join(result.content, "\n")
    let raw_content = substitute(
          \ raw_content, escape(tempfile1, '^$~.*[]\'),
          \ (tempfile1 =~# '^/' ? '/' : '') . a:hita.get_relative_path(a:filename), 'g'
          \)
    let raw_content = substitute(
          \ raw_content, escape(tempfile2, '^$~.*[]\'),
          \ (tempfile2 =~# '^/' ? '/' : '') . a:hita.get_relative_path(a:filename), 'g'
          \)
    return split(raw_content, '\r\?\n')
  finally
    call delete(tempfile1)
    call delete(tempfile2)
  endtry
endfunction

function! s:on_BufWriteCmd() abort
  let commit = hita#core#get_meta('commit', '')
  let options = hita#core#get_meta('options', {})
  let filename = hita#core#get_meta('filename', '')
  if !empty(commit) || empty(filename)
    call hita#util#prompt#warn(join([
          \ 'Partial patching is only available in a INDEX file, namely',
          \ 'a file opened by ":Hita show [--filename={filename}]"',
          \]))
    return
  endif
  silent doautocmd BufWritePre
  let hita = hita#core#get()
  try
    let content = s:get_diff_content(hita, getline(1, '$'), filename, options)
    if empty(content)
      " fail or no difference
      return
    endif
    let result = hita#command#apply#call({
          \ 'diff_content': content,
          \ 'cached': 1,
          \ 'unidiff-zero': 1,
          \})
    if empty(result)
      return
    endif
    call hita#command#show#edit({'force': 1})
    silent diffupdate
    silent doautocmd BufWritePost
  catch /^vim-hita:/
    call hita#util#handle_exception(v:exception)
  endtry
endfunction

function! hita#command#show#bufname(...) abort
  let options = hita#option#init('show', get(a:000, 0, {}), {
        \ 'commit': '',
        \ 'filename': '',
        \})
  if options.commit ==# s:WORKTREE
    return hita#variable#get_valid_filename(options.filename)
  endif

  let hita = hita#core#get()
  try
    call hita.fail_on_disabled()
    let commit = hita#variable#get_valid_range(options.commit, {
          \ '_allow_empty': 1,
          \})
    let filename = empty(options.filename)
          \ ? ''
          \ : hita#variable#get_valid_filename(options.filename)
  catch /^vim-hita:/
    call hita#util#handle_exception(v:exception)
    return
  endtry
  return hita#autocmd#bufname(hita, {
        \ 'content_type': 'show',
        \ 'extra_options': [],
        \ 'treeish': commit . ':' . hita.get_relative_path(filename),
        \})
endfunction
function! hita#command#show#call(...) abort
  let options = hita#option#init('show', get(a:000, 0, {}), {
        \ 'commit': '',
        \ 'filename': '',
        \})
  let hita = hita#core#get()
  try
    call hita.fail_on_disabled()
    let commit = hita#variable#get_valid_range(options.commit, {
          \ '_allow_empty': 1,
          \})
    if empty(options.filename)
      let filename = ''
      let content = s:get_revision_content(hita, commit, filename, options)
    else
      let filename = hita#variable#get_valid_filename(options.filename)
      if commit =~# '^.\{-}\.\.\..*$'
        let content = s:get_ancestor_content(hita, commit, filename, options)
      elseif commit =~# '^.\{-}\.\..*$'
        let commit  = hita#variable#split_range(commit)[0]
        let content = s:get_revision_content(hita, commit, filename, options)
      else
        let content = s:get_revision_content(hita, commit, filename, options)
      endif
    endif
    let result = {
          \ 'commit': commit,
          \ 'filename': filename,
          \ 'content': content,
          \}
    return result
  catch /^vim-hita:/
    call hita#util#handle_exception(v:exception)
    return {}
  endtry
endfunction
function! hita#command#show#open(...) abort
  let options = extend({
        \ 'opener': '',
        \}, get(a:000, 0, {}))
  let opener = empty(options.opener)
        \ ? g:hita#command#show#default_opener
        \ : options.opener
  let bufname = hita#command#show#bufname(options)
  if !empty(bufname)
    call hita#util#buffer#open(bufname, {
          \ 'opener': opener,
          \})
    " BufReadCmd will call ...#edit to apply the content
  endif
endfunction
function! hita#command#show#read(...) abort
  let options = extend({}, get(a:000, 0, {}))
  let result = hita#command#show#call(options)
  if empty(result)
    return
  endif
  call hita#util#buffer#read_content(result.content)
endfunction
function! hita#command#show#edit(...) abort
  let options = extend({
        \ 'force': 0,
        \}, get(a:000, 0, {}))
  if options.force || hita#core#get_meta('content_type', '') !=# 'show'
    " Reload content only when 1) no content exists yet, 2) ! applied to non modified buffer
    let result = hita#command#show#call(options)
    if empty(result)
      return
    endif
    call hita#core#set_meta('content_type', 'show')
    call hita#core#set_meta('options', s:Dict.omit(options, ['force']))
    call hita#core#set_meta('commit', result.commit)
    call hita#core#set_meta('filename', result.filename)
    call hita#core#set_meta('content', result.content)
    let commit = result.commit
    let filename = result.filename
    let content = result.content
  else
    let commit = hita#core#get_meta('commit')
    let filename = hita#core#get_meta('filename')
    let content = hita#core#get_meta('content')
  endif
  call hita#util#buffer#edit_content(content)
  if empty(filename)
    setfiletype git
    setlocal buftype=nowrite
    setlocal readonly
  else
    setlocal buftype=acwrite
    augroup vim_gita_internal_show_apply_diff
      autocmd! * <buffer>
      autocmd BufWriteCmd <buffer> call s:on_BufWriteCmd()
    augroup END
    if empty(commit)
      setlocal noreadonly
    else
      setlocal readonly
    endif
  endif
endfunction

function! s:get_parser() abort
  if !exists('s:parser') || g:hita#develop
    let s:parser = s:ArgumentParser.new({
          \ 'name': 'Hita show',
          \ 'description': 'Show a content of a commit or a file',
          \ 'complete_threshold': g:hita#complete_threshold,
          \})
    call s:parser.add_argument(
          \ '--opener', '-o',
          \ 'A way to open a new buffer such as "edit", "split", etc.', {
          \   'type': s:ArgumentParser.types.value,
          \})
    call s:parser.add_argument(
          \ '--summary',
          \ 'Show summary of the repository instead of file content', {
          \   'conflicts': ['filename'],
          \})
    call s:parser.add_argument(
          \ '--filename',
          \ 'A filename', {
          \   'complete': function('hita#variable#complete_filename'),
          \   'conflicts': ['summary'],
          \})
    call s:parser.add_argument(
          \ '--worktree',
          \ 'Open a content of a file in working tree', {
          \   'conflicts': ['summary'],
          \})
    call s:parser.add_argument(
          \ 'commit',
          \ 'A commit', {
          \   'complete': function('hita#variable#complete_commit'),
          \})
    function! s:parser.hooks.post_validate(options) abort
      if has_key(a:options, 'summary')
        let a:options.filename = ''
        unlet a:options.summary
      endif
      if has_key(a:options, 'worktree')
        let a:options.commit = s:WORKTREE
        unlet a:options.worktree
      endif
    endfunction
    call s:parser.hooks.validate()
  endif
  return s:parser
endfunction
function! hita#command#show#command(...) abort
  let parser  = s:get_parser()
  let options = call(parser.parse, a:000, parser)
  if empty(options)
    return
  endif
  call hita#option#assign_commit(options)
  call hita#option#assign_filename(options)
  " extend default options
  let options = extend(
        \ deepcopy(g:hita#command#show#default_options),
        \ options,
        \)
  call hita#command#show#open(options)
endfunction
function! hita#command#show#complete(...) abort
  let parser = s:get_parser()
  return call(parser.complete, a:000, parser)
endfunction

call hita#define_variables('command#show', {
      \ 'default_options': {},
      \ 'default_opener': 'edit',
      \})
