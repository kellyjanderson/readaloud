# S6 R4: lazy packaged Python runtimes

Owner /root; source [#137](https://github.com/kellyjanderson/readaloud/issues/137), parent #110 R23. Baseline `6f98390`. Lifecycle: unpublished design amendment. This addresses the user's explicit slow-first-launch repair within S6; it preserves audio-only release scope and every standing acceptance requirement.

[Runtime packaging amendment](runtime-packaging.md) retains full speech and optional analysis capabilities while allowing completed audio books to open without preparing their unused runtimes. The S7 resource slice must reconcile this implementation rather than duplicate its owner.
