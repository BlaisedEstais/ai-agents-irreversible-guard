// Plugin OpenClaw « catastrophe-guard » : soumet exec / process / apply_patch / write / edit / sessions_spawn au
// garde-fou partagé (~/.claude/hooks/catastrophe_guard.py, le même que Claude Code, Codex et Hermes).
//  - action irréversible  -> demande d'approbation OpenClaw (tu approuves ou refuses dans l'app / le canal)
//  - action à confirmer    -> refus avec checklist ; l'agent peut s'auto-confirmer (`# cg-ack: ...`)
//  - erreur du garde-fou   -> laisse passer (fail-open, comme les autres hooks : ne jamais bloquer l'agent par bug)
// Pré-filtre RISKY (copie JS de cg-prefilter.sh) : Python (~0,4 s) n'est lancé que si l'appel PEUT être dangereux.
import { execFile } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const HOME = os.homedir();
const GUARD = path.join(HOME, ".claude", "hooks", "catastrophe_guard.py");
const PYTHONS = [
  "/Library/Developer/CommandLineTools/usr/bin/python3",
  "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
  "/usr/local/bin/python3",
];

// Doit rester un SUR-ENSEMBLE de ce que bloque catastrophe_guard.py (test_guard.py le vérifie).
export const RISKY = new RegExp(
  [
    String.raw`(^|[^a-zA-Z0-9_])rm(\s|\\t)`, String.raw`["'=]rm`, "unlink", "rmtree", "rmSync", "rmdir", "rm_r", "rimraf",
    String.raw`\.rm\(`, "FileUtils", "[Rr]emove", String.raw`find .*-(delete|exec|ok)`, "xargs",
    String.raw`rsync.*-(-delete|-remove|d)`, String.raw`(^|[^a-z])sync `, String.raw`ch(mod|own|grp|flags).*-.*R`, "of=",
    "git.*push", "git.*clean", String.raw`git.*stash.*clear`, "git.*reflog.*expire", "git.*gc.*prune",
    "gh .*repo", "gh .*api", "DELETE|[Dd]elete|destroy|purge", "[Dd][Rr][Oo][Pp]([^a-zA-Z0-9_]|$)", "dropdb",
    "dropDatabase", "TRUNCATE|truncate", String.raw`diskutil|tmutil|newfs|asr |gpt |fdisk|bless(\s|\\t)|startosinstall|sysadminctl`,
    "dscl|csrutil|nvram|softwareupdate|osascript", "[Ee]mpty.*[Tt]rash", String.raw`\.Trash`,
    "rclone|gcloud|gsutil|bq |wrangler|supabase|vercel|netlify|firebase|aws |heroku|fly |flyctl|railway",
    "terraform|tofu|pulumi|kubectl|docker|unpublish|prisma|db:",
    "catastrophe_guard|catastrophe-guard", String.raw`\.claude/hooks|ClaudeCode|AllHooks|\.claude/settings`,
    String.raw`codex/hooks\.json|shell-hooks-allowlist|server-commander|hooks revoke|defaultShell`,
  ].join("|"),
);
const GUARD_PATH = /\.claude\/(hooks|settings)|ClaudeCode|AllHooks|codex\/hooks\.json|shell-hooks-allowlist|catastrophe-guard/;

function verdict(payload) {
  const py = PYTHONS.find((p) => fs.existsSync(p));
  if (!py || !fs.existsSync(GUARD)) return Promise.resolve({ verdict: "allow" });
  return new Promise((resolve) => {
    const child = execFile(py, ["-I", "-S", GUARD, "--verdict"], { timeout: 12000, encoding: "utf8" }, (err, stdout) => {
      if (err || !stdout) return resolve({ verdict: "allow" });
      try {
        resolve(JSON.parse(stdout.trim().split("\n").pop()));
      } catch {
        resolve({ verdict: "allow" });
      }
    });
    child.stdin.end(JSON.stringify(payload));
  });
}

const str = (v) => (typeof v === "string" ? v : Array.isArray(v) ? v.join(" ") : "");

// Traduit l'appel OpenClaw dans le vocabulaire du garde-fou ; null = rien à vérifier.
export function toPayload(event) {
  const p = event.params || {};
  switch (event.toolName) {
    case "exec": {
      // Code Mode : même nom d'outil « exec », code JS dans code (et recopié dans command)
      if (event.toolKind === "code_mode_exec" || (typeof p.code === "string" && (!p.command || p.command === p.code))) {
        return { tool_name: "js", tool_input: { code: p.code || p.command || "" }, always: true };
      }
      if (typeof p.command === "string") return { tool_name: "Bash", tool_input: { command: p.command }, text: p.command };
      if (typeof p.source === "string") return { tool_name: "js", tool_input: { code: p.source }, always: true };
      return null;
    }
    case "process": {
      if (!["write", "submit", "paste", "send-keys"].includes(p.action)) return null;
      const data = str(p.data) || str(p.text) || str(p.literal) || str(p.keys);
      return { tool_name: "process", tool_input: { action: p.action, data }, text: data };
    }
    case "apply_patch":
      return { tool_name: "apply_patch", tool_input: p, text: JSON.stringify(p), guardOnly: true };
    case "write":
    case "edit": {
      const file = str(p.path) || str(p.file_path);
      return { tool_name: "write_file", tool_input: { path: file }, text: file, guardOnly: true };
    }
    case "sessions_spawn":
      return { tool_name: "delegate_task", tool_input: { goal: str(p.task) || JSON.stringify(p) }, always: true };
    default:
      return null;
  }
}

export default {
  id: "catastrophe-guard",
  name: "Catastrophe guard",
  description: "Bloque ou fait approuver les actions catastrophiques (même garde-fou que Claude Code / Codex / Hermes).",
  register(api) {
    api.on(
      "before_tool_call",
      async (event, ctx) => {
        try {
          const payload = toPayload(event);
          if (!payload) return undefined;
          const { text, always, guardOnly } = payload;
          delete payload.text;
          delete payload.always;
          delete payload.guardOnly;
          if (!always && !(guardOnly ? GUARD_PATH : RISKY).test(text || "")) return undefined;
          const wd = (event.params || {}).workdir;
          const base = (ctx && (ctx.cwd || ctx.workspaceDir)) || path.join(HOME, ".openclaw", "workspace");
          payload.cwd = wd && path.isAbsolute(wd) ? wd : wd ? path.resolve(base, wd) : base;
          payload.session_id = (ctx && (ctx.sessionId || ctx.sessionKey)) || "openclaw";
          payload.agent = "openclaw";
          const v = await verdict(payload);
          if (v.verdict === "hard") {
            return {
              requireApproval: {
                title: "Garde-fou : action irréversible",
                description: v.message || "Action irréversible détectée.",
                severity: "critical",
                allowedDecisions: ["allow-once", "deny"],
              },
            };
          }
          if (v.verdict === "soft") {
            return { block: true, blockReason: v.message || "Confirmation requise par le garde-fou." };
          }
        } catch {
          // fail-open
        }
        return undefined;
      },
      { matcher: ["exec", "process", "apply_patch", "write", "edit", "sessions_spawn"], priority: 100 },
    );
  },
};
