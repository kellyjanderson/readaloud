# Test Specification: Persistent Folder Access For Startup Restore

Paired feature specification:

- [Persistent Folder Access For Startup Restore](../specifications/persistent-file-access-for-startup-restore.md)

## Manual Smoke Check

- Open a file-backed document on macOS.
- If the app asks to remember the folder, grant that access once.
- Close and relaunch the app.
- Confirm that the remembered document reopens automatically without a user-facing access error and without requiring the file to be chosen again.

## Automated Smoke Expectations

- controller coverage verifies that startup restore can use persisted folder access data when available
- controller coverage verifies that non-actionable startup restore failures remain out of the Reader status surface
- preferences coverage verifies that persisted directory access data is saved and loaded with the remembered file-backed document state
- controller or import coverage verifies that a permission-shaped read failure can trigger one folder-access recovery attempt before failing

## Automated Acceptance Expectations

- sandboxed restore uses persisted folder access before falling back to file-specific access or a plain path
- the restore path remains safe on platforms that do not provide or require persistent access data
- failure paths degrade to diagnostics rather than misleading user-facing permission messaging
