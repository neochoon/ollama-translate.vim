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
