# S6 R6: early playable packets

Owner /root. Source [S6 #137](https://github.com/kellyjanderson/readaloud/issues/137),
defects [#140](https://github.com/kellyjanderson/readaloud/issues/140) and
[#141](https://github.com/kellyjanderson/readaloud/issues/141), parent #110 R23/R24.
Implementation baseline 0489667. Lifecycle: unpublished corrective implementation
design within the user-authorized S6 completion. Publication does not establish
implementation or acceptance. R1/R5 scene/persistence/runtime requirements remain.

[Packet admission contract](early-playable-packets.md) removes complete-scene
playback barriers while retaining complete native scenes as the persistence and
editing unit. It does not waive startup, continuity, responsiveness or cleanup.
