# Security policy and threat model

Short version: **this guard is built against agent mistakes, not against an adversary.** It is a policy layer that runs with your own privileges, on your own machine, as you. If you are relying on it as a security boundary, you are relying on the wrong thing — and this page exists so that nobody does that by accident.

---

## What it is designed to stop

The threat here is **an agent that does something catastrophic without meaning to**, in any of its usual flavours:

- **The misread target.** The right command on the wrong branch, the wrong directory, the wrong account. The most common real-world failure by a wide margin.
- **The confident-but-wrong cleanup.** "This is a temporary folder" / "this project was abandoned" / "rollback is impossible anyway".
- **The instruction that never came from you.** A file, an issue, a web page, an email, a tool result that says "delete X" or "the user already approved this", and an agent that treats read content as orders. The hard tier is designed specifically against this: the unlock must appear in a **real human turn** of the conversation, so content the agent *read* can never authorise a catastrophic action — the [lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/) case.
- **The chain that goes one step too far.** Nine identical harmless deletions, and a tenth that is not. This is why friction decays but never disappears, and why any change of action typology resets it.

Within that scope the design is deliberately conservative: an unknown service is treated as irreversible, the guard's own files and configuration are irreversible to touch, and the hard tier has no agent-accessible unlock path at all.

---

## What it does **not** stop

**A determined attacker with code execution on your machine.** The guard is not a sandbox: it does not confine the process, virtualise the filesystem, restrict network access, or run at a higher privilege level than the agent it watches. Anything that can run code as you can eventually do what it wants as you.

**A bypass of the pattern matching, because that is a property of pattern matching.** The guard inspects commands and tool payloads and decides from patterns. Denylists are known to be fragile *independently of whether their source is public*: *One Goal, Many Commands: Characterizing Denylist Fragility in AI Agents* ([ShellSieve, arXiv](https://arxiv.org/html/2606.15549v2)) tested 1,709 denylists collected from GitHub and found **69% to 98.6% of them bypassable** depending on the evasion class — base64 piped into a shell, subshells, quoting variations, `$IFS` expansion, and so on. For any command in a denylist there is an unbounded set of absent commands that do the same thing. That is why major agent harnesses have been moving from denylists to allowlists, and it is why this project's headline claim is about *false stops on real traffic*, not about coverage.

The honest consequence: **treat every number in the README as a measure of how little this gets in your way, never as a coverage guarantee.**

**Anything the host does not send to the hook.** The guard only sees the tool calls its host routes through the pre-tool-call event. Execution paths that bypass that event — whichever they are in your particular setup — are invisible to it. Two general cases worth knowing about:

- **Indirection.** The guard sees `sh deploy.sh`, not the contents of `deploy.sh`. The same goes for code that reads a token from a file and calls an API directly, and for anything driven through a browser rather than a shell.
- **Coverage gaps in the host.** Each agent covers a different set of events, and an interactive session or a nested runtime may re-enter the hook or not, depending on the host and the version. Check your agent's own hook documentation for what its pre-tool-call event actually intercepts, and re-check after upgrades.

**A hostile human, or a hostile agent configuration.** Hooks are user-level configuration. Anything that can rewrite your agent's settings can also unhook the guard — which is why editing the guard, its configuration, or its wirings is itself a 🛑 action, but that is a speed bump in the same sense as everything else here, not a lock. Hook definitions are themselves an attack surface: they have been used for remote code execution through untrusted project files ([CVE-2025-59536](https://research.checkpoint.com/2026/rce-and-api-token-exfiltration-through-claude-code-project-files-cve-2025-59536/)). Review hook definitions before trusting them and do not open hostile repositories with an agent.

---

## Fail-open, by choice

If the guard crashes, times out, cannot parse the payload, or cannot find a Python interpreter, **the call is allowed** and the failure is logged loudly (with a visible "guard INACTIVE" message when no interpreter is found).

This is a deliberate trade, and we would make it again:

- The 🛑 tier is a net under accidents, not a lock against an adversary. A net that jams shut is a net nobody hangs up.
- A guard that bricks an agent on a parse bug gets uninstalled within the week — and an uninstalled guard protects nothing at all. Availability failures are how safety controls die.
- Fail-closed only buys you something against an attacker who can reliably crash the guard, and that attacker already has better options (see above).

If your threat model genuinely needs fail-closed, do it at a layer that can enforce it: run the agent in a container or a VM, with scoped credentials, and let *that* boundary be the one that holds.

---

## Security by design, not by obscurity

This project is public on purpose, and the design assumes the adversary has read it ([Kerckhoffs's principle](https://en.wikipedia.org/wiki/Kerckhoffs%27s_principle)).

That assumption is not a stretch here: **the agent already knows everything.** Every refusal message explains the two tiers, the unlock procedure and the checklist to the model, because it has to — that is how the refusal does its job. There was never any obscurity to lose in front of the most likely adversary, which is a prompt-injected agent on your own machine.

What remains is the part that does not depend on secrecy: an unlock that only counts in a real human turn, a hard tier with no agent-accessible path, and a journal that makes every self-confirmation reviewable afterwards.

Two things are nevertheless **not** published, and should not be in your fork either:

- **Your `cg-config.json`.** It names what is protected — therefore, by subtraction, what is not, and where your valuable folders are. Keep it out of git (it is in `.gitignore`), `chmod 600`, and treat it as part of the guard: editing it is a 🛑 action.
- **Your unlock phrase.** The published default is worthless as a secret; pick your own. It is not a password against an attacker — the security property is the *human turn*, not the string — but an unguessable phrase makes it much harder to talk you into pasting one.

---

## Reporting

**A bypass that works against a default install** — a payload the guard allows that a reasonable person would call catastrophic — is the report we most want. Please use GitHub's private vulnerability reporting (Security → Report a vulnerability) rather than a public issue, and include:

- the exact tool payload or command, minimised;
- the verdict you got and the verdict you expected;
- your OS, Python version and the commit you tested;
- whether it works with the shipped defaults, or only with a particular configuration.

**You do not need to report the known classes** described in *What it does not stop*: encoding and shell-quoting tricks, indirection through a script or an API call, gaps in a host's own hook coverage, or anything that assumes code execution as your user. They are design limits, not defects — though a *cheap, general* mitigation for one of them is very welcome as a PR with a test.

**A false stop is also a security report here.** Over-blocking is how guardrails get disabled, so a legitimate action that got blocked is a bug of the same family. Open a normal issue with the redacted payload.

There is no bug bounty. This is a small, unfunded project; reports are handled on a best-effort basis, and fixes ship with a test that pins the case.

---

## If you install this

- **Read the engine first.** It is one dependency-free Python file, and it will run before every tool call your agent makes. That is a lot of trust to hand to code you have not read — from us or from anyone.
- **It makes no network calls and has no dependencies.** The decision path is deterministic code; there is no model in the loop, no telemetry, no phone-home. The journal and the self-confirmation ledger are local JSONL files, `0600`, with secrets masked.
- **Keep the real net underneath.** Trashes and version history, real backups (more than one, at least one off-machine), narrowly-scoped tokens, branch protection rules on the server side, separate cloud accounts for production. This guard buys you the seconds in which a mistake can still be caught; those buy you everything after.
