# GitHub Workflow Proposal — DiceLab

*Second survey — 2026-09-28.* The 2026-09-27 proposal (below, §History) was
adopted and shipped: CI, labels, milestones-as-display, semver tags, releases,
`release.yml`, PR template, `delete_branch_on_merge`, `allow_auto_merge`,
Apache-2.0. This revision re-surveys the repo *after* that adoption and asks
what's still unused — not what was missing then.

## What exists today (verified live)

| Capability | State | Evidence |
|---|---|---|
| Tags | **8 annotated tags** `v0.8.0`–`v0.9.4`, each pointing at its closeout merge carrying the `MARKETING_VERSION` bump | `git tag -l`, `git show v0.9.4` → `c0e4650` |
| Releases | **8 GitHub releases**, hand-authored titles ("M9e: localization preparation"), generated notes | `gh release list` |
| `.github/` | `workflows/ci.yml`, `release.yml` (label→changelog categories), `pull_request_template.md` | `ls .github/` |
| CI | **Runs**: `macos-26`, `check_review_md.py` → `xcodegen generate` → `xcodebuild test` on a runtime-picked iPhone sim. Triggers: PRs + pushes to `main` | `.github/workflows/ci.yml` |
| Milestones | 2 on GitHub, **both `open` with 0 open issues** — M9d and M9e finished but never closed | `gh api .../milestones` |
| Labels | Custom set in use — `engine:scenekit`, `engine:realitykit`, `model`, `ui`, `hygiene`, `tech-debt` + defaults; applied to PRs #14,#15,#17,#19,#20 but **not** closeouts #16,#18 | `gh label list`, PR inspection |
| Merge convention | Merge commits exclusively (#1–#20); `squashMergeAllowed`, `rebaseMergeAllowed` also enabled but unused | PR history |
| `delete_branch_on_merge` | **`true`** | repo API |
| `allow_auto_merge` | **`true`** — enabled 2026-09-27, **never used** (all PRs merged manually after CI) | repo API, PR history |
| Branch protection / rulesets | **None** — `main` accepts direct pushes and force-push; the 2026-09-27 decision deferred this deliberately | `GET .../branches/main/protection` → 404, rulesets `[]` |
| Issues | **0 ever opened** — planning rides in Roadmap.md + PR bodies | `gh issue list --state all` |
| Issue templates | None | `ls .github/ISSUE_TEMPLATE` → absent |
| Dependabot | None; only external dep is `actions/checkout@v5` | `.github/dependabot.yml` absent |
| License | `LICENSE` Apache-2.0 added 2026-09-27 | repo |
| `SECURITY.md` / `CONTRIBUTING.md` / `CODEOWNERS` | Absent | `ls` |
| Discussions / Projects / Wiki | Discussions off (correct); Projects+Wiki on, unused | repo API |

Facts that shape the proposals:

- **Solo maintainer, milestone-driven.** Docs-as-source-of-truth
  (`Roadmap.md`, `TechDebt.md`, `Design.md`); PR template enforces the
  doc-sync + dual-engine checklist.
- **CI is green and real now** — the reason auto-merge/protection were
  deferred ("nothing to wait on") no longer holds.
- **Releases are checkpoints, not distribution** — no TestFlight/App Store
  pipeline; a release anchors "build this on the iPhone," nothing more.
- **Tag↔version contract is manual**: a tag must point at a closeout commit
  whose `MARKETING_VERSION` was already bumped (v0.9.4 does). Nothing enforces
  it — a tag on the wrong commit ships a release claiming a wrong version.
- **Closeout commits still push straight to `main`** by design — the
  2026-09-27 decision that deferred branch protection.

---

## Proposals — cheapest first

### 1. Close milestones at closeout (repo-agnostic habit) — 10 seconds, do now

M9d and M9e show `open` on GitHub with zero open items — they read as
unfinished forever. The closeout PR already bumps the version and updates
Roadmap.md; closing the GitHub milestone is one API call in the same step:

```bash
gh api repos/laconicman/DiceLab/milestones/1 -X PATCH -f state=closed   # M9d
gh api repos/laconicman/DiceLab/milestones/2 -X PATCH -f state=closed   # M9e
```

Fold it into the closeout convention (the PR template's `## Milestone`
field already names the milestone — the closer just runs the call).

### 2. Label closeout PRs (repo-specific convention) — 30 s/PR

`#16` and `#18` carry no labels, so `.github/release.yml` files their
changes under "Other" in generated notes. Label them `hygiene` (they're
version bumps + doc moves — exactly what `hygiene` describes) or create a
`release` label mapped to a "Releases" changelog category. Pick one —
either is a habit, not infrastructure.

### 3. Use `--auto` on merges (repo-agnostic mechanism, already enabled) — 0 setup

`allow_auto_merge=true` since 2026-09-27 and CI exists — every ingredient
is in place; the flag has simply never been used:

```bash
gh pr merge 21 --merge --auto   # merges itself the moment CI greens
```

Payoff solo: fire-and-forget instead of polling the check. Note the
subtlety *without* required-status-checks protection: `--auto` waits for
the checks that exist on the PR, which is exactly CI here. If CI is ever
skipped on a PR (`[skip ci]` paths, docs-only changes still run the full
workflow — fine), auto-merge lands immediately — acceptable at this scale.

### 4. Release on tag push + version assert (repo-specific payoff) — ~20 lines of YAML, removes a manual step

Today: closeout merge → `git tag -a vX.Y.Z` → `git push --tags` →
`gh release create --generate-notes --title "M.."`. The middle two steps
stay human (tagging is a decision); the last can be a workflow:

```yaml
# .github/workflows/release.yml
name: Release
on:
  push:
    tags: ["v*"]
jobs:
  release:
    runs-on: macos-26
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v5
      - name: Assert MARKETING_VERSION matches tag
        run: |
          TAG=${GITHUB_REF_NAME#v}
          VER=$(sed -n 's/.*MARKETING_VERSION: *"\(.*\)".*/\1/p' project.yml)
          [ "$VER" = "$TAG" ] || { echo "tag $TAG ≠ MARKETING_VERSION $VER"; exit 1; }
      - name: Create release
        run: gh release create "$GITHUB_REF_NAME" --generate-notes \
             --title "$(git tag -l --format='%(contents:subject)' "$GITHUB_REF_NAME")"
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Two wins in one file:

- **The assert enforces the tag↔version contract** — a tag on a commit
  that didn't bump `MARKETING_VERSION` fails loudly instead of publishing
  a release that claims a wrong version. This is the exact trap the
  closeout convention was built to avoid; today it relies on memory.
- **The release title comes free** — tags are annotated with the milestone
  title (`v0.9.4`'s subject is "M9e — localization preparation"), so
  `--generate-notes` + the tag's own subject reproduce today's hand-typed
  titles exactly.

Tradeoff, stated not chosen: a workflow means tags are now *published*
artifacts — a typo'd tag push creates a public release that needs deleting.
Mitigation: the version assert catches most typos (a `v0.95` tag fails
against `0.9.5`); `gh release delete` cleans up the rest.

### 5. Branch protection revisited (decision needed — context changed since the deferral)

The 2026-09-27 call was correct *then*: no CI existed, and closeouts push
directly to `main`. Two things changed: CI runs on PRs now, and every PR
merge in the last 7 went through green CI anyway. Re-stating the options
against today's facts:

- **(a) Keep deferred** — direct closeout pushes stay frictionless. The
  honest risk remains a `push --force`/rebase typo on `main` — rare, but
  unrecoverable *remotely* (the local clone always has the objects; GitHub
  just loses the ref and the PR linkage).
- **(b) Narrow ruleset: block force-push + deletion only** — zero habit
  change, direct pushes unaffected, kills the two catastrophic cases.
  Ruleset config:
  ```json
  { "name": "protect main", "target": "branch", "enforcement": "active",
    "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
    "rules": [ { "type": "non_fast_forward" }, { "type": "deletion" } ] }
  ```
  Apply via `gh api repos/laconicman/DiceLab/rulesets -X POST --input ruleset.json`.
- **(c) Require PRs + the CI check** — converts closeouts into PRs; the
  cost the original deferral was avoiding. Still solo-scale-poor.

**Recommendation shifted since v1:** (b). It didn't exist as an option
then in this doc's framing (the choice was PRs-or-nothing); it now reads
as the obviously-correct middle: the catastrophic surface closes, the
closeout habit survives untouched. (a) remains defensible — the risk is
theoretical — but (b) costs nothing now.

### 6. Dependabot for GitHub Actions (repo-agnostic, tiny) — one file

The repo's only external dependency is `actions/checkout@v5`. A monthly
(near-silent) bot bump keeps it from rotting:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule: { interval: "monthly" }
```

Payoff is small but the cost is one file. Marginal either way — list as
optional.

### 7. Disable unused merge methods (repo-agnostic, cosmetic) — optional

Squash and rebase are enabled but never used (20/20 merge commits). Each
enabled method adds a dropdown option on the merge button — a fat-finger
target that rewrites a PR's history shape. One API call prunes the surface:

```bash
gh api repos/laconicman/DiceLab -X PATCH \
  -F allow_squash_merge=false -F allow_rebase_merge=false
```

Purely cosmetic — keep or drop, no real stakes.

### 8. Small hygiene files (repo-agnostic) — minutes each, low priority

- **`SECURITY.md`** — 5 lines ("report via issues/Discussions-off → email").
  Standard public-repo hygiene; not urgent for a dice app with no attack
  surface, costs nothing.
- **`CONTRIBUTING.md`** — the one thing it would say is "run `xcodegen`
  after cloning or editing `project.yml`" — README already says it. The
  stale-generated-project trap bit locally this week (a `.xcodeproj`
  generated before a `bundleIdPrefix` change kept installing the old ID).
  A pointer file helps nobody the README didn't already reach — **skip
  unless the README note grows into a real contributor guide.**

---

## Reaffirmed deferrals — re-checked, still team-scale or inapplicable

| Feature | Why it still doesn't pay |
|---|---|
| Issues as canonical tracker | Still 0 issues ever; Roadmap.md + TechDebt.md in-repo remain the working system. The v1 "(a) milestones as display" decision already captured the useful part. |
| Issue templates / forms | No external reporters; blank issues allowed if one appears. |
| CODEOWNERS | One maintainer; review routing is meaningless. |
| Required reviews | Can't review your own PR; Devin Review via MCP is the de-facto reviewer and already runs per-PR. |
| GitHub Projects | Roadmap.md is the board; a second board duplicates it. |
| Discussions | Off is correct — no community. |
| Wiki | Enabled-but-unused; could be turned off (`-F has_wiki=false`) to reduce surface — cosmetic. |
| Signed commits / required signing | Contributor-authenticity is the payoff; solo repo gains little. |
| SwiftLint in CI | Optional; this codebase's conventions are comment-driven, not lint-driven. Revisit if style drift becomes visible. |
| Device/sim split in CI | CI stays simulator-only — haptics, audio session, real physics timing can't run there (TD-6 stays manual either way). The PR template's dual-engine visual checklist is the guard. |

---

## Rollout

**Now (~15 min, all reversible):**

```bash
gh api repos/laconicman/DiceLab/milestones/1 -X PATCH -f state=closed   # §1
gh api repos/laconicman/DiceLab/milestones/2 -X PATCH -f state=closed   # §1
gh label list                                                          # §2: confirm `hygiene` exists
# pick §5(b) or (a); if (b):
gh api repos/laconicman/DiceLab/rulesets -X POST --input ruleset.json   # §5(b)
```

**Next milestone (habits, not setup):**

- `gh pr create --milestone ...` (existing) + `--label hygiene` on closeouts (§2)
- `gh pr merge N --merge --auto` once CI is seen green before (§3)
- Commit `.github/workflows/release.yml` + `dependabot.yml` (§4, §6) — then
  the *following* closeout tag exercises the release automation end-to-end

**Watch for breakage:** the first tag-pushed release asserts
`MARKETING_VERSION` — `project.yml` stores it as `MARKETING_VERSION: "X.Y.Z"`,
which the sed line matches verbatim today; if that line ever moves to
plist-style `=` syntax, update the pattern.

**Defer until non-solo:** required reviews, CODEOWNERS, issue templates,
Projects, mandatory PRs for closeouts.

---

## History — the 2026-09-27 proposal and its resolutions

*(Verbatim record — superseded states marked ↷.)*

v1 surveyed an empty `.github/`, no tags, no CI, default labels, and
proposed: `deleteBranchOnMerge` ↷ **adopted**, milestone tags ↷ adopted as
semver `v*` + `MARKETING_VERSION`, `gh release create --generate-notes`
↷ adopted per milestone, custom label set ↷ adopted, PR template ↷
adopted, `.github/release.yml` grouping ↷ adopted, narrow-branch-protection
ruleset ↷ **deferred** (revisited in §5), CI ↷ adopted (`macos-26`,
validator + xcodegen + sim tests), `allow_auto_merge` ↷ adopted-but-unused
(revisited in §3), milestones-as-display ↷ adopted, issues/templates/
Projects/CODEOWNERS ↷ deferred (still deferred above), Apache-2.0 license
↷ adopted.
