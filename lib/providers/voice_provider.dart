import 'package:flutter/foundation.dart';
import '../voice/stt_service.dart';
import '../nlu/hybrid_extractor.dart';
import '../models/transaction.dart';

/// Manages the voice recording → STT → NLU pipeline state.
///
/// States:
///   idle → recording → transcribing → parsed → confirming → saved
///   idle → recording → transcribing → failed → idle
enum VoiceState { idle, recording, transcribing, parsed, failed }

class VoiceProvider extends ChangeNotifier {
  final SttService _stt = SttService();
  final HybridExtractor _nlu = HybridExtractor();

  VoiceState _state = VoiceState.idle;
  String _currentTranscript = '';
  ParsedTransaction? _lastResult;
  String _errorMessage = '';
  String _activeLanguage = 'en';
  bool _loading = true;
  bool _disposed = false;
  Future<void>? _starting;

  /// True while the speech models are still loading (mic taps are ignored).
  bool get isLoading => _loading;

  VoiceState get state => _state;
  String get transcript => _currentTranscript;
  ParsedTransaction? get lastResult => _lastResult;
  String get errorMessage => _errorMessage;
  String get activeLanguage => _activeLanguage;

  bool get isRecording => _state == VoiceState.recording;
  bool get isProcessing => _state == VoiceState.transcribing;
  bool get isIdle => _state == VoiceState.idle;

  // ── Lifecycle ───────────────────────────────────────────────

  /// Initialize the STT service (load models).
  Future<void> initialize() async {
    try {
      await _stt.initialize(defaultLanguage: _activeLanguage);
      // Show model-load errors in the UI (models not downloaded).
      if (!_stt.modelStatus.anyReady && _stt.modelStatus.errors.isNotEmpty) {
        _errorMessage = _stt.modelStatus.errors.first;
      }
    } catch (e) {
      _errorMessage = 'Failed to initialize STT: $e';
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Toggle between EN and ZH.
  void setLanguage(String lang) {
    _activeLanguage = lang;
    _stt.setLanguage(lang);
    notifyListeners();
  }

  // ── Recording flow ──────────────────────────────────────────

  /// Start listening.
  Future<void> startRecording() async {
    if (_loading) {
      debugPrint('VOICE: models still loading, ignoring tap');
      return;
    }
    if (_state == VoiceState.recording) {
      debugPrint('VOICE: already recording, ignoring');
      return;
    }
    _currentTranscript = '';
    _lastResult = null;
    _errorMessage = '';
    _state = VoiceState.recording;
    notifyListeners();
    debugPrint('VOICE: state → recording');

    try {
      final starting = _stt.startListening();
      _starting = starting;
      await starting;
      debugPrint('VOICE: startListening OK');
    } catch (e) {
      debugPrint('VOICE: startListening ERROR: $e');
      _errorMessage = 'Microphone error: $e';
      _state = VoiceState.failed;
      notifyListeners();
    }
  }

  /// Stop recording and run STT + NLU.
  Future<void> stopRecording() async {
    if (_state != VoiceState.recording) {
      debugPrint('VOICE: stopRecording called but state is $_state, ignoring');
      return;
    }
    _state = VoiceState.transcribing;
    notifyListeners();
    debugPrint('VOICE: state → transcribing');

    try {
      // A quick tap can release before the recorder has finished starting
      // (e.g. while the permission prompt is up); let it finish first.
      try {
        await _starting;
      } catch (_) {
        return; // startRecording() already reported the failure.
      }
      if (_state != VoiceState.transcribing) return;

      // Run STT.
      final sttResult = await _stt.stopListening();
      _currentTranscript = sttResult.text;
      debugPrint('VOICE: STT result → "$_currentTranscript" (empty=${sttResult.isEmpty})');

      if (sttResult.isTooShort) {
        _errorMessage = 'Hold the mic a little longer and speak clearly, then release.';
        _state = VoiceState.failed;
        notifyListeners();
        return;
      }

      if (sttResult.isEmpty) {
        _errorMessage = 'No speech detected. Try again.';
        _state = VoiceState.failed;
        notifyListeners();
        return;
      }

      // Run NLU on the transcribed text.
      final lang = sttResult.language;
      final parsed = _nlu.extract(_currentTranscript, language: lang);
      _lastResult = parsed;
      debugPrint('VOICE: NLU result → ${parsed != null ? "parsed" : "null"}');

      if (parsed == null) {
        _errorMessage =
            'Could not understand the expense. Please type it in.';
        _state = VoiceState.failed;
        notifyListeners();
        return;
      }

      _state = VoiceState.parsed;
    } catch (e) {
      debugPrint('VOICE: stopRecording ERROR: $e');
      _errorMessage = 'Recognition error: $e';
      _state = VoiceState.failed;
    }
    notifyListeners();
  }

  /// Cancel current recording without processing.
  Future<void> cancelRecording() async {
    await _stt.cancel();
    _currentTranscript = '';
    _lastResult = null;
    _errorMessage = '';
    _state = VoiceState.idle;
    notifyListeners();
  }

  /// Helper used by the text-input flow to update the transcript.
  void updateTranscript(String text) {
    _currentTranscript = text;
  }

  /// Helper used by the text-input flow to go to parsed state.
  void setStateParsed(ParsedTransaction result) {
    _lastResult = result;
    _state = VoiceState.parsed;
    notifyListeners();
  }

  /// Helper used by the text-input flow to go to failed state.
  void setStateFailed(String message) {
    _errorMessage = message;
    _state = VoiceState.failed;
    notifyListeners();
  }

  /// User has edited the parsed result → update it.
  void updateParsedResult(ParsedTransaction updated) {
    _lastResult = updated;
    notifyListeners();
  }

  /// Reset to idle after saving or discarding.
  void reset() {
    _currentTranscript = '';
    _lastResult = null;
    _errorMessage = '';
    _state = VoiceState.idle;
    notifyListeners();
  }

  /// Process typed text directly (skips STT, runs NLU only).
  void processText(String text) {
    if (text.trim().isEmpty) return;
    _currentTranscript = text.trim();

    final parsed = _nlu.extract(_currentTranscript, language: _activeLanguage);
    _lastResult = parsed;

    if (parsed == null) {
      _errorMessage = 'Could not understand: "$text". Try a different format, '
          'e.g. "spent 15 on lunch" or "salary 5000".';
      _state = VoiceState.failed;
    } else {
      _state = VoiceState.parsed;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stt.dispose();
    super.dispose();
  }
}
