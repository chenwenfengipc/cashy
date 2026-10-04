import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/voice_provider.dart';
import '../providers/settings_provider.dart';
import '../models/transaction.dart';
import '../widgets/parsed_result_preview.dart';

/// Modal bottom sheet that handles the voice → STT → NLU flow,
/// with a fallback text input to type transactions directly.
///
/// Returns a map of `{'parsed': ParsedTransaction, 'amountInBase': double}`
/// when the user confirms, or null if they cancel.
class VoiceInputSheet extends StatefulWidget {
  const VoiceInputSheet({super.key});

  @override
  State<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends State<VoiceInputSheet>
    with SingleTickerProviderStateMixin {
  late VoiceProvider _voice;
  late SettingsProvider _settings;
  ParsedTransaction? _editedResult;
  final _textController = TextEditingController();

  // Ripple animation
  late AnimationController _rippleCtrl;
  late Animation<double> _ripple1;
  late Animation<double> _ripple2;
  late Animation<double> _ripple3;

  // Wave visualizer
  Timer? _waveTimer;
  final List<double> _waveHeights = List.generate(15, (_) => 4.0);

  // Transcribing dot animation
  Timer? _dotTimer;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _voice = VoiceProvider();
    _voice.initialize();

    // Ripple animation controller — pulses continuously.
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _ripple1 = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _ripple2 = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: const Interval(0.15, 0.75, curve: Curves.easeOut)),
    );
    _ripple3 = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: const Interval(0.3, 0.9, curve: Curves.easeOut)),
    );
  }

  @override
  void dispose() {
    _voice.dispose();
    _textController.dispose();
    _rippleCtrl.dispose();
    _waveTimer?.cancel();
    _dotTimer?.cancel();
    super.dispose();
  }

  void _parseText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _voice.updateTranscript(text);
    _voice.processText(text);
  }

  /// Start waveform bars animation.
  void _startWave() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _waveHeights.length; i++) {
          _waveHeights[i] = 8 + (i.isEven ? 1.0 : -1.0) * (i % 5 * 2) +
              (DateTime.now().millisecond % 24).toDouble();
        }
      });
    });
  }

  void _stopWave() {
    _waveTimer?.cancel();
  }

  /// Animated dots for "Transcribing..."
  void _startDots() {
    _dotTimer?.cancel();
    _dotTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _dotCount = (_dotCount + 1) % 4);
    });
  }

  void _stopDots() {
    _dotTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    _settings = context.read<SettingsProvider>();

    return ChangeNotifierProvider.value(
      value: _voice,
      child: Consumer<VoiceProvider>(
        builder: (context, voice, _) {
          // Start/stop wave animation based on recording state.
          if (voice.state == VoiceState.recording && _waveTimer == null) {
            _startWave();
          } else if (voice.state != VoiceState.recording) {
            _stopWave();
          }

          // Start/stop dots on transcribing.
          if (voice.state == VoiceState.transcribing && _dotTimer == null) {
            _startDots();
          } else if (voice.state != VoiceState.transcribing) {
            _stopDots();
            _dotCount = 0;
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Pre-blended to an opaque color — a translucent alpha here
                // would let the screen behind this modal (e.g. the
                // dashboard's balance card) show through the sheet.
                colors: [
                  Color.alphaBlend(
                    Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.15),
                    Theme.of(context).colorScheme.surface,
                  ),
                  Theme.of(context).colorScheme.surface,
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Title bar.
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text('Add Transaction',
                          style: Theme.of(context).textTheme.titleLarge),
                      const Spacer(),
                      // Language toggle.
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'en', label: Text('EN')),
                          ButtonSegment(value: 'zh', label: Text('中文')),
                        ],
                        selected: {voice.activeLanguage},
                        onSelectionChanged: (s) => voice.setLanguage(s.first),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Main content area with animated transitions.
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _buildContent(context, voice),
                  ),
                ),

                // Bottom action bar.
                if (voice.state == VoiceState.parsed)
                  _buildActionBar(context, voice),
              ],
            ),
          ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, VoiceProvider voice) {
    switch (voice.state) {
      case VoiceState.idle:
      case VoiceState.recording:
        return _buildMicArea(context, voice);
      case VoiceState.transcribing:
        return _buildTranscribing();
      case VoiceState.parsed:
        return _buildResult(context, voice);
      case VoiceState.failed:
        return _buildError(context, voice);
    }
  }

  // ── Mic recording area + text input fallback ────────────────

  Widget _buildMicArea(BuildContext context, VoiceProvider voice) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isRecording = voice.state == VoiceState.recording;

    return SingleChildScrollView(
      key: const ValueKey('mic_area'),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Text(
            isRecording ? 'Listening...' : 'Tap & speak your transaction',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Try: "spent 15 ringgit on lunch" or "工资5000"',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Live transcript.
          if (voice.transcript.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(voice.transcript,
                  style: const TextStyle(fontSize: 20),
                  textAlign: TextAlign.center),
            ),

          // ── Mic with ripple rings ──
          SizedBox(
            width: 170,
            height: 170,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ripple ring 3 (slowest).
                if (isRecording)
                  AnimatedBuilder(
                    animation: _ripple3,
                    builder: (context, _) {
                      final scale = 1.0 + _ripple3.value * 0.5;
                      final opacity = (1.0 - _ripple3.value) * 0.2;
                      return _rippleRing(
                        size: 80,
                        scale: scale,
                        opacity: opacity,
                        color: cs.primary,
                      );
                    },
                  ),
                // Middle ripple ring 2.
                if (isRecording)
                  AnimatedBuilder(
                    animation: _ripple2,
                    builder: (context, _) {
                      final scale = 1.0 + _ripple2.value * 0.35;
                      final opacity = (1.0 - _ripple2.value) * 0.3;
                      return _rippleRing(
                        size: 80,
                        scale: scale,
                        opacity: opacity,
                        color: cs.primary,
                      );
                    },
                  ),
                // Inner ripple ring 1 (fastest).
                if (isRecording)
                  AnimatedBuilder(
                    animation: _ripple1,
                    builder: (context, _) {
                      final scale = 1.0 + _ripple1.value * 0.2;
                      final opacity = (1.0 - _ripple1.value) * 0.4;
                      return _rippleRing(
                        size: 80,
                        scale: scale,
                        opacity: opacity,
                        color: cs.primary,
                      );
                    },
                  ),
                // Mic button.
                // Raw pointer events: a gesture recognizer would cancel the
                // hold if the finger drifts or the scroll view claims the touch.
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) {
                    debugPrint('VOICE: tap down → startRecording');
                    voice.startRecording();
                  },
                  onPointerUp: (_) {
                    debugPrint('VOICE: tap up → stopRecording');
                    voice.stopRecording();
                  },
                  onPointerCancel: (_) {
                    debugPrint('VOICE: tap cancelled → cancelRecording');
                    voice.cancelRecording();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isRecording ? Colors.red.shade50 : cs.primaryContainer,
                      border: Border.all(
                        color: isRecording ? Colors.red : cs.primary,
                        width: isRecording ? 3 : 2,
                      ),
                      boxShadow: isRecording
                          ? [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.2),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.15),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                    ),
                    child: Icon(
                      isRecording ? Icons.mic : Icons.mic_none,
                      size: 36,
                      color: isRecording ? Colors.red : cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Audio wave visualizer ──
          if (isRecording)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 32,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_waveHeights.length, (i) {
                    final opacity = 0.3 + (i % 5) * 0.12;
                    if (opacity > 1.0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200 + i * 15),
                        width: 4,
                        height: _waveHeights[i].clamp(4.0, 48.0),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: opacity),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),

          Text(
            voice.isLoading
                ? 'Loading voice model…'
                : isRecording
                    ? 'Release to transcribe'
                    : 'Tap and hold',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),

          // ── Divider ──
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ),

          // ── Text input fallback ──
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              hintText: 'Type your transaction…',
              prefixIcon: const Icon(Icons.edit_outlined),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded),
                onPressed: _parseText,
              ),
            ),
            onSubmitted: (_) => _parseText(),
            textInputAction: TextInputAction.send,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Build a single ripple ring.
  Widget _rippleRing({
    required double size,
    required double scale,
    required double opacity,
    required Color color,
  }) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(
            color: color.withValues(alpha: opacity),
            width: 2,
          ),
        ),
      ),
    );
  }

  // ── Transcribing ──

  Widget _buildTranscribing() {
    final theme = Theme.of(context);
    final dots = '.' * (_dotCount + 1);

    return Center(
      key: const ValueKey('transcribing'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: theme.textTheme.bodyLarge!,
            child: Text('Transcribing$dots'),
          ),
        ],
      ),
    );
  }

  // ── Parsed result ──

  Widget _buildResult(BuildContext context, VoiceProvider voice) {
    final result = _editedResult ?? voice.lastResult;
    if (result == null) {
      return const Center(child: Text('Could not parse result'));
    }

    return SingleChildScrollView(
      key: const ValueKey('parsed'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Original transcript.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              voice.transcript,
              style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 16),

          // Editable parsed result.
          ParsedResultPreview(
            result: result,
            onChanged: (updated) {
              _editedResult = updated;
            },
          ),
        ],
      ),
    );
  }

  // ── Error state ──

  Widget _buildError(BuildContext context, VoiceProvider voice) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      key: const ValueKey('error'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline, size: 40, color: cs.error),
          ),
          const SizedBox(height: 16),
          Text(
            voice.errorMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: () {
              voice.reset();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
          const SizedBox(height: 24),

          // ── Type it in instead ──
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              hintText: 'Type your transaction here…',
              prefixIcon: const Icon(Icons.edit_outlined),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded),
                onPressed: _parseText,
              ),
            ),
            onSubmitted: (_) => _parseText(),
            textInputAction: TextInputAction.send,
          ),
          const SizedBox(height: 16),
          Text(
            'Examples: "spent 15 on lunch" or "salary 5000"',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Action bar (save / edit) ──

  Widget _buildActionBar(BuildContext context, VoiceProvider voice) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () => _save(context, voice),
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Save logic ──

  Future<void> _save(BuildContext context, VoiceProvider voice) async {
    final result = _editedResult ?? voice.lastResult;
    if (result == null) return;

    final amountInBase = await _settings.convertToBase(
        result.amount, result.currency);

    if (context.mounted) {
      Navigator.pop(context, {
        'parsed': result,
        'amountInBase': amountInBase,
      });
    }
  }
}
