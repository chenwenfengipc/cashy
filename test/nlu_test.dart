import 'package:flutter_test/flutter_test.dart';
import 'package:cashy/nlu/pattern_extractor_en.dart';
import 'package:cashy/nlu/pattern_extractor_zh.dart';
import 'package:cashy/models/transaction.dart';

/// NLU unit tests for both EN and ZH extractors.
void main() {
  group('PatternExtractorEn', () {
    final extractor = PatternExtractorEn();

    test('basic expense', () {
      final result = extractor.extract('I spent 15 ringgit on lunch at McDonalds');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.amount, closeTo(15, 0.01));
      expect(result.currency, 'SGD');
      expect(result.categoryName, 'Food');
    });

    test('income detection', () {
      final result = extractor.extract('received salary 5000 dollars yesterday');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.income);
      expect(result.amount, closeTo(5000, 0.01));
      expect(result.currency, 'USD');
    });

    test('bare amount implies SGD', () {
      final result = extractor.extract('grab 12.50');
      expect(result, isNotNull);
      expect(result!.amount, closeTo(12.5, 0.01));
      expect(result.currency, 'SGD');
      expect(result.categoryName, 'Transport');
    });

    test('bill payment', () {
      final result = extractor.extract('paid electricity bill 150 ringgit');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.categoryName, 'Bills & Utilities');
      expect(result.amount, closeTo(150, 0.01));
    });

    test('null on empty text', () {
      expect(extractor.extract(''), isNull);
      expect(extractor.extract('   '), isNull);
    });

    test('spoken number words', () {
      final a = extractor.extract('Spent fifteen singapore dollar on lunch.')!;
      expect(a.amount, 15);
      expect(a.currency, 'SGD');
      expect(a.categoryName, 'Food');

      final b = extractor.extract('received salary five thousand dollars')!;
      expect(b.amount, 5000);
      expect(b.type, TransactionType.income);

      final c = extractor.extract('paid one hundred and twenty five singapore dollar for rent')!;
      expect(c.amount, 125);

      final d = extractor.extract('spent twelve point five singapore dollar on coffee')!;
      expect(d.amount, 12.5);

      final e = extractor.extract('bought shoes for a hundred ringgit')!;
      expect(e.amount, 100);
    });
  });

  group('PatternExtractorZh', () {
    final extractor = PatternExtractorZh();

    test('basic expense in Chinese', () {
      final result = extractor.extract('中午在麦当劳花了15块钱');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.amount, closeTo(15, 0.01));
      expect(result.currency, 'SGD');
      expect(result.note, contains('麦当劳'));
    });

    test('income in Chinese', () {
      final result = extractor.extract('昨天发工资5000块');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.income);
      expect(result.amount, closeTo(5000, 0.01));
    });

    test('Chinese number characters', () {
      final result = extractor.extract('花了十五块钱吃饭');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.amount, closeTo(15, 0.01));
      expect(result.categoryName, 'Food');
    });

    test('bill in Chinese', () {
      final result = extractor.extract('交了150块电费');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.amount, closeTo(150, 0.01));
      expect(result.categoryName, 'Bills & Utilities');
    });

    test('yang beri payment with ringgit', () {
      final result = extractor.extract('在Jaya Grocer买了30令吉的菜');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.amount, closeTo(30, 0.01));
      expect(result.currency, 'SGD');
    });
  });
}
