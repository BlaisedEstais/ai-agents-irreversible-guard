# Bibliothèque sh (sourcée par catastrophe_guard.sh et cg-zsh) : cg_risky "<texte>" réussit si le texte
# contient un mot-clé d'action potentiellement catastrophique. Tout en builtins (aucun programme lancé).
# Règle : ces motifs doivent rester un SUR-ENSEMBLE de ce que bloque catastrophe_guard.py
# (test_guard.py le vérifie sur chaque cas BLOCK, JSON compact et espacé).
# Le texte peut être du JSON : \n et \t y apparaissent comme deux caractères.
cg_risky() {
  case "$1" in
    rm[[:space:]]*|*[!a-zA-Z0-9_]rm[[:space:]]*|*[!a-zA-Z0-9_]rm'\t'*|*'\nrm'[[:space:]]*|*'\nrm\t'*|*'\trm'*|\
    *'"rm'*|*"'rm'"*|*'=rm'*|*unlink*|*rmtree*|*rmSync*|*rmdir*|*rm_r*|*rimraf*|*'.rm('*|*FileUtils*|\
    *remove*|*Remove*|*'find '*'-delete'*|*'find '*'-exec'*|*'find '*'-ok'*|*xargs*|*rsync*'--delete'*|*rsync*'--remove'*|\
    *rsync*'-d'*|*[!a-z]sync' '*|*chmod*'-'*R*|*chown*'-'*R*|*chgrp*'-'*R*|*chflags*'-'*R*|*'of='*|\
    *git*push*|*git*clean*|*git*stash*clear*|*git*reflog*expire*|*git*gc*prune*|*'gh '*repo*|*'gh '*api*|\
    *DELETE*|*delete*|*Delete*|*destroy*|*purge*|*[Dd][Rr][Oo][Pp][!a-zA-Z0-9_]*|*dropdb*|*dropDatabase*|\
    *TRUNCATE*|*truncate*|\
    *diskutil*|*tmutil*|*newfs*|*'asr '*|*'gpt '*|*fdisk*|*bless[[:space:]]*|*'bless\t'*|*startosinstall*|*sysadminctl*|\
    *dscl*|*csrutil*|*nvram*|*softwareupdate*|*osascript*|*[Ee]mpty*[Tt]rash*|*'.Trash'*|\
    *rclone*|*gcloud*|*gsutil*|*'bq '*|*wrangler*|*supabase*|*vercel*|*netlify*|*firebase*|*'aws '*|*heroku*|\
    *'fly '*|*flyctl*|*railway*|*terraform*|*tofu*|*pulumi*|*kubectl*|*docker*|*unpublish*|*prisma*|*'db:'*|\
    *catastrophe_guard*|*catastrophe-guard*|*.claude/hooks*|*ClaudeCode*|*AllHooks*|*.claude/settings*|\
    *codex/hooks.json*|*shell-hooks-allowlist*|*server-commander*|*'hooks revoke'*|*defaultShell*) return 0 ;;
  esac
  return 1
}
