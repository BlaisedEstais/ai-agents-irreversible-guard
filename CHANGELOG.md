# Changelog

Notable changes, newest first. The versions below predate the first public release; they are kept because each one is an answer to something that went wrong in practice, and together they explain why the design looks like this.

The direction of travel is worth stating: after v3, every release **removed** friction. That is the intended direction. A guardrail that fires on recoverable actions gets routed around, and a bypassed guardrail is worse than none.

---

## [Unreleased] — first public release

- **The engine is now generic.** Everything machine-specific — protected paths, unlock phrase, scratch roots, exempt tool prefixes — moved out of the code into a `cg-config.json` read at start-up (`$CG_CONFIG`, then `~/.claude/hooks/cg-config.json`, then next to the engine). Without a config the guard still runs on conservative generic defaults.
- The configuration file is protected exactly like the engine: editing or deleting it is a 🛑 action, so weakening the guard is not easier than removing it.
- Published with documentation: `README.md`, `SECURITY.md` (threat model, denylist fragility, fail-open rationale), a fully documented `cg-config.example.json`, MIT licence.

---

## v5 — Friction decays when you chain

Deleting thirty test pages in a row should not cost thirty checklists. Repeating the same checklist is theatre after the second time; removing the net entirely is how "delete them all" gets executed at speed.

- **Per-typology backoff on the ⚠️ tier**: full checklist → short checklist (target and reversibility only) → one-line reminder → one pass in two → straight through with a periodic reminder.
- A series is keyed on **action kind + tool + container** (same document, same account, same repository), expires after 30 minutes of quiet, and **any change of typology resets it to zero**.
- The reminder no longer repeats the checklist. It asks the only question that still discriminates mid-chain: *is this one exactly the same thing as the previous ones?* — because that is where a chain turns dangerous.
- Straight-through passes are granted only for recoverable actions; for the rest, friction gets lighter but a written justification is still required every time.
- The minimum length of a `cg-ack:` justification relaxes as the series decays, instead of demanding a full paragraph for the ninth identical cleanup.

## v4 — Fewer over-triggers

Measured on replayed history, the guard was interrupting for things that had a documented way back. Every one of those is a bug.

- **The recovery-window map became the deciding data structure**, per service and per action, each row sourced. Same verb, different tier, depending on what actually happens to the data.
- **Recoverable deletions never escalate to the human.** A page or a document in a service with a trash or version history is a ⚠️ the agent settles alone — no model check, no effort check, no path to 🛑.
- **Deleting what the agent created earlier in the same session is free**: the guard finds the creation in the transcript and asks nothing.
- One confirmation **covers the next ones of the same kind** for a short window, so a clean-up does not re-run the checklist on every line.
- **Context saturation removed as an escalation trigger.** It measured the agent's fatigue, not the stakes of the action; it fired at the end of long, harmless sessions on trivial deletions, and it was the single largest source of over-blocking. It survives as one line of the checklist the agent asks itself.
- Kept, on the non-recoverable half only: escalation to the human for **small models** and **low reasoning effort**, and a requirement to declare the exact model id when the guard cannot determine it.

## v3 — Adversarial review

Three agents were pointed at the guard with a single instruction: get a catastrophic action past it. They did, repeatedly, and every hole became a test.

- Coverage added for the ways a destructive command hides: heredocs, `xargs`, `find -delete`, base64 and other obfuscation, split and chained commands, redirections and `dd` targets, interactive REPL sessions, patch-application tools, and deletions performed from code rather than a shell (`shutil.rmtree`, `fs.rmSync`, and friends).
- **Touching the guard is itself 🛑**: its own files, its configuration and each of its per-agent wirings. The refusal text says so to the model, and explicitly rules out routing around it through another tool, a generated script, or a delegated subagent.
- **The pre-filter is now provably a superset of the analyzer** — a dedicated test asserts that every payload the analyzer would block reaches it, in both the shell and JavaScript pre-filters. A fast path that silently drops a dangerous case is worse than no fast path.
- Performance pinned as a safety property: ~150 ms on the overwhelming majority of calls, because Python only starts for payloads that could be destructive.
- Secrets masked in the journal.

## v2 — Multi-agent coverage

One guard, one policy, every agent. A rule enforced in one harness and not in the next is a rule the work simply walks around.

- The same engine now sits behind every agent that has a pre-tool-call event, plus a **guarded shell** (`cg-zsh`) for tools that have no hook API at all: it submits the `-c` command, then `exec`s the real shell.
- A host plugin (`openclaw-plugin/`) demonstrating the same contract with a JavaScript pre-filter and a verdict bridge.
- **`cg-ack.sh`**: one-shot self-confirmation for MCP tool calls, where a justification comment cannot be attached to a JSON payload — the refusal hands out a 16-character key, valid once, for five minutes, for that exact action.
- **An installer** that runs the test suite first and refuses to install if anything fails, copies the scripts into a single directory the guard protects from any other write, and wires each detected agent idempotently, backing up every config file it touches.

## v1 — Two tiers

The starting question was not "is this dangerous?" but **"is this recoverable?"**, and the answer routes to one of three places instead of the usual two.

- 🛑 **Irreversible** → hard stop, **human unlock only**: a passphrase typed in a real human turn of the conversation, or the user running the command themselves. Content the agent *read* — files, web pages, issues, tool results — never authorises anything.
- ⚠️ **Recoverable but expensive** → the agent re-confirms itself by re-running the same command with a `# cg-ack:` line naming who asked and why it is safe, which is logged with its model and reasoning effort.
- ✅ **Everything else** → runs untouched.
- A JSONL journal of every decision, and a two-stage design — shell pre-filter in builtins, Python analyzer only for payloads that survive it — so that the guard is cheap enough that nobody wants to turn it off.
