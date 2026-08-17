# Dragon Fruit Flower Counter

A Flutter (Android-first, Material 3) app for dragon fruit farmers to map every
post in a farm and record flower counts over time — offline-first, built for
fast one-tap-per-post workflows in bright sunlight.

## Getting it running

This project was authored as pure Dart/Flutter source in an environment
without the Flutter SDK installed, so it has **not** been run through
`flutter pub get` / `flutter analyze` / `flutter build`. Before running it:

```bash
# From an empty-ish checkout of this folder (it already has lib/ and pubspec.yaml):
flutter create . --project-name dragon_fruit_flower_counter --org com.yourcompany
# ^ This scaffolds android/, ios/, and platform boilerplate without touching
#   the existing lib/ or pubspec.yaml (Flutter merges, it won't overwrite).

flutter pub get
flutter run
```

Then do a normal `flutter analyze` pass — with ~30 hand-written files there
may be a small number of naming/import nits to fix on a real SDK (none were
found in manual review, but this hasn't been compiler-verified).

## Architecture

Clean-architecture-flavored layering:

```
lib/
  core/            # theme, constants, the SQLite DatabaseHelper (no business logic)
  data/
    models/        # plain Dart data classes + toMap/fromMap
    repositories/  # all SQL lives here — screens/providers never import sqflite directly
  presentation/
    providers/     # ChangeNotifier view-models (Provider package)
    screens/       # one folder per feature area
    widgets/       # shared widgets (canvas, popups, post marker)
    utils/         # export (CSV/Excel/PDF) and backup helpers
  main.dart
```

### Why it's built this way
- **Repositories are the only thing that touches SQLite.** Swapping to a
  cloud backend later means adding a new repository implementation behind
  the same method signatures — providers and screens don't change.
- **UUID primary keys + `updated_at`/`is_synced` columns** on every table,
  so a future sync layer can diff local vs. remote without a migration that
  touches keys.
- **`LayoutEditorProvider` and `CountingProvider` are screen-scoped**
  (created via `ChangeNotifierProvider` right where their screen is pushed),
  while `FarmProvider`/`SettingsProvider` live for the app's lifetime — this
  keeps memory bounded even on a farm with thousands of posts across many
  sessions.

## Feature coverage vs. the spec

**Implemented:**
- Home screen, farm CRUD, layout editor (add/move/delete/duplicate/undo/redo,
  pinch-zoom/pan, optional grid snap)
- Fast Count Mode: tap → popup → number → save → auto-close → next post,
  with live running totals by color and grand total
- Gray → flowering-bubble post state transitions, editable after the fact
- Session history list, tapping a date reopens that day's layout with counts
- Long-press post detail page: flower history table + photo attachments
- Search by Post ID (highlights the match) and filter by color / counted
  status on the counting canvas
- Statistics dashboard: week/month/season totals, average per post, highest
  and lowest producing post, average by color, 30-day line chart
- CSV / Excel / PDF export, Settings (theme, units, DB backup/share)

**Stubbed / left as extension points** (flagged with comments in code):
- Restore-from-backup only shows a placeholder — wiring a file picker to
  actually replace the live `.db` file is a small, isolated follow-up
- Cloud sync itself is not implemented — the schema is ready for it
  (see `is_synced` columns), but no sync client exists yet
- GPS-per-post and QR codes have DB columns (`latitude`, `longitude`,
  `qr_code`) but no UI yet
- AI camera counting, multi-worker concurrent counting, weather/harvest/
  irrigation/fertilizer records are unbuilt, per "Future Ready" in the spec
