" The Python provider helper
if exists('s:loaded_pythonx_provider')
  finish
endif

let s:loaded_pythonx_provider = 1

let s:stderr = {}
let s:job_opts = {'rpc': v:true}
let s:job_chan_ids = []

" TODO(bfredl): this logic is common and should be builtin
function! s:job_opts.on_stderr(chan_id, data, event)
  let stderr = get(s:stderr, a:chan_id, [''])
  let last = remove(stderr, -1)
  let a:data[0] = last.a:data[0]
  call extend(stderr, a:data)
  let s:stderr[a:chan_id] = stderr
endfunction

function! s:job_opts.on_exit(chan_id, data, event)
  call filter(s:job_chan_ids, 'v:val !=# '.a:chan_id)
endfunction

function! provider#pythonx#Require(host) abort
  let ver = (a:host.orig_name ==# 'python') ? 2 : 3

  " Python host arguments
  let prog = (ver == '2' ?  provider#python#Prog() : provider#python3#Prog())
  let args = [prog, '-c', 'import sys; sys.path.remove(""); import neovim; neovim.start_host()']

  " Collect registered Python plugins into args
  let python_plugins = remote#host#PluginsForHost(a:host.name)
  for plugin in python_plugins
    call add(args, plugin.path)
  endfor

  try
    let channel_id = jobstart(args, s:job_opts)
    let s:job_chan_ids += [channel_id]
    call timer_start(0, function('s:checkStatus', [channel_id, a:host.orig_name]))
    return channel_id
  catch
    echomsg v:throwpoint
    echomsg v:exception
    call s:echoErrMessage(channel_id)
  endtry
  throw remote#host#LoadErrorForHost(a:host.orig_name,
        \ '$NVIM_PYTHON_LOG_FILE')
endfunction

function! s:echoErrMessage(channel_id)
  for row in get(s:stderr, a:channel_id, [])
    echomsg row
  endfor
endfunction

function! s:checkStatus(channel_id, host_name, id)
  " not check if job exit
  if index(s:job_chan_ids, a:channel_id) == -1 | return | endif
  let res = jobwait([a:channel_id], 0)[0]
  " It could be invalid because UpdateRemotePlugin would close this channel
  if res == -3 | return s:echoErrMessage(a:channel_id) | endif
  if res == -1 && rpcrequest(a:channel_id, 'poll') ==# 'ok'
    return
  endif

  call s:echoErrMessage(a:channel_id)
  throw remote#host#LoadErrorForHost(a:host_name,
        \ '$NVIM_PYTHON_LOG_FILE')
endfunction

function! provider#pythonx#Detect(major_ver) abort
  if a:major_ver == 2
    if exists('g:python_host_prog')
      return [g:python_host_prog, '']
    else
      let progs = ['python2', 'python2.7', 'python2.6', 'python']
    endif
  else
    if exists('g:python3_host_prog')
      return [g:python3_host_prog, '']
    else
      let progs = ['python3', 'python3.5', 'python3.4', 'python3.3', 'python']
    endif
  endif

  let errors = []

  for prog in progs
    let [result, err] = s:check_interpreter(prog, a:major_ver)
    if result
      return [prog, err]
    endif
    " Accumulate errors in case we don't find
    " any suitable Python interpreter.
    call add(errors, err)
  endfor

  " No suitable Python interpreter found.
  return ['', 'provider/pythonx: Could not load Python ' . a:major_ver
        \ . ":\n" .  join(errors, "\n")]
endfunction

function! s:check_interpreter(prog, major_ver) abort
  let prog_path = exepath(a:prog)
  if prog_path ==# ''
    return [0, a:prog . ' not found in search path or not executable.']
  endif

  let min_version = (a:major_ver == 2) ? '2.6' : '3.3'

  " Try to load neovim module, and output Python version.
  " Return codes:
  "   0  Neovim module can be loaded.
  "   2  Neovim module cannot be loaded.
  "   Otherwise something else went wrong (e.g. 1 or 127).
  let prog_ver = system([ a:prog , '-c' ,
        \ 'import sys; ' .
        \ 'sys.path.remove(""); ' .
        \ 'sys.stdout.write(str(sys.version_info[0]) + "." + str(sys.version_info[1])); ' .
        \ 'import pkgutil; ' .
        \ 'exit(2*int(pkgutil.get_loader("neovim") is None))'
        \ ])

  if v:shell_error == 2 || v:shell_error == 0
    " Check version only for expected return codes.
    if prog_ver !~ '^' . a:major_ver
      return [0, prog_path . ' is Python ' . prog_ver . ' and cannot provide Python '
            \ . a:major_ver . '.']
    elseif prog_ver =~ '^' . a:major_ver && prog_ver < min_version
      return [0, prog_path . ' is Python ' . prog_ver . ' and cannot provide Python >= '
            \ . min_version . '.']
    endif
  endif

  if v:shell_error == 2
    return [0, prog_path . ' does not have the neovim module installed. '
          \ . 'See ":help provider-python".']
  elseif v:shell_error == 127
    " This can happen with pyenv's shims.
    return [0, prog_path . ' does not exist: ' . prog_ver]
  elseif v:shell_error
    return [0, 'Checking ' . prog_path . ' caused an unknown error. '
          \ . '(' . v:shell_error . ', output: ' . prog_ver . ')'
          \ . ' Please report this at github.com/neovim/neovim.']
  endif

  return [1, '']
endfunction
