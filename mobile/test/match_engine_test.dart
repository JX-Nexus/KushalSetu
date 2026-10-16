import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaushalsetu/models/models.dart';
import 'package:kaushalsetu/services/match_engine.dart';

void main() {
  final raw = jsonDecode(File('assets/data/catalogue.json').readAsStringSync()) as Map<String, dynamic>;
  final packs = (raw['packs'] as List)
      .map((e) => QualPack.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
  final engine = MatchEngine(packs);

  String top(String text) => engine.rank(text).matches.first.code;

  test('catalogue parses', () {
    expect(packs.length, 4);
    expect(packs.every((p) => p.allCriteria.isNotEmpty), true);
  });

  test('maps English, Hindi, Marathi and Hinglish declarations offline', () {
    expect(top('I am a plumber fitting taps and pipes in houses'), 'KS-PLB-L4');
    expect(top('मैं इलेक्ट्रीशियन हूँ, घरों में वायरिंग और अर्थिंग करता हूँ'), 'KS-ELE-L4');
    expect(top('मी वेल्डिंगचे काम करतो, लोखंडी गेट बनवतो'), 'KS-WLD-L4');
    expect(top('main raj mistri hu, eent ki chinai aur plaster karta hu'), 'KS-MSN-L3');
  });

  test('empty text gives no result', () {
    expect(engine.rank('   ').confidence, 'none');
  });
}
