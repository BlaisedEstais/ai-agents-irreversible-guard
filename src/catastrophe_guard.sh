#!/bin/sh
# Pré-filtre rapide de catastrophe_guard.py (hook PreToolUse de Claude Code / Codex, pre_tool_call d'Hermes).
# Ne lance Python (~0,3 s) que si l'appel d'outil PEUT être catastrophique.
# Tout en builtins (pas de `cat`) : lancer un programme coûte déjà ~90 ms.
# test_guard.py vérifie (CG_PREFILTER_ONLY=1) que chaque cas BLOCK passe bien jusqu'à Python.
DIR="${0%/*}"
input=
while IFS= read -r line || [ -n "$line" ]; do
  input="$input$line
"
done

pass() {
  if [ -n "$CG_PREFILTER_ONLY" ]; then echo PASS; exit 0; fi
  for py in /Library/Developer/CommandLineTools/usr/bin/python3 \
            /Library/Frameworks/Python.framework/Versions/Current/bin/python3 \
            /usr/local/bin/python3 /opt/homebrew/bin/python3; do
    if [ -x "$py" ]; then
      printf '%s' "$input" | "$py" -I -S -c 'import sys; sys.path.insert(0, sys.argv[1]); import catastrophe_guard as g; sys.exit(g.main([]))' "$DIR"
      exit $?
    fi
  done
  echo "catastrophe_guard : aucun python3 trouvé, garde-fou INACTIF" >&2
  exit 1
}

case "$input" in
  # éditions de fichiers : seuls la config Claude et le garde-fou installé sont surveillés
  *'"tool_name":"Write"'*|*'"tool_name":"Edit"'*|*'"tool_name":"MultiEdit"'*|*'"tool_name":"NotebookEdit"'*|\
  *'"tool_name": "Write"'*|*'"tool_name": "Edit"'*|*'"tool_name": "MultiEdit"'*|*'"tool_name": "NotebookEdit"'*|\
  *'"tool_name":"apply_patch"'*|*'"tool_name": "apply_patch"'*|\
  *'"tool_name":"write_file"'*|*'"tool_name": "write_file"'*|*'"tool_name":"patch"'*|*'"tool_name": "patch"'*)
    case "$input" in
      *.claude/settings*|*ClaudeCode*|*.claude/hooks*|*AllHooks*|*codex/hooks.json*|*shell-hooks-allowlist*|\
      *catastrophe-guard*) pass ;;
      *) exit 0 ;;
    esac ;;
  # outils MCP retenus par le matcher, code JS de Codex (js / Code Mode), envois de messages Hermes : toujours analysés
  *'"tool_name":"mcp__'*|*'"tool_name": "mcp__'*|*'"tool_name":"js"'*|*'"tool_name": "js"'*|\
  *'"tool_name":"exec"'*|*'"tool_name": "exec"'*|*'"tool_name":"send_message"'*|*'"tool_name": "send_message"'*|\
  *'"tool_name":"yb_send_dm"'*|*'"tool_name": "yb_send_dm"'*|*'"tool_name":"discord"'*|*'"tool_name": "discord"'*|\
  *'"tool_name":"feishu_drive_reply_comment"'*|*'"tool_name": "feishu_drive_reply_comment"'*) pass ;;
esac

. "$DIR/cg-prefilter.sh"
# seulement la partie tool_input (pas le chemin du transcript, le cwd, la session...)
cg_risky "${input#*\"tool_input\"}" && pass
exit 0
