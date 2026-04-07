import 'package:flutter/material.dart';

enum ReaderAppearanceMode {
  system,
  light,
  dark;

  ThemeMode get themeMode => switch (this) {
    ReaderAppearanceMode.system => ThemeMode.system,
    ReaderAppearanceMode.light => ThemeMode.light,
    ReaderAppearanceMode.dark => ThemeMode.dark,
  };

  String get storageValue => name;

  String get label => switch (this) {
    ReaderAppearanceMode.system => 'Follow System',
    ReaderAppearanceMode.light => 'Light',
    ReaderAppearanceMode.dark => 'Dark',
  };

  static ReaderAppearanceMode fromStorageValue(String? value) {
    for (final mode in ReaderAppearanceMode.values) {
      if (mode.storageValue == value) {
        return mode;
      }
    }
    return ReaderAppearanceMode.system;
  }
}
