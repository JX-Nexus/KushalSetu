// Unit tests for the deterministic qualification-matching engine.
// Pure domain logic — no Flutter, no platform channels, no database.

import 'package:flutter_test/flutter_test.dart';
import 'package:kaushalsetu_app/domain/matching.dart';
import 'package:kaushalsetu_app/domain/models.dart';

void main() {
  const engine = MatchingEngine();

  final worker = Worker(
    id: 'w1',
    name: 'Meera',
    preferredLanguage: LanguageCode.hi,
    primaryTrade: 'Sewing Machine Operator',
    yearsOfExperience: 4.5,
    locationRegion: 'Jaipur',
    priorFormalTraining: false,
    createdAt: DateTime(2026),
  );

  final experience = ExperienceDeclaration(
    id: 'e1',
    workerId: 'w1',
    tradeContext: 'Garment stitching unit',
    dailyTasks: [
      'Stitching shirts using lockstitch machine',
      'Balancing thread tension on the machine',
    ],
    toolsUsed: ['Lockstitch machine', 'Bobbin case'],
    safetyPractices: ['Finger guard check', 'Power switch off when changing needle'],
    freeTextDescription: 'मैंने 4 साल गारमेंट यूनिट में काम किया है।',
    informalLearningSource: 'Apprenticeship',
    createdAt: DateTime(2026),
  );

  const sewingPack = QualificationPack(
    id: 'qp-sew',
    tradeId: 'trade-sewing',
    code: 'DEMO/SEW/Q0001',
    title: 'Sewing Machine Operator',
    nsqfLevel: 3,
    typicalTools: ['Lockstitch machine', 'Bobbin case', 'Thread snips'],
    units: [
      QpUnit(unitCode: 'SEW-U1', title: 'Operate lockstitch machine', description: 'Stitching garments'),
    ],
    sourceNote: 'demo',
  );

  const elecPack = QualificationPack(
    id: 'qp-elec',
    tradeId: 'trade-electrician',
    code: 'DEMO/ELE/Q0001',
    title: 'Domestic Electrician',
    nsqfLevel: 4,
    typicalTools: ['Multimeter', 'Insulated screwdriver'],
    units: [
      QpUnit(unitCode: 'ELE-U1', title: 'Isolate supply', description: 'Lockout tagout'),
    ],
    sourceNote: 'demo',
  );

  test('ranks the matching trade pack above an unrelated one', () {
    final matches = engine.match(
      worker: worker,
      experience: experience,
      packs: [sewingPack, elecPack],
    );
    expect(matches, isNotEmpty);
    expect(matches.first.qualificationId, 'qp-sew');
    expect(matches.first.matchScorePct, greaterThan(50.0));
    final elec = matches.firstWhere((m) => m.qualificationId == 'qp-elec');
    expect(elec.matchScorePct, lessThan(50.0));
  });

  test('reports uncertainty for informal, uncertified experience', () {
    final matches = engine.match(worker: worker, experience: experience, packs: [sewingPack]);
    expect(matches.first.uncertaintyLevel, anyOf('Low', 'Moderate', 'High'));
    expect(matches.first.uncertaintyFactors, isNotEmpty);
  });

  test('handles a missing declaration without throwing', () {
    final matches = engine.match(worker: worker, experience: null, packs: [sewingPack]);
    expect(matches.length, 1);
  });
}
