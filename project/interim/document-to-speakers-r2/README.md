# Document-to-speakers R2 release qualification amendment

The Read Aloud release coordinator records this user-directed qualification
change for [design #170](https://github.com/kellyjanderson/readaloud/issues/170)
and [release #122](https://github.com/kellyjanderson/readaloud/issues/122). The
implementation baseline is release branch `9a7584d7c043b82badc5161bcb2739c9d1ac25c2`.
The fixed [R1 predecessor](https://github.com/kellyjanderson/readaloud/tree/42bfff7d5496b1448546161cc3264827d522323c/project/interim/document-to-speakers-r1)
remains the source for the rest of the pipeline design and work orders.

[The owner decision](https://github.com/kellyjanderson/readaloud/issues/122#issuecomment-7234797323) makes physical M3 qualification optional.
Verify the supported hardware available for the exact package and identify it
in acceptance evidence. App-startup timing is deferred to
[#207](https://github.com/kellyjanderson/readaloud/issues/207) after
[#190](https://github.com/kellyjanderson/readaloud/issues/190) and completion of
the native Dart speech rewrite. R25 document-load timing continues from Open
after normal startup. This amendment changes qualification policy. Runtime
behavior and requirements such as responsiveness and continuity follow their
existing contracts.

Use the [work-order replacements](slices.md) with R1. GitHub owns dispatch,
release admission, evidence and final reconciliation.
