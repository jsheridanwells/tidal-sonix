---
name: hint
description: Graduated hint for the task Jeremy is typing himself.
argument-hint: "[1|2|3] [what I'm stuck on]"
disable-model-invocation: true
---

Jeremy is writing this code himself and is stuck. Level requested: $0. Full request: $ARGUMENTS

Give exactly the level asked for, then stop:

- **1 — Concept.** Which idea or mechanism he's missing, and which Microsoft Learn page covers it (search with the Microsoft Learn MCP tools if available; name the page, don't paste it). Two to four sentences.
- **2 — API.** The specific types, methods, or options involved, and the order they're called in. Names only, no bodies.
- **3 — Shape.** A skeleton with signatures filled in and `/* ??? */` where the logic goes, plus the one gotcha most likely to bite.

Never give level 4 (a working implementation). If he asks for more than 3, say the next step is opening the reference himself and pasting the block back for comparison.
