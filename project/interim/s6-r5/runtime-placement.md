# S6 R5 runtime placement amendment

Source #137; parent #110 R23; predecessor S6 R4; implementation baseline `5060dac`.

## Reason for replacement

R4 achieved 1873.721458ms opening-to-captured-speech in a full archived-resource candidate, but macOS refused execution of its sandbox-extracted interpreter. A bundled interpreter also stalled loading an extracted native library in dyld signature validation. Source checks and archive integrity do not establish platform executability. No quarantine attributes or security policy were changed.

A disposable split control retaining native code in the signed app started real MLX inference. Its native playback onset was 2166.762ms before emitted-onset accounting, so this direction is not yet accepted against the two-second requirement. Pruning redundant bytecode alone remained too slow (4114.236917ms emitted upper bound). Preserve those failures independently.

## Replacement packaging contract

Keep every Mach-O executable, extension and dynamic library in the signed application, retaining its runtime-relative native layout and required adjacent native resources (including Metal libraries). Build-time classification uses file content, not only suffixes. Known `.so`/`.dylib`/interpreter members that are not valid supported Mach-O must fail packaging. Preserve the qualified BookNLP OpenMP binary/license, dependency versions, both independent interpreters and all application features. Only redundant bytecode with matching source may be omitted. Do not remove optional dependencies speculatively.

The default native root is `Resources/python-runtimes/<id>-native/`; compressed pure Python/data resources and bounded manifests remain adjacent. Code-placement refinements into correctly signed nested helper bundles are permitted only when their relative native layout and exact manifest binding are retained and independently tested; never disguise code as data or bypass signature verification. No native code is extracted, copied or re-signed in Application Support. Existing source runtimes, model assets and installed apps remain untouched.

The signed manifest uses a new schema/policy and binds the complete logical runtime: ordinary files/directories/contained relative links plus explicit bundled-native entries with exact bundled relative path, size, mode and post-sign SHA-256. Archive membership must equal only the declared data members. Verify every native target is a regular file contained in the canonical native root, with exact hash/mode; validate the interpreter architecture/signature. Native library signatures remain build/package admission requirements. Arbitrary external paths, undeclared native files, escaping links and mismatched code/data fail closed.

## Immutable runtime view and child launch

The installer retains R4's off-main-isolate archive/inventory/tree checks and bounded lifecycle. In its private staging directory, it creates only explicit manifest-owned links for bundled-native entries, then verifies the complete logical view. Ordinary relative links may resolve outside the data tree only when they resolve to the exact verified bundled-native target declared by the manifest. No broad exception for external links is permitted.

Publish under a new policy/version namespace, with both complete runtime digest and canonical bundle-location identity. An app moved to a different location builds a new immutable view; never rewrite links in a published view. Existing R4 output is not silently reused or repaired. Verify the current bundle targets on each acquisition; a removed or changed bundle produces actionable failure rather than falling back to unrelated code. Concurrent publication, loser cleanup, cancellation, timeouts and shutdown retain R4 guarantees.

Acquisition returns a typed verified runtime containing the bundled interpreter path and the immutable Python home. Pass `PYTHONHOME` explicitly only to that runtime's owned child; MLX and BookNLP retain independent homes and identities. Never alter global process environment or infer one engine's home for another. Explicit developer interpreter overrides retain their explicit provenance and do not acquire an unrelated packaged home. Preserve compatibility for existing injected test providers where appropriate.

## Acceptance and reconciliation

Add meaningful source cases for native target hash/mode/type/path mismatch, links through undeclared targets, incomplete archives, code/data identity changes, relocation, immutable reuse and cancellation. Retain existing archive-corruption, concurrency, cleanup, process lifecycle and provenance coverage. Use maintained `ditto`, codecs and filesystem facilities; only manifest policy/view assembly are application-specific.

Native acceptance requires the actual packaged resolver without interpreter/home overrides: first extraction and real MLX synthesis, real BookNLP analysis, cancel/replacement/normal Quit with no owned processes, and a fresh signed full-feature candidate's opening-to-expected-emitted-speech within two seconds. No first-use exemptions or requirement relaxation. Cached reuse cannot prove uncached generation continuity. Preserve the earlier missing-middle 1021.68ms gap, interactive-save heartbeat 511ms and pending human listening until new comparable evidence resolves them.

Reconcile final placement and evidence limits into architecture, setup and packaging docs. R5 is a correction within the already authorized audio-only S6 scope, not permission to close S6, merge to main or publish a release. S7 must reuse the resulting owner.
