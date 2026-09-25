#!/bin/sh
# Auto-confirmation d'un agent pour UNE action de niveau « confirmation » faite via un outil qui n'est pas
# un shell (outil MCP : suppression d'un document, envoi d'un message…). Liée à la clé de l'action affichée par le
# garde-fou, valable 5 min, un seul appel, et seulement si la checklist vient d'être affichée pour cette action.
#   sh ~/.claude/hooks/cg-ack.sh <clé> "<qui l'a demandé + pourquoi c'est sûr ou réversible>"
key="$1"
case "$key" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) shift ;;
  *) echo "Usage : sh cg-ack.sh <clé à 16 caractères donnée par le garde-fou> \"<justification>\"" >&2; exit 1 ;;
esac
j="$*"
if [ ${#j} -lt 25 ]; then
  echo "Justification trop courte (25 caractères min.) : qui l'a demandé + pourquoi c'est sûr ou réversible." >&2
  exit 1
fi
esc=$(printf '%s' "$j" | tr '\n\r\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g')
f="${CG_ACKS:-$HOME/.claude/hooks/acks.jsonl}"
ts=$(date +%s)
# L'identité d'une confirmation, c'est cet id : deux confirmations émises dans la même seconde ne doivent pas
# être confondues (sinon la seconde passe pour « déjà utilisée »).
printf '{"ts": %s, "id": "%s-%s", "key": "%s", "justification": "%s", "cwd": "%s"}\n' "$ts" "$ts" "$$" "$key" "$esc" "$(printf '%s' "$PWD" | sed 's/"/\\"/g')" >> "$f"
chmod 600 "$f"
echo "Confirmation enregistrée pour l'action $key (5 min, un seul appel). Refais maintenant l'appel à l'identique."
