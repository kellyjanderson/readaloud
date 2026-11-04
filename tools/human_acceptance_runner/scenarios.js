/* Human listening cases target rapid changes between dialogue speakers. */
window.HUMAN_ACCEPTANCE_SCENARIOS = [
  {
    id: 'fast-two-speaker-dialogue',
    title: 'Fast back-and-forth · two voices',
    passageId: 'quick-two-speaker',
    question: 'As Mara and Jonah trade short lines, can you follow who is speaking? Do the voices switch cleanly from one line to the next?',
    steps: ['Copy the passage below.', 'In Read Aloud, choose File → Paste Text and paste it.', 'Press Play and listen through the exchange.'],
    expected: 'The conversation is easy to follow. Voices change when the speaker changes, with no line that seems skipped, repeated, spoken by the wrong character, or cut off.'
  },
  {
    id: 'fast-three-speaker-dialogue',
    title: 'Fast back-and-forth · three voices',
    passageId: 'quick-three-speaker',
    question: 'When Mara, Jonah, and Niko take quick turns, can you keep track of them? Does a speaker change sound clear and timely?',
    steps: ['Copy the passage below.', 'In Read Aloud, choose File → Paste Text and paste it.', 'Press Play and listen through the exchange.'],
    expected: 'The three speakers remain distinguishable across quick turns. No line seems skipped, repeated, assigned to the wrong character, or cut off.'
  }
];
