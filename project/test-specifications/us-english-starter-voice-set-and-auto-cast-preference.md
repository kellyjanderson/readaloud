# Test Specification: US-English Starter Voice Set And Auto-Cast Preference

Status: final

## Manual Smoke Test

1. Launch the app on a clean voice install.
2. Open the voice management dialog.
3. Confirm the starter voices surfaced as included with the app are all US-English voices.
4. Confirm the starter set contains five bundled voices and surfaces two female, two male, and one neutral voice in app-owned metadata.
5. Start multi-voice reading on a document with detected characters and confirm automatic assignments prefer bundled US-English voices before British voices when both are installed.

## Automated Acceptance Coverage

The automated suite should cover:

- catalog tests that assert the bundled starter voice ids, default narrator voice id, and bundled-role metadata
- voice metadata tests that assert the neutral starter voice is represented through app-owned metadata rather than absent metadata
- cast-assignment tests that assert automatic character selection prefers US-English voices over other English regional voices when quality and other factors are otherwise comparable
- document-import or controller-level tests that assert bundled default casting uses the curated US-English starter pool on a fresh install

## Pass Criteria

- the bundled starter voice set is exactly the curated US-English set
- the default narrator voice id resolves from that set
- automatic cast assignment prefers US-English voices over other English regional voices when it is choosing automatically
