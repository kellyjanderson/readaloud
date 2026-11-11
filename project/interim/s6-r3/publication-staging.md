# S6 R3 publication staging amendment

Source #137; predecessor S6 R2; baseline `41fa094`.

Replace R1's literal requirement to stage beside the destination with staging in a private directory on the destination volume. A sandbox Save panel grants access to the chosen file, not arbitrary sibling paths. The macOS adapter uses Foundation's [`FileManager.url(for:in:appropriateFor:create:)`](https://developer.apple.com/documentation/foundation/filemanager/url(for:in:appropriatefor:create:)) with `itemReplacementDirectory` and the destination URL. Other platforms retain sibling staging until their corresponding maintained platform facility is needed.

The existing package owner starts cancellation/deadline ownership before requesting the directory. Native allocation runs on a utility queue and replies on the main queue; late allocations after cancellation are removed by the owning request. The archive worker writes and flushes in that directory, waits for current-owner commit admission, and atomically renames the complete file to the selected destination. No copy fallback across devices, broader entitlement, general folder lease, or change to input protection is permitted. Failure leaves prior valid output intact and cleans only the request's staging directory. Normal shutdown drains its owned work.

This is a correction within the already-authorized Save Audio Book outcome. Acceptance requires the signed sandboxed app to save through NSSavePanel to an external destination, reopen that actual file, preserve its source/directions/audio, and quit normally. Unit coverage must exercise custom staging, cancellation during delayed allocation, allocation failure, and worker publication.
