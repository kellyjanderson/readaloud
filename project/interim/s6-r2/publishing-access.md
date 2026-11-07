# S6 R2 publishing access amendment

Source #137; parent #110 R23; predecessor S6 R1 at `6d3cc28`; baseline `8dcae50`.

R1's promise not to broaden entitlements overlooked that the existing macOS target only has user-selected **read-only** access. S6's already-authorized publishing outcome needs a usable Save Audio Book action and write access to the destination the user selects in NSSavePanel. Apple documents [user-selected read-write access](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write) for this purpose.

Replace only `com.apple.security.files.user-selected.read-only` with `com.apple.security.files.user-selected.read-write` in the app targets and update the signing preflight. Retain sandboxing, app-scoped bookmarks, inherited helper restrictions and existing networking. Do not grant general home-directory access, fixed-path exceptions or new automation permissions. Add Save Audio Book to the existing File/output menus; Cmd-S invokes it, leaving the existing audio export shortcut intact. The user chooses the destination through the maintained file-picker package/platform save panel. Original input protection, staged atomic publication, cancellation and unknown-schema failure remain required. This is an implementation correction within audio-only S6, not an expansion of the release's product scope.

Validate signed entitlements, the normal UI save action and copied-package reopen from a user-selected destination. Files saved only inside an app test container do not establish external publishing access. Keep the slice open if the actual save-panel path remains unverified.
