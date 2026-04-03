# Agent Documentation Index

This folder defines how agents should operate within this repository.

Start here before taking action.

---

## Documents

* **architecture.md**
  Defines what architecture documents are and how they describe system structure and cross-domain solutions.

* **specifications.md**
  Defines how architecture is refined into implementable specification units.

* **planning.md**
  Defines how specifications are sequenced and tracked for implementation.

* **research.md**
  Defines how research is stored as durable project knowledge.

* **workflow.md**
  Defines how agents move through product definition, architecture, specification refinement, and implementation.

* **git-and-github.md**
  Defines branching and pull request rules for bug fixes and feature work.

---

## Project Documentation

Project-level documents live in:

```text
project/
  agents/
  product-definition.md
  architecture/
  specifications/
  planning/
  research/
```

Agents should consult relevant project documents before making changes.

Project-specific agent rules live in:

```text
project/agents/
```

That folder is the canonical place for instructions that apply specifically to this project, while the root `agents/` folder remains the shared process guidance for the repository.

---

## Starting Point

When beginning work:

1. review `project/product-definition.md` (if present)
2. review `project/agents/` for project-specific operating rules
3. review `git-and-github.md` before implementation work
4. review relevant architecture
5. follow the workflow defined in `workflow.md`

---

## Guiding Principle

The system is defined by its documents.

Code is an implementation of that system.
