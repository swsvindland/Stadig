#!/bin/zsh
# Claude Code's PostToolUse hook (see .claude/settings.json): formats the Swift file Claude just wrote
# or edited with swift-format and the repo's .swift-format, so every edit lands already formatted.
# Reads the hook's JSON on stdin. Never fails the edit: a file that doesn't parse is left as it is.
root=${0:A:h:h}
file=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')
[[ $file == *.swift && -f $file && ${file:A} == $root/* ]] || exit 0
xcrun swift-format format --in-place "$file" 2>/dev/null
exit 0
