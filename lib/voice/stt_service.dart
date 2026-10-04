import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Describes which STT models are available.
class SttModelStatus {
  final bool enReady;
  final bool zhReady;
  final List<String> errors;

  const SttModelStatus({
    this.enReady = false,
    this.zhReady = false,
    this.errors = const [],
  });

  bool get anyReady => enReady || zhReady;
}

/// Result emitted by the STT pipeline.
class SttResult {
  final String text;
  final String language; // "en" or "zh"
  final bool isEmpty;
  final bool isTooShort;

  const SttResult({
    required this.text,
    this.language = 'en',
    this.isEmpty = false,
    this.isTooShort = false,
  });

  // Factory for an empty result when no speech is detected.
  static const empty = SttResult(text: '', isEmpty: true);

  // Factory for a recording held too briefly to contain a full phrase —
  // skipped before recognition rather than fed to the model and
  // misrecognised as garbage.
  static const tooShort = SttResult(text: '', isEmpty: true, isTooShort: true);
}

/// Wraps microphone recording + sherpa_onnx for on-device STT.
///
/// Architecture:
///   English â†’ Moonshine Tiny (~124 MB int8, optimized for EN)
///   Chinese â†’ SenseVoice (supports ZH + EN, ~240 MB)
///
/// Models are downloaded separately (see README) and placed in
/// [appDocuments]/sherpa_models/[model_name]/
class SttService {
  static const _sampleRate = 16000;

  // Below this, a hold-to-record gesture almost certainly cut off the
  // phrase before it finished — feeding it to the model tends to produce
  // confident-sounding but wrong text rather than a clean failure, so we
  // skip recognition entirely and ask the user to hold longer instead.
  static const _minRecordingMs = 900;

  final AudioRecorder _recorder = AudioRecorder();
  final List<int> _audioBuffer = [];
  bool _isRecording = false;
  bool _initialized = false;

  OfflineRecognizer? _recognizerEn; // Moonshine (EN)
  OfflineRecognizer? _recognizerZh; // SenseVoice (ZH)
  String _activeLanguage = 'en';

  String? _modelDir;
  final List<String> _initErrors = [];

  /// Current model load status.
  SttModelStatus get modelStatus => SttModelStatus(
    enReady: _recognizerEn != null,
    zhReady: _recognizerZh != null,
    errors: List.unmodifiable(_initErrors),
  );

  // List of model files for Moonshine EN (V1 format).
  // V1 requires both cachedDecoder AND uncachedDecoder.
  static const _moonshineFiles = [
    'encode.int8.onnx',
    'cached_decode.int8.onnx',
    'uncached_decode.int8.onnx',
    'preprocess.onnx',
    'tokens.txt',
  ];

  // List of model files for SenseVoice ZH.
  static const _senseVoiceFiles = [
    'model.int8.onnx',
    'tokens.txt',
  ];

  // â”€â”€ Initialization â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> initialize({String defaultLanguage = 'en'}) async {
    if (_initialized) return;

    // Load the native sherpa-onnx shared library (DLL/.so/.dylib).
    // Must be called once before creating any recognizer.
    initBindings();

    _activeLanguage = defaultLanguage;
    _initErrors.clear();

    final appDir = await getApplicationDocumentsDirectory();
    _modelDir = p.join(appDir.path, 'sherpa_models');
    debugPrint('STT: appDocDir=$appDir');
    debugPrint('STT: modelDir=$_modelDir');
    await Directory(_modelDir!).create(recursive: true);

    // Copy models from Flutter asset bundle â†’ documents directory.
    await _copyModelsFromAssets('moonshine-tiny-en', _moonshineFiles);
    await _copyModelsFromAssets('sense-voice-zh-en', _senseVoiceFiles);

    // Ensure all required files exist â€” search in subdirectories, etc.
    await _ensureModelFiles('moonshine-tiny-en', _moonshineFiles);
    await _ensureModelFiles('sense-voice-zh-en', _senseVoiceFiles);

    await _loadMoonshineEn();
    await _loadSenseVoiceZh();

    debugPrint('STT: EN model ready=${_recognizerEn != null}  ZH model ready=${_recognizerZh != null}  errors=${_initErrors.length}');

    _initialized = true;
  }

  /// Copy model files from [assets/models/<subDir>/] (Flutter bundle)
  /// to the app documents directory if they don't already exist there.
  Future<void> _copyModelsFromAssets(String subDir, List<String> files) async {
    final targetDir = p.join(_modelDir!, subDir);
    await Directory(targetDir).create(recursive: true);

    for (final file in files) {
      final targetPath = p.join(targetDir, file);
      if (File(targetPath).existsSync()) continue; // already copied.

      final assetPath = 'assets/models/$subDir/$file';
      try {
        final data = await rootBundle.load(assetPath);
        debugPrint('STT: loaded $assetPath (${data.lengthInBytes} bytes)');
        await File(targetPath).writeAsBytes(data.buffer.asUint8List());
        debugPrint('STT: wrote â†’ $targetPath');
      } catch (e) {
        debugPrint('STT: FAILED to copy $assetPath â€” $e');
      }
    }
  }

  /// Ensure that all [requiredFiles] exist inside [subDir] under the models
  /// directory. If they are missing, search recursively in subfolders
  /// (common .tar.bz2 extraction artefact) and copy them up.
  Future<void> _ensureModelFiles(String subDir, List<String> requiredFiles) async {
    final modelDir = p.join(_modelDir!, subDir);
    await Directory(modelDir).create(recursive: true);

    final missing = requiredFiles
        .where((f) => !File(p.join(modelDir, f)).existsSync())
        .toList();
    if (missing.isEmpty) return; // all good

    debugPrint('STT: $subDir missing $missing â€” searching subdirectoriesâ€¦');

    // List what's actually inside modelDir.
    try {
      final entries = Directory(modelDir).listSync(recursive: false);
      for (final e in entries) {
        debugPrint('STT:   entry: ${e.path}  (${e is Directory ? "dir" : "file"})');
      }
    } catch (_) {}

    // Search one level deep for the missing files.
    for (final file in missing.toList()) {
      // Look in subdirectories of modelDir.
      final subDirs = Directory(modelDir).listSync().whereType<Directory>();
      for (final dir in subDirs) {
        final candidate = p.join(dir.path, file);
        if (File(candidate).existsSync()) {
          await File(candidate).copy(p.join(modelDir, file));
          debugPrint('STT: recovered $file from ${p.basename(dir.path)}');
          missing.remove(file);
          break;
        }
      }
    }

    if (missing.isNotEmpty) {
      _initErrors.add(
        '$subDir model missing files: ${missing.join(", ")}\n'
        'Put them in: $modelDir\n'
        'See README.md for download links.',
      );
    }
  }

  /// Moonshine Tiny English (int8 quantized, V1 format)
  ///
  /// V1 requires both [cachedDecoder] and [uncachedDecoder] in the config.
  Future<void> _loadMoonshineEn() async {
    final modelDir = p.join(_modelDir!, 'moonshine-tiny-en');
    final encoder = p.join(modelDir, 'encode.int8.onnx');
    final cachedDecoder = p.join(modelDir, 'cached_decode.int8.onnx');
    final uncachedDecoder = p.join(modelDir, 'uncached_decode.int8.onnx');
    final preprocessor = p.join(modelDir, 'preprocess.onnx');
    final tokens = p.join(modelDir, 'tokens.txt');

    // Final check â€” if _ensureModelFiles already reported, we still try to load
    // in case some files were found.
    final missing = <String>[];
    if (!File(encoder).existsSync()) missing.add('encode.int8.onnx');
    if (!File(cachedDecoder).existsSync()) missing.add('cached_decode.int8.onnx');
    if (!File(uncachedDecoder).existsSync()) missing.add('uncached_decode.int8.onnx');
    if (!File(preprocessor).existsSync()) missing.add('preprocess.onnx');
    if (!File(tokens).existsSync()) missing.add('tokens.txt');

    debugPrint('STT: Moonshine dir=$modelDir  missing=$missing');

    if (missing.isNotEmpty) {
      // Only add error if _ensureModelFiles didn't already.
      if (!_initErrors.any((e) => e.contains('moonshine-tiny-en'))) {
        _initErrors.add(
          'Moonshine EN model missing files: ${missing.join(", ")}\n'
          'Put them in: $modelDir',
        );
      }
      return;
    }

    try {
      _recognizerEn = OfflineRecognizer(
        OfflineRecognizerConfig(
          feat: const FeatureConfig(),
          model: OfflineModelConfig(
            moonshine: OfflineMoonshineModelConfig(
              encoder: encoder,
              cachedDecoder: cachedDecoder,
              uncachedDecoder: uncachedDecoder,
              preprocessor: preprocessor,
            ),
            tokens: tokens,
            numThreads: 2,
            provider: 'cpu',
            debug: true,
          ),
          decodingMethod: 'greedy_search',
        ),
      );
      debugPrint('STT: Moonshine EN loaded OK');
    } catch (e) {
      _initErrors.add('Moonshine EN load error: $e');
      debugPrint('STT: Moonshine EN load FAILED: $e');
    }
  }

  /// SenseVoice (Chinese + English + Japanese + Korean + Cantonese)
  Future<void> _loadSenseVoiceZh() async {
    final modelDir = p.join(_modelDir!, 'sense-voice-zh-en');
    final model = p.join(modelDir, 'model.int8.onnx');
    final tokens = p.join(modelDir, 'tokens.txt');

    final missing = <String>[];
    if (!File(model).existsSync()) missing.add('model.int8.onnx');
    if (!File(tokens).existsSync()) missing.add('tokens.txt');

    if (missing.isNotEmpty) {
      if (!_initErrors.any((e) => e.contains('sense-voice-zh-en'))) {
        _initErrors.add(
          'SenseVoice ZH model missing files: ${missing.join(", ")}\n'
          'Put them in: $modelDir',
        );
      }
      return;
    }

    try {
      _recognizerZh = OfflineRecognizer(
        OfflineRecognizerConfig(
          feat: const FeatureConfig(),
          model: OfflineModelConfig(
            senseVoice: OfflineSenseVoiceModelConfig(
              model: model,
              language: 'zh',
            ),
            tokens: tokens,
            numThreads: 2,
            provider: 'cpu',
            debug: false,
          ),
          decodingMethod: 'greedy_search',
        ),
      );
      debugPrint('STT: SenseVoice ZH loaded OK');
    } catch (e) {
      _initErrors.add('SenseVoice ZH load error: $e');
      debugPrint('STT: SenseVoice ZH load FAILED: $e');
    }
  }

  // â”€â”€ Language control â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void setLanguage(String lang) {
    assert(lang == 'en' || lang == 'zh');
    _activeLanguage = lang;
  }

  String get activeLanguage => _activeLanguage;

  bool get isModelReady {
    if (_activeLanguage == 'zh') return _recognizerZh != null;
    return _recognizerEn != null;
  }

  // â”€â”€ Recording â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  StreamSubscription<Uint8List>? _streamSubscription;

  // Bumped by stopListening()/cancel() so a startListening() call that is
  // still awaiting permission/stream setup can detect it was superseded
  // and clean itself up instead of leaving an orphaned recording stream.
  int _opId = 0;

  Future<void> startListening() async {
    if (_isRecording) return;
    final opId = ++_opId;
    _audioBuffer.clear();

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('Microphone permission not granted');
    }

    debugPrint('STT: starting stream...');
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );
    debugPrint('STT: stream started OK');

    if (opId != _opId) {
      // stopListening()/cancel() ran while we were still starting up —
      // shut the recorder back down instead of leaving it running.
      debugPrint('STT: startListening superseded — stopping recorder');
      await _recorder.stop();
      return;
    }

    _isRecording = true;

    _streamSubscription = stream.listen(
      (data) {
        if (_isRecording) {
          _audioBuffer.addAll(data);
          debugPrint('STT: received ${data.length} bytes (total buffer: ${_audioBuffer.length})');
        }
      },
      onError: (e) {
        debugPrint('STT: stream ERROR: $e');
      },
    );
  }

  Future<SttResult> stopListening() async {
    _opId++; // supersede any in-flight startListening()
    if (!_isRecording) return SttResult.empty;

    // Stop the native recorder FIRST so any buffered audio flushes
    // into the stream before we unsubscribe.
    debugPrint('STT: stopListening, buffer=${_audioBuffer.length} bytes');
    await _recorder.stop();

    // Now safe to cancel the subscription.
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _isRecording = false;

    if (_audioBuffer.isEmpty) {
      debugPrint('STT: audio buffer empty â€” no data captured');
      return SttResult.empty;
    }

    final durationMs = (_audioBuffer.length / 2) / _sampleRate * 1000;
    if (durationMs < _minRecordingMs) {
      debugPrint('STT: recording too short (${durationMs.toStringAsFixed(0)}ms) â€” skipping recognition');
      return SttResult.tooShort;
    }

    debugPrint('STT: processing ${_audioBuffer.length} bytes â†’ ${_audioBuffer.length ~/ 2} samples');

    final samples = _pcmToFloat32(_audioBuffer);
    final recognizer =
        _activeLanguage == 'zh' ? _recognizerZh : _recognizerEn;

    if (recognizer == null) {
      throw Exception(
        'STT model not loaded.\n\n'
        'Download Moonshine EN model to:\n'
        '${p.join(_modelDir!, "moonshine-tiny-en")}\n\n'
        'Or SenseVoice ZH model to:\n'
        '${p.join(_modelDir!, "sense-voice-zh-en")}\n\n'
        'See README.md for download links.',
      );
    }

    try {
      // Diagnostic: check audio level before feeding to model.
      double maxSample = 0;
      int zeroCrossings = 0;
      double prev = 0;
      for (final s in samples) {
        final abs = s < 0 ? -s : s;
        if (abs > maxSample) maxSample = abs;
        if (prev >= 0 && s < 0 || prev < 0 && s >= 0) zeroCrossings++;
        prev = s;
      }
      debugPrint('STT: audio â€” max=$maxSample  zeroCrossings=$zeroCrossings  totalSamples=${samples.length}');

      if (maxSample < 0.001) {
        debugPrint('STT: audio too quiet â€” check microphone');
        return SttResult.empty;
      }

      // Moonshine/SenseVoice expect roughly full-scale speech; a quiet OS
      // mic level (well below clipping but under this target) reliably
      // decodes to empty text rather than a bad guess. Boost it back up,
      // capping the gain so a near-silent buffer isn't amplified into noise.
      const targetPeak = 0.5;
      if (maxSample < targetPeak) {
        final gain = (targetPeak / maxSample).clamp(1.0, 20.0);
        if (gain > 1.0) {
          for (var i = 0; i < samples.length; i++) {
            samples[i] = (samples[i] * gain).clamp(-1.0, 1.0);
          }
          debugPrint('STT: boosted quiet audio ${gain.toStringAsFixed(1)}x (was max=$maxSample)');
        }
      }

      // Save WAV for offline inspection (helps identify sample-rate issues).
      // Debug builds only — this is raw voice audio and must not be
      // retained on a user's device in release builds.
      if (kDebugMode) {
        unawaited(_saveWav(List.from(_audioBuffer)));
      }

      final stream = recognizer.createStream();
      stream.acceptWaveform(
        sampleRate: _sampleRate,
        samples: Float32List.fromList(samples),
      );
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text.trim();
      stream.free();

      if (text.isEmpty) {
        debugPrint('STT: recognizer returned empty text (audio may be silence or unrecognised)');
        return SttResult.empty;
      }
      debugPrint('STT: recognised: "$text"');
      return SttResult(text: text, language: _activeLanguage);
    } catch (e) {
      debugPrint('STT: recognition error: $e');
      return SttResult(text: 'STT error: $e');
    }
  }

  Future<void> cancel() async {
    _opId++; // supersede any in-flight startListening()
    _isRecording = false;
    _audioBuffer.clear();
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    await _recorder.stop();
  }

  Future<void> dispose() async {
    await cancel();
    _recognizerEn?.free();
    _recognizerZh?.free();
    await _recorder.dispose();
    _initialized = false;
  }

  // â”€â”€ WAV diagnostic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Save PCM16 bytes as a WAV file for offline inspection.
  Future<String> _saveWav(List<int> pcmBytes, {int sampleRate = _sampleRate}) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = p.join(dir.path, 'stt_debug_$ts.wav');

    final header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, 36 + pcmBytes.length, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // (space)
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, pcmBytes.length, Endian.little);

    await File(path).writeAsBytes([...header.buffer.asUint8List(), ...pcmBytes]);
    debugPrint('STT: saved WAV â†’ $path');
    return path;
  }

  // â”€â”€ PCM conversion â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  List<double> _pcmToFloat32(List<int> bytes) {
    final samples = <double>[];
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      final sample = (bytes[i] | (bytes[i + 1] << 8)).toSigned(16);
      samples.add(sample / 32768.0);
    }
    return samples;
  }

  static List<String> supportedLanguages() => ['en', 'zh'];
}
