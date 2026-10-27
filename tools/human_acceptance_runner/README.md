# Human acceptance runner

Open `index.html` in a local browser. The runner uses no network services or external packages. Session fields and case results autosave to that browser's local storage; use **Export results** to download a JSON record before clearing browser data or switching devices.

The build path and source revision start with the latest locally verified RC2 candidate (`9ed4532`). Replace them when qualifying a different build; previously saved session values take precedence.

## Test workflow

1. Enter the exact app/build identity, source revision, tester and device/OS.
2. Review one case at a time and select **Start this test** before launching the build. Other cases stay locked until the app is closed. Follow its preparation, steps and expected result. Fixture cases show an absolute path and a copy button; open the fixture in Read Aloud through its ordinary File → Open Document action.
3. Select Pass, Fail, Blocked or Not run. Record observations and evidence paths. Use Blocked when setup or a dependency prevents a valid result; do not mark a missing or unrun check as passed.
4. Quit Read Aloud with **Read Aloud → Quit** or **⌘Q**, then confirm the exact test process has exited in Activity Monitor. If the case was not run, confirm the test build is not running. Check **App is closed** only after verification; this is required before the case counts as recorded or the runner advances. Pass/Fail also requires starting the test; use Blocked or Not run when no test execution occurred.
5. Export the session JSON and retain it with the referenced evidence.

The page cannot launch or inspect the native app process from a browser. It gives the exact test steps and fixture path; the tester launches the recorded build and confirms closure. It does not replace issue contracts, automated checks, audio analysis or human judgment. A result is a tester record, not an attestation that release criteria are met.

## Case sources

Scenarios are derived from the RC2 acceptance contracts in GitHub issues [#83](https://github.com/kellyjanderson/readaloud/issues/83), [#86](https://github.com/kellyjanderson/readaloud/issues/86), [#88](https://github.com/kellyjanderson/readaloud/issues/88), [#90](https://github.com/kellyjanderson/readaloud/issues/90) and [#78](https://github.com/kellyjanderson/readaloud/issues/78). Update `scenarios.js` when those accepted contracts change; preserve separate pass/fail/blocked/not-run results per test.
