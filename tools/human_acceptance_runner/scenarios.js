/* User judgments collected for the final release candidate. */
window.HUMAN_ACCEPTANCE_SCENARIOS = [
  {
    id: 'cancel-first-play',
    issue: 140,
    title: 'Cancel while speech is preparing',
    passageId: 'quick-two-speaker',
    question: 'Can you cancel the pending Play promptly? Does the app remain silent until you request Play again?',
    steps: ['Start with Read Aloud closed, then open the supplied candidate.', 'Paste the passage and press Play. While speech preparation is visible, press Cancel pending Play.', 'Wait for preparation to settle. Press Play again and listen. If preparation finishes before you can cancel, skip this case and say so in the note.'],
    expected: 'The control responds promptly, no cancelled speech starts later, and a fresh Play still works.'
  },
  {
    id: 'installed-model-switch',
    issue: 112,
    title: 'Switch between prepared speech models',
    fixtureId: 'model-workflow',
    question: 'Can you follow the selected and active model states, switch between the supplied installed models, and start a fresh reading without unexpected speech?',
    steps: ['Open the supplied candidate using the isolated test profile described in the fixture. Use only the two already installed model choices named there.', 'Open Settings and switch to the other model. Watch the status, then close and reopen Settings to confirm the selected and active choice.', 'Return to the supplied short document and press Play. Listen briefly, stop, and switch back. If the fixture says a model is not installed or needs a download, skip and record that mismatch.'],
    expected: 'Settings stays responsive and shows the actual selected and active choices. Switching starts no speech by itself. A fresh Play uses the chosen prepared model.'
  },
  {
    id: 'preparation-recovery-keyboard',
    issue: 119,
    title: 'Recover preparation using the keyboard',
    fixtureId: 'model-workflow',
    question: 'Can you understand the preparation status, copy a problem, and reach Cancel, Retry and Activity using the keyboard in a narrow window?',
    steps: ['Use the isolated profile and the qualified recovery document described in the fixture. Make the window narrow and use the larger text setting specified there.', 'Use Tab and Space to open Activity, cancel document preparation and retry it. Follow the fixture to reproduce its recoverable error, then copy the status and retry.', 'If reduced motion is enabled for this case, observe completed rows leaving Activity without a fade. Close and reopen the candidate and check that your Activity choice is remembered.'],
    expected: 'The reader and controls stay reachable. The summary describes its own operation and progress, errors remain readable and copyable, cancellation does not later start speech, Retry starts a fresh attempt, and Activity remembers your choice.'
  },
  {
    id: 'fast-two-speaker-dialogue',
    issue: 111,
    title: 'Fast back-and-forth · two voices',
    passageId: 'quick-two-speaker',
    question: 'As Mara and Jonah trade short lines, can you follow who is speaking? Do the voices switch cleanly from one line to the next?',
    steps: ['Copy the passage below.', 'In Read Aloud, choose File → Paste Text and paste it.', 'Press Play and listen through the exchange.'],
    expected: 'The conversation is easy to follow. Voices change when the speaker changes, with no line that seems skipped, repeated, spoken by the wrong character, or cut off.'
  },
  {
    id: 'fast-three-speaker-dialogue',
    issue: 111,
    title: 'Fast back-and-forth · three voices',
    passageId: 'quick-three-speaker',
    question: 'When Mara, Jonah, and Niko take quick turns, can you keep track of them? Does a speaker change sound clear and timely?',
    steps: ['Copy the passage below.', 'In Read Aloud, choose File → Paste Text and paste it.', 'Press Play and listen through the exchange.'],
    expected: 'The three speakers remain distinguishable across quick turns. No line seems skipped, repeated, assigned to the wrong character, or cut off.'  },
  {
    id: 'saved-book-expression',
    issue: 137,
    title: 'Listen to a saved audio book',
    fixtureId: 'expressive-book',
    question: 'Can you follow the characters by voice? Do their delivery and the transitions between scenes sound natural?',
    steps: ['Open the provided audio book with File → Open.', 'Press Play and listen through the marked scenes.', 'Quit and reopen Read Aloud. Open the same book and listen to the exchange again.'],
    expected: 'The characters keep their voices across scenes and after reopening. The marked delivery is audible, transitions sound continuous, and every marked passage includes its final words without skips, repetition or cut-off endings.'
  },
  {
    id: 'edited-book-voice',
    issue: 137,
    title: 'Change a character’s voice and save the book',
    fixtureId: 'editable-book',
    question: 'Can you tell that the chosen character changed voices? Does the rest of the scene still sound as you expect?',
    steps: ['Open the provided audio book with File → Open and listen to the marked exchange.', 'Use the Character voice control to change the named character to the suggested voice. Listen to the same exchange again.', 'Choose File → Save Audio Book and give the copy a new name. Open your copy and listen to the exchange.'],
    expected: 'Only the chosen character sounds different. Your saved copy keeps the new voice, and the exchange is comfortable to follow.'
  }
];
