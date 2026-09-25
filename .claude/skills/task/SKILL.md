---
name: task
description: Load one spec task and frame it before any work starts.
argument-hint: "[spec-number] [task-number]"
disable-model-invocation: true
---

Frame Task $1 of `specs/SPEC-$0.md`. Read that spec's frontmatter and Task $1, and `adr/ADR-$0.md`. Do not read other specs. Do not read `reference/`.

Current state of the tree:
!`git status --short`

Reply in at most ten lines, no code:

1. The task in one sentence, in your words.
2. Which `success_criteria` it moves forward.
3. Files it will touch or create.
4. Its bucket tag ([A] Jeremy types, [B] you draft and he defends, [C] you own it). If the heading has no tag, say so and ask which. Default is A.
5. One question Jeremy should be able to answer before starting. Ask it and stop.
