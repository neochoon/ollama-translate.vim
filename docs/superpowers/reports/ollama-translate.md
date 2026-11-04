# ollama-translate.vim — Implementation Record

Issue: [#1](https://github.com/neochoon/ollama-translate.vim/issues/1)
Spec: `docs/superpowers/specs/2026-11-03-ollama-translate-design.md`
Plan: `docs/superpowers/plans/2026-11-03-ollama-translate.md`

## Feature digest (catch-up doc)

A Vim-only plugin: pressing `<leader>tr` (or `:OllamaTranslate`) sends the
whole current buffer to a locally running Ollama instance for translation,
asynchronously, and shows the result in a new scratch vertical-split
buffer. Three pure functions (`BuildRequest`, `ParseResponse`,
`BuildCurlArgv`) build and parse the HTTP exchange and are fully
vader.vim-tested; a thin `Translate()` orchestration wires them to
`job_start`/`timer_start`/`close_cb` and is verified manually against a
real local Ollama instance, per the spec's own testing-scope decision (the
async/network path isn't vader-tested by design).

Two rounds of post-implementation fixes were needed on top of the plan's
literal code — both are documented below under Task 5 and the Final Review
entry, since they're exactly the kind of "why" a diff alone doesn't show.

## Running ledger

- Task 1: complete (commits 7600e68..436e94e)
- Task 2: complete (commits 436e94e..d14e8cb)
- Task 3: complete (commits d14e8cb..c04ba1a)
- Task 4: complete (commits c04ba1a..85ab0a8)
- Task 5: complete (commits 85ab0a8..ea81d76, 1 fix round)
- Task 6: complete (commits ea81d76..03c4ab2)
- Task 7: complete (commits 03c4ab2..d70df48)
- Final whole-branch review fixes: commits 2806026 (plan file), 18d0900 (code/README fixes)

## Task 1: Vader test harness

**Intent:** Stand up a `make test` target so every later task can TDD against vader.vim.

**What was built:** `Makefile`, `.gitignore` entry for `.vader-vim/`, `tests/smoke.vader`.

**Key decisions / trade-offs:** None beyond the plan.

**Deviations from the plan:** The plan's exact Makefile (`set rtp+=... ; filetype plugin on ; Vader! ...`) failed with `E492: Not an editor command: Vader!` because `vim -u NONE` doesn't autoload plugins from `runtimepath` the way a normal startup does. Fixed by explicitly `exe 'source' '$(VADER_DIR)/plugin/vader.vim'` and adding `-N` (nocompatible) to the `vim` invocation. Functionally equivalent to the plan's intent, just the loading mechanism had to change.

**Files touched:** `Makefile`, `.gitignore`, `tests/smoke.vader`.

**Follow-ups / known gaps:** None.

## Task 2: `BuildRequest()` pure function

**Intent:** First pure function — build the Ollama `/api/generate` JSON payload.

**What was built:** `autoload/ollama_translate.vim` created with `ollama_translate#BuildRequest(text, target_lang, model)`.

**Key decisions / trade-offs:** None beyond the plan — implemented verbatim.

**Deviations from the plan:** None.

**Files touched:** `autoload/ollama_translate.vim`, `tests/build_request.vader`.

**Follow-ups / known gaps:** None.

## Task 3: `ParseResponse()` pure function

**Intent:** Second pure function — extract translated text or an error from Ollama's JSON response.

**What was built:** `ollama_translate#ParseResponse(json_str)` appended to the same autoload file.

**Key decisions / trade-offs:** None beyond the plan — implemented verbatim.

**Deviations from the plan:** None.

**Files touched:** `autoload/ollama_translate.vim`, `tests/parse_response.vader`.

**Follow-ups / known gaps:** None.

## Task 4: `BuildCurlArgv()` pure function

**Intent:** Third pure function — build the exact `curl` argv for `job_start`.

**What was built:** `ollama_translate#BuildCurlArgv(host, payload)` appended to the same autoload file.

**Key decisions / trade-offs:** None beyond the plan — implemented verbatim.

**Deviations from the plan:** None.

**Files touched:** `autoload/ollama_translate.vim`, `tests/build_curl_argv.vader`.

**Follow-ups / known gaps:** Reviewer noted (Minor, not acted on): the function assumes `host` has no trailing slash. True of the default and of the test, low risk, not fixed.

## Task 5: `Translate()` async orchestration — plus one fix round

**Intent:** Wire the three pure functions together via `job_start`/`timer_start` to actually call Ollama asynchronously and show the result.

**What was built:** `ollama_translate#Translate()` and private helpers, implemented verbatim from the plan initially, manually verified against a real local Ollama instance (model `gemma3:4b` substituted for the unpulled default `llama3.1` during verification only — the code default stayed `llama3.1`).

**Key decisions / trade-offs:** The plan's literal code used `exit_cb` for both status and final processing. A task review (confirmed against Vim's own `channel.txt` docs, not just taken on faith) found this design — mandated by the plan, not an implementer error — had two real bugs, plus a reviewer-found third:
1. **Double error message on timeout:** `job_stop()` after a timeout causes `exit_cb` to fire again with a nonzero status, producing a second "request failed" message after the timeout message.
2. **`exit_cb`/data-drain race:** `exit_cb` only guarantees the process exited, not that all buffered `stdout` reached `out_cb` — risking truncated JSON for large responses.
3. **No re-entrancy guard:** calling `Translate()` again while a job was in flight let two jobs share the same script-local output/timer state.

**Deviations from the plan (fix commit `ea81d76`):** Replaced `exit_cb` entirely with `close_cb` (Vim's docs guarantee `close_cb` fires only after all data has reached `out_cb`, closing #2), read the exit status inside `close_cb` via `ch_getjob()` + `job_status()` + `job_info().exitval` guarded by an `s:timed_out` flag set before `job_stop()` (closing #1, by construction — only one code path ever produces the failure message), and added an `s:active_job` script-local checked at the top of `Translate()` to reject overlapping invocations (closing #3). The fix implementer also caught and corrected a bug in the fix's own first draft: comparing a live `Job` value with the Number `-1` throws `E910` in Vim — fixed by using `v:null` as the sentinel instead. Both the original fix and this correction were independently re-reviewed and verified against real Vim behavior (not just narrative).

**Files touched:** `autoload/ollama_translate.vim` (no new test files — this task has no vader coverage by design, per the spec's testing-scope decision).

**Follow-ups / known gaps:**
- A narrow, unreproduced theoretical race remains: a job's `job_status()` could in principle report non-`'run'` before its `close_cb` has fully fired, which — if ever true — would let an immediately-following `Translate()` call reset shared script-local state out from under the still-pending `close_cb`. The final whole-branch review examined this independently and judged it very low-severity/likely-unreachable interactively; tracked as [issue #2](https://github.com/neochoon/ollama-translate.vim/issues/2) rather than fixed in this branch.
- If `job_start()`'s underlying process fails to even launch, no callback fires at all. On Unix/macOS this does not occur for a missing/bad `curl` (confirmed empirically: both callbacks still fire with the OS's "command not found" exit code). On Windows, Vim's docs suggest this can leave the job in a `'fail'` status with zero callbacks ever firing, i.e. an indefinite "Translating via Ollama..." hang. Addressed in the final-review fix round (see below).

## Task 6: `plugin/` entry point

**Intent:** Register `:OllamaTranslate` and the default `<leader>tr` mapping.

**What was built:** `plugin/ollama-translate.vim` — load guard, command, `<Plug>(ollama-translate)` mapping, conditional default mapping that respects a user's pre-existing `<leader>tr` or `<Plug>` mapping.

**Key decisions / trade-offs:** None beyond the plan — implemented verbatim.

**Deviations from the plan:** None.

**Files touched:** `plugin/ollama-translate.vim`, `tests/plugin_entry.vader`.

**Follow-ups / known gaps:** None.

## Task 7: README and docs sync

**Intent:** Replace README's `TBD` Setup/Usage sections with real documentation.

**What was built:** Full README content (Requirements, Setup, Usage, Development sections), matching the plan verbatim.

**Key decisions / trade-offs:** None.

**Deviations from the plan:** None.

**Files touched:** `README.md`.

**Follow-ups / known gaps:** None (later amended once more — see Final Review Fixes below).

## Final whole-branch review fixes

**Intent:** Address findings from the final, most-capable-model review of the full branch diff (`ed73f9d..d70df48`) before PR.

**What was built/fixed:**
1. **(Important) Windows job-launch-failure guard:** added an `if job_status(job) ==# 'fail'` check immediately after `job_start()` in `Translate()`, reporting an error and returning instead of silently hanging — closes the Task 5 follow-up gap noted above.
2. **(Minor, user-requested) Cleaner error display:** replaced every `echoerr` in the async callbacks with `echohl ErrorMsg | echomsg ... | echohl None`, avoiding Vim's noisy multi-line "Error detected while processing function..." wrapper. This was a deliberate deviation from the plan's literal `echoerr` choice, approved by the user after the reviewer flagged the UX rough edge.
3. **(Minor) Removed a no-op `job_status(job)` call** in `s:OnOllamaClose` that the reviewer confirmed has no effect on `job_info().exitval`'s correctness.
4. **(Minor) One-line security note added to README** noting the buffer is sent as-is to whatever host is configured.

**Key decisions / trade-offs:** The final review also raised two items explicitly deferred rather than fixed:
- The narrow `s:job_output`/`close_cb` timing race from Task 5, tracked as [issue #2](https://github.com/neochoon/ollama-translate.vim/issues/2) rather than fixed here.
- The plan and this implementation record itself were initially missing from the branch (process gap, not a code defect) — fixed by committing `docs/superpowers/plans/2026-11-03-ollama-translate.md` and writing this file, both before the PR.

**Deviations from the plan:** Item 2 above (echoerr → echohl/echomsg) is a user-approved deviation from the plan's Data Flow section, which specified `echoerr`. Documented here per CLAUDE.md's "deviations" requirement.

**Files touched:** `autoload/ollama_translate.vim`, `README.md`, `docs/superpowers/plans/2026-11-03-ollama-translate.md` (newly committed), `docs/superpowers/reports/ollama-translate.md` (this file).
