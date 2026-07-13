# CLAUDE.md Operations Guide

## What This Guide Defines

> **What to read → which model to assign → where to work → what to record → who reviews the work → how to hand it off to the next session**

---

## System at a Glance

```text
User request
    │
    ▼
Lead orchestrator (fable-5)
    │
    ├─ 1. Load project knowledge
    │      continue.md ─ Current status and next task
    │           ↓
    │      design.md   ─ Approved goals and architecture
    │           ↓
    │      idea.md     ─ Concepts and rationale for the final goal
    │           ↓
    │      problem.md  ─ Gaps between implementation and target
    │
    ├─ 2. Classify the task and select a model
    │      Design and decisions       → fable-5
    │      High-risk work and review  → gpt-5.6-sol
    │      Bulk and mechanical work   → gpt-5.6-terra
    │      Routine verification       → gpt-5.6-luna
    │
    ├─ 3. Invoke a sonnet-5 thin wrapper
    │      └─ codex exec -m <actual GPT model>
    │
    ├─ 4. Record the delegation explicitly
    │      agents/<date>-<NN>-<task>/<NN>-<role>/
    │        ├─ input.md   ─ Exact instructions sent to Codex
    │        ├─ output.md  ─ Complete action, tool, and execution log
    │        └─ result.md  ─ Final result read by the parent agent
    │
    ├─ 5. Isolate parallel implementation
    │      worktrees/<task>/
    │        └─ Implement and verify on a dedicated branch
    │
    ├─ 6. Optionally perform an independent review
    │      gpt-5.6-sol
    │        └─ approve / approve with notes / request changes
    │
    └─ 7. Integrate and hand off
           Inspect code, tests, and documentation
                ↓
           Update continue.md
                ↓
           Hand off to the next session
```

---

## Document Roles

```text
CLAUDE.md
   └─ Reading order and operating rules

continue.md
   └─ Current progress and the next task

design.md
   └─ Approved design and boundaries that must be preserved

idea.md
   └─ What the project is building and why

problem.md
   └─ How the current implementation differs from the target
```

## 1. Match Models to Capability and Cost

Using the most expensive model for every task wastes resources. Assigning difficult work to an inexpensive but unsuitable model reduces quality and safety.

`CLAUDE.md` defines each model's Cost, Intelligence, Taste, and role.

| Task | Assigned Model | Reason |
|---|---|---|
| Architecture and complex decisions | fable-5 | Strong reasoning and design quality |
| Adversarial review and advanced refactoring | gpt-5.6-sol | Independent verification and high code quality |
| Bulk implementation, analysis, and migrations | gpt-5.6-terra | Strong execution ability and cost efficiency |
| Routine builds, tests, and static checks | gpt-5.6-luna | Lowest cost for narrow, deterministic work |
| Lightweight relay for invoking GPT models | sonnet-5 | Handles invocation and records without doing the substantive work |

The governing priority is:

> **Intelligence > Taste > Cost**

Correctness and safety come first. Cost distinguishes between otherwise suitable models.

## 2. The Thin Wrapper Makes the Real Worker Explicit

Claude's native agent interface cannot directly select the required GPT model, so sonnet-5 acts as a thin wrapper.

```text
Lead orchestrator
      │ Task instructions
      ▼
sonnet-5 thin wrapper
      │ Record prompt + invoke codex exec
      ▼
gpt-5.6-sol / terra / luna
      │ Perform implementation, verification, or review
      ▼
input.md + output.md + result.md
```

The wrapper does not perform the substantive task. It records the instructions, invokes the selected GPT model, and preserves the resulting files.

This makes the actual working model visible in both the user interface and the audit trail.

## 3. `input.md`, `output.md`, and `result.md` Make Delegation Auditable

Every delegated task produces three files.

```text
agents/2026-07-10-01-example/01-terra-implement/
  input.md
  output.md
  result.md
```

| File | Contents | Primary Reader |
|---|---|---|
| `input.md` | Exact requirements and constraints sent to Codex | Worker and auditor |
| `output.md` | Complete Codex action, tool-use, and execution log | Auditor and troubleshooter |
| `result.md` | Final changes, verification, decision, and remaining risks | Parent agent |

The parent agent normally reads only `result.md`. It consults `output.md` when validating an important claim or investigating a failure.

This separation achieves two goals:

- The parent agent does not waste context on a long execution log.
- The complete behavior and evidence remain available for audit when needed.

## 4. Worktrees Prevent Conflicts During Parallel Work

If several implementation agents share one working directory, they can overwrite the same files or damage unfinished user changes.

Parallel implementation therefore runs in independent worktrees directly under the repository root.

```text
factory/
  worktrees/
    error-contract/     ─ Dedicated branch A
    staged-qc/          ─ Dedicated branch B
    assembly-engine/    ─ Dedicated branch C
```

Each agent modifies only its assigned files and packages. Before integration, inspect its diff, commits, and verification results. After merging, remove the worktree and its temporary branch.

## 5. Use an Independent Reviewer When the Risk Justifies It

An author naturally carries the same assumptions into the review of their own solution. When a change is security-sensitive, concurrency-sensitive, migration-heavy, cross-cutting, public-facing, difficult to reverse, or otherwise high risk, use a separate gpt-5.6-sol agent to review it from the original request and repository evidence.

Independent review is optional for routine, narrow, deterministic work whose result is easy to verify directly.

```text
Implementation agent
    │ Patch + result.md
    ▼
Independent gpt-5.6-sol review
    ├─ approve
    ├─ approve with non-blocking notes
    └─ request changes
```

The reviewer does not trust the report by default. It inspects the code, diff, tests, and configuration directly, separates confirmed defects from plausible risks, and provides a concrete remediation path for every blocking issue.

## 6. Keep Code and Documentation Current Together

If the code changes without a corresponding update to `continue.md`, the next session may repeat completed work or start from the wrong point.

Update `continue.md` immediately when:

- A commit or merge is completed.
- A design decision changes.
- The next starting point changes.
- Run instructions, verification procedures, or cautions change.

---

## Repository Structure

```text
factory/
├─ CLAUDE.md                         AI operating rules
├─ continue.md                       Progress and next starting point
├─ design.md                         Approved goals and architecture
├─ idea.md                           Concepts and rationale
├─ problem.md                        Gaps between implementation and target
│
├─ agents/                           Delegation audit trail
│  └─ <date>-<task>/
│     └─ <actual-model>-<role>/
│        ├─ input.md
│        ├─ output.md
│        └─ result.md
│
└─ worktrees/                        Isolated parallel implementation
   └─ <task>/
```

---

## End-to-End Workflow

```text
1. Receive the request
   ↓
2. Read continue.md and design.md
   ↓
3. Define acceptance criteria and assess risk
   ↓
4. Select the appropriate model
   ↓
5. Create agents/.../input.md
   ↓
6. Invoke codex exec through the thin wrapper
   ├─ output.md: complete execution log
   └─ result.md: final result
   ↓
7. Implement in a dedicated worktree when required
   ↓
8. Run verification through the verification agent
   ↓
9. Optionally obtain an independent gpt-5.6-sol review when risk warrants it
   ↓
10. Integrate and commit the changes
   ↓
11. Update continue.md
   ↓
12. Report the result and remaining risks to the user
```

---

## Core Principles

The purpose of `CLAUDE.md` is not to burden an AI with a large set of rules. It preserves direction, quality, and traceability across multiple sessions and models.

Remember these five principles:

1. **Keep project knowledge in repository documents, not conversational memory.**
2. **Assign work to models according to capability and cost.**
3. **Record every delegation through input, output, and result files.**
4. **Isolate parallel implementation with worktrees and add independent review when the risk warrants it.**
5. **Update the handoff document whenever the code changes.**

When these rules are followed, a new contributor or AI session can continue the project under the same standards, and the team can always determine who did what and why.
