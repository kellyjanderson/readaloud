import 'package:flutter/material.dart';

class ReadingFocusRecenterButton extends StatelessWidget {
  const ReadingFocusRecenterButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.my_location),
      label: const Text('Recenter'),
    );
  }
}
