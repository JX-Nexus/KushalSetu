import 'dart:math' as math;
import '../models/models.dart';

class PackMatch {
  final String code;
  final double score;
  final List<String> terms;
  const PackMatch(this.code, this.score, this.terms);
}

class MatchOutcome {
  final List<PackMatch> matches;
  final String confidence; // high | medium | low | none
  const MatchOutcome(this.matches, this.confidence);
}

/// On-device mapper (works fully offline). Same idea as the server: TF-IDF over
/// words and character trigrams against each qualification pack's vocabulary.
/// The server re-runs its own (authoritative) mapping once synced.
class MatchEngine {
  static const Set<String> _stop = {
    'a', 'an', 'the', 'i', 'am', 'is', 'are', 'was', 'of', 'to', 'in', 'on', 'at', 'for', 'with',
    'and', 'or', 'my', 'me', 'have', 'has', 'had', 'from', 'by', 'as', 'work', 'works', 'worked',
    'working', 'job', 'years', 'year', 'since', 'also', 'very', 'many', 'some', 'all', 'do', 'does',
    'है', 'हूँ', 'हूं', 'हैं', 'था', 'थे', 'का', 'की', 'के', 'में', 'और', 'से', 'को', 'पर', 'मैं',
    'साल', 'करता', 'करती', 'करते', 'मी', 'आहे', 'आणि', 'चा', 'ची', 'चे', 'मध्ये', 'करतो',
    'hu', 'hun', 'hai', 'hain', 'ka', 'ki', 'ke', 'ko', 'mi', 'mein', 'main', 'aur', 'se', 'par',
    'ek', 'saal', 'sal', 'karta', 'karti', 'karte', 'kam', 'kaam',
  };

  final List<QualPack> packs;
  final List<Map<String, double>> _wordVecs = [];
  final List<Map<String, double>> _charVecs = [];
  final List<Set<String>> _vocab = [];
  final Map<String, double> _wordIdf = {};
  final Map<String, double> _charIdf = {};

  MatchEngine(this.packs) {
    _build();
  }

  static final RegExp _splitter = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

  static List<String> tokenize(String s) {
    final out = <String>[];
    for (final t in s.toLowerCase().split(_splitter)) {
      if (t.length < 2) continue;
      if (_stop.contains(t)) continue;
      if (int.tryParse(t) != null) continue;
      out.add(t);
    }
    return out;
  }

  static List<String> _trigrams(List<String> tokens) {
    final out = <String>[];
    for (final t in tokens) {
      final p = ' $t ';
      if (p.length < 3) continue;
      for (var i = 0; i + 3 <= p.length; i++) {
        out.add(p.substring(i, i + 3));
      }
    }
    return out;
  }

  static Map<String, double> _tf(List<String> items) {
    final counts = <String, int>{};
    for (final i in items) {
      counts[i] = (counts[i] ?? 0) + 1;
    }
    return counts.map((k, v) => MapEntry(k, 1.0 + math.log(v)));
  }

  String _packText(QualPack p) {
    final kw = p.keywords.values.expand((e) => e).join(' ');
    final sb = StringBuffer();
    sb.write('${p.title.all} ${p.description.all} ');
    sb.write('$kw $kw $kw ');
    for (final n in p.nos) {
      sb.write('${n.title.all} ');
      for (final c in n.criteria) {
        sb.write('${c.text.all} ');
        for (final i in c.indicators) {
          sb.write('${i.kw.join(' ')} ');
        }
      }
    }
    return sb.toString();
  }

  void _build() {
    final wordTfs = <Map<String, double>>[];
    final charTfs = <Map<String, double>>[];
    for (final p in packs) {
      final toks = tokenize(_packText(p));
      _vocab.add(toks.toSet());
      wordTfs.add(_tf(toks));
      charTfs.add(_tf(_trigrams(toks)));
    }
    final n = packs.length;
    void idf(List<Map<String, double>> tfs, Map<String, double> out) {
      final df = <String, int>{};
      for (final tf in tfs) {
        for (final k in tf.keys) {
          df[k] = (df[k] ?? 0) + 1;
        }
      }
      df.forEach((k, v) {
        out[k] = math.log((1 + n) / (1 + v)) + 1.0;
      });
    }

    idf(wordTfs, _wordIdf);
    idf(charTfs, _charIdf);
    for (final tf in wordTfs) {
      _wordVecs.add(_weigh(tf, _wordIdf));
    }
    for (final tf in charTfs) {
      _charVecs.add(_weigh(tf, _charIdf));
    }
  }

  static Map<String, double> _weigh(Map<String, double> tf, Map<String, double> idf) {
    final out = <String, double>{};
    var norm = 0.0;
    tf.forEach((k, v) {
      final w = v * (idf[k] ?? 1.0);
      out[k] = w;
      norm += w * w;
    });
    norm = math.sqrt(norm);
    if (norm == 0) return out;
    return out.map((k, v) => MapEntry(k, v / norm));
  }

  static double _dot(Map<String, double> a, Map<String, double> b) {
    final small = a.length < b.length ? a : b;
    final big = identical(small, a) ? b : a;
    var s = 0.0;
    small.forEach((k, v) {
      final o = big[k];
      if (o != null) s += v * o;
    });
    return s;
  }

  MatchOutcome rank(String text) {
    final toks = tokenize(text);
    if (toks.isEmpty || packs.isEmpty) return const MatchOutcome([], 'none');
    final qw = _weigh(_tf(toks), _wordIdf);
    final qc = _weigh(_tf(_trigrams(toks)), _charIdf);
    final results = <PackMatch>[];
    for (var i = 0; i < packs.length; i++) {
      final score = 0.6 * _dot(_wordVecs[i], qw) + 0.4 * _dot(_charVecs[i], qc);
      final terms = toks.toSet().where((t) => _vocab[i].contains(t)).toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      results.add(PackMatch(packs[i].code, score, terms.take(6).toList()));
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    final top = results.first.score;
    final second = results.length > 1 ? results[1].score : 0.0;
    final margin = second > 1e-9 ? top / second : double.infinity;
    String conf;
    if (top < 0.04 || results.first.terms.isEmpty) {
      conf = 'low';
    } else if (margin >= 1.6 && top >= 0.12) {
      conf = 'high';
    } else if (margin >= 1.2) {
      conf = 'medium';
    } else {
      conf = 'low';
    }
    return MatchOutcome(results, conf);
  }
}
