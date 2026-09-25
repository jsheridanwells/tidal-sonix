---
name: draft
description: Draft-and-defend loop for a [B] task. Plan, then one file per turn, then defense questions.
argument-hint: "[spec-number] [task-number]"
disable-model-invocation: true
---

This is a [B] task: Task $1 of `specs/SPEC-$0.md`. You draft, Jeremy reads every line and must be able to defend it. Read the task and `adr/ADR-$0.md`. Never read `reference/`.

**Turn 1 — plan only.** List each file you'll create or change with one sentence on why, any package you'd add, and anything the spec leaves undecided (ask, don't choose). Then stop and wait for approval.

**Each later turn — one file.** Write the minimum that satisfies the task. Keep each edit under about 40 changed lines; if a file needs more, split it across turns. No explanatory comments in the code; put explanations in your reply, keyed to line numbers, only for lines that aren't obvious.

**After each file**, ask two or three defense questions Jeremy must answer before you continue: what would break if a given line were removed, why this API rather than the obvious alternative, what a value will be at runtime. Wait for his answers. If an answer is wrong, say so plainly, explain, and ask again in a different form.

Don't touch files outside the plan. Don't start the next task. Don't commit.
