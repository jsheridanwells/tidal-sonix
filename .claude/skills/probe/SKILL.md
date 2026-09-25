---
name: probe
description: Curl-before-code. Draft an .http request for an external endpoint before any client code exists.
argument-hint: "[service] [what to call]"
disable-model-invocation: true
---

Before any C# talks to $0, the call exists in `http/$0.http` and a real response is saved. Target: $ARGUMENTS

1. Say what you believe the request looks like (method, URL, headers, body, auth) and, for each part, whether it comes from official docs (name the page) or is a guess. Guesses are expected; label them.
2. Append the request to `http/$0.http` in REST Client syntax. Tokens and IDs are `{{variables}}` resolved from the gitignored `http/http-client.env.json`, never inline.
3. Stop. Jeremy runs it and saves the response under `http/responses/$0-<short-name>.json` with tokens redacted.
4. When he says it's saved, read the response and list what differs from your belief in step 1. Those differences go in his notes, not yours.

Do not write any C# in this skill.
