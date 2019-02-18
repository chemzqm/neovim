" Common functions for providers

" Start the provider and perform a 'poll' request
"
" Returns a valid channel on success
function! provider#Poll(argv, orig_name, log_env) abort
  let job = {'rpc': v:true, 'stderr_buffered': v:true, 'on_stderr': funcref('s:OnError')}
  try
    let channel_id = jobstart(a:argv, job)
    if channel_id > 0
      return channel_id
    endif
  catch
    echomsg v:throwpoint
    echomsg v:exception
  endtry
  throw remote#host#LoadErrorForHost(a:orig_name, a:log_env)
endfunction

function! s:OnError(id, data, event)
  if !empty(a:data)
    echohl Error
    for row in a:data
      echomsg row
    endfor
    echohl None
  endif
endfunction
