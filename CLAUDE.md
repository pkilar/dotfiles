# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A dotfiles repo whose only content today is `claude/skills/` — 15 Claude Code Agent Skills
kept under version control. There is no build system, no test runner, no package manifest,
and no CI. The deliverables are Markdown documents plus a handful of Bash and Python
scripts the skills shell out to.

## The repo is a mirror, not the live install

Claude Code loads user-level skills from `~/.claude/skills/`. This repo stores them at
`claude/skills/` — no leading dot — which is on no skill search path: not the user path,
and not the project path (`.claude/skills/`). **Editing a file here has no effect on any
running session until it is copied to `~/.claude/skills/<name>/`.**

There is no install or sync script. Copies are made by hand, in both directions, so drift
is normal and has already occurred in both. Before editing any skill, check it:

```bash
diff -rq claude/skills/<name> ~/.claude/skills/<name>

# sweep everything
for d in claude/skills/*/; do n=$(basename "$d"); \
  diff -rq "$d" ~/.claude/skills/"$n" >/dev/null 2>&1 || echo "DRIFT $n"; done
```

`~/.claude/skills/` holds far more than this repo tracks — the plugin-installed `gstack`
suite and its ~50 siblings, `atari-800-skills`, and the `linux-packaging-workspace/`
fixture tree. Only the 15 directories checked in here are tracked. Never bulk-copy
`~/.claude/skills/` back into the repo.

## Commit and PR rules

`claude/skills/commit/SKILL.md` and `claude/skills/cpr/SKILL.md` are the author's standing
rules. They apply to work *in* this repo and they override Claude Code's default git
behaviour:

- Never commit to `main`. Branch, then open a PR — that is how the initial import landed.
- No `Co-Authored-By:` trailers, no "Generated with Claude Code", no mention of AI or
  Claude anywhere in a commit message or a PR description.
- PR titles use active voice with a present-tense verb: "Add user authentication", not
  "Added user authentication".
- PR description sections, in order: `## Why`, `## Approach`, `## How it works`, `## Links`.

## Skill anatomy

One directory per skill; `SKILL.md` is required and is the entry point.

Frontmatter is YAML with `name` and `description`. The description is the *only* thing the
loader indexes for triggering, so the good ones enumerate phrasings a user would actually
type rather than describing the topic — compare `linux-packaging` and `security-audit`
(long, trigger-dense, naming tools and error symptoms) against `commit` (one line).
`allowed-tools` is optional; `go-expert`, `rust-expert`, and `connect-chrome` use it.

Progressive disclosure is the organizing principle: `SKILL.md` is a router that stays
small, and the bulk lives in subdirectories the model loads only when it needs them.

| Subdir | Role |
|---|---|
| `references/` | Deep material pulled in on demand. `security-audit` subdivides further: `references/stages/` holds seven sequential stage guides (read one before each stage), and `references/domains/` is fronted by `_index.md`, which maps a stack classification to the domain files worth loading. |
| `assets/` | Copied out and then edited, never edited in place. `security-audit/assets/*.template.md` are copied into a per-audit workspace; `linux-packaging/assets/templates/{rpm,debian,arch,multi-distro}/` are lifted into a target project. |
| `scripts/` | Executables the skill runs. |
| `evals/` | Only `linux-packaging` has one — `evals.json`, three graded scenarios. |

Two skills park a single extra document beside `SKILL.md` instead of using a subdirectory
(`managing-dotfiles/yadm-command-reference.md`,
`reviewing-code/ml-research-review-checklist.md`), and `mcp-builder` spells its directory
`reference/`, singular, against everything else.

`linux-packaging` and `security-audit` are both built on the same conviction, worth
preserving when editing either: reading the artifact you just produced is not verification.
`linux-packaging` refuses to call a package working until a package manager has installed
*and upgraded* it in a clean container; `security-audit` refuses to call a vulnerability
real until a sandboxed PoC proves it, and keeps stages 1–4 read-only until a user approval
gate. Edits that soften those bars remove the point of the skill.

## Running the bundled scripts

`linux-packaging/scripts/` — Bash; needs `podman` or `docker` for the container tiers:

```bash
# cheap organizational pass; exit status is the finding count, so it can gate CI
claude/skills/linux-packaging/scripts/audit-layout.sh [repo-root]

# diff what the BUILT packages contain across formats (at least two required)
claude/skills/linux-packaging/scripts/parity-check.sh --rpm DIR|GLOB --deb DIR|GLOB --arch DIR|GLOB

# the four-tier ladder: build -> lint the built package -> install+assert -> upgrade over an older build
claude/skills/linux-packaging/scripts/verify-package.sh \
  --format rpm|deb|arch --repo DIR --build-cmd CMD \
  [--upgrade-from DIR] [--tier N] [--image IMG] [--site DIR] [--lint-args ARGS]
```

Default images are `fedora:latest`, `debian:stable`, `archlinux:base-devel`. Without
`--upgrade-from`, tier 4 — the only tier that tests whether a site admin's config edits
survive — is skipped and reported as untested, never silently passed.

`mcp-builder/scripts/` — Python; `pip install -r requirements.txt` (anthropic, mcp); needs
`ANTHROPIC_API_KEY`. Run from inside `scripts/`, since `evaluation.py` imports
`connections` as a sibling module:

```bash
python evaluation.py -t stdio -c python -a my_server.py eval.xml
python evaluation.py -t sse -u https://example.com/mcp -H "Authorization: Bearer token" eval.xml
```

`nano-banana-pro/scripts/generate_image.py` — needs `GEMINI_API_KEY` or `--api-key`:

```bash
python generate_image.py -p "prompt" -f out.png [-i input.png] [-r 1K|2K|4K]
```

## Known defects and traps

- `go-code-reviewer/SKILL.md` has **no frontmatter at all**. The loader falls back to
  truncating its first prose line into the description, so the skill triggers badly. Add
  `name` and `description` if you touch it.
- `managing-dotfiles/` documents **yadm** — work tree `$HOME`, repo at
  `~/.local/share/yadm/repo.git`. That is not how this repository works. This is a plain
  git repo and yadm is not installed on this machine. It is shipped content describing a
  setup used elsewhere; do not follow it to manage this repo.
- `linux-packaging/evals/evals.json` references fixtures at
  `../../linux-packaging-workspace/fixtures/`, which resolves inside `~/.claude/skills/`
  and is not checked in. The evals cannot run from a clean clone.
- `mcp-builder/SKILL.md` frontmatter claims `license: Complete terms in LICENSE.txt`, but
  no `LICENSE.txt` ships with the skill. The repo's own license is MIT, at the root.
- `connect-chrome/` is a modified copy of the gstack plugin's `open-gstack-browser` skill
  and still carries gstack-only frontmatter keys (`preamble-tier`, `version`, `triggers`).
  Upstream changes to it are not tracked here.
