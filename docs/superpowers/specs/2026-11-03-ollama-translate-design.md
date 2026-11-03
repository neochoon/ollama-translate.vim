# ollama-translate.vim — Design

**Issue:** [#1](https://github.com/neochoon/ollama-translate.vim/issues/1)

## Purpose

A Vim plugin that lets the user press a keybinding to send the entire
current buffer to a locally running [Ollama](https://ollama.com) instance
for translation, and view the translated text in a new split buffer.

## Scope

- Target editor: **Vim only** (not Neovim). Uses Vim 8+ `job_start` /
  `timer_start` for async job control.
- Translates the **entire buffer content as-is**, regardless of filetype.
  No special handling for code vs. prose, no chunking.
- Call is **asynchronous** — Vim must not freeze while waiting for Ollama.
- Target language is a **fixed setting**, not chosen per-invocation. No
  interactive language prompt and no `:Translate <lang>` command in this
  iteration.
- No retry logic. On any failure, show an error in the status line and stop.

## Architecture

```
plugin/ollama-translate.vim     " command/mapping registration, entry point
autoload/ollama_translate.vim   " core logic: pure functions + job orchestration
tests/*.vader                   " vader.vim tests
```

- `plugin/ollama-translate.vim` is a thin wrapper loaded at startup. It
  defines the `<leader>tr` mapping and the `:OllamaTranslate` command, both
  of which just call into `autoload/ollama_translate.vim`.
- `autoload/ollama_translate.vim` holds the real logic, split into:
  - **Pure functions** (`BuildRequest()`, `ParseResponse()`) — no I/O,
    fully unit-testable with vader.vim.
  - **I/O orchestration** (`job_start` call, timer-based timeout, exit
    callback) — a thin glue layer, not unit tested; verified manually
    against a real local Ollama instance.

## Data Flow

1. User presses `<leader>tr` → mapping calls `ollama_translate#Translate()`.
2. Read the whole buffer with `getline(1, '$')` (a list of lines) and join
   with `"\n"` explicitly (`join(lines, "\n")`) to preserve newlines before
   building the request. (Joining without an explicit `"\n"` separator
   would silently drop line breaks.)
3. `ollama_translate#BuildRequest(text, target_lang, model)` — pure
   function — builds the JSON payload for Ollama's `/api/generate`
   endpoint:
   - Prompt instructs the model to translate the given text into
     `target_lang`, output only the translated text, and add no
     explanations or markdown code fences.
   - `"stream": false`, so the full response arrives in one JSON blob.
   - Uses `json_encode()`, which escapes embedded newlines/quotes safely.
4. Start the HTTP call via `job_start(['curl', '-s', host .. '/api/generate',
   '-d', json_payload])`. Show a status message ("Translating via
   Ollama...") immediately.
5. Start a `timer_start(timeout_ms, ...)` alongside the job. If the timer
   fires before the job exits, call `job_stop()` and report a timeout error.
6. On job exit: pass the collected stdout (JSON) to
   `ollama_translate#ParseResponse(json)` — pure function — which extracts
   the translated text, or returns an error indicator (e.g. `v:null` /
   an error dict) if the JSON is malformed or missing the expected field.
7. **On success:** open a new scratch buffer in a vertical split
   (`buftype=nofile`) and fill it with the translated text. The user saves
   it manually with `:w` if they want a file — the plugin does not write to
   disk automatically.
8. **On failure** (non-zero curl exit, connection error, parse failure, or
   timeout): `echoerr` the error message to the status line. No buffer is
   opened. No retry.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `g:ollama_translate_host` | `'http://localhost:11434'` | Ollama server endpoint |
| `g:ollama_translate_model` | `'llama3.1'` | Model name to use |
| `g:ollama_translate_target_lang` | `'ko'` | Target translation language |
| `g:ollama_translate_timeout_ms` | `60000` | Response timeout in milliseconds |

All overridable in the user's `vimrc`. Default mapping: `<leader>tr` →
`:OllamaTranslate`.

## Testing

- Introduce **vader.vim** as the test framework (`tests/*.vader`), run
  headless: `vim -Nu NONE -c "Vader! tests/*.vader"`.
- TDD focuses on the two pure functions:
  - `BuildRequest()`: given text/language/model, produces the correct JSON
    payload string; explicitly covers newline preservation from the
    buffer-join step.
  - `ParseResponse()`: given a well-formed Ollama JSON response, extracts
    the translated text; given malformed/unexpected JSON, returns an error
    indicator rather than throwing.
- `job_start` / real network interaction is **not** covered by vader tests
  (would require a real or mocked Ollama server); verified manually with a
  locally running Ollama instance instead.

## Out of Scope (this iteration)

- Neovim support
- Per-invocation language selection (`:Translate <lang>`, language prompt)
- Chunking/handling very large buffers specially
- Retry on failure
- Automatically writing the translated buffer to a file
