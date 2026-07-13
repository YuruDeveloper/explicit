# CLAUDE.md

## 1. Session Start and Context Budget

At the beginning of every new session, read only `continue.md` in full. It is a small checkpoint (see 1.2). Every other project document is a searchable knowledge store: never read it in full.

| Document | Purpose | How to Read |
|---|---|---|
| `continue.md` | Current goal, state, verification results, open issues, next action | **Read in full, always first** |
| `design.md` | Approved target architecture, technical decisions, and phased roadmap | Search headers/keywords, read only the relevant sections |
| `idea.md` |  conceptual framework, and rationale for the final goal | Partial read only, when concepts or direction matter |
| `problem.md` | Gaps between the current implementation and the target, prioritized as P0/P1/P2 | Partial read only, when prioritizing |
| `report.md` | Subagent audit report | Partial read only, as historical evidence |
| `history/tasks/` | Archived task records | Never bulk-read; search filenames/titles first, then read only the needed part |

Session start procedure:

```text
Read continue.md
→ Identify the current task's keywords and relevant documents
→ Search those documents by header or keyword
→ Read only the needed sections
→ Confirm actual behavior from code and tests
```

Full-file reads of `idea.md`, `design.md`, `problem.md`, and `report.md` are prohibited. Procedure: (1) search headers, keywords, or exact terms first; (2) identify the relevant section and line range; (3) read the minimal range; (4) expand only if the meaning is unclear; (5) never re-read an unchanged section already read in this session. `design.md` remains the single source of truth for design — authority does not justify full reads.

Document authority and conflict rules:

- `design.md` is the single source of truth for goals and approved design decisions.
- `continue.md` is the source of truth for implementation status and the next task.
- `idea.md` explains what the project is building and why.
- `problem.md` records only the gaps between the current implementation and the approved design.
- Confirm actual behavior from the relevant code, diffs, and verification results.

When documents conflict, use `design.md` for goals and architecture, `continue.md` for implementation status, and code plus tests for actual behavior. Update stale documents when a conflict is found.

### 1.1 Explicit Project Knowledge Management

Do not store project knowledge in Claude's automatic memory or rely on implicit session memory.

- Record persistent working rules, user preferences, model routing, and coding standards in `CLAUDE.md`.
- Record architecture decisions in `design.md`.
- Record current gaps from the target in `problem.md`.
- Record implementation progress and the next starting point in `continue.md`.
- Record independent audits in `report.md` or `agents/.../result.md`. `output.md` is a raw audit log, not project knowledge (see 4.3).
- Do not create or update `.claude/projects/.../memory`, `MEMORY.md`, or individual memory files.
- In a new session, read the repository documents directly instead of assuming automatic memory is correct.

Keep `continue.md` current at all times. Update it immediately when commits, merges, design decisions, the next starting point, or run instructions change. Never end a session with documentation that is older than the code.

### 1.2 `continue.md` Size Limit and `history/tasks/`

`continue.md` is a small checkpoint, not a chronicle.

- Keep it under ~2,000 tokens; if token counting is impractical, use 8,000 characters as a conservative cap.
- Keep only: current goal, current state, verification results, open issues, and next actions.
- Do not accumulate detailed narratives of completed work.
- Before exceeding the cap, move completed or inactive records to `history/tasks/YYYY-MM-DD-task-name.md`, one file per task.
- After moving, leave only the path and a one-line relevance note in `continue.md`.

### 1.3 Context Maintenance at Task-Loop Boundaries

Perform context cleanup at real task boundaries, not per tool call. One task loop is:

```text
Investigate → implement or decide → verify → update continue.md and archive old records → report
```

A single file read, a single command run, or a single error fix does not count as its own loop.

## 2. Current Implementation Status and Problems

Use `continue.md` as the detailed and current source of truth.

### 2.1 How to Use `problem.md` and `report.md`

`problem.md` classifies current gaps as P0, P1, or P2. `report.md` is a report produced by a subagent.

Do not treat `report.md` as a current defect list without verification. Use it as a regression checklist and as evidence for historical claims. Reconfirm the current state from the code, tests, and `continue.md`.

## 3. Model Routing Architecture

All scores use a 1–10 scale. Higher Intelligence and Taste scores are better. A higher Cost score means the model is less expensive to use.

| Model | Cost | Intelligence | Taste | Primary Use Case |
|---|:---:|:---:|:---:|---|
| **fable-5** | 2 | 9 | 9 | High-level planning, complex reasoning, and architecture design |
| **opus-48** | 3 | 7 | 8 | Refinement and high-quality code modifications |
| **sonnet-5** | 5 | 5 | 7 | Lightweight orchestration and thin-wrapper execution |
| **gpt-5.6-terra** | 7 | 8 | 5 | Mechanical bulk work, data analysis, migrations, and computer use |
| **gpt-5.6-sol** | 4 | 9 | 9 | Adversarial review, agent evaluation, and advanced refactoring |
| **gpt-5.6-luna** | 10 | 3 | 3 | Simple, narrow, deterministic, low-risk tasks |
| **grok-4.5** | 8 | 7 | 7 | Self-contained single-shot UI/frontend implementation, low-cost auxiliary parallel work |

For production code, use the strict priority **Intelligence > Taste > Cost**. Cost is only a tie-breaker.

- fable-5 focuses on specifications, design decisions, and reviewing results. It does not perform routine implementation, builds, or tests directly.
- Route design-sensitive, concurrency-sensitive, and structurally risky implementation to gpt-5.6-sol.
- Route well-specified mechanical implementation and migrations to gpt-5.6-terra.
- Route routine verification to gpt-5.6-luna.
- UI, user-facing copy, and API/SDK design require a model with Taste 7 or higher.
- Route runtime, browser, and computer-use verification to gpt-5.6-terra.
- Route independent plan challenges, patch reviews, and agent evaluations to gpt-5.6-sol.
- If a lower-cost model does not meet the quality bar, rerun the task with a more capable model without requesting separate permission.
- Never use Haiku. Use sonnet-5 for lightweight wrappers.
- Use gpt-5.6-luna only for simple, deterministic, low-risk tasks that are easy to verify.
- grok-4.5 runs on a SuperGrok subscription (300–500 text interactions per rolling 24h, fair-use policy on sustained heavy use), so marginal cost is zero within the cap. Prefer it for self-contained, single-turn tasks; do not put it in long multi-turn sessions or always-on pipelines. It reports completion without self-verification, so route verification separately per the existing rules.

### 3.1 Role of gpt-5.6-sol

gpt-5.6-sol is the senior review and refactoring authority.

- **Adversarial Review:** Challenge plans and patches, looking for security issues, concurrency defects, edge cases, and dropped requirements.
- **Agent Evaluation:** Compare another agent's report against the original request and repository evidence.
- **Advanced Refactoring:** Improve package boundaries, ownership, APIs, testability, and performance.

Do not accept the author's summary as fact. Start from the original request and inspect the code, diffs, tests, and configuration directly. Keep the reviewer separate from the author whenever possible.

## 4. Claude Thin Wrapper and Explicit Agent Invocation

Claude's native Workflow/Agent interface cannot directly select GPT models. Therefore, every task assigned to `gpt-5.6-luna`, `gpt-5.6-terra`, or `gpt-5.6-sol` must use a **sonnet-5 thin wrapper with `codex exec`**.

### 4.1 Thin-Wrapper Requirements

The wrapper performs only the following duties:

1. Convert the request into a self-contained Codex prompt.
2. Write the exact prompt to `input.md` in the designated `agents/` directory.
3. Invoke the selected GPT model with `codex exec -m <model>`.
4. Save every Codex action and execution output verbatim to `output.md` in the same directory.
5. Save Codex's final result to `result.md` so the parent agent can read it directly.
6. Send the orchestrator only a brief completion notice and the location of `result.md`.

The wrapper must not perform the actual design, implementation, or review. The GPT model named in the task label must do the substantive work.

Use `scripts/delegate.sh` (bash) or `scripts/delegate.ps1` (Windows PowerShell) as the standard invocation path. Both perform the mechanical wrapper duties deterministically — record `input.md`, invoke `codex exec -m <model> --output-last-message`, preserve `output.md`/`result.md` and the Codex exit code — and additionally guard the audit directory with an atomic per-target lock (stale-owner recovery, orphaned-Codex detection, no double writers):

```bash
scripts/delegate.sh <task-slug> <role> <model> [input-file]
# example
printf '%s\n' "$PROMPT" | scripts/delegate.sh 2026-07-10-task terra-implement gpt-5.6-terra
```

```powershell
scripts/delegate.ps1 [-f|--force|-Force] <task-slug> <role> <model> [input-file]
# examples
$Prompt | pwsh -NoProfile -File scripts/delegate.ps1 2026-07-10-task terra-implement gpt-5.6-terra
pwsh -NoProfile -File scripts/delegate.ps1 2026-07-10-task terra-implement gpt-5.6-terra prompt.md
```

Contract tests for both helpers live in `scripts/test_delegate.sh` and `scripts/test_delegate.ps1`.

Equivalent raw invocation when the helper is unavailable:

```bash
codex exec --sandbox workspace-write \
  -m gpt-5.6-terra \
  --output-last-message agents/2026-07-10-01-task/01-terra-implement/result.md \
  - < agents/2026-07-10-01-task/01-terra-implement/input.md \
  > agents/2026-07-10-01-task/01-terra-implement/output.md
```

Run workers sandboxed (`--sandbox workspace-write`) rather than with `--dangerously-bypass-approvals-and-sandbox`; orchestrator approval gates commonly block the latter.

If the environment does not support `--output-last-message`, the wrapper must separately extract Codex's final response into `result.md` without adding judgment, summarizing it, or rewriting it.

**Commit ownership under sandboxing.** In a `git worktree`, the Git index lives under the parent repository's `.git` directory, so a sandboxed worker cannot run `git add`/`git commit` there. Therefore:

- The worker changes files only; state "Do NOT git commit (the orchestrator commits)" in its `input.md`.
- The orchestrator makes the commit, naming the actual working model and the `agents/<date>-<NN>-<task>/<NN>-<role>/` record path in the commit message so the audit trail is preserved.

### 4.2 Required `agents/` Records

Record every delegated task under the repository root using this structure:

```text
agents/<YYYY-MM-DD>-<NN>-<task-slug>/<NN>-<agent-role>/
  input.md
  output.md
  result.md
```

`<NN>` is a two-digit sequence number: per-date for task directories and per-task for role directories. `scripts/delegate.sh` and `scripts/delegate.ps1` allocate it automatically (max existing + 1) and reuse an existing directory when the same slug/role already exists for that date/task.

Example:

```text
agents/2026-07-10-01-stage0-sample/
  01-terra-implement/input.md
  01-terra-implement/output.md
  01-terra-implement/result.md
  02-luna-verify/input.md
  02-luna-verify/output.md
  02-luna-verify/result.md
  03-sol-review/input.md
  03-sol-review/output.md
  03-sol-review/result.md
```

- `input.md` contains the exact instructions sent to Codex.
- `output.md` is the verbatim log of all Codex actions, tool use, and execution output.
- `result.md` is Codex's final result. It must give the parent agent the changes, verification results, decision, and remaining risks.
- During a normal handoff, the parent agent reads `result.md` first. It reads `output.md` when validating claims, auditing work, or diagnosing a failure.
- Committing the three files to Git is optional and follows the user's preference. Ask the user (or follow their previously stated preference) before committing `agents/` records.
- The orchestrator must not write or transcribe the prompt, execution log, or result report on the wrapper's behalf.
- The wrapper writes the complete input/output/result trail itself.
- Use the scratchpad only for temporary information with no audit value.
- The scratchpad is `scratchpad/` directly under the repository root. Never use the session-specific system scratchpad directory; create and use `scratchpad/` at the repository root instead.
- Make the real model visible in role names and UI labels, such as `terra-implement`, `sol-review`, `luna-verify`, or `gpt-5.6-sol:review-payments`.
- Do not record secrets, tokens, or unnecessary internal reasoning.

### 4.3 `output.md` Isolation Rules

Full-file reads of any `output.md` are prohibited.

- The parent agent always reads `result.md` first.
- Treat `output.md` as a raw audit log, not project knowledge.
- Only when diagnosing a failure or verifying a claim, search it for the specific command, error, filename, or marker, and read only a narrow line range around the hits.
- Never read, combine, or fully summarize multiple `output.md` files at once.
- Exclude `agents/**/output.md` and `history/**` from broad repository searches by default:

```powershell
rg "term" . -g "!agents/**/output.md" -g "!history/**"
```

- Never feed a past `output.md` into another agent as input.
- Longer term, consider storing raw logs as `artifacts/output.log` or in an external CI artifact store instead of Markdown.

### 4.4 Foreground First, Exponential Fallback 

Subagents cannot idle-wait: foreground `sleep` is blocked, and ending the turn to "wait for codex" makes the harness treat the wrapper as completed (three early-exit incidents on 2026-07-11).

1. The wrapper runs `codex exec` as a single **foreground** Bash call with explicit `timeout: 600000` (10-minute ceiling; most codex tasks finish in 5–7 minutes).
2. On timeout, re-launch (or confirm still-running) codex in background and poll for `result.md` with **exponentially increasing waits** (1, 2, 4, 8… minutes) using harness-tracked background Bash.
3. If the orchestrator sees a wrapper exit early while codex still runs, it attaches its own harness-tracked watcher on `result.md` instead of respawning the wrapper.
4. Tasks expected to exceed 10 minutes should be split into smaller codex runs when practical.

### 4.5 grok-4.5 Invocation

grok-4.5 is invoked via the `grok` CLI, not `codex exec`. Verified behavior (v0.2.93):

- Headless run with tools: `grok --always-approve --cwd <absolute-path> -p "<prompt>"`
- stdout is the concatenation of ALL assistant text (intermediate remarks + final message), not the final message alone. There is no `--output-last-message` equivalent.
- No output format exposes tool calls: `plain` and `json` merge intermediate and final text; `streaming-json` emits only thought/text/end events. A verbatim action log (`output.md` equivalent) cannot be obtained.
- Wrapper rules:
  1. Instruct in the prompt: "Output only the final report; no intermediate remarks" (still expect an occasional stray line).
  2. Save stdout as both the quasi-log and the basis for `result.md`; extract the final section into `result.md` without rewriting it.
  3. Because a tool-call audit trail is unavailable, do NOT use grok for work requiring audit evidence (design changes, migrations); use codex models.
- `--output-format json` returns `sessionId`; follow-up turns can attach via `grok --resume <sessionId>`.
- Unique options: `--json-schema` (structured output), `--best-of-n` (parallel N runs, heavy quota consumption — use sparingly), `--worktree`.

## 5. Worktree and Parallel Implementation Rules

Parallel implementation agents work in explicit worktrees directly under the repository root.

```text
worktrees/<name>/
```

Mandatory rules:

1. Do not rely on hidden `.claude/worktrees/` directories.
2. The orchestrator creates a dedicated branch and path explicitly with `git worktree add`.
3. Give the wrapper and Codex the exact absolute path of the assigned worktree.
4. State each agent's file or package ownership in its prompt.
5. Do not parallelize implementation tasks that modify the same files.
6. An agent must not modify or revert user changes outside its assigned worktree.
7. Before integration, inspect the branch diff, commits, and verification results.
8. Resolve conflicts by reviewing their meaning. Do not mechanically overwrite one side.
9. After merging, confirm that no unmerged changes remain, then remove the worktree and delete its temporary branch.
10. For long-running work, use an appropriate timeout or background execution and poll for the creation of `result.md`. Read `output.md` only when checking progress or diagnosing failure.

Do not create a worktree for a short, read-only task performed by one agent. A worktree is mandatory for parallel implementation, independent code modifications, or work with a meaningful conflict risk.

## 6. Optional Independent Review and Agent Evaluation

Independent review is optional and should be used when the task's risk, complexity, or uncertainty justifies the additional cost. It is recommended for security-sensitive, concurrency-sensitive, migration-heavy, cross-cutting, public-contract, or difficult-to-reverse changes. Routine, narrow, deterministic work does not require a separate reviewer when its result is easy to verify directly.

### 6.1 Adversarial Review Procedure

1. Restate the acceptance criteria and implicit invariants from the user's request.
2. Inspect the relevant implementation, tests, configuration, and diff directly.
3. Try to falsify the solution using realistic failure scenarios and boundary conditions.
4. Rank findings by severity and cite exact files and lines where possible.
5. Separate confirmed defects, plausible risks, questions, and style preferences.
6. If there is no material defect, approve explicitly and state the evidence checked.

The verdict must be one of `approve`, `approve with non-blocking notes`, or `request changes`. Every blocking finding must include a concrete remediation path.

### 6.2 Evaluation Criteria

| Dimension | Standard |
|---|---|
| Correctness | Satisfies the request and preserves the required behavior and contracts |
| Completeness | Includes every deliverable, edge case, migration, and integration point |
| Evidence | Supports claims with code, diffs, static checks, tests, or runtime results |
| Design Quality | Maintains clear responsibilities and boundaries with appropriate complexity |
| Safety | Addresses security, data integrity, compatibility, concurrency, and rollback risks |
| Communication | Accurately reports changes, verification, limitations, and residual risks |

Explain every material deduction. Do not approve an output merely because the report is well written.

## 7. Verification and Execution Rules

- The fable-5 orchestrator performs only the reading and static investigation needed for design decisions.
- Route routine `go test`, `go vet`, `tsc`, migration checks, and builds through a gpt-5.6-luna wrapper.
- Route browser, live-runtime, and computer-use verification through a gpt-5.6-terra wrapper.
- Never claim that a check passed if it was not run.
- Distinguish existing failures from failures introduced by the current change.
- Do not weaken requirements or tests merely to make verification pass.

## 8. Git, Changes, and Handoff

- Inspect `git status` and the relevant diff before starting work.
- Treat existing changes as user-owned and do not revert them.
- Do not run destructive Git commands without explicit approval.
- Make normal file changes that are necessary and within the requested implementation scope.
- Confirm before making unrelated changes or expanding operational impact.
- Group related changes into intentional commits.
- Committing `agents/.../input.md`, `output.md`, `result.md` records and the `scratchpad/` directory is optional, decided by the user's preference. Confirm with the user before including them in a commit.
- Update `continue.md` immediately after a commit, merge, design decision, or change to the next starting point.
- Use Korean for the product UI and project documentation by default. Prefer kaomoji over emoji when a visual expression is needed.
- Use `temp/` for drafts and scratch work shared with the user.

The final handoff must cover the changes, verification results, design decisions and assumptions, unverified risks, migration or deployment follow-up, and the next starting point.

## 9. Pre-Work Checklist

1. Did you read `continue.md` (and only `continue.md`) in full?
2. Did you confirm the approved boundaries in `design.md` via targeted section reads, not a full read?
3. When relevant, did you search and partially read `idea.md`, `problem.md`, `report.md`, and `history/tasks/`?
4. Did you inspect Git status and existing user changes?
5. Did you define the acceptance criteria and risk level?
6. Did you route implementation, verification, and review according to the Cost, Intelligence, and Taste table?
7. Are GPT calls going through a sonnet-5 thin wrapper?
8. Is the wrapper writing `agents/.../input.md`, `output.md`, and `result.md` itself?
9. For parallel implementation, did you create a dedicated worktree directly under the repository root?
10. If the task warrants independent review, are the implementation agent and gpt-5.6-sol reviewer separate?
11. Did you inspect the verification evidence?
12. Are the code and `continue.md` consistent?
13. Is `continue.md` under its size cap, with old records moved to `history/tasks/`?
