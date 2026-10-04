# Cashy — Voice Expense Tracker

Speak to log income and expenses. Fully offline, on-device, privacy-first.

> Looking for how to *use* the app? See the [User Guide](USER_GUIDE.md). Working on the code? See [CLAUDE.md](CLAUDE.md) for architecture notes.

## Tech Stack

| Layer | Library | Size |
|-------|---------|-----:|
| STT (EN) | Moonshine Tiny via `sherpa_onnx` | **~124 MB** |
| STT (ZH) | SenseVoice via `sherpa_onnx` | **~240 MB** |
| NLU | Pattern-based extractor (EN + ZH) | 0 MB |
| DB | SQLite via `sqflite` | 0 MB |
| State | Provider | 0 MB |
| Audio | `record` (16 kHz, PCM int16) | 0 MB |
| **Total** | | **~364 MB** |

## Prerequisites

- Flutter SDK 3.5+ ([install guide](https://docs.flutter.dev/get-started/install))
- A physical Android/iOS device (Moonshine won't run well on emulators)

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Download model files

Extract each into `assets/models/<model_name>/`. The app copies them to the device on first launch.

#### English STT — Moonshine Tiny (~124 MB)

```bash
# Download from sherpa-onnx releases
curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-moonshine-tiny-en-int8.tar.bz2

# Extract into assets/models/moonshine-tiny-en/
tar xvf sherpa-onnx-moonshine-tiny-en-int8.tar.bz2
mkdir -p assets/models/moonshine-tiny-en/
cp sherpa-onnx-moonshine-tiny-en-int8/* assets/models/moonshine-tiny-en/
```

Expected files:
```
assets/models/moonshine-tiny-en/
├── encode.int8.onnx          # encoder model
├── cached_decode.int8.onnx   # decoder model (cached)
├── tokens.txt                # token vocabulary
├── preprocess.onnx           # audio preprocessor
└── LICENSE
```

#### Chinese STT — SenseVoice (~240 MB)

```bash
# Download from sherpa-onnx releases
curl -SL -O https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2

# Extract into assets/models/sense-voice-zh-en/
tar xvf sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2
mkdir -p assets/models/sense-voice-zh-en/
cp sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/* assets/models/sense-voice-zh-en/
```

Expected files:
```
assets/models/sense-voice-zh-en/
├── model.int8.onnx            # quantized model
├── tokens.txt                 # token vocabulary
└── ...
```

> If you can't use `curl`, download the `.tar.bz2` files manually from:
> - [sherpa-onnx/releases/tag/asr-models](https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models)
> - Search for "moonshine" and "sense-voice" in the assets list.
>
> Then place the extracted files as shown above.

### 3. Run

```bash
flutter run
```

## How It Works

```
User selects language (EN / 中文)
    → Tap & hold mic → speak → release
    → Audio (16 kHz PCM) → sherpa_onnx → text
    → Pattern extractor → { amount, category, ... }
    → User confirms → saved to local SQLite → balance updates
```

### Key Files

| File | Purpose |
|------|---------|
| `lib/voice/stt_service.dart` | Microphone + sherpa_onnx (Moonshine/SenseVoice) |
| `lib/nlu/pattern_extractor_en.dart` | English expense/income parser |
| `lib/nlu/pattern_extractor_zh.dart` | Chinese expense/income parser |
| `lib/nlu/hybrid_extractor.dart` | Routes to correct language parser |
| `lib/db/database_helper.dart` | SQLite schema, CRUD, seeds defaults |
| `lib/screens/voice_input_sheet.dart` | Hold-to-speak UI + parsed result |
| `lib/screens/dashboard_screen.dart` | Balance + categories overview |

## Model Architecture

```
English selected:
  ─→ Moonshine Tiny (~124 MB int8, this build's asset files)
      Best accuracy/size ratio for EN.
      ~4.5% WER on LibriSpeech — beats Whisper Tiny.

Chinese selected:
  ─→ SenseVoice (~240 MB int8, this build's asset files)
      Handles ZH + EN + JA + KO + Cantonese.
      ~95% accuracy on Mandarin in quiet environments.
```

## Data Model

```sql
transactions (id, type, amount, currency, amount_in_base,
              category_name, note, created_at, raw_voice)

categories   (id, name, type, icon, keywords_en, keywords_zh)
settings     (key, value)  -- JSON: base_currency, language, budget
exchange_rates (from_currency, to_currency, rate, is_manual)
```

## Exchange Rates

Default rates are seeded on first launch (approximate). Edit them in Settings (edited rates are kept as "set by you"). Only used to convert spoken currency to the user's base currency for dashboard totals; any pair of currencies converts, using a third currency as a bridge when there is no direct rate.

Optional monthly download: put a `rates.json` on your website (run `tools/update_rates.ps1` to create it), then set `RatesService.ratesUrl` in `lib/services/rates_service.dart` to its https address. The app then fetches it at most once per calendar month, or when you tap "Update now" in Settings. Leave `ratesUrl` empty to keep the app fully offline.

## Future Upgrades

- **TinyBERT fallback** — when pattern matching fails, run a small BERT model (~17 MB). Uncomment the dependencies in `pubspec.yaml`.
- **Recurring transactions** — monthly patterns (rent, salary).
- **CSV export** — share transaction history.

## Testing

```bash
flutter test
```

## License

MIT
