// Deterministic qualification-matching engine (ported from the prototype).
//
// This is intentionally NOT a language model: it is a transparent, auditable
// weighted score. It never certifies a candidate and always reports its
// uncertainty reasoning. Runs fully on-device.

import 'models.dart';

const Map<String, List<String>> _tradeFamilies = {
  'electrical': ['elec', 'wireman', 'wiring', 'electrical', 'power', 'circuit', 'voltage', 'motor', 'fan'],
  'sewing': ['sew', 'sewing', 'garment', 'apparel', 'stitch', 'tailor', 'machine operator'],
  'masonry': ['mason', 'brick', 'plaster', 'construction', 'cement', 'concrete', 'mortar'],
  'plumbing': ['plumb', 'pipe', 'sanitary', 'water supply', 'drainage'],
  'solar': ['solar', 'pv', 'photovoltaic', 'renewable'],
};

const List<String> _safetyKeywords = [
  'isolat', 'ppe', 'tester', 'helmet', 'scaffold', 'voltage', 'hazard',
  'glove', 'guard', 'oil', 'off', 'switch', 'earth', 'ground', 'mask',
];

class MatchingEngine {
  const MatchingEngine();

  List<QualificationMatch> match({
    required Worker worker,
    required ExperienceDeclaration? experience,
    required List<QualificationPack> packs,
  }) {
    final tasks = experience?.dailyTasks ?? const [];
    final tools = experience?.toolsUsed ?? const [];
    final safety = experience?.safetyPractices ?? const [];
    final context = experience?.tradeContext ?? '';
    final freeText = experience?.freeTextDescription ?? '';

    final workerFamily = _detectFamily('${worker.primaryTrade} $context $freeText');

    final results = <QualificationMatch>[];
    for (final q in packs) {
      final qFamily = _detectFamily('${q.title} ${q.units.map((u) => u.title).join(' ')}');
      final primary = worker.primaryTrade.toLowerCase();

      final sameFamily = workerFamily == qFamily && workerFamily != 'other';
      final tradeMatch = sameFamily ||
          (primary.contains('elec') && q.title.toLowerCase().contains('elec')) ||
          (primary.contains('sew') && q.title.toLowerCase().contains('sew')) ||
          (primary.contains('mason') && q.title.toLowerCase().contains('mason')) ||
          (primary.contains('plumb') && q.title.toLowerCase().contains('plumb'));

      final matchedTools = tools.where((t) {
        final tl = t.toLowerCase();
        return q.typicalTools.any((qt) {
          final qtl = qt.toLowerCase();
          return qtl.contains(tl) || tl.contains(qtl);
        });
      }).toList();

      final matchedTasks = <String>[];
      for (final task in tasks) {
        final taskWords = task
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 3)
            .toSet();
        for (final unit in q.units) {
          final unitWords = '${unit.title} ${unit.description}'
              .toLowerCase()
              .split(RegExp(r'\s+'))
              .where((w) => w.length > 3)
              .toSet();
          if (taskWords.intersection(unitWords).isNotEmpty) {
            if (!matchedTasks.contains(task)) matchedTasks.add(task);
            break;
          }
        }
      }

      final matchedSafety =
          safety.where((s) => _safetyKeywords.any((k) => s.toLowerCase().contains(k))).toList();

      // Scoring — trade family dominates.
      final tradePts = sameFamily ? 45.0 : (tradeMatch ? 30.0 : 2.0);
      final taskPts = (matchedTasks.length * 8.0).clamp(0.0, 25.0);
      final toolRatio = matchedTools.length / (q.typicalTools.isEmpty ? 1 : q.typicalTools.length);
      final toolPts = (toolRatio * 22.0).clamp(0.0, 18.0);
      final safetyPts = (matchedSafety.length * 4.0).clamp(0.0, 12.0);

      var total = tradePts + taskPts + toolPts + safetyPts;
      if (!tradeMatch && !sameFamily) total = total.clamp(0.0, 18.0);

      // Uncertainty.
      var uncertaintyPts = 15.0;
      final factors = <String>[
        'Baseline RPL uncertainty: self-declared experience without third-party certification.',
      ];
      if (!worker.priorFormalTraining) {
        uncertaintyPts += 10.0;
        factors.add('Informal apprenticeship: skills acquired on-site without a standardised curriculum.');
      }
      if (matchedTools.length < (q.typicalTools.isEmpty ? 1 : q.typicalTools.length) * 0.5) {
        uncertaintyPts += 8.0;
        factors.add('Tool verification gap: standard toolkit instruments unconfirmed.');
      }
      if (matchedSafety.length < 2) {
        uncertaintyPts += 8.0;
        factors.add('Safety protocol gap: limited formal hazard mitigation declared.');
      }
      if (!sameFamily) {
        uncertaintyPts += 12.0;
        factors.add('Trade family mismatch: this pack may not be the closest fit.');
      }
      final uncertaintyScore = uncertaintyPts.clamp(15.0, 80.0);
      final level = uncertaintyScore < 20 ? 'Low' : (uncertaintyScore < 40 ? 'Moderate' : 'High');

      // Missing units.
      final missing = <String>[];
      for (final unit in q.units) {
        final covered = matchedTasks.any((task) => task
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 3)
            .any((w) => '${unit.title} ${unit.description}'.toLowerCase().contains(w)));
        if (!covered) missing.add('${unit.unitCode}: ${unit.title}');
      }

      final rationale = sameFamily || tradeMatch
          ? 'Strong trade concordance with "${worker.primaryTrade}" '
              '(${worker.yearsOfExperience} yrs reported). Matched ${matchedTasks.length} tasks '
              'and ${matchedTools.length} tools.'
          : 'Weak alignment: declared trade family does not match this qualification pack.';

      results.add(QualificationMatch(
        qualificationId: q.id,
        qualificationTitle: q.title,
        matchScorePct: double.parse(total.toStringAsFixed(1)),
        uncertaintyLevel: level,
        uncertaintyFactors: factors,
        matchedTasks: matchedTasks,
        matchedTools: matchedTools,
        missingUnits: missing,
        rationale: rationale,
      ));
    }

    results.sort((a, b) => b.matchScorePct.compareTo(a.matchScorePct));
    return results;
  }

  String _detectFamily(String text) {
    final t = text.toLowerCase();
    for (final entry in _tradeFamilies.entries) {
      if (entry.value.any((kw) => t.contains(kw))) return entry.key;
    }
    return 'other';
  }
}
