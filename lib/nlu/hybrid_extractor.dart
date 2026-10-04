import '../models/transaction.dart';
import 'nlu_extractor.dart';
import 'pattern_extractor_en.dart';
import 'pattern_extractor_zh.dart';

/// Hybrid NLU extractor: tries a lightweight pattern extractor first,
/// then (in the future) falls back to a TinyBERT model.
///
/// Architecture:
/// ```
/// text → PatternExtractorEn (if EN) or PatternExtractorZh (if ZH)
///      → if confidence < threshold → TinyBertExtractor (future)
///      → return best result
/// ```
class HybridExtractor {
  final PatternExtractorEn _en = PatternExtractorEn();
  final PatternExtractorZh _zh = PatternExtractorZh();

  // Future: add TinyBERT extractor here when ready.
  // final TinyBertExtractor _bertEn = TinyBertExtractor('en');
  // final TinyBertExtractor _bertZh = TinyBertExtractor('zh');

  /// Extract transaction info from [text].
  ///
  /// [language] should be "en" or "zh".  If null, auto-detect.
  ParsedTransaction? extract(String text, {String? language}) {
    if (text.trim().isEmpty) return null;

    final lang = language ?? _detectLanguage(text);
    final extractor = lang == 'zh' ? (_zh as NluExtractor) : _en;

    // Phase 1: pattern extraction.
    var result = extractor.extract(text);

    // Phase 2 (future): fall back to TinyBERT if confidence too low.
    if (result == null || result.confidence < extractor.confidenceThreshold) {
      // final bertResult = lang == 'zh'
      //     ? _bertZh.extract(text)
      //     : _bertEn.extract(text);
      // if (bertResult != null &&
      //     (result == null || bertResult.confidence > result.confidence)) {
      //   result = bertResult;
      // }
    }

    return result;
  }

  /// Simple language detection: if text contains Chinese characters → zh.
  String _detectLanguage(String text) {
    // Check for CJK Unified Ideographs (U+4E00–U+9FFF).
    final hasChinese = RegExp(r'[一-鿿]').hasMatch(text);
    if (hasChinese) return 'zh';
    return 'en';
  }

  /// Force-register the TinyBERT extractors (to be called after init).
  // void registerBertExtractors(TinyBertExtractor en, TinyBertExtractor zh) {
  //   _bertEn = en;
  //   _bertZh = zh;
  // }
}
