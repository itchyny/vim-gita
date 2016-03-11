let s:V = gita#vital()
let s:Dict = s:V.import('Data.Dict')
let s:StringExt = s:V.import('Data.StringExt')
let s:File = s:V.import('System.File')
let s:Path = s:V.import('System.Filepath')
let s:Git = s:V.import('Git')
let s:GitTerm = s:V.import('Git.Term')
let s:GitInfo = s:V.import('Git.Info')
let s:ArgumentParser = s:V.import('ArgumentParser')

function! s:find_commit_meta(git, commit) abort
  let config = s:GitInfo.get_repository_config(a:git)
  if a:commit =~# '^.\{-}\.\.\..*$'
    let [lhs, rhs] = s:GitTerm.split_range(a:commit)
    let lhs = empty(lhs) ? 'HEAD' : lhs
    let rhs = empty(rhs) ? 'HEAD' : rhs
    let remote = s:GitInfo.get_branch_remote(config, lhs)
    let lhs = s:GitInfo.find_common_ancestor(a:git, lhs, rhs)
  elseif a:commit =~# '^.\{-}\.\..*$'
    let [lhs, rhs] = s:GitTerm.split_range(a:commit)
    let lhs = empty(lhs) ? 'HEAD' : lhs
    let rhs = empty(rhs) ? 'HEAD' : rhs
    let remote = s:GitInfo.get_branch_remote(config, lhs)
  else
    let lhs = empty(a:commit) ? 'HEAD' : a:commit
    let rhs = ''
    let remote = s:GitInfo.get_branch_remote(config, lhs)
  endif
  let remote = empty(remote) ? 'origin' : remote
  let remote_url = s:GitInfo.get_remote_url(config, remote)
  return [lhs, rhs, remote, remote_url]
endfunction
function! s:translate_url(url, scheme_name, translation_patterns, repository) abort
  let symbol = a:repository ? '^' : '_'
  for [domain, info] in items(a:translation_patterns)
    for pattern in info[0]
      let pattern = substitute(pattern, '\C' . '%domain', domain, 'g')
      if a:url =~# pattern
        let scheme = get(info[1], a:scheme_name, info[1][symbol])
        let repl = substitute(a:url, '\C' . pattern, scheme, 'g')
        return repl
      endif
    endfor
  endfor
  return ''
endfunction
function! s:find_url(git, commit, filename, options) abort
  let relpath = s:Path.unixpath(
        \ s:Git.get_relative_path(a:git, a:filename),
        \)
  " normalize commit to figure out remote, commit, and remote_url
  let [commit1, commit2, remote, remote_url] = s:find_commit_meta(a:git, a:commit)
  let revision1 = s:GitInfo.get_remote_hash(a:git, remote, commit1)
  let revision2 = s:GitInfo.get_remote_hash(a:git, remote, commit2)

  " get selected region
  if has_key(a:options, 'selection')
    let line_start = get(a:options.selection, 0, 0)
    let line_end   = get(a:options.selection, 1, 0)
  else
    let line_start = 0
    let line_end = 0
  endif
  let line_end = line_start == line_end ? 0 : line_end

  " create a URL
  let data = {
        \ 'path':       relpath,
        \ 'commit1':    commit1,
        \ 'commit2':    commit2,
        \ 'revision1':  revision1,
        \ 'revision2':  revision2,
        \ 'remote':     remote,
        \ 'line_start': line_start,
        \ 'line_end':   line_end,
        \}
  let format_map = {
        \ 'pt': 'path',
        \ 'c1': 'commit1',
        \ 'c2': 'commit2',
        \ 'r1': 'revision1',
        \ 'r2': 'revision2',
        \ 'ls': 'line_start',
        \ 'le': 'line_end',
        \}
  let translation_patterns = extend(
        \ deepcopy(g:gita#command#browse#translation_patterns),
        \ g:gita#command#browse#extra_translation_patterns,
        \)
  let url = s:translate_url(
        \ remote_url,
        \ empty(a:filename) ? '^' : get(a:options, 'scheme', '_'),
        \ translation_patterns,
        \ empty(a:filename),
        \)
  if empty(url)
    call gita#throw(printf(
          \ 'Warning: No url translation pattern for "%s" is found.',
          \ remote_url,
          \))
  endif
  return s:StringExt.format(url, format_map, data)
endfunction

function! gita#command#browse#call(...) abort
  let options = extend({
        \ 'commit': '',
        \ 'filename': '',
        \}, get(a:000, 0, {}))
  let git = gita#core#get_or_fail()
  let local_branch = s:GitInfo.get_local_branch(git)
  let commit = empty(options.commit) ? local_branch.name : options.commit
  let commit = gita#variable#get_valid_range(commit)
  if empty(options.filename)
    let filename = ''
  else
    let filename = gita#variable#get_valid_filename(options.filename)
  endif
  let url = s:find_url(git, commit, filename, options)
  return {
        \ 'commit': commit,
        \ 'filename': filename,
        \ 'url': url,
        \ 'options': options,
        \}
endfunction
function! gita#command#browse#open(...) abort
  let options = get(a:000, 0, {})
  let result = gita#command#browse#call(options)
  call s:File.open(result.url)
endfunction
function! gita#command#browse#echo(...) abort
  let options = get(a:000, 0, {})
  let result = gita#command#browse#call(options)
  echo result.url
endfunction
function! gita#command#browse#yank(...) abort
  let options = get(a:000, 0, {})
  let result = gita#command#browse#call(options)
  call gita#util#clip(result.url)
endfunction

function! s:get_parser() abort
  if !exists('s:parser') || g:gita#develop
    let s:parser = s:ArgumentParser.new({
          \ 'name': 'Gita browse',
          \ 'description': 'Open/Yank/Echo a URL of a content of the remote',
          \ 'complete_unknown': function('gita#complete#filename'),
          \ 'unknown_description': '<path>...',
          \ 'complete_threshold': g:gita#complete_threshold,
          \})
    call s:parser.add_argument(
          \ '--repository', '-r',
          \ 'Use a URL of the repository instead',
          \)
    call s:parser.add_argument(
          \ '--open', '-o',
          \ 'Open a URL of a selected region of the remote in a system default browser (Default)', {
          \   'conflicts': ['yank', 'echo'],
          \})
    call s:parser.add_argument(
          \ '--yank', '-y',
          \ 'Yank a URL of a selected region of the remote.', {
          \   'conflicts': ['open', 'echo'],
          \})
    call s:parser.add_argument(
          \ '--echo', '-e',
          \ 'Echo a URL of a selected region of the remote.', {
          \   'conflicts': ['open', 'yank'],
          \})
    call s:parser.add_argument(
          \ '--scheme', '-s',
          \ 'Which scheme to determine remote URL.', {
          \   'type': s:ArgumentParser.types.value,
          \   'default': '_',
          \})
    call s:parser.add_argument(
          \ '--selection',
          \ 'A line number or range of the selection', {
          \   'pattern': '^\%(\d\+\|\d\+-\d\+\)$',
          \})
    call s:parser.add_argument(
          \ 'commit', [
          \   'A commit which you want to see.',
          \   'If nothing is specified, it open a remote content of the current branch.',
          \   'If <commit> is specified, it open a remote content of the named <commit>.',
          \   'If <commit1>..<commit2> is specified, it try to open a diff page of the remote content',
          \   'If <commit1>...<commit2> is specified, it try to open a diff open of the remote content',
          \], {
          \   'complete': function('gita#complete#commit'),
          \})
    function! s:parser.hooks.pre_validate(options) abort
      if empty(s:parser.get_conflicted_arguments('open', a:options))
        let a:options.open = 1
      endif
    endfunction
    function! s:parser.hooks.post_validate(options) abort
      if has_key(a:options, 'repository')
        let a:options.filename = ''
        unlet a:options.repository
      endif
    endfunction
    call s:parser.hooks.validate()
  endif
  return s:parser
endfunction
function! gita#command#browse#command(...) abort
  let parser  = s:get_parser()
  let options = call(parser.parse, a:000, parser)
  if empty(options)
    return
  endif
  call gita#option#assign_commit(options)
  call gita#option#assign_filename(options)
  call gita#option#assign_selection(options)

  " extend default options
  let options = extend(
        \ deepcopy(g:gita#command#browse#default_options),
        \ options,
        \)
  if get(options, 'yank')
    call gita#command#browse#yank(options)
  elseif get(options, 'echo')
    call gita#command#browse#echo(options)
  else
    call gita#command#browse#open(options)
  endif
endfunction
function! gita#command#browse#complete(...) abort
  let parser = s:get_parser()
  return call(parser.complete, a:000, parser)
endfunction

call gita#util#define_variables('command#browse', {
      \ 'default_options': {},
      \ 'translation_patterns': {
      \   'github.com': [
      \     [
      \       '\vhttps?://(%domain)/(.{-})/(.{-})%(\.git)?$',
      \       '\vgit://(%domain)/(.{-})/(.{-})%(\.git)?$',
      \       '\vgit\@(%domain):(.{-})/(.{-})%(\.git)?$',
      \       '\vssh://git\@(%domain)/(.{-})/(.{-})%(\.git)?$',
      \     ], {
      \       '^':     'https://\1/\2/\3/tree/%c1/',
      \       '_':     'https://\1/\2/\3/blob/%c1/%pt%{#L|}ls%{-L|}le',
      \       'exact': 'https://\1/\2/\3/blob/%r1/%pt%{#L|}ls%{-L|}le',
      \       'blame': 'https://\1/\2/\3/blame/%c1/%pt%{#L|}ls%{-L|}le',
      \     },
      \   ],
      \   'bitbucket.org': [
      \     [
      \       '\vhttps?://(%domain)/(.{-})/(.{-})%(\.git)?$',
      \       '\vgit://(%domain)/(.{-})/(.{-})%(\.git)?$',
      \       '\vgit\@(%domain):(.{-})/(.{-})%(\.git)?$',
      \       '\vssh://git\@(%domain)/(.{-})/(.{-})%(\.git)?$',
      \     ], {
      \       '^':     'https://\1/\2/\3/branch/%c1/',
      \       '_':     'https://\1/\2/\3/src/%c1/%pt%{#cl-|}ls',
      \       'exact': 'https://\1/\2/\3/src/%r1/%pt%{#cl-|}ls',
      \       'blame': 'https://\1/\2/\3/annotate/%c1/%pt',
      \       'diff':  'https://\1/\2/\3/diff/%pt?diff1=%c1&diff2=%c2',
      \     },
      \   ],
      \ },
      \ 'extra_translation_patterns': {},
      \})
