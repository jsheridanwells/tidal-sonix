#!/usr/bin/env bash
# Blocks any tool call that names reference/ in a path, glob, or shell command.
# Belt to the Read(reference/**) deny rule's suspenders: deny rules don't cover
# every Bash form or every Grep path. Requires jq.
set -euo pipefail

input=$(cat)
fields=$(jq -r '[.tool_input.command, .tool_input.file_path, .tool_input.path, .tool_input.pattern]
                | map(select(. != null)) | join("\n")' <<<"$input")

# reference/ as a path segment, or a bare "reference" directory argument to Grep/Glob.
if grep -Eq '(^|[^A-Za-z0-9_.-])reference/' <<<"$fields" \
   || grep -Eqx '(\./)?reference|.*/reference' <<<"$(jq -r '.tool_input.path // empty' <<<"$input")"; then
  echo "reference/ is off-limits in this repo (see CLAUDE.md). If Jeremy wants a comparison he will paste the block. Do not retry another way." >&2
  exit 2
fi
exit 0
