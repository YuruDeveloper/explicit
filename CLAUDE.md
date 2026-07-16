# CLAUDE.md

## 1. Session Start and Context Budget

At session start, read only `continue.md` in full. Every other document is a searchable store — never read it in full.

| Document | Purpose | Read |
|---|---|---|
| `continue.md` | Current goal, state, verification, open issues, next action | **Full, always first** |
| `design.md` | Approved architecture, decisions, roadmap | Search + relevant sections only |
| `idea.md` | Conceptual framework and rationale | Partial, when direction matters |
| `problem.md` | Gaps vs. target, prioritized P0/P1/P2 | Partial, when prioritizing |
| `report.md` | Subagent audit report | Partial, as historical evidence |
| `history/tasks/` | Archived task records | Search filenames first, then minimal range |

- Full reads of `idea.md`, `design.md`, `problem.md`, `report.md` are prohibited — authority does not justify a full read. Search terms → identify line range → read the minimal range → expand only if unclear → never re-read an unchanged section.
- Authority: `design.md` = goals/design; `continue.md` = status/next task; `idea.md` = what/why; `problem.md` = gaps; code + tests = actual behavior. On conflict, prefer these sources by domain and update the stale document.

### 1.1 Explicit Knowledge Management

- Do not use Claude's automatic memory; in a new session read the repository documents directly.
- Record: working rules/preferences/routing/standards → `CLAUDE.md`; architecture → `design.md`; gaps → `problem.md`; progress and next start → `continue.md`; audits → `report.md` or `agents/.../result.md`.
- Do not create or update `.claude/projects/.../memory`, `MEMORY.md`, or memory files.
- Keep `continue.md` current: update immediately on commits, merges, design decisions, next-start, or run-instruction changes. Never leave docs older than the code.

### 1.2 `continue.md` Size Limit

- Keep under ~2,000 tokens (or 8,000 characters).
- Keep only: current goal, state, verification results, open issues, next actions — no narratives of completed work.
- Before exceeding the cap, move completed/inactive records to `history/tasks/YYYY-MM-DD-task-name.md` (one file per task), leaving only the path and a one-line note.

### 1.3 Context Maintenance

Clean up context at real task boundaries — `investigate → implement/decide → verify → update continue.md + archive → report` — not per single read, command, or fix.

## 2. Status and Problems

`continue.md` is the current source of truth for status. `problem.md` classifies gaps P0/P1/P2. `report.md` is a subagent report — not a current defect list: use it as a regression checklist and historical evidence, and reconfirm from code, tests, and `continue.md`.

## 3. Model Routing

Scores are 1–10; higher Intelligence/Taste is better, higher Cost means cheaper.

| Model | Cost | Int | Taste | Primary Use |
|---|:---:|:---:|:---:|---|
| **fable-5** | 2 | 9 | 9 | Planning, complex reasoning, architecture |
| **opus-48** | 3 | 7 | 8 | Refinement, high-quality modifications |
| **sonnet-5** | 5 | 5 | 7 | Lightweight orchestration, thin-wrapper execution |
| **gpt-5.6-terra** | 7 | 8 | 5 | Bulk/mechanical work, analysis, migrations, computer use |
| **gpt-5.6-sol** | 4 | 9 | 9 | Adversarial review, agent evaluation, advanced refactoring |
| **gpt-5.6-luna** | 10 | 3 | 3 | Simple, deterministic, low-risk tasks |

Priority for production code: **Intelligence > Taste > Cost** (Cost only breaks ties).

- **fable-5** — specs, design decisions, reviewing results; not routine implementation/builds/tests.
- **gpt-5.6-sol** — design/concurrency/structurally risky implementation; plan challenges, patch reviews, agent evaluations.
- **gpt-5.6-terra** — well-specified mechanical implementation, migrations; runtime/browser/computer-use verification.
- **gpt-5.6-luna** — routine verification and simple low-risk tasks.
- UI, user-facing copy, and API/SDK design require Taste ≥ 7.
- If a cheaper model misses the quality bar, rerun with a stronger one without asking. Never use Haiku; use sonnet-5 for wrappers.

### 3.1 gpt-5.6-sol

Senior review/refactoring authority: adversarial review (security, concurrency, edge cases, dropped requirements), agent evaluation (report vs. request + evidence), advanced refactoring (boundaries, ownership, APIs, testability, performance). Do not accept the author's summary — inspect code, diffs, tests, and config directly, and keep reviewer separate from author.

## 4. Thin Wrapper and Agent Invocation

Claude's native interface cannot select GPT models, so every `gpt-5.6-*` task runs through a **sonnet-5 thin wrapper with `codex exec`**.

### 4.1 Wrapper Requirements

The wrapper does mechanical relay only — never the substantive design/implementation/review, which the named GPT model must do. Duties:

1. Convert the request into a self-contained Codex prompt (optionally staged in an input file).
2. Invoke Codex via `scripts/delegate.sh` (bash) or `scripts/delegate.ps1` (PowerShell), never `codex exec` directly.
3. Let the helper record the trail automatically — it writes the prompt verbatim to `input.md`, the raw actions/output to `output.md`, and Codex's final result to `result.md`; the wrapper must not transcribe these itself.
4. Report to the orchestrator only a brief notice and the `result.md` path.

- Standard path: `scripts/delegate.sh <task-slug> <role> <model> [input-file]` (bash) or `scripts/delegate.ps1 [-Force] <task-slug> <role> <model> [input-file]` (PowerShell). Both record `input.md`, invoke `codex exec -m <model> --output-last-message`, preserve `output.md`/`result.md` + exit code, and hold an atomic per-target lock. Contract tests: `scripts/test_delegate.*`.
- Run workers sandboxed (`--sandbox workspace-write`), not with `--dangerously-bypass-approvals-and-sandbox`.
- Without `--output-last-message`, extract Codex's final response into `result.md` without judging, summarizing, or rewriting.
- **Commit ownership:** in a worktree a sandboxed worker cannot `git commit` (index lives under the parent `.git`). The worker changes files only ("Do NOT git commit" in `input.md`); the orchestrator commits, naming the real model and the record path.

### 4.2 `agents/` Records

Structure: `agents/<YYYY-MM-DD>-<NN>-<task-slug>/<NN>-<agent-role>/{input,output,result}.md`. `<NN>` is a two-digit sequence (per-date for tasks, per-task for roles), allocated automatically by the helpers, reusing an existing dir for the same slug/role.

- `input.md` = exact instructions; `output.md` = verbatim action log; `result.md` = final result (changes, verification, decision, risks).
- Handoff: read `result.md` first; read `output.md` only to validate claims, audit, or diagnose failure.
- The helper (`delegate.sh`/`delegate.ps1`) writes the full input/output/result trail — neither the wrapper nor the orchestrator transcribes it by hand.
- Make the real model visible in role names/labels (`terra-implement`, `sol-review`, `luna-verify`). Do not record secrets or unnecessary reasoning.
- Committing the three files is optional per the user's preference — ask first.
- Use `scratchpad/` (repo root, not the system scratchpad) only for information with no audit value.

### 4.3 `output.md` Isolation

Full reads of `output.md` are prohibited — it is a raw log, not knowledge.

- Read `result.md` first. Search `output.md` only for a specific command/error/marker and read a narrow range.
- Never combine/summarize multiple `output.md` at once, or feed a past `output.md` into another agent.
- Exclude from broad searches by default: `rg "term" . -g "!agents/**/output.md" -g "!history/**"`.

### 4.4 Foreground First, Exponential Fallback

Subagents cannot idle-wait (foreground `sleep` is blocked; ending the turn marks the wrapper complete).

1. Run `codex exec` as one **foreground** Bash call with `timeout: 600000`.
2. On timeout, run codex in background and poll for `result.md` with exponentially increasing waits (1, 2, 4, 8… min) via harness-tracked background Bash.
3. If a wrapper exits early while codex runs, attach a harness-tracked watcher on `result.md` instead of respawning.
4. Split tasks expected to exceed 10 minutes into smaller runs.

## 5. Worktree and Parallel Implementation

Parallel implementation agents work in explicit `worktrees/<name>/` under the repo root. A worktree is mandatory for parallel implementation, independent modifications, or meaningful conflict risk — not for short read-only single-agent tasks.

1. Do not rely on hidden `.claude/worktrees/`.
2. The orchestrator creates a dedicated branch/path with `git worktree add` and gives Codex the exact absolute path.
3. State each agent's file/package ownership in its prompt; do not parallelize tasks on the same files.
4. An agent must not modify or revert user changes outside its worktree.
5. Before integration, inspect branch diff, commits, and verification.
6. Resolve conflicts by meaning, not by overwriting one side.
7. After merging, confirm no unmerged changes, then remove the worktree and its temp branch.
8. For long work, use timeout/background execution and poll for `result.md`.

## 6. Optional Independent Review

Optional — used when risk/complexity/uncertainty justifies the cost (security, concurrency, migrations, cross-cutting, public-contract, hard-to-reverse changes). Routine deterministic work needs no separate reviewer.

**Procedure:** restate acceptance criteria + invariants → inspect implementation/tests/config/diff directly → try to falsify with realistic failure and boundary cases → rank findings by severity with file:line → separate confirmed defects / risks / questions / style → approve explicitly if no material defect. Verdict is `approve`, `approve with non-blocking notes`, or `request changes`; every blocking finding needs a concrete remediation path.

**Criteria:** Correctness (request + contracts), Completeness (deliverables, edge cases, migrations), Evidence (code/diffs/checks/tests/runtime), Design Quality (responsibilities, boundaries, complexity), Safety (security, data integrity, compatibility, concurrency, rollback), Communication (changes, verification, limits, residual risk). Explain every material deduction; do not approve on a well-written report alone.

## 7. Verification and Execution

- The fable-5 orchestrator does only the reading/static investigation needed for design decisions.
- Route routine `go test`/`go vet`/`tsc`/migration checks/builds through gpt-5.6-luna; browser/live-runtime/computer-use verification through gpt-5.6-terra.
- Never claim a check passed if it was not run. Distinguish pre-existing failures from new ones. Do not weaken requirements or tests to pass.

## 8. Git, Changes, and Handoff

- Inspect `git status` and the relevant diff first. Treat existing changes as user-owned; do not revert them. No destructive Git commands without approval.
- Make necessary in-scope changes; confirm before unrelated changes or expanded impact. Group related changes into intentional commits.
- Committing `agents/` records and `scratchpad/` is optional per the user's preference — confirm first.
- Update `continue.md` immediately after a commit, merge, design decision, or next-start change.
- Use Korean for UI and docs; prefer kaomoji over emoji. Use `temp/` for drafts shared with the user.
- Final handoff covers: changes, verification results, decisions/assumptions, unverified risks, migration/deploy follow-up, next starting point.

## 9. Pre-Work Checklist

Confirm before starting:

1. **State** — read `continue.md` + Git status in; keep `continue.md` current, consistent, and under cap out.
2. **Delegation** — route per the model table (§3); run every GPT task through a sonnet-5 wrapper that writes its own `agents/.../` records.
3. **Evidence** — inspect actual verification results; never claim an unrun check.
