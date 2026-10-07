# Layout and publish contract

GitHub owner: `luxiangze`.

Catalogue repository: `luxiangze/skills`. Checkout: `$HOME/skills/skills`.

Single-skill repository: `luxiangze/<name>`. Checkout: `$HOME/skills/<name>`.

`gh skill` discovers `skills/<name>/SKILL.md`. The parent directory of `SKILL.md` is `<name>`. A `SKILL.md` at the git root fails validation because that directory name is `.`.

## Frontmatter

Required `name` and `description`. `name` is 1–64 characters, matches `^[a-z0-9]+(-[a-z0-9]+)*$`, and equals the skill directory name. `description` is at most 1024 characters and states what the skill does and which user requests should trigger it.

Optional `license` is the SPDX identifier of the repository license. This catalogue uses `BSD-3-Clause`.

`allowed-tools`, when present, is one string. `metadata.github-*` is install provenance written by `gh skill install`. Other `metadata` keys may stay.

## Where a skill goes

Put the skill in the catalogue when it is ordinary instruction content: `SKILL.md`, small scripts, and small reference files.

Create or update `luxiangze/<name>` instead when any of these is true:

- A single file is larger than 1 MiB.
- The skill vendors a database, an annotation package, or a third-party data snapshot.
- The user asks for a separate repository.
- The skill must be private, or it contains data whose redistribution terms differ from the catalogue license.

Clone the catalogue when `$HOME/skills/skills/.git` is missing. Create the missing destination repository with the commands below before copying into it.

## Repository files

Skill files live only under `skills/<name>/`. The repository root holds `README.md`, `LICENSE`, and `.gitignore`. The catalogue README lists skill names and the install command. A single-skill README states that skill's install command. Do not add `README.md` inside `skills/<name>/`.

The source is the directory that directly contains `SKILL.md`. Copy only that directory:

```bash
rsync -a --delete --exclude '.git' --exclude '.DS_Store' \
  "$SOURCE/" "$REPO/skills/<name>/"
```

`$REPO` is the catalogue or single-skill checkout. `--delete` applies only to `skills/<name>/`. Before committing, remove `metadata.github-*` and set `license` when the skill does not already name one.

## Reject the source

Stop before creating a commit when any of these is true:

- `name` or `description` is missing, or `name` violates the frontmatter rules.
- The tree contains a nested `.git`.
- A file contains a credential, a token, or an environment file of secrets.
- Any file is larger than 100 MiB. GitHub rejects that push.

## Version tags

One release tags the whole repository. In the catalogue, that tag covers every skill.

- First release of a repository: `v1.0.0`.
- Adding a skill, or adding behavior: bump minor.
- Fixing instructions or bundled files: bump patch.
- Removing a skill, or changing inputs the skill requires: bump major.

Read the current tag with `gh release view --repo luxiangze/<repo> --json tagName`. No release yet means the next tag is `v1.0.0`.

## Commands

Clone or create the catalogue:

```bash
gh repo clone luxiangze/skills "$HOME/skills/skills"
```

```bash
mkdir -p "$HOME/skills/skills"
cd "$HOME/skills/skills"
git init -b main
gh repo create skills --public --source=. --remote=origin \
  --description "Personal agent skills catalogue. Install with gh skill." \
  --push
```

Create a single-skill repository from `$HOME/skills/<name>` after the skill files and root README are committed:

```bash
gh repo create <name> --public --source=. --remote=origin \
  --description "Agent skill <name>. Install with gh skill." \
  --push
```

Use `--private` instead of `--public` when the skill must stay private.

From a clean repository root, after `main` is pushed:

```bash
gh skill publish --dry-run
gh skill publish --tag <tag>
```

`--dry-run` and `--tag` are separate invocations. `--fix` strips install provenance and does not publish; commit the result and run the dry run again.

Check the release, then install only into a temporary directory:

```bash
gh release view <tag> --repo luxiangze/<repo> --json tagName,url,isDraft
gh skill install luxiangze/<repo> <name> --dir "$TMPDIR/skill-install-check" --pin <tag>
```

Delete that temporary directory after checking the files. The install command to give the user is:

```bash
gh skill install luxiangze/<repo> <name>
```

For Grok on another machine, add `--agent grok --scope user`.
