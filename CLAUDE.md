# ollama-translate.vim

Vim plugin that sends the current buffer's full text to a local Ollama
instance for translation and shows the result in a new split buffer.

## Stack
- Language: Vimscript (Vim 8+, `job_start`/`timer_start` for async)
- Test framework: vader.vim (`tests/*.vader`)
- External dependency: `curl` (shells out to call Ollama's HTTP API),
  a locally running Ollama server

## Layout
- `plugin/ollama-translate.vim` — commands/mappings, thin entry point
- `autoload/ollama_translate.vim` — core logic; pure functions
  (`BuildRequest`, `ParseResponse`) are kept separate from I/O
  (`job_start` orchestration) so the former can be unit tested with vader
- `tests/` — vader.vim test files

## Design docs
Specs and plans live under `docs/superpowers/specs/` and
`docs/superpowers/plans/` per the global workflow (see `~/.claude/CLAUDE.md`).
