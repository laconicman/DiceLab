# DiceLab — agent notes

- `DiceLab.xcodeproj/project.xcproj` is the committed source of truth (Xcode
  27.2 JSON format, JSON5) — edit it in Xcode, with `xcrun xcodeproj`, or via
  `xcrun xcprojformatter`. Both source folders are filesystem-synchronized,
  so new files need no project edits.
- GitHub milestones mirror the docs' M-numbering: every PR gets the milestone for
  the M-batch it belongs to, and the milestone must exist — create it if missing.
  `gh pr edit --milestone` only sees *open* milestones; assign by number instead:
  `gh api repos/laconicman/DiceLab/issues/<PR> -X PATCH -F milestone=<n>`.
- Simulator-only build/test:
  `xcodebuild -project DiceLab.xcodeproj -scheme DiceLab -destination 'platform=iOS Simulator,name=<booted iPhone>' test`.
- Commits: imperative ~60-char subjects, no conventional prefixes, no AI
  attribution or Co-Authored-By trailers; author/committer
  `laconicman <laconicman@icloud.com>`.
- `REVIEW.md` is authoritative for reviewer expectations; `TechDebt.md` /
  `Design.md` / `Roadmap.md` under `DiceLab/Documentation.docc/` record decisions.
