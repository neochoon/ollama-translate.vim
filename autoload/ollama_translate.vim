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
