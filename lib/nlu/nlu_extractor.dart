import '../models/transaction.dart';

/// Abstract NLU extractor interface.
///
/// Each language has a dedicated implementation (PatternExtractorEn,
/// PatternExtractorZh).  The HybridExtractor runs all registered
/// extractors and picks the best result.  In the future the TinyBERT
/// fallback implements the same interface and can be plugged in.
abstract class NluExtractor {
  /// Language code this extractor handles ("en" / "zh").
  String get language;

  /// Extract transaction info from [text].
  /// Returns null if parsing fails.
  ParsedTransaction? extract(String text);

  /// Confidence threshold below which results are considered unreliable.
  double get confidenceThreshold => 0.7;
}
