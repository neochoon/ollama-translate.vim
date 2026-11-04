# ollama-translate.vim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Vim plugin where pressing `<leader>tr` sends the current buffer's full text to a local Ollama instance for translation and shows the result in a new split buffer.

**Architecture:** `plugin/ollama-translate.vim` is a thin entry point that registers the `:OllamaTranslate` command and `<leader>tr` mapping. `autoload/ollama_translate.vim` holds the logic, split into pure functions (`BuildRequest`, `ParseResponse`, `BuildCurlArgv` — no I/O, unit-tested with vader.vim) and a thin `Translate()` orchestration function that shells out to `curl` via `job_start`/`timer_start` and is verified manually against a real local Ollama instance.

**Tech Stack:** Vimscript (Vim 8+), `curl` (shelled out via `job_start`), vader.vim for tests, Ollama's `/api/generate` HTTP endpoint.

## Global Constraints

- Target editor: Vim only (Vim 8+, uses `job_start`/`timer_start`). No Neovim-specific code.
- The call to Ollama must be asynchronous — Vim must not block while waiting for a response.
- Entire buffer content is sent as-is (`join(getline(1, '$'), "\n")`), regardless of filetype. No chunking.
- Target language, model, host, and timeout are fixed settings (`g:ollama_translate_*`), not chosen per invocation. No `:Translate <lang>` command and no interactive language prompt in this iteration.
- No retry logic. Any failure (connection error, non-zero curl exit, timeout, malformed response) results in an `echoerr` to the status line and nothing else.
- Translation result opens in a new scratch vertical-split buffer (`buftype=nofile`). The plugin never writes to disk automatically.
- Test framework: vader.vim, run headless. Only the pure functions (`BuildRequest`, `ParseResponse`, `BuildCurlArgv`) and the `plugin/` registration are covered by automated vader tests, per the spec's explicit testing scope — the `job_start`/network orchestration in `Translate()` is verified manually against a real local Ollama instance, not by vader.
- Config defaults (exact values, from spec):
  - `g:ollama_translate_host` = `'http://localhost:11434'`
  - `g:ollama_translate_model` = `'llama3.1'`
  - `g:ollama_translate_target_lang` = `'ko'`
  - `g:ollama_translate_timeout_ms` = `60000`
- Default mapping: `<leader>tr` → `:OllamaTranslate`.

---

## Task 1: Vader test harness

**Files:**
- Create: `Makefile`
- Modify: `.gitignore` (add `.vader-vim/`)
- Create: `tests/smoke.vader`

**Interfaces:**
- Produces: a `make test` target that any later task's vader tests run under. Later tasks assume `tests/*.vader` files are picked up automatically by this target.

- [ ] **Step 1: Write the Makefile**

Create `Makefile`:

```makefile
VADER_DIR := .vader-vim
VADER_URL := https://github.com/junegunn/vader.vim

.PHONY: test
test:
	@if [ ! -d $(VADER_DIR) ]; then \
		git clone --depth 1 $(VADER_URL) $(VADER_DIR); \
	fi
	vim -Nu NONE -c "set rtp+=$(VADER_DIR)" -c "set rtp+=." \
		-c "filetype plugin on" \
		-c "Vader! tests/*.vader"
```

- [ ] **Step 2: Add `.vader-vim/` to `.gitignore`**

Append to `.gitignore`:

```
.vader-vim/
```

- [ ] **Step 3: Write a smoke test to verify the harness itself**

Create `tests/smoke.vader`:

```vader
Execute (sanity check: vader itself runs):
  AssertEqual 1 + 1, 2
```

- [ ] **Step 4: Run it to verify the harness works end-to-end**

Run: `make test`
Expected output ends with something like:
```
Vader: Starting Vader: tests/smoke.vader
Vader: Success/Total: 1/1
```
(exit code 0; `.vader-vim/` directory is created on first run)

- [ ] **Step 5: Commit**

```bash
git add Makefile .gitignore tests/smoke.vader
git commit -m "test: add vader.vim test harness"
```

---

## Task 2: `BuildRequest()` pure function

**Files:**
- Create: `autoload/ollama_translate.vim`
- Test: `tests/build_request.vader`

**Interfaces:**
- Produces: `ollama_translate#BuildRequest(text, target_lang, model)` — takes 3 strings, returns a JSON string suitable for `curl -d`. Later tasks (`ParseResponse`, `Translate`) do not depend on this function's internals, only that it returns a valid JSON string containing `model`, `prompt`, and `"stream":false`.

- [ ] **Step 1: Write the failing test**

Create `tests/build_request.vader`:

```vader
Execute (BuildRequest: includes model and stream:false):
  let g:result = ollama_translate#BuildRequest('hello', 'ko', 'llama3.1')
  let g:decoded = json_decode(g:result)

Then:
  AssertEqual 'llama3.1', g:decoded.model
  AssertEqual v:false, g:decoded.stream

Execute (BuildRequest: prompt mentions target language and contains the source text):
  let g:result = ollama_translate#BuildRequest('hello world', 'ko', 'llama3.1')
  let g:decoded = json_decode(g:result)

Then:
  AssertEqual 1, g:decoded.prompt =~# 'ko'
  AssertEqual 1, g:decoded.prompt =~# 'hello world'

Execute (BuildRequest: preserves newlines in multi-line source text):
  let g:result = ollama_translate#BuildRequest("line one\nline two", 'ko', 'llama3.1')
  let g:decoded = json_decode(g:result)

Then:
  AssertEqual 1, g:decoded.prompt =~# "line one\nline two"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `tests/build_request.vader` reports an error like `Unknown function: ollama_translate#BuildRequest` (autoload file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `autoload/ollama_translate.vim`:

```vim
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `Vader: Success/Total: 3/3` for `tests/build_request.vader` (plus the smoke test still passing).

- [ ] **Step 5: Commit**

```bash
git add autoload/ollama_translate.vim tests/build_request.vader
git commit -m "feat: add BuildRequest pure function"
```

---

## Task 3: `ParseResponse()` pure function

**Files:**
- Modify: `autoload/ollama_translate.vim`
- Test: `tests/parse_response.vader`

**Interfaces:**
- Consumes: nothing from Task 2.
- Produces: `ollama_translate#ParseResponse(json_str)` — takes a JSON string, returns a dict: `{'ok': 1, 'text': <string>}` on success, or `{'ok': 0, 'error': <string>}` on failure (malformed JSON, or JSON missing/mistyped `response` field). Task 5 (`Translate()`) relies on exactly this `{ok, text}` / `{ok, error}` shape.

- [ ] **Step 1: Write the failing test**

Create `tests/parse_response.vader`:

```vader
Execute (ParseResponse: extracts text from a well-formed Ollama response):
  let g:result = ollama_translate#ParseResponse('{"response": "안녕하세요", "done": true}')

Then:
  AssertEqual 1, g:result.ok
  AssertEqual '안녕하세요', g:result.text

Execute (ParseResponse: returns ok=0 on malformed JSON):
  let g:result = ollama_translate#ParseResponse('not valid json {{{')

Then:
  AssertEqual 0, g:result.ok
  AssertEqual 1, has_key(g:result, 'error')

Execute (ParseResponse: returns ok=0 when "response" field is missing):
  let g:result = ollama_translate#ParseResponse('{"done": true}')

Then:
  AssertEqual 0, g:result.ok
  AssertEqual 1, has_key(g:result, 'error')

Execute (ParseResponse: returns ok=0 when "response" field is not a string):
  let g:result = ollama_translate#ParseResponse('{"response": 123}')

Then:
  AssertEqual 0, g:result.ok
  AssertEqual 1, has_key(g:result, 'error')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `Unknown function: ollama_translate#ParseResponse`.

- [ ] **Step 3: Write minimal implementation**

Append to `autoload/ollama_translate.vim`:

```vim
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `Vader: Success/Total: 4/4` for `tests/parse_response.vader` (plus all previously passing tests still passing).

- [ ] **Step 5: Commit**

```bash
git add autoload/ollama_translate.vim tests/parse_response.vader
git commit -m "feat: add ParseResponse pure function"
```

---

## Task 4: `BuildCurlArgv()` pure function

**Files:**
- Modify: `autoload/ollama_translate.vim`
- Test: `tests/build_curl_argv.vader`

**Interfaces:**
- Consumes: nothing from Tasks 2–3 directly (takes a host string and a pre-built payload string).
- Produces: `ollama_translate#BuildCurlArgv(host, payload)` — returns a `List` of strings suitable for `job_start()`. Task 5 relies on this exact argv shape: `['curl', '-sS', '-f', '-X', 'POST', <host> . '/api/generate', '-d', <payload>]`.

- [ ] **Step 1: Write the failing test**

Create `tests/build_curl_argv.vader`:

```vader
Execute (BuildCurlArgv: builds the expected curl argv):
  let g:result = ollama_translate#BuildCurlArgv('http://localhost:11434', '{"a":1}')

Then:
  AssertEqual ['curl', '-sS', '-f', '-X', 'POST',
        \ 'http://localhost:11434/api/generate', '-d', '{"a":1}'], g:result
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `Unknown function: ollama_translate#BuildCurlArgv`.

- [ ] **Step 3: Write minimal implementation**

Append to `autoload/ollama_translate.vim`:

```vim
function! ollama_translate#BuildCurlArgv(host, payload) abort
  return ['curl', '-sS', '-f', '-X', 'POST', a:host . '/api/generate', '-d', a:payload]
endfunction
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `Vader: Success/Total: 1/1` for `tests/build_curl_argv.vader` (plus all previously passing tests still passing).

- [ ] **Step 5: Commit**

```bash
git add autoload/ollama_translate.vim tests/build_curl_argv.vader
git commit -m "feat: add BuildCurlArgv pure function"
```

---

## Task 5: `Translate()` async orchestration

**Files:**
- Modify: `autoload/ollama_translate.vim`

**Interfaces:**
- Consumes: `ollama_translate#BuildRequest(text, target_lang, model)` (Task 2), `ollama_translate#ParseResponse(json_str)` (Task 3), `ollama_translate#BuildCurlArgv(host, payload)` (Task 4).
- Produces: `ollama_translate#Translate()` — no arguments, no return value. Task 6's `:OllamaTranslate` command calls exactly this function.

This task is **not covered by vader tests** — per the spec, `job_start`/network behavior is verified manually against a real local Ollama instance, not unit tested. There's no test step here; verification is the manual check in Step 2.

- [ ] **Step 1: Implement `Translate()` and its job callbacks**

Append to `autoload/ollama_translate.vim`:

```vim
let s:job_output = []
let s:timer = -1

function! ollama_translate#Translate() abort
  let text = join(getline(1, '$'), "\n")
  let target_lang = get(g:, 'ollama_translate_target_lang', 'ko')
  let model = get(g:, 'ollama_translate_model', 'llama3.1')
  let host = get(g:, 'ollama_translate_host', 'http://localhost:11434')
  let timeout_ms = get(g:, 'ollama_translate_timeout_ms', 60000)

  let payload = ollama_translate#BuildRequest(text, target_lang, model)
  let argv = ollama_translate#BuildCurlArgv(host, payload)

  let s:job_output = []
  echo 'Translating via Ollama...'

  let job = job_start(argv, {
        \ 'out_cb': function('s:OnOllamaOut'),
        \ 'exit_cb': function('s:OnOllamaExit'),
        \ })
  let s:timer = timer_start(timeout_ms, function('s:OnOllamaTimeout', [job]))
endfunction

function! s:OnOllamaOut(channel, msg) abort
  call add(s:job_output, a:msg)
endfunction

function! s:OnOllamaTimeout(job, timer) abort
  if job_status(a:job) ==# 'run'
    call job_stop(a:job)
    echoerr 'Ollama translate: timed out waiting for a response'
  endif
endfunction

function! s:OnOllamaExit(job, status) abort
  call timer_stop(s:timer)

  if a:status != 0
    echoerr 'Ollama translate: request failed (curl exit code ' . a:status . ')'
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
```

- [ ] **Step 2: Manually verify against a real local Ollama instance**

Prerequisite: Ollama running locally with the default model pulled:
```bash
ollama pull llama3.1
ollama serve &
```

Then in Vim:
```
:source autoload/ollama_translate.vim
:call ollama_translate#Translate()
```
Expected: status line shows "Translating via Ollama...", then after a delay a new vertical split opens containing a Korean translation of the current buffer's text.

Then verify the failure path — stop Ollama (`kill %1` or stop the `ollama serve` process) and repeat `:call ollama_translate#Translate()`.
Expected: an `echoerr` appears in the status line (e.g. "Ollama translate: request failed (curl exit code ...)"), and no split buffer opens.

- [ ] **Step 3: Commit**

```bash
git add autoload/ollama_translate.vim
git commit -m "feat: add async Translate orchestration via job_start"
```

---

## Task 6: `plugin/` entry point — command and mapping

**Files:**
- Create: `plugin/ollama-translate.vim`
- Test: `tests/plugin_entry.vader`

**Interfaces:**
- Consumes: `ollama_translate#Translate()` (Task 5).
- Produces: the `:OllamaTranslate` command and the `<Plug>(ollama-translate)` / `<leader>tr` mapping. Nothing later depends on this beyond the command/mapping names themselves.

- [ ] **Step 1: Write the failing test**

Create `tests/plugin_entry.vader`:

```vader
Before:
  if exists('g:loaded_ollama_translate')
    unlet g:loaded_ollama_translate
  endif
  silent! nunmap <leader>tr
  silent! nunmap <Plug>(ollama-translate)

Execute (plugin registers the :OllamaTranslate command):
  source plugin/ollama-translate.vim

Then:
  AssertEqual 2, exists(':OllamaTranslate')

Execute (plugin maps <leader>tr to the <Plug> mapping by default):
  source plugin/ollama-translate.vim

Then:
  AssertEqual 1, maparg('<leader>tr', 'n') =~# 'ollama-translate'

Execute (sourcing the plugin twice is a no-op the second time):
  source plugin/ollama-translate.vim
  let g:loaded_ollama_translate_before = g:loaded_ollama_translate
  source plugin/ollama-translate.vim

Then:
  AssertEqual g:loaded_ollama_translate_before, g:loaded_ollama_translate
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test`
Expected: FAIL — `tests/plugin_entry.vader` errors because `plugin/ollama-translate.vim` does not exist (`E484: Can't open file`).

- [ ] **Step 3: Write minimal implementation**

Create `plugin/ollama-translate.vim`:

```vim
if exists('g:loaded_ollama_translate')
  finish
endif
let g:loaded_ollama_translate = 1

command! OllamaTranslate call ollama_translate#Translate()

nnoremap <silent> <Plug>(ollama-translate) :OllamaTranslate<CR>

if !hasmapto('<Plug>(ollama-translate)') && maparg('<leader>tr', 'n') ==# ''
  nmap <unique> <leader>tr <Plug>(ollama-translate)
endif
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test`
Expected: `Vader: Success/Total: 3/3` for `tests/plugin_entry.vader` (plus all previously passing tests still passing — full suite green).

- [ ] **Step 5: Commit**

```bash
git add plugin/ollama-translate.vim tests/plugin_entry.vader
git commit -m "feat: register :OllamaTranslate command and <leader>tr mapping"
```

---

## Task 7: README and docs sync

**Files:**
- Modify: `README.md`

**Interfaces:**
- None (documentation only).

- [ ] **Step 1: Replace the `Setup` and `Usage` placeholders**

Replace the full contents of `README.md` with:

```markdown
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

## Development

Run the test suite (fetches vader.vim on first run):

```bash
make test
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document setup and usage for ollama-translate.vim"
```
