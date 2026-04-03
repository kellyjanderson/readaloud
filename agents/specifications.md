# Specification Guidance

Specification documents define how architecture is refined into actionable implementation work.

A specification represents a unit of work derived from either:

* an architecture document, or
* another specification document

Each specification must have exactly one backlink to its parent document.

This parent may be:

* an architecture document, or
* a specification document

A specification should not have multiple parents.

---

## Purpose

Specifications translate architecture into implementable form.

They isolate individual implementation concerns and refine them until they can be acted on directly.

Specifications are downstream of architecture.

They should only be written after the relevant architecture branch has been completed breadth first so the system-level picture for that area is already known.

---

## Specification Process

Specifications are not written in a one-shot process.

They are produced through iterative refinement.

Specification refinement is recursive.

The expected result is a tree structure that may grow both wide and deep:

* architecture produces first-generation specifications
* those specifications may produce child specifications
* those children may produce their own children
* refinement continues downward until the current leaves are sized appropriately for clean implementation

Each architecture document is first broken down into specifications that isolate major implementation concerns described by that architecture.

That step happens only after the relevant architecture documents are complete enough to describe the whole system area being refined.

If important architecture-level relationships, data flow, or cross-domain decisions are still missing, specification work should pause and the process should return to architecture.

After this first round, there should usually be multiple specifications associated with a single architecture document.

Each specification is then evaluated to determine whether it is implementable as written or requires further refinement.

* If a specification can be implemented directly, it should be marked final.
* If a specification cannot yet be implemented directly, it should be refined into one or more child specifications.

If a specification still contains more work than can reasonably be completed in one clean implementation round, it is not final yet, even if the overall idea is coherent.

Refinement should not optimize for the smallest possible leaves.

The goal is to arrive at the largest cohesive implementation unit that can still be completed cleanly in one round without hiding major unresolved decisions.

If several concerns are tightly coupled and would naturally be implemented together in one pass, they should usually stay in one final leaf rather than being split only for the sake of atomization.

Each child specification must backlink to the specification it refines.

This process continues until all leaf specifications are marked final.

Agents should expect to review newly created child specifications in later rounds and either:

* mark them final if they are now implementation-sized, or
* refine them again into smaller child specifications

When deciding whether to refine further, prefer asking:

* would this realistically be implemented as one coherent change set?
* does this leaf still hide another full round of work?
* are there unresolved decisions that would force further design during implementation?

If the answer to those questions is "no," the leaf should usually remain final even if it still contains multiple closely related details.

The process is complete only when every executable leaf in the tree is final.

At the end of each specification pass, the agent should explicitly report how many specifications still require another refinement round.

That count should reflect the number of specifications that are still not final.

---

## Scope

A specification should cover one implementation concern, such as:

* a feature
* a component
* a behavior
* an interface
* a workflow

A specification should not be so broad that major design decisions still need to be made during implementation.

---

## Final Specifications

A final specification is a specification that can be implemented directly.

A final specification should be small enough and clear enough that implementation can proceed without further specification-level refinement.

`Final` does not mean "complete as a thought" or "the whole concern is now described."

`Final` means the remaining work described by that specification is sized appropriately to be implemented cleanly in one round of work.

If a specification still bundles multiple rounds of implementation work together, it must not be marked final. That work must be pushed down into child specifications until the leaf specifications represent implementation-sized units.

This does not mean every distinguishable subtopic needs its own child specification.

The preferred granularity is the largest cohesive unit that:

* can be implemented in one round
* does not hide major unresolved decisions
* does not imply a second clean implementation pass that should have been specified separately

All implementation work implied by a specification must be represented at the leaf level before execution. Parent specifications may remain broad, but executable work belongs in final leaf specifications only.

If a parent specification still implies work that is not represented by child leaves, refinement is not finished yet.

---

## Recommended Structure

Specification documents should generally include:

### Overview

A short description of the concern being specified.

### Backlink

A reference to the parent architecture or specification document.

### Scope

What this specification covers.

### Behavior

What this part of the system should do.

### Constraints

Requirements that must be satisfied.

### Refinement Status

Whether the specification is final or requires further refinement.

### Child Specifications

References to any specification documents derived from this one.

### Acceptance

What must be true for the work to be considered complete.

---

## Relationship to Architecture

Architecture defines the system-level solution.

Specifications refine that solution into implementable units.

Specifications should remain aligned to the parent document they refine.
