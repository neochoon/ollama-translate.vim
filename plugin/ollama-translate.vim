if exists('g:loaded_ollama_translate')
  finish
endif
let g:loaded_ollama_translate = 1

command! OllamaTranslate call ollama_translate#Translate()

nnoremap <silent> <Plug>(ollama-translate) :OllamaTranslate<CR>

if !hasmapto('<Plug>(ollama-translate)') && maparg('<leader>tr', 'n') ==# ''
  nmap <unique> <leader>tr <Plug>(ollama-translate)
endif
