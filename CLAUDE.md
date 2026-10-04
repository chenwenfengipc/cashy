# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get                    # install dependencies
flutter run                        # run on the default connected device
flutter run -d windows             # run on Windows desktop (also: macos, linux, chrome, or an Android/iOS device id from `flutter devices`)
flutter analyze                    # static analysis (uses flutter_lints defaults, no custom rules in analysis_options.yaml)
flutter test                       # run the full test suite
flutter test test/nlu_test.dart    # run a single test file
flutter test --plain-name "income detection"   # run a single test by name (matches across files)
flutter build windows --debug      # debug build; swap `windows` for apk/ios/macos/linux as needed
```

### On-device STT models

The app bundles two `sherpa_onnx` ASR models as Flutter assets under `assets/models/` (Moonshine Tiny for English, SenseVoice for Chinese). These are large binary files (tens to ~240 MB) fetched separately per the download steps in `README.md` — if `assets/models/moonshine-tiny-en/` or `assets/models/sense-voice-zh-en/` are missing their `.onnx`/`tokens.txt` files, the app still builds and runs but `SttService` logs missing-file errors and voice input is disabled (text input still works). On first launch the app copies these from the asset bundle into the platform's application-documents directory (`sherpa_models/`) before loading them.

## Architecture

### Layers and data flow

```
lib/models/     plain data classes (Transaction, TransactionCategory, AppSettings, ExchangeRate, ParsedTransaction)
lib/db/         DatabaseHelper — singleton SQLite access (schema, seeds, CRUD, aggregation queries)
lib/nlu/        text → ParsedTransaction (pattern-based, no ML)
lib/voice/      microphone → transcript (sherpa_onnx wrapper)
lib/services/   BackupService — JSON export/import of the full dataset
lib/providers/  ChangeNotifier state glueing the above to the UI
lib/screens/, lib/widgets/   UI
```

Voice-to-transaction pipeline: hold-to-record in `voice_input_sheet.dart` → `VoiceProvider` drives `SttService` (mic capture via `record`, on-device recognition via `sherpa_onnx`: Moonshine for English, SenseVoice for Chinese) → resulting transcript is handed to `HybridExtractor`, which auto-detects EN vs ZH (presence of CJK characters) and delegates to `PatternExtractorEn`/`PatternExtractorZh` → each extractor independently regexes out amount+currency, classifies expense/income by verb keyword lists, parses relative dates ("yesterday", "上周一"), assigns a category by keyword hit-count, and strips all recognized tokens from the original text to leave a free-text note → the resulting `ParsedTransaction` is shown in `ParsedResultPreview` for the user to correct before `TransactionProvider.addTransaction()` persists it. Typed input skips STT and enters the same `HybridExtractor` step directly (`VoiceProvider.processText`).

Both `NluExtractor` implementations are pure pattern/keyword matching. A `HybridExtractor` fallback slot to a small ML model ("TinyBERT", triggered when confidence is below `NluExtractor.confidenceThreshold`) is scaffolded but commented out — see `hybrid_extractor.dart` and the commented dependencies in `pubspec.yaml`.

### Currency handling

Every `Transaction` stores both its original `amount`/`currency` and an `amountInBase` computed at entry time via `SettingsProvider.convertToBase()` → `DatabaseHelper.convertCurrency()`, which builds a `RateTable` (`lib/utils/rate_table.dart`) from the `exchange_rates` table and resolves any pair directly, by inverse, or through a third currency (so the seeded MYR-based rows still cover every pair under any base currency). Rows are built-in estimates, rates downloaded from the project website, or user-typed (`is_manual = 1`, kept across downloads). `RatesService` (`lib/services/rates_service.dart`) fetches a small JSON file from `RatesService.ratesUrl` — empty by default, which switches the feature off — at most once per calendar month at startup (`SettingsProvider.autoRefreshRatesIfDue`) or on "Update now"; `tools/update_rates.ps1` generates that file. Dashboard aggregates (`totalIncome`, `categoryBreakdown`, `getMonthlyTotals`) all sum `amount_in_base`, so changing a rate later does not retroactively change historical totals.

### STT concurrency invariant

`SttService` guards `startListening()` / `stopListening()` / `cancel()` with an internal `_opId` counter because `startListening()` has two real `await` points (permission check, then `_recorder.startStream()`) before it can mark itself recording. Any change to this file must preserve the invariant that a `startListening()` call detects if it was superseded by a stop/cancel that happened during that window, and tears the recorder back down itself — otherwise the native mic stream leaks with nothing left to stop it.

### State management

`main.dart` creates a single `MultiProvider` for the app's lifetime holding `SettingsProvider` and `TransactionProvider` (both loaded from SQLite before `runApp`). `VoiceProvider`, by contrast, is instantiated fresh inside `VoiceInputSheet.initState()` and disposed when the sheet closes — it is not a long-lived singleton like the other two.

### Database

`DatabaseHelper` (`lib/db/database_helper.dart`) is a singleton opened once (`sqflite` on mobile, `sqflite_common_ffi` on Windows/macOS/Linux — selected in `main.dart` based on `Platform.is*` before `runApp`). Schema changes must go through `_upgradeTables` (an `onUpgrade` callback keyed by `if (oldVersion < N)` blocks) with `_dbVersion` bumped — `_createTables` alone only runs for a brand-new database file.

### Backup format

`BackupService` reads/writes a self-describing JSON document (`app`, `backup_version`, `settings`, `exchange_rates`, `categories`, `transactions`) via the OS share sheet (export) or a local-file picker limited to the app's own documents directory (restore — there is no cross-app file picker dependency). Import is an intentional non-destructive merge: transactions are matched by `id`, categories by `name` + `type`; nothing already in the database is deleted by an import.
