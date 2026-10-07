---
name: publish-agent-skill
description: >
  Publish a local agent skill to the GitHub catalogue luxiangze/skills, or to
  its own repository when it is large, private, or covered by separate data
  terms, and cut a gh skill release. Use when the user wants a SKILL.md on
  another machine, mentions gh skill publish, asks to upload a skill from
  ~/skills, or asks whether skills should share one repository.
license: BSD-3-Clause
metadata:
  short-description: Publish a local skill with gh skill
---

# Publish an agent skill

Publish a local skill so another machine can install it with `gh skill`. Read [references/layout.md](references/layout.md) and follow that contract for paths, frontmatter, commands, and version tags.

## Choose the repository

Use the public catalogue unless a separate-repository condition in the layout reference matches. Update an existing dedicated checkout in place. A private source gets a private single-skill repository and is not added to the catalogue.

## Publish

1. Reject the source when the layout reference says to reject it.
2. Copy the skill into the chosen repository as the layout reference specifies. On an update, remove files that are no longer in the source. On a catalogue addition, add the skill name to the repository README list.
3. Commit the skill files and push `main`. From the repository root, validate and publish the next tag with the commands in the layout reference.
4. Install that tag into a temporary directory, confirm `SKILL.md` and the bundled files are present, then delete the temporary directory.
5. Tell the user the install command for this skill. Stop there unless the user asks to install it into the current project or agent.
