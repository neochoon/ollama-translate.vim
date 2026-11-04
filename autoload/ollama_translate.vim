function! ollama_translate#BuildRequest(text, target_lang, model) abort
  let prompt = 'Translate the following text into ' . a:target_lang
        \ . ". Output only the translated text, with no explanations"
        \ . " and no markdown code fences.\n\n" . a:text
  let payload = {
        \ 'model': a:model,
        \ 'prompt': prompt,
        \ 'stream': v:false,
        \ }
  return json_encode(payload)
endfunction

function! ollama_translate#ParseResponse(json_str) abort
  try
    let decoded = json_decode(a:json_str)
  catch
    return {'ok': 0, 'error': 'Failed to parse Ollama response: ' . v:exception}
  endtry

  if type(decoded) != v:t_dict
        \ || !has_key(decoded, 'response')
        \ || type(decoded.response) != v:t_string
    return {'ok': 0, 'error': 'Unexpected response format from Ollama'}
  endif

  return {'ok': 1, 'text': decoded.response}
endfunction

function! ollama_translate#BuildCurlArgv(host, payload) abort
  return ['curl', '-sS', '-f', '-X', 'POST', a:host . '/api/generate', '-d', a:payload]
endfunction

let s:job_output = []
let s:timer = -1
let s:active_job = v:null
let s:timed_out = 0

function! ollama_translate#Translate() abort
  if s:active_job != v:null && job_status(s:active_job) ==# 'run'
    echo 'Ollama translate: a translation is already in progress'
    return
  endif

  let text = join(getline(1, '$'), "\n")
  let target_lang = get(g:, 'ollama_translate_target_lang', 'ko')
  let model = get(g:, 'ollama_translate_model', 'llama3.1')
  let host = get(g:, 'ollama_translate_host', 'http://localhost:11434')
  let timeout_ms = get(g:, 'ollama_translate_timeout_ms', 60000)

  let payload = ollama_translate#BuildRequest(text, target_lang, model)
  let argv = ollama_translate#BuildCurlArgv(host, payload)

  let s:job_output = []
  let s:timed_out = 0
  echo 'Translating via Ollama...'

  let job = job_start(argv, {
        \ 'out_cb': function('s:OnOllamaOut'),
        \ 'close_cb': function('s:OnOllamaClose'),
        \ })
  let s:active_job = job
  let s:timer = timer_start(timeout_ms, function('s:OnOllamaTimeout', [job]))
endfunction

function! s:OnOllamaOut(channel, msg) abort
  call add(s:job_output, a:msg)
endfunction

function! s:OnOllamaTimeout(job, timer) abort
  if job_status(a:job) ==# 'run'
    let s:timed_out = 1
    call job_stop(a:job)
    echoerr 'Ollama translate: timed out waiting for a response'
  endif
endfunction

function! s:OnOllamaClose(channel) abort
  call timer_stop(s:timer)

  if s:timed_out
    let s:timed_out = 0
    return
  endif

  let job = ch_getjob(a:channel)
  call job_status(job)
  let status = job_info(job).exitval

  if status != 0
    echoerr 'Ollama translate: request failed (curl exit code ' . status . ')'
    return
  endif

  let result = ollama_translate#ParseResponse(join(s:job_output, "\n"))
  if !result.ok
    echoerr 'Ollama translate: ' . result.error
    return
  endif

  call s:ShowTranslation(result.text)
endfunction

function! s:ShowTranslation(text) abort
  vnew
  setlocal buftype=nofile bufhidden=wipe noswapfile
  call setline(1, split(a:text, "\n"))
  normal! gg
endfunction
