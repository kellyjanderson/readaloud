# Fish Drama catalog updates

`FishDramaCatalogStore` separates supported model data from the installed Python
runtime. The bundled `fish_drama_models.json` and
`fish_drama_model_checksums.json` are the trusted offline fallback. A valid saved
catalog is loaded before network access. A session captures one immutable
snapshot, so a later refresh cannot change its checkpoint or verification input.

The managed integration refreshes in the background for a later session; it must
not wait for the network before using an already available catalog. It must use
the same captured model/checksum JSON for Dart lookup and the Python helper,
materialized beside that helper in a directory specific to the snapshot identity.
The integration owns calling `close()` on the store when its session retires.

The only update origin is the first-party repository on
`raw.githubusercontent.com`. The normal manifest path is
`kellyjanderson/readaloud/main/assets/fish_drama_catalog_update.json`.
Qualification can pin this same manifest path to a 40-character Git commit;
there is no configurable host, repository, asset path or executable URL.
Redirects are rejected. The manifest and each asset are limited to 256 KiB, with
an eight-second total refresh deadline. A 404 before the update manifest reaches
the published branch is a recoverable refresh failure.

The manifest schema is version 1. It names a positive, monotonically increasing
`catalogVersion`, an immutable repository `sourceRevision`, the exact installed
runtime/architecture/platform ceiling, and SHA-256 digests of the two catalog
files. Both files are retrieved at that source commit. Unknown fields, changed
runtime requirements, broadened capabilities, mutable revisions and digest
mismatches are rejected. Required model files must have complete pinned integrity
entries and be configuration, tokenizer, template, notice or safe tensor data;
Python files and new runtime dependencies cannot be added through this path.
The existing three engine IDs and precision mapping remain stable. New engine
IDs or architectures require an app/runtime change.

Validated updates are persisted as one envelope at
`<mlx-root>/catalog/last-valid.json`, using a flushed temporary file and atomic
rename. Models and checksums are never published separately. Invalid saved data
falls back to the bundle. A failed network refresh retains the last valid
snapshot and returns its error to the caller. A lower catalog version or a
different payload at the same version is rejected. Deleting the saved envelope
restores the bundled fallback; existing model weights are unaffected.

One session owns one store, with at most one active refresh and no retry queue.
Duplicate refresh requests share that attempt. Parsing, schema validation and
hashing run in a short-lived isolate; HTTP and file I/O use platform asynchronous
facilities. The store owns and closes its HTTP client on completion, timeout or
session shutdown. Shutdown fences further publication and drains an already
issued file operation before the next session starts. The caller must drain the
retiring store before creating another writer for the same root. Errors and late
network completions cannot replace a captured current-session snapshot.

To prepare an update, first commit the two catalog assets, then point the
manifest at that exact commit and record their SHA-256 digests. Increment the
catalog version for any metadata or payload change. The version 1 manifest in
this change describes the existing bundled checkpoints; it does not select a
new default or establish runtime/acoustic qualification. Catalog integrity and
runtime compatibility do not qualify a new checkpoint for native scenes, memory
limits, voice identity or audible continuity. Those require their separate
source policy and running-app evidence under issue #112.

The focused store tests cover frozen snapshots, offline persistence reuse,
fixed-origin pinned URLs, schema/runtime/hash rejection, executable-file
rejection, rollback/collision rejection, coalescing, cancellation, timeout and
last-valid retention. They do not establish model-download completion or native
playback acceptance.
