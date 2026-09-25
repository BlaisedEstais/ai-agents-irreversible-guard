#!/bin/sh
# Installe / met à jour le garde-fou anti-catastrophe des agents IA.
#   sh install.sh            -> Claude Code (hook PreToolUse dans ~/.claude/settings.json)
#   sh install.sh --all      -> + Codex, Hermes, OpenClaw (ceux qui sont installés)
#   options séparées : --codex --hermes --openclaw
# - refuse d'installer si un test échoue ;
# - copie les scripts dans ~/.claude/hooks (seul chemin de mise à jour : toute autre écriture y est bloquée) ;
# - branche chaque agent de façon idempotente, avec sauvegarde des fichiers de config touchés.
# Desktop Commander : réglage defaultShell = ~/.claude/hooks/cg-zsh (à poser via son outil set_config_value).
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/.claude/hooks"
PY=/Library/Developer/CommandLineTools/usr/bin/python3
[ -x "$PY" ] || PY=python3
ALL=; CODEX=; HERMES=; OPENCLAW=
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;; --codex) CODEX=1 ;; --hermes) HERMES=1 ;; --openclaw) OPENCLAW=1 ;;
  esac
done
[ -n "$ALL" ] && { [ -d "$HOME/.codex" ] && CODEX=1; [ -d "$HOME/.hermes" ] && HERMES=1; [ -d "$HOME/.openclaw" ] && OPENCLAW=1; }

GUARD_SRC="$SRC/src" "$PY" -B "$SRC/tests/test_guard.py"

mkdir -p "$DST"
for f in catastrophe_guard.py catastrophe_guard.sh cg-prefilter.sh cg-zsh cg-ack.sh mcp-profiles.json; do
  cp "$SRC/src/$f" "$DST/$f"
done
# Réglages propres à ce poste (chemins personnels, mot de déblocage) : jamais publiés, jamais dans le dépôt public.
# Réglages du poste : copiés depuis l'exemple au premier passage, jamais écrasés ensuite.
if [ ! -f "$DST/cg-config.json" ] && [ -f "$SRC/cg-config.example.json" ]; then
  cp "$SRC/cg-config.example.json" "$DST/cg-config.json" && chmod 600 "$DST/cg-config.json"
  echo "Réglages copiés dans $DST/cg-config.json (à adapter : chemins à protéger, mot de déblocage)"
fi
chmod 644 "$DST/catastrophe_guard.py" "$DST/cg-prefilter.sh"
chmod 755 "$DST/catastrophe_guard.sh" "$DST/cg-zsh" "$DST/cg-ack.sh"
[ -f "$DST/catastrophe_guard.log" ] && chmod 600 "$DST/catastrophe_guard.log"
echo "Garde-fou copié dans $DST"

"$PY" - "$CODEX" <<'EOF'
import json, os, shutil, sys, time
HOME = os.path.expanduser("~")
CMD = 'if [ -f "$HOME/.claude/hooks/catastrophe_guard.sh" ]; then /bin/sh "$HOME/.claude/hooks/catastrophe_guard.sh"; fi'
# Regex non ancrée (doc hooks Claude Code). Write/Edit ont leurs propres entrées ci-dessous.
# Le hook ne tourne que sur ces outils : tout ce qui lance une commande, écrit, supprime, envoie ou paie.
# Les verbes destructifs sont listés largement (un connecteur peut dire « purge » ou « wipe » plutôt que « delete »).
CLAUDE_MATCHER = ("Bash|Monitor|mcp__.*(bash|run_in_terminal|set_config_value|start_process|interact_with_process|"
                  "osascript|hermes_delegate|execute|write_action|delete|destroy|purge|drop|wipe|erase|revoke|"
                  "write_file|edit_block|move_file|send|reply|forward|transfer|payment|pay).*")
# Éditions de fichiers : le hook ne se lance que sur les fichiers du garde-fou (champ `if`, syntaxe des règles de
# permission, une règle par entrée ; une règle Edit couvre Write/Edit/MultiEdit/NotebookEdit ; « //** » = partout sur
# le disque, « **/ » seul ne couvrirait que le dossier courant). Évite de faire
# lire au hook le contenu de chaque gros Write.
EDIT_MATCHER = "Write|Edit|MultiEdit|NotebookEdit"
EDIT_RULES = ["Edit(~/.claude/hooks/**)", "Edit(~/.claude/settings*.json)", "Edit(//**/.claude/settings*.json)",
              "Edit(//Library/Application Support/ClaudeCode/**)", "Edit(~/.codex/hooks.json)",
              "Edit(~/.hermes/shell-hooks-allowlist.json)", "Edit(~/.openclaw/extensions/catastrophe-guard/**)"]


def handler(rule=None):
    h = {"type": "command", "command": CMD, "timeout": 15}
    if rule:
        h["if"] = rule
    return h


def set_hooks(path, entries):
    data = json.load(open(path)) if os.path.exists(path) else {}
    pre = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
    mine = [e for e in pre if "catastrophe_guard" in json.dumps(e)]
    if mine == entries:
        print("hook déjà à jour :", path)
        return False
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak-" + time.strftime("%Y%m%d-%H%M%S"))
    pre[:] = [e for e in pre if "catastrophe_guard" not in json.dumps(e)] + entries
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    json.load(open(tmp))
    os.replace(tmp, path)
    print("hook ajouté/mis à jour :", path)
    return True


set_hooks(os.path.join(HOME, ".claude", "settings.json"),
          [{"matcher": CLAUDE_MATCHER, "hooks": [handler()]},
           {"matcher": EDIT_MATCHER, "hooks": [handler(t + r[4:]) for r in EDIT_RULES for t in ("Edit", "Write")]}])
if sys.argv[1:] and sys.argv[1]:
    changed = set_hooks(os.path.join(HOME, ".codex", "hooks.json"),
                        [{"matcher": "Bash|apply_patch|js|exec|mcp__.*", "hooks": [handler()]}])
    try:
        trusted = "trusted_hash" in open(os.path.join(HOME, ".codex", "config.toml")).read()
    except OSError:
        trusted = False
    if changed or not trusted:
        print("\u26a0\ufe0f  Codex : le hook n'est actif qu'une fois approuvé. Lancer `codex`, taper /hooks, "
              "choisir catastrophe_guard -> trust (à refaire après chaque changement du hook).", file=sys.stderr)
EOF

if [ -n "$HERMES" ]; then
  HCMD="/bin/sh $DST/catastrophe_guard.sh"
  HCONF="$HOME/.hermes/config.yaml"
  [ -f "$HCONF" ] || { echo "Hermes : pas de config.yaml, rien à brancher"; HERMES=; }
  # regex appliquée au nom entier de l'outil (fullmatch)
  HMATCH="terminal|process|execute_code|write_file|patch|delegate_task|send_message|yb_send_dm|discord|feishu_drive_reply_comment"
  if grep -q "catastrophe_guard" "$HCONF"; then
    if grep -qF "matcher: \"$HMATCH\"" "$HCONF"; then
      echo "Hermes : hook déjà à jour"
    else
      cp -p "$HCONF" "$HCONF.bak-$(date +%Y%m%d-%H%M%S)"
      "$PY" - "$HCONF" "$HMATCH" <<'EOF'
import re, sys
p, m = sys.argv[1], sys.argv[2]
lines = open(p).read().split("\n")
for i, l in enumerate(lines):
    if "catastrophe_guard" in l and i and re.match(r'^\s*- matcher: ', lines[i - 1]):
        lines[i - 1] = re.sub(r'matcher: .*$', 'matcher: "%s"' % m, lines[i - 1])
open(p, "w").write("\n".join(lines))
EOF
      echo "Hermes : matcher du hook mis à jour"
    fi
  elif grep -qE '^hooks:' "$HCONF"; then
    echo "Hermes : une section hooks: existe déjà, ajouter à la main :"
    echo "  pre_tool_call: - matcher: \"$HMATCH\"  command: $HCMD"
  else
    cp -p "$HCONF" "$HCONF.bak-$(date +%Y%m%d-%H%M%S)"
    printf '\n# Garde-fou anti-catastrophe partagé\nhooks:\n  pre_tool_call:\n    - matcher: "%s"\n      command: "%s"\n      timeout: 20\n' "$HMATCH" "$HCMD" >> "$HCONF"
    echo "Hermes : hook ajouté à $HCONF"
  fi
  # consentement (sinon Hermes ignore le hook en mode non interactif, ex. pont Claude -> Hermes)
  if (cd "$HOME/.hermes/hermes-agent" && ./venv/bin/python -c "import sys; from agent.shell_hooks import _record_approval; _record_approval('pre_tool_call', sys.argv[1])" "$HCMD"); then
    echo "Hermes : hook approuvé (shell-hooks-allowlist.json)"
  else
    echo "Hermes : approbation automatique impossible -> lancer \`hermes hooks list\` et approuver le hook"
  fi
fi

if [ -n "$OPENCLAW" ]; then
  OC="$HOME/.openclaw/bin/openclaw"
  if "$OC" plugins install "$SRC/openclaw-plugin" --force --accept-capabilities && "$OC" plugins enable catastrophe-guard; then
    echo "OpenClaw : plugin catastrophe-guard installé et activé"
  else
    echo "OpenClaw : installation du plugin à vérifier (openclaw plugins list)"
  fi
fi
echo "Terminé."
