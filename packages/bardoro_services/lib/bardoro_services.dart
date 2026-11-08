// SPDX-License-Identifier: GPL-3.0-or-later
/// Application services for Bardoro: everything between `bardoro_core` (pure
/// pipeline logic) and the Flutter UI.
///
/// * structure comes from `zero_nads` (`Result`, `Task`, `Option`, `Snapshot`);
/// * concurrency comes from `volley` (a coroutine for epub analysis, an actor
///   for the long-running conversion).
library;

export 'src/analysis.dart';
export 'src/conversion.dart';
export 'src/conversion_progress.dart';
export 'src/job_builder.dart';
export 'src/library.dart';
export 'src/settings.dart';
export 'src/words_file.dart';
