# GitHub Workflow Proposal — DiceLab

Surveyed 2026-09-27 against the live repo (`laconicman/DiceLab`) and local
worktree. Every recommendation below is grounded in that survey — what's
already present, what's missing, and what the repo's actual shape rewards.

## What exists today

| Capability | State | Evidence |
|---|---|---|
| Tags | **None** | `git tag -l` empty across 13 merged milestones |
| Releases | **None** | `gh release list` empty |
| `.github/` | **Absent** — no templates, workflows, CODEOWNERS, dependabot | `ls .github/` → no such dir |
| Milestones | **0 on GitHub** — milestone tracking lives in `DiceLab/Documentation.docc/Roadmap.md` (M0–M9e) | `gh api .../milestones` → `[]` |
| Issues | **0 ever opened** — all planning rides in PR titles/bodies and Roadmap.md | `gh issue list --state all` empty |
| Labels | **GitHub defaults only** (bug, enhancement, documentation, …) | `gh label list` |
| Merge convention | **Merge commits**, branch deleted after each PR (`#1`–`#13` all `--merge`) | PR history + local branch hygiene |
| `deleteBranchOnMerge` | **`false`** — remote branches pruned manually (8 stale refs cleaned post-M9b) | repo settings API |
| `allow_auto_merge` | **`false`** | repo settings API |
| Branch protection / rulesets | **None** — `main` accepts direct pushes and force-push | `GET .../branches/main/protection` → 404 |
| CI | **None** — no Actions workflows; build+test run locally (`xcodegen` + `xcodebuild test`, 37 tests) | no `*.yml` outside `project.yml` |
| Review automation | **Devin Review via MCP** (not Actions), fed by `REVIEW.md`; `scripts/check_review_md.py` validates that file but is run manually | `REVIEW.md`, `scripts/` |
| License | **None** — public repo, `licenseInfo: null`; upstream lack of license recorded as TD-2 | repo API, TechDebt.md |
| Discussions / Wiki | Available but unused; Discussions off | repo settings API |

Notable repo-specific facts that shape the proposals:

- **Solo maintainer + AI pair**, milestone-driven (M-numbers), docs-as-source-of-truth
  (`Roadmap.md`, `TechDebt.md`, `Design.md`).
- **iOS app, no binary distribution** — no TestFlight/App Store pipeline; releases
  would be *checkpoints* (device-QA snapshots), not distribution artifacts.
- **xcodegen-generated `.xcodeproj`** — not committed; CI must run `xcodegen` first.
- **No package dependencies** — xcodegen is a dev tool; there is nothing for
  Dependabot/Renovate to watch.
- **Doc closeouts push straight to `main`** post-merge (e.g. `f2411f7` roadmap
  closeout) — branch protection must not break that habit or the habit must change.

---

## Proposals — cheapest first

### 1. Flip `deleteBranchOnMerge` (repo-agnostic) — 1 command, immediate payoff

Milestone PRs are merged with `--merge` and the remote branch lingers until
manually pruned (the M9b merge cleanup just deleted 8 stale tracking refs).
One API call ends that chore forever:

```bash
gh api repos/laconicman/DiceLab -X PATCH -F delete_branch_on_merge=true
```

Zero workflow change: `git branch -d` still works locally; remote cleanup is
now automatic. **Apply to every repo.**

### 2. Tag milestone merges (repo-specific convention, pattern is agnostic) — minutes

13 milestone merges have no recoverable anchor — `git log` archaeology is the
only way back to "what did M8a ship as?". Milestone tags are free and serve the
device-QA habit (checkout `m9c` → deploy to iPhone):

```bash
git tag m9c 0e72905          # anchor the merge commit
git push --tags
```

Two naming options — decision needed:

- **`m<N>` tags** (`m8a`, `m9b`, `m9c`): matches the Roadmap vocabulary already
  used in PR titles. Cheap, honest to the project's actual versioning (there
  is no version number).
- **Semver tags** (`v0.9.0`): only honest once the app has a version/marketing
  number (`MARKETING_VERSION` is unset today — default `1.0`). Adopting it now
  invents a numbering scheme the app doesn't have.

**Recommendation:** `m<N>` now; semver only if the app ever gains
`MARKETING_VERSION` or ships to TestFlight.

### 3. Releases per milestone via `gh release create --generate-notes` (repo-agnostic mechanism, repo-specific payoff)

PR titles are already clean and milestone-prefixed (`M9c: optional history
panel + sheet detents`) — `--generate-notes` produces a usable changelog
**today, for free**, off those merges:

```bash
gh release create m9c --generate-notes --title "M9c — history panel + editor fixes"
```

Payoff specific to this repo: **device validation**. The recurring "validate on
the iPhone" step gets a named artifact instead of "build whatever main happens
to be". Each milestone release is a fixed point the device runs against.

Optional upgrade once labels exist (proposal 4): `.github/release.yml` groups
generated notes by label instead of a flat PR list:

```yaml
# .github/release.yml
changelog:
  categories:
    - title: Engine work
      labels: ["engine:scenekit", "engine:realitykit"]
    - title: Model & shared
      labels: ["model"]
    - title: UI & editor
      labels: ["ui"]
    - title: Docs & hygiene
      labels: ["documentation", "hygiene"]
```

Costs one file; only pays off if milestone releases actually happen.

### 4. A small repo-specific label set — minutes, enables §3's grouping

Defaults (`bug`, `enhancement`, …) don't describe this repo's axes. The
meaningful split is *engine × layer*. A handful, not a taxonomy:

```bash
gh label create "engine:scenekit"  -d "SceneKit-side change"      -c 8b5cf6
gh label create "engine:realitykit" -d "RealityKit-side change"   -c 0e8a16
gh label create "model"            -d "Engine-free model layer"   -c bfdadc
gh label create "ui"               -d "SwiftUI shell / editor"    -c fbca04
gh label create "hygiene"          -d "Warnings, deprecation, cleanup" -c d4c5f9
gh label create "tech-debt"        -d "TD-n register item"        -c 5319e7
```

Labeling is a habit, not infrastructure: 30 seconds per PR, or `--label` on
`gh pr create`. Pays twice — release-notes grouping and searchable history
("what touched RealityKit physics? `gh pr list --label engine:realitykit`").

### 5. PR template (repo-agnostic) — one file, codifies an existing habit

The merged PRs already follow a Summary/Test-plan format. Codifying it in
`.github/pull_request_template.md` keeps the human-authored and agent-authored
PRs identical, and puts the doc-sync rule (REVIEW.md already enforces
`Design.md` updates) in the author's face rather than the reviewer's:

```markdown
## Summary
-

## Milestone
M__ — links to Roadmap.md section

## Test plan
- [ ] `xcodebuild test` green (37 tests, iOS Simulator)
- [ ] Visual check — SceneKit engine
- [ ] Visual check — RealityKit engine
- [ ] Design.md / TechDebt.md updated if decisions changed
```

Cost: one file. Payoff: the engine-pair checklist is a real trap — M9b's
RealityView wedge shipped *because* only one engine got checked. Making
"both engines" a checkbox is cheap insurance.

### 6. Protect `main` — decisions needed (see below), minutes to minutes+habit-change

`main` currently accepts force-push, deletion, and direct commits. The actual
exposure: the AI agent pushes doc closeouts to `main` routinely — a
`push --force` typo or a bad rebase is unrecoverable upstream. Options:

- **(a) Ruleset: block force-push + deletion only** — `gh api .../rulesets`
  or Settings → Rules. Keeps direct pushes (doc closeouts unaffected). Catches
  the catastrophic cases. **My pick for this repo.**
- **(b) Require PRs for everything** — cleanest hygiene, but turns every
  roadmap-closeout commit into a PR round-trip. On a solo repo that's ~5 extra
  minutes per milestone for marginal gain.
- **(c) Require PRs + allow maintainer bypass** — repo rulesets support
  bypass actors; adds config complexity for a team of one.

Minimal-ruleset config for (a):

```json
{ "name": "protect main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ] }
```

**Repo-specific caveat:** (b)/(c) only pay off if a second contributor appears.
Flag as team-scale.

### 7. CI: `xcodegen` + `xcodebuild test` on a macOS runner (repo-specific, medium cost)

The 37-test suite already exists and is deterministic — this is the one
infrastructure item worth its cost even solo. Sketch:

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
  push: { branches: [main] }
jobs:
  test:
    runs-on: macos-26            # Xcode 26 per README; verify image's Xcode
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: xcodegen generate
      - run: >
          xcodebuild -project DiceLab.xcodeproj -scheme DiceLab
          -destination 'platform=iOS Simulator,name=iPhone 17'
          test
```

Honest costs for this repo:

- **Setup:** ~20–40 min + inevitable runner flakiness (simulator boots, Xcode
  version drift between `macos-*` images and the README's Xcode 26 requirement —
  add a `- run: xcodebuild -version` step and `xcodes` if pinning is needed).
- **Free:** Actions minutes are unmetered on public repos.
- **What it can't test:** device-only paths (haptics, audio session, real
  physics timing — TD-6 stays manual either way), and the Devin-Review workflow
  stays MCP-side; CI doesn't replace it.
- **Ordering:** lands *before* auto-merge makes sense; pairs with §6(b) if
  PR-required protection is ever adopted (status check becomes the gate).

### 8. Auto-merge (repo-agnostic mechanism, value here is conditional) — 1 command, but only after CI

```bash
gh api repos/laconicman/DiceLab -X PATCH -F allow_auto_merge=true
# then per PR: gh pr merge <N> --merge --auto
```

Solo-payoff is small but real: "queue the merge once CI greens" instead of
polling. **Without CI there is nothing to wait on** — the flag does nothing.
Enable when §7 lands; skip until then.

### 9. Issues + milestones — decision needed; currently duplicated, not missing

This is the one category where "add the platform feature" may be *wrong*.
`Roadmap.md` is already the milestone tracker and `TechDebt.md` the debt
register — both live in the repo, versioned with the code they describe.
GitHub milestones/issues would duplicate that, and on a solo repo the
synchronization tax lands on one person.

Options:

- **(a) Keep docs canonical; use GitHub milestones as a *display* layer** —
  create `M9d`, `M9e`… milestones, attach PRs to them. Zero bookkeeping
  (one dropdown on `gh pr create --milestone`), payoff: milestone pages show
  progress + releases can filter by milestone. Light duplication.
- **(b) Migrate to issues/milestones as canonical** — pays only if the repo
  gains external contributors or the user wants web-side planning. Adds an
  issues habit the project has demonstrably not needed (0 issues in 13 PRs).
- **(c) Status quo** — Roadmap.md remains the only tracker. Also fine.

**Recommendation:** (a) if anything — milestone-on-PR is nearly free and
feeds release notes. (b) is team-scale.

Issue templates: defer entirely — they matter when someone other than the
author files bugs. `isBlankIssuesEnabled` already permits ad-hoc issues.

---

## Explicitly skipped — team-scale or inapplicable here

| Feature | Why it doesn't pay here |
|---|---|
| **CODEOWNERS** | Solo repo; review routing is meaningless with one maintainer. |
| **Dependabot / Renovate** | No dependency manifests — xcodegen is a dev tool, not an SPM/CocoaPods dep. |
| **Issue templates / forms** | Zero external reporters; blank issues already allowed. |
| **GitHub Projects** | Roadmap.md already does this; a board duplicates it. Revisit if collaborating. |
| **Discussions** | No community to discuss with; off is correct. |
| **Required status checks on `main`** | Needs CI first (§7) and breaks the direct doc-closeout habit (§6). |
| **Signed commits / required signing** | Value is contributor-authenticity at scale; solo repo gains little. Local signing is still good hygiene, unrelated to repo settings. |
| **License / `LICENSE` file** | Not a workflow feature, but worth naming: public repo, `licenseInfo: null`, TD-2 documents the upstream-no-license entanglement. DiceLab is fresh-authored ("no derived code verbatim") — the author *can* license it (MIT/CC0). Decision belongs to the user; it affects how "releaseable" the releases are. |
| **SECURITY.md** | Public repo; worth a 5-line file if issues ever open. Low priority. |

---

## Rollout

**Now (total ~10 min, all reversible):**

```bash
gh api repos/laconicman/DiceLab -X PATCH -F delete_branch_on_merge=true   # §1
git tag m9c 0e72905 && git push --tags                                   # §2
gh release create m9c --generate-notes --title "M9c — history panel + editor fixes"  # §3
# labels via §4 commands
# .github/pull_request_template.md via §5
# main ruleset (a) via §6
```

**Next milestone (M9d lands):** tag `m9d`, release it, label the PR, confirm
the template renders. That's the whole habit — everything in "Now" paid for.

**After CI lands (§7):** enable `allow_auto_merge` (§8), optionally move §6
from ruleset-(a) to a required-checks model if direct-pushing to main starts
feeling wrong.

**Defer until non-solo:** milestones-as-display (§9a is optional anyway),
issue templates, Projects, CODEOWNERS, required reviews.

## Decisions — resolved 2026-09-27

1. **Tag scheme:** semver/`MARKETING_VERSION`, not `m<N>`. Mapping
   `v<major milestone>.<sub-letter index>` (a=0): M8a→`v0.8.0` … M9c→`v0.9.2`.
   Retroactive tags + releases published; `MARKETING_VERSION` added to
   `project.yml` and tracks the latest tag.
2. **Branch protection: deferred entirely.** Direct pushes to `main` stay —
   avoiding a PR + paid review round-trip on low-risk closeouts is worth more
   than the protection. Revisit if force-push becomes a real risk.
3. **Milestones:** accepted as display layer — `M9d`, `M9e` created on GitHub;
   attach via `gh pr create --milestone`. Roadmap.md stays canonical.
4. **License: Apache-2.0** — copyright held by `laconicman` (public git
   identity). Resolves the "releases mean something legally" question;
   TD-2's upstream debt is unaffected.
5. **Auto-merge:** flag enabled (`allow_auto_merge=true`); habit adoption
   deferred until CI proves useful.
6. **CI:** adopted — `.github/workflows/ci.yml` on `macos-26` (Xcode 26.6
   default ≥ README's Xcode 26 requirement): `check_review_md.py` →
   `xcodegen generate` → `xcodebuild test` on an iOS Simulator picked at
   runtime.

### Applied (2026-09-27)

- `delete_branch_on_merge=true`, `allow_auto_merge=true` (repo API)
- Labels: `engine:scenekit`, `engine:realitykit`, `model`, `ui`, `hygiene`, `tech-debt`
- Tags `v0.8.0`–`v0.9.2` on milestone merge commits; releases with
  `--generate-notes` for each
- `.github/`: `workflows/ci.yml`, `pull_request_template.md`, `release.yml`
- `LICENSE` (Apache-2.0), README license/versioning sections, `project.yml`
  `MARKETING_VERSION`, TechDebt TD-2 note
