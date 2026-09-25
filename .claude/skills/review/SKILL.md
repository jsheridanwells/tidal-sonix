---
name: review
description: Fresh-context review of the working diff against a spec's success criteria.
argument-hint: "[spec-number] [task-number?]"
disable-model-invocation: true
context: fork
agent: spec-reviewer
---

Review the current working diff against `specs/SPEC-$0.md` (Task $1 if given, otherwise the spec's full success criteria) and `adr/ADR-$0.md`. Findings only.
