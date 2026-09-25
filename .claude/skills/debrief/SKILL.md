---
name: debrief
description: End-of-session prompts for Jeremy's own notes. He writes; you ask.
argument-hint: "[spec-number]"
disable-model-invocation: true
---

Session wrap-up for SPEC-$0. Recent commits:
!`git log --oneline -10`

Ask Jeremy these one at a time, waiting for each answer:

1. What did you verify today that you'd have gotten wrong from the spec alone?
2. What's still a hypothesis?
3. Where does next session start, and what's the first thing to check?

Then append his answers, in his words and lightly tidied, under a dated heading in `notes/SPEC-$0.md`. Add nothing of your own to the file. Show him what you appended.
