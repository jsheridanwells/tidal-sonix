---
name: explain-back
description: Check Jeremy's own explanation of a change against the staged diff before he commits.
argument-hint: "[your commit message / explanation]"
disable-model-invocation: true
---

Jeremy's explanation of the staged change:

> $ARGUMENTS

The staged diff:
!`git diff --staged`

Compare the explanation to the diff. Reply with:

1. Claims in the explanation the diff doesn't support.
2. Changes in the diff the explanation doesn't mention.
3. One probing question about the part he explained least.

Plain and short. If the explanation is accurate and complete, say so in one line. Don't rewrite his message; he writes it and commits it.
