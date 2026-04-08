# Persistent Folder Access For Startup Restore

Status: final

## Overview

This specification defines how the app preserves platform-owned folder access for remembered file-backed documents so startup restore can reopen them reliably in sandboxed environments.

Issue anchor:

- GitHub issue `#43`

## Backlink

Parent specification:

- [Reader Session Continuity And Live Input](reader-session-continuity-and-live-input.md)

## Scope

This specification covers:

- persisting app-owned folder access data for remembered file-backed documents
- preferring remembered folder access over a plain stored path during startup restore
- sandboxed macOS restore behavior for previously user-selected document folders

## Behavior

When the app successfully opens a file-backed document through a user-granted file-selection flow on a platform that requires persistent access state for future reopen, the app should persist:

- the normalized absolute path
- the normalized absolute parent-folder path
- platform-owned folder restore access data such as a security-scoped bookmark or equivalent token when available

On startup restore, the app should prefer remembered folder access over the raw stored path when reopening the remembered document.

If remembered folder access resolves to an updated or stale-corrected folder path, the app should continue restore using the remembered file path inside that folder and update its remembered directory identity as needed.

The app may also retain file-specific access data as a compatibility fallback, but folder access is the primary durable mechanism.

If the remembered folder access token is unavailable, invalid, or not required on the current platform, the app may fall back to file-specific access data or the plain path.

If a file read still fails because the platform reports missing access, the app should treat that read failure as a recovery point: request the needed folder access, retry once, and only then surface failure.

If startup restore still fails in a non-actionable way, the failure should remain diagnostic rather than surfacing as a primary Reader error toast.

## Constraints

- the solution must remain best-effort and cross-platform safe
- platforms that do not require persistent access state must continue to work without special handling
- startup restore must not assume that a previously user-selected macOS file remains readable from path alone
- the durable-access model should feel like a normal Mac document app rather than like repeated file-by-file permission recovery

## Acceptance

- on sandboxed macOS, a previously user-selected remembered document can be reopened on a later launch from remembered folder access without requiring the user to choose the file again
- when persistent access data is unavailable or invalid, the app falls back safely without surfacing misleading user-facing permission noise
- platforms that do not require persistent restore access continue to use the same remembered-document behavior without regression
