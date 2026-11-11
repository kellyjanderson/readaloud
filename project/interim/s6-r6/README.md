# S6 R6: early playable packets

Owner /root. Source [S6 #137](https://github.com/kellyjanderson/readaloud/issues/137),
defects [#140](https://github.com/kellyjanderson/readaloud/issues/140) and
[#141](https://github.com/kellyjanderson/readaloud/issues/141), parent #110 R23/R24.
Implementation baseline 0489667. Lifecycle: [published corrective design](https://github.com/kellyjanderson/readaloud/issues/137#issuecomment-6786619846)
at immutable 9cc4a11 within the user-authorized S6 completion. Publication does not establish
implementation or acceptance. R1/R5 scene/persistence/runtime requirements remain.

[Packet admission contract](early-playable-packets.md) removes complete-scene
playback barriers while retaining complete native scenes as the persistence and
editing unit. It does not waive startup, continuity, responsiveness or cleanup.
