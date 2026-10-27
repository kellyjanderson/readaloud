/* Human-facing checks based on the frozen, reviewed RC2 prose passages. */
window.HUMAN_ACCEPTANCE_SCENARIOS = [
  {
    id: 'p0-narrator', title: 'Narration without dialogue', passageId: 'tide',
    question: 'Does the narration sound clear and steady? In Character Voices, do you see a narrator without any character voices?',
    steps: ['Copy the passage below.', 'In Read Aloud, choose File → Paste Text and paste the passage.', 'Press Play and listen for a few paragraphs.', 'Open Character Voices and look at the people listed there.'],
    expected: 'The passage is read by the narrator. No dialogue character is listed because nobody speaks in this passage.'
  },
  {
    id: 'p1-one-person', title: 'One person speaks', passageId: 'lantern',
    question: 'Can you tell when Mara speaks? Does the voice list show Mara without adding Ellis, who is only mentioned?',
    steps: ['Copy the passage below and paste it into Read Aloud with File → Paste Text.', 'Press Play. Listen to Mara’s spoken lines and the surrounding narration.', 'Open Character Voices and check the names.'],
    expected: 'The list has the narrator and Mara. Mara’s speech is read with her selected voice; Ellis does not appear as a speaker.'
  },
  {
    id: 'p2-two-people', title: 'Two people talk', passageId: 'orchard',
    question: 'Are Mara and Jonah easy to follow as the conversation changes speaker?',
    steps: ['Copy the passage below and paste it into Read Aloud.', 'Press Play and listen through several exchanges.', 'Open Character Voices and check the names.'],
    expected: 'The list has the narrator, Mara and Jonah. The spoken lines are easy to follow, and the people only mentioned in the story are not listed as speakers.'
  },
  {
    id: 'p3-three-people', title: 'Three people talk', passageId: 'platform',
    question: 'Can you follow the conversation as Niko joins Mara and Jonah?',
    steps: ['Copy the passage below and paste it into Read Aloud.', 'Press Play and listen for the changes between speakers.', 'Open Character Voices and check the names.'],
    expected: 'The list has the narrator, Mara, Jonah and Niko. Ellis, who is only mentioned, is not listed as a speaker.'
  },
  {
    id: 'p4-four-people', title: 'Four people talk', passageId: 'bridge',
    question: 'Can you keep track of Mara, Jonah, Niko and Saira? Does the voice list stay understandable?',
    steps: ['Copy the passage below and paste it into Read Aloud.', 'Press Play and listen through the conversation.', 'Open Character Voices and check the names.'],
    expected: 'The list has the narrator, Mara, Jonah, Niko and Saira. Ellis is mentioned but does not speak, so Ellis is not listed.'
  },
  {
    id: 'choose-voices', title: 'Choose character voices', passageId: 'orchard',
    question: 'Can you choose different voices for Mara and Jonah, and hear the choices while they speak?',
    steps: ['Copy the passage below and paste it into Read Aloud.', 'Open Character Voices. Choose different voices for Mara and Jonah, then apply your choices.', 'Press Play. Listen for each person’s voice.', 'Quit and reopen Read Aloud, then paste the passage again and check whether your choices are remembered.'],
    expected: 'Voice choices are available for both people. Their lines use the voices you selected, and the choices remain after reopening the app.'
  },
  {
    id: 'reading-along', title: 'Read along while listening', passageId: 'bridge',
    question: 'Is it comfortable to follow the highlighted words while the passage is spoken? Do scrolling and playback controls feel understandable?',
    steps: ['Copy the passage below and paste it into Read Aloud.', 'Press Play and follow the highlighted words.', 'Scroll the page and use Back 30 seconds and Forward 30 seconds.', 'Listen for any obvious repeated words, missing lines or interruptions.'],
    expected: 'The highlighted text is easy to follow, controls behave as their labels suggest, and the passage plays without an obvious interruption.'
  }
];
