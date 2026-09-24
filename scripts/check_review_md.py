#!/usr/bin/env python3
"""Validate REVIEW.md: referenced paths exist, rules are anchored and directive.

Usage: python3 scripts/check_review_md.py REVIEW.md --repo-root .
Exit 1 on errors; warnings don't fail.
"""
import re
import sys
from pathlib import Path

DIRECTIVES = {
    "flag", "reject", "require", "prefer", "avoid", "keep", "ensure",
    "verify", "check", "allow", "ignore", "use", "insist",
}
LONG_BULLET = 160
PATHISH = re.compile(r"[`‘']([^`']+)[`’]")


def looks_like_path(token: str) -> bool:
    return "/" in token or token.endswith(
        (".swift", ".md", ".yml", ".json", ".png", ".plist")
    )


def main() -> int:
    args = sys.argv[1:]
    review = Path(args[0])
    root = Path(args[args.index("--repo-root") + 1]) if "--repo-root" in args else Path(".")
    errors = warnings = 0

    # A bullet is the `- `/`* ` line plus its indented continuation lines —
    # paths and verbs may sit on any of them.
    bullets: list[tuple[int, str]] = []
    for lineno, raw in enumerate(review.read_text().splitlines(), 1):
        line = raw.strip()
        if line.startswith(("- ", "* ")):
            bullets.append((lineno, line[2:]))
        elif bullets and raw.startswith(" ") and line:
            bullets[-1] = (bullets[-1][0], bullets[-1][1] + " " + line)

    for lineno, body in bullets:
        loc = f"{review}:{lineno}"

        spans = PATHISH.findall(line)
        paths = [s for s in spans if looks_like_path(s)]
        if not paths:
            print(f"{loc}: warn: [unanchored] rule names no file/path")
            warnings += 1
        for p in paths:
            if not (root / p).exists():
                print(f"{loc}: error: [missing-path] `{p}` does not exist")
                errors += 1

        if body.split()[0].lower() not in DIRECTIVES:
            print(f"{loc}: warn: [non-directive] start with a directive verb")
            warnings += 1
        if len(body) > LONG_BULLET:
            print(f"{loc}: warn: [long-bullet] {len(body)} chars — split it")
            warnings += 1

    status = "invalid" if errors else "valid"
    print(f"{status} ({errors} error(s), {warnings} warning(s))")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
