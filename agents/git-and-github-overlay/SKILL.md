---
name: git-and-github-overlay
description: Apply Read Aloud-specific Git and GitHub rules that limit planning anchors to issues or specifications and keep the branch model simple.
---

# Read Aloud Git And GitHub Overlay

This Skill narrows `git-and-github-core` for Read Aloud.

## Allowed Planning Anchors

Implementation changes must not happen without one of these durable anchors:

* a specification for feature work
* an issue for bug-fix work

Do not begin code changes from ad hoc discussion alone.

## Durable Linkage

Issue-driven fixes must be back-referenced into the architecture or specification tree so the resulting behavior does not live only in issue text, PR text, or branch history.

## Branch Model

Use the simpler issue-or-spec branch model for this workspace.

Workspace-specific naming can remain lightweight as long as the branch clearly maps to the issue or specification anchor.
