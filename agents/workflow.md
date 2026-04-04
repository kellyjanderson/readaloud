# Workflow Guidance

This document defines how agents move through the project from product definition to implementation.

---

## Overview

Work progresses through three phases:

1. Exploration (product and architecture refinement)
2. Stabilization (product and architecture become fixed enough to proceed)
3. Specification refinement and implementation

Research supports all phases and is used to store durable information.

Project-specific agent rules are stored separately in:

```text
project/agents/
```

Agents should consult that folder before substantial work begins and keep project-specific operating rules there rather than scattering them through transient discussion.

Repository-wide branching and pull request rules are defined in:

```text
agents/git-and-github.md
```

Agents should satisfy those branch and PR requirements before making code changes.

UI definition guidance is defined in:

```text
agents/ui-definitions.md
```

Project UI definition documents should live in:

```text
project/ui/
```

---

## Exploration Loops

### Product ↔ Research

Product definition is refined through research.

Primary product document:

```text
project/product-definition.md
```

* identify unknowns in the product definition
* perform research to answer those questions
* store findings in the research folder
* update the product definition as needed

This loop continues until the product definition is sufficiently clear.

---

### UI Definitions ↔ Research

UI definitions are refined through research and observation.

Primary UI definition documents live in:

```text
project/ui/
```

* identify interface unknowns, clutter, ambiguity, or interaction problems
* perform research or observation where needed
* store findings in the research folder when they are durable
* update UI definitions to reflect resolved interaction structure

This loop continues until the relevant UI surface is sufficiently coherent.

UI definition work is breadth first across the relevant interface area.

The goal is to define the visible structure and interaction semantics of the surface before narrower specifications or implementation details are finalized.

---

### Architecture ↔ Research

Architecture is refined through research.

* identify cross-domain problems or unknowns
* perform research where needed
* store findings in the research folder
* update architecture to reflect resolved solutions

This loop continues until architecture provides a coherent system-level solution.

Architecture work is breadth first.

Agents should expand the architectural picture across the whole relevant system before beginning specification refinement for that architectural branch.

The goal is to understand how the parts work together at system level, not to fully specify one isolated branch while other architecture gaps remain unresolved.

---

## Stabilization

At some point:

* product definition becomes stable enough to guide development
* UI definitions become stable enough to guide interface work
* architecture becomes stable enough to define system structure

For architecture, "stable enough" means the relevant architecture documents for the area of work have been completed breadth first.

That means:

* the major system parts for that area are identified
* their relationships are described
* the high-level data flow is described
* the cross-domain solutions are resolved

Specification work should not start while important architecture-level gaps still exist for the same system area.

These do not need to be perfect, but must be stable enough that implementation can proceed without constant structural change.

Once stabilized, the exploration loops should diminish and specification work becomes primary.

---

## Specification Refinement Loop

After stabilization:

* break architecture into specifications
* evaluate each specification for implementability

Specifications are written only after the relevant architecture and UI definition documents are complete enough to describe the whole system area being refined.

Architecture and UI definitions come first for their respective concerns.

Specification refinement is not a substitute for unfinished architecture work.
It is also not a substitute for unfinished UI definition work when the interface structure itself is still unclear.

For each specification:

* if implementable, mark it final
* if not, refine it into child specifications

Store all specifications and maintain backlinks.

This process continues until all leaf specifications are marked final.

This refinement is recursive.

Agents should expect to:

* create first-generation specifications from architecture
* review those specifications
* create child specifications where needed
* review those children in later rounds
* continue refining downward until the tree consists of implementation-sized final leaves

The intended result is a specification tree, not a flat one-pass list.

The goal is not to atomize work into the smallest possible leaves.

Specification refinement should usually stop at the largest cohesive unit that can still be implemented cleanly in one round without hiding another full round of work.

After each specification pass, report how many specifications still require another refinement round so progress toward completed specification work remains visible.

---

## Progression Initialization

The progression document does not exist during product definition, architecture, or specification refinement.

Once all leaf specifications are marked final:

* create the progression document:

```text
project/planning/progression.md
```

* populate it with references to the final leaf specifications
* arrange those references according to dependency order
* apply secondary ordering where needed

The progression document must contain only final leaf specifications.

Parent or umbrella specifications do not belong in progression and must not be tracked there.

The progression document becomes the execution sequence for the project.

---

## Specification Execution

After the progression document is created:

* implement specifications using the progression document as the source of execution order
* update completion status as specifications are implemented

Implementation proceeds only from specifications represented in the progression document.

Implementation should also proceed only from the correct git branch context:

* bug-fix work on a bug-fix branch linked to an issue
* feature work on a feature branch linked to a specification

Code changes should not be made directly on `main`.

---

## Progression Audit

During execution:

* ensure that implemented specifications remain consistent with their specification documents
* ensure that the progression document remains aligned with the current set of specifications

If specifications change during execution:

* update the affected specifications
* update the progression document to reflect those changes before continuing

---

## Architecture and Product Changes

If implementation reveals issues that affect:

* product definition, or
* UI definition, or
* system structure

return to the appropriate loop:

* product ↔ research
* UI definitions ↔ research
* architecture ↔ research

Update documents before continuing.

---

## Research Use

When research is required:

* perform research intentionally
* store findings in the research folder
* use research to inform product, architecture, or specifications

Do not rely on transient context for important information.

---

## Completion

Work continues until all relevant specifications in the progression document are implemented.

Completion criteria are defined separately.

---

## Guiding Principle

Follow the structure of the system.

Use loops to resolve uncertainty, and only proceed to implementation once the system is sufficiently defined.
