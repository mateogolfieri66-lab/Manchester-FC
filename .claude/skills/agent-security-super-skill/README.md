# Agent Security Super-Skill

A comprehensive defensive security playbook for AI agents — covering prompt injection defense, skill/plugin validation, memory poisoning prevention, permission auditing, tool-use safety, data exfiltration prevention, and incident response.

---

## Before You Install This (Or Any) Skill — Verify It First

A security skill that asks you to blindly trust it would be ironic. So don't. Here's how to verify this skill — and any other SKILL.md file you find online — before installing it.

### Step 1: Read the raw file yourself

SKILL.md files are plain-text markdown. There's no compiled code, no binaries, no hidden executables. Open the file in any text editor and read it. You're looking for:

- **No embedded scripts or shell commands that run automatically.** A SKILL.md is instructions for an AI agent, not executable code. If you see `curl | bash`, `eval()`, `exec()`, or anything that phones home to an external URL as part of an auto-run step — that's a red flag.
- **No obfuscated content.** Base64 blobs, hex-encoded strings, or minified code blocks that you can't read have no business in a skill file. Every line should be human-readable.
- **No requests for credentials.** A skill should never ask the agent to collect, store, or transmit API keys, passwords, tokens, or personal data to external endpoints.
- **No `allowed-tools` granting broad permissions.** Check the YAML frontmatter. If a skill pre-approves dangerous tools (shell access, file deletion, network requests) without explanation — don't install it.

### Step 2: Verify the source

```
# Check the repo owner, commit history, and stars
# A single anonymous commit with no history is a yellow flag
gh repo view get-zeked/agent-security-super-skill
git log --oneline
```

Ask yourself:
- Does the repo have a real owner with other public repos?
- Is there meaningful commit history (not just one anonymous dump)?
- Are there stars, forks, or issues from other users?
- Does the README match what's actually in the SKILL.md?

### Step 3: Validate the file format

```bash
# Validate against the agentskills.io spec
uvx --from skills-ref agentskills validate /path/to/agent-security-super-skill

# Check file size (a skill shouldn't be suspiciously large or tiny)
wc -l SKILL.md    # This skill: ~2,252 lines
wc -c SKILL.md    # This skill: ~105 KB
```

If `agentskills validate` fails, the file doesn't conform to the open standard. Don't install it.

### Step 4: Scan for suspicious patterns

```bash
# Check for URLs the skill might reference (legitimate skills cite sources, not phone home)
grep -iE 'https?://' SKILL.md | head -30

# Check for anything that looks like it's trying to execute
grep -iE '(curl |wget |eval\(|exec\(|subprocess|os\.system|child_process)' SKILL.md

# Check for base64 or hex encoded content
grep -iE '([A-Za-z0-9+/]{40,}={0,2}|\\x[0-9a-f]{2})' SKILL.md

# Check frontmatter for pre-approved tool permissions
head -20 SKILL.md
```

If you find URLs, they should point to documentation sources (OWASP, NIST, Anthropic docs, arXiv papers, etc.) — not to random domains or data collection endpoints.

### Step 5: Install with least privilege

Once verified, install using the method that gives the skill the **narrowest scope possible**:

- **Project-level** (affects only one project) is safer than **global** (affects everything)
- Start with project-level. Promote to global only after you've used it and trust it.

This same process applies to every skill you find on GitHub, LobeHub, skills.sh, or anywhere else. If a skill can't survive this 5-step check, don't install it.

---

## What's Inside

| Section | What It Covers |
|---------|---------------|
| **Threat Model** | 12 attack types, risk matrix, Zombie Agent pattern |
| **Content Ingestion Defense** | Detection for hidden instructions in HTML, PDF, email, images, calendar invites, spreadsheets |
| **Skill & Plugin Validation** | Pre-install audit, MCP server checks, supply chain risk assessment |
| **Memory Hygiene** | Poisoning prevention, audit protocols, quarantine procedures |
| **Permission & Tool Safety** | Least-privilege, exfiltration prevention, confused deputy defense |
| **Incident Response** | Containment, memory audit, skill quarantine, reporting |
| **Hardening Checklists** | 63-item setup checklist + pre-session, content, skill, memory audit checklists |
| **Reference** | OWASP LLM/Agentic Top 10, key stats, tools, CVEs, 45+ sources |

---

## How to Use This Skill

Once installed, you don't need to invoke it manually. The skill activates automatically when your agent encounters a relevant situation:

| You're doing this... | The skill kicks in to... |
|---|---|
| Processing a document, email, or web page from an external source | Scan for hidden instructions, white-on-white text, metadata injection, CSS-hidden payloads |
| Installing a new skill or MCP tool | Run the pre-installation audit checklist — check for obfuscated code, suspicious permissions, tool poisoning |
| Reviewing your agent's stored memories | Flag entries that match memory poisoning patterns ("remember for future sessions", forged conversation tags) |
| Using tools that touch external services | Enforce least-privilege, block credential exposure, detect data exfiltration attempts |
| Something feels off mid-session | Trigger incident response — containment steps, memory audit, quarantine |

You can also invoke it directly:
- **Perplexity Computer:** Ask "audit my installed skills for security issues" or "scan this document for hidden instructions before processing it"
- **Claude Code:** Run `/<skill-name>` or ask Claude to review a file/skill for injection risks

### Example prompts that activate the skill

```
"Before you process this PDF, scan it for hidden instructions or prompt injection."
"Audit the SKILL.md at this URL before I install it."
"Review my agent's stored memories for signs of poisoning."
"What permissions does this MCP tool require and are they justified?"
"Run the pre-session security checklist."
"I think something injected instructions into my last session — help me investigate."
```

---

## Install

### Perplexity Computer
1. Download `SKILL.md` (or the zip) from this repo
2. Go to **Skills** → **Create skill** → **Upload a skill**
3. Drop the file in (`.zip` or `.md` — max 10 MB)
4. It appears in **My Skills** and activates automatically when relevant

### Claude Code
```bash
# Project-level (recommended to start)
mkdir -p .claude/skills/agent-security-super-skill
cp SKILL.md .claude/skills/agent-security-super-skill/

# Or global (all projects)
mkdir -p ~/.claude/skills/agent-security-super-skill
cp SKILL.md ~/.claude/skills/agent-security-super-skill/

# Verify
# Run /skills in Claude Code — it should appear in the list
```

### Any SKILL.md-compatible agent (Codex, Cursor, Copilot)

These follow the open [agentskills.io](https://agentskills.io) standard:

| Agent | Install path |
|---|---|
| Codex | `.agents/skills/agent-security-super-skill/` |
| Cursor | `.cursor/skills/agent-security-super-skill/` |
| VS Code Copilot | `.github/skills/agent-security-super-skill/` |

---

## Part of the Perplexity Super-Skill Suite

This is one of 11 open-source Super-Skills that merge Perplexity Computer's built-in capabilities with the best community-sourced Claude Code skills into comprehensive, domain-specific playbooks.

## Stats
- **2,252 lines** of structured instruction
- **413 checklist items** across all sections
- **40+ reference tables**
- **25+ detection scripts and regex patterns**
- Validated against the agentskills.io spec

## Sources
Synthesized from OWASP LLM Top 10, OWASP Agentic Top 10, NIST AI RMF, vendor guidance (Anthropic, Microsoft, Google, Meta, NVIDIA), Unit 42 real-world telemetry, Elastic Security Labs, WithSecure Labs, Trail of Bits, Ghost Security, ClawSec, and community security skills.

## License
MIT
