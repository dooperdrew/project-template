# AGENTS.md — Mandatory Operating Guidelines for AI Agents

> You are working on **{{PROJECT_NAME}}** ({{REPO_URL}}).
> These rules are binding for every agent and every conversation in this repository.

## 1. Mission
{{ONE_PARAGRAPH_MISSION}}

## 2. Mandatory reading order (before any implementation)
1. `docs/01-vision.md`: problem, principles, non-goals
2. `docs/02-requirements.md`: requirement IDs (F…, NFR-…) and budgets
3. `docs/03-architecture.md`: components, boundaries, key designs
4. `docs/04-ux.md`: UI/UX spec (if present)
5. `docs/05-roadmap.md`: **the single source of truth for tasks**
6. `docs/06-qa-and-validation.md`: verification matrices, NFR measurements, and empirical testing
7. `docs/m0-spike-findings.md`: verified ground truth from M0 spikes. Don't contradict or guess beyond it.
8. `docs/07-ux-and-improvements.md`: UX polish, onboarding flows, and product evolution backlog
9. `docs/08-community-and-growth-strategy.md`: distribution channels (WinGet, Scoop) and crowdsourced QA
10. `docs/multi-agent-methodology.md`: parallel worker orchestration, Copilot cloud integration, and reporting templates
11. `docs/decisions/`: ADRs. Changing a decision requires a new ADR.
12. `docs/lessons-learned.md`, `docs/retrospective.md`, and `CHANGELOG.md`: history, pitfalls to avoid, and past retrospective findings

## 3. Continuous Learning & Self-Correction Rule
Whenever the user corrects, redirects, or clarifies a requirement:
- **Do not silently apply the change.**
- You MUST explicitly formulate the takeaway as a rule and propose writing it into `docs/lessons-learned.md` (or `AGENTS.md` if binding).
- This ensures that lessons learned in one chat session immediately persist for all subsequent sessions.

## 4. Roles (multi-agent)
- **Lead agent (sole committer):** Antigravity interactive session. The **only** entity allowed to `git commit`, `git push`, tag, release, merge PRs, or close issues. Plans parallel work, creates bounded tasks in GitHub Issues, reviews worker/Copilot output, runs the verification gate, and syncs docs.
- **Worker subagents (`project-worker`):** Autonomous local subagents working in isolated branch workspaces (`Workspace: "branch"`) on **disjoint files**. **Forbidden:** `git commit`, `git push`, `git checkout main`, closing issues. They deliver results via the completion report in §8.
- **Cloud Worker agent (GitHub Copilot Agent):** Operates asynchronously in GitHub Cloud or IDE on bounded issues created via `.github/ISSUE_TEMPLATE/agent_task.yml`. Bound by `.github/copilot-instructions.md`. Delivers work exclusively via **Draft Pull Requests** on `task/<issue-id>-<description>`. **Forbidden:** pushing directly to `main`, merging PRs, or closing issues.
- Worker role names follow `<Tier>-<Domain>-<Milestone>` (e.g. `T1-Core-M1`).

## 5. Complexity tiers & model selection
| Tier | Scope | Model |
|---|---|---|
| T1 Lean | pure logic, schemas, tests, i18n, docs, scripts | `flash_lite` / `flash` |
| T2 Moderate | UI, IPC, standard platform APIs | `flash` / `pro` |
| T3 Critical | {{CRITICAL_AREAS e.g. concurrency, security, hot paths, hardware}} | `pro` / `inherit` |

Fallback order: `inherit` → `pro` → `flash` → `flash_lite`. Every fallback **must** be logged in
`docs/model-fallback-log.md`, and a review task for it goes into the hardening milestone.

## 6. Task lifecycle
**Before:** find the task in the roadmap, restate the task + tier + target files + acceptance criteria, and check that `git status` is clean. Ensure toolchain PATH is initialized.
**During:** respect the hard rules (§7). Unverified assumptions are marked 🔬 and probed, not guessed. Decouple headless tests from physical QA (keep manual QA as Pending).
**Draft PR Review (for Copilot / Worker tasks):** Lead pulls branch locally, runs the full verification gate, inspects diff for ownership and safety invariants, refines if needed, merges to `main`, and closes the corresponding issue.
**Gate (must pass before finishing):**
```bash
{{VERIFICATION_GATE_COMMANDS}}
# Examples:
# Rust: cargo fmt -- --check; cargo clippy -D warnings; cargo test --workspace; cargo build --release
# TypeScript / Web: npm run lint; npm test; npm run build
# Python: ruff check .; ruff format --check; pytest; uv build
```
**After (lead only):** tick the roadmap box (date + commit), add a CHANGELOG entry, update docs/ADRs if the design changed,
add any lesson to `docs/lessons-learned.md`, commit (`M<x>.<y>: <summary>`), push, and update the issue.

## 7. Hard rules
{{PROJECT_HARD_RULES — performance budgets, safety constraints, forbidden techniques, security rules}}
- **GitHub Governance (Milestones, Issues & Releases):** Every roadmap milestone (`M0`..`Mn`) MUST have a corresponding GitHub Milestone and tracked GitHub Issues. Completed tasks close their issue with a commit/release reference; pending hardware/manual QA stays open in its milestone. Every release MUST attach a pre-built downloadable bundle (`.zip` / installer) on GitHub Releases via `gh release create` (or `.github/workflows/release.yml`) even while physical hardware QA remains `Pending`.
- **Single-Binary & Setup Ergonomics:** Release bundles must NEVER contain multiple confusing executables. Distribute a single standalone installer (`<AppName>-Setup.exe`) and a clean portable archive containing only the primary executable, assets, and uninstaller. Launching the main executable directly must always open settings/main UI without blocking or erroring.
- **Documentation Parity Rule:** Whenever packaging, installation, or distribution capabilities are added or updated, `README.md` (`## 📥 Installation & Distribution Options`) and `docs/user-guide.md` MUST be updated in the same commit to document all distribution channels (WinGet, Scoop, Setup Wizard, Portable ZIP) and uninstallation steps.
- **Claims follow evidence:** Never claim a test, benchmark, or QA item passed without having run it. Hardware/manual QA stays `Pending` until the user confirms.
- **Keep claims in docs factual:** Avoid marketing language ("pioneering", "zero bugs") in technical specs while QA is pending.
- **Environment resiliency:** Never assume standard toolchains are in `$PATH`. Prepend `$env:USERPROFILE\.cargo\bin`, `$env:APPDATA\npm`, or relevant toolchain paths in PowerShell commands to guard against PATH omissions.
- **Test concurrency:** Tests touching global OS resources (pipes, sockets, registry, hooks) must use unique names and timeout protection to prevent test hangs.
- **Windows / PowerShell hygiene:** When writing files from PowerShell, force UTF-8 without BOM (`[System.IO.File]::WriteAllText(..., [System.Text.UTF8Encoding]::new($false))` or `Set-Content -Encoding utf8`) and set `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` before capturing external CLI stdout (`gh`, `git`). Prefer dedicated file-writing tools over shell redirection. Use `;` rather than `&&` on Windows PowerShell 5. Avoid unconstrained recursive searches over dependency caches (`node_modules`, `target`, `.venv`).
- User-facing strings go through i18n files. Don't hardcode UI text.
- Files are UTF-8. Never commit build artifacts (e.g. `dist/`, `target/`); releases go to GitHub Releases.

## 8. Worker completion report (required format)
```markdown
### WORKER COMPLETION REPORT: <Role>
- Task: <ID + description>
- Model used: <model> (fallback? yes/no + reason)
- Files created/modified: <list>
- Verification: <each gate command: PASS/FAIL, test counts>
- Decisions & rationale: <numbered>
- Open issues / risks / follow-ups: <list>
```

## 9. Escalation
If reality contradicts the docs (tests, hardware, external API behaviour): **stop**, report the evidence to the user,
propose a probe, and update the docs only after the user agrees.

## 10. Build & run
{{BUILD_RUN_COMMANDS}}
```bash
# Examples:
# Native Desktop (Rust): cargo run --bin {{PROJECT_NAME}}
# Fullstack Web (Node/Next.js): npm run dev
# CLI Utility: cargo run --bin {{PROJECT_NAME}}-cli -- --help
```
