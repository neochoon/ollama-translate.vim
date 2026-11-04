# ollama-translate.vim

Vim plugin that sends the current buffer's full text to a local Ollama
instance for translation and shows the result in a new split buffer.

## Requirements

- Vim 8+ (uses `job_start`/`timer_start`)
- `curl` on your `$PATH`
- A locally running [Ollama](https://ollama.com) server with a model pulled,
  e.g.:
  ```bash
  ollama pull llama3.1
  ollama serve
  ```

## Setup

Install with your plugin manager of choice, e.g. with
[vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'neochoon/ollama-translate.vim'
```

Optionally override the defaults in your `vimrc`:

```vim
let g:ollama_translate_host = 'http://localhost:11434'
let g:ollama_translate_model = 'llama3.1'
let g:ollama_translate_target_lang = 'ko'
let g:ollama_translate_timeout_ms = 60000
```

## Usage

Press `<leader>tr` (or run `:OllamaTranslate`) in any buffer. The whole
buffer is sent to Ollama for translation; the result opens in a new
vertical split scratch buffer. Save it yourself with `:w` if you want to
keep it as a file.

On failure (Ollama not running, timeout, unexpected response), an error is
shown on the status line and no split is opened.

Note: the entire buffer is sent as-is to the configured
`g:ollama_translate_host` — only point this at a host you trust.

## Development

Run the test suite (fetches vader.vim on first run):

```bash
make test
```
