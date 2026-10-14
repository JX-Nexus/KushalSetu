// Reference seed data, stored locally on first launch.
//
// IMPORTANT: every qualification pack and criterion is illustrative demo data
// ("DEMO DATA — NOT AN OFFICIAL QUALIFICATION"). No official NSQF pack codes,
// levels, or issuing bodies are invented or claimed as real.

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

const String demoSourceNote =
    'DEMO DATA — NOT AN OFFICIAL QUALIFICATION. Illustrative prototype pack only.';

Future<void> seedIfEmpty(Database db) async {
  final count = Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM trades'),
  );
  if ((count ?? 0) > 0) return;

  final batch = db.batch();
  for (final t in _trades) {
    batch.insert('trades', t.toMap());
  }
  for (final q in _qualificationPacks) {
    batch.insert('qualification_packs', q.toMap());
  }
  for (final r in _rubrics) {
    batch.insert('rubrics', r.toMap());
  }
  await batch.commit(noResult: true);
}

const List<Trade> _trades = [
  Trade(
    id: 'trade-sewing',
    code: 'sewing',
    name: 'Sewing Machine Operator',
    sector: 'Apparel & Textiles',
    description:
        'Operates single needle industrial lockstitch machines: thread tension, seam quality and preventive maintenance.',
  ),
  Trade(
    id: 'trade-electrician',
    code: 'electrician',
    name: 'Domestic Electrician',
    sector: 'Construction & Electrical',
    description:
        'Residential wiring and maintenance: safe isolation, conduit routing, cable sizing, distribution boards and earthing.',
  ),
  Trade(
    id: 'trade-mason',
    code: 'mason',
    name: 'General Mason & Bricklayer',
    sector: 'Construction',
    description:
        'Site safety, mortar preparation, brick bonds, plumb/level work, plastering and curing.',
  ),
];

const List<QualificationPack> _qualificationPacks = [
  QualificationPack(
    id: 'qp-sewing-01',
    tradeId: 'trade-sewing',
    code: 'DEMO/SEW/Q0001',
    title: 'Sewing Machine Operator — Industrial Lockstitch',
    nsqfLevel: 3,
    typicalTools: [
      'Single needle lockstitch machine',
      'Bobbin case',
      'Thread snips',
      'Seam ripper',
      'Measuring tape',
      'Tweezers',
    ],
    units: [
      QpUnit(
        unitCode: 'SEW-U1',
        title: 'Operate single needle lockstitch machine',
        description:
            'Stitches straight and curved seams on woven fabric with correct seating, machine control and fabric guidance.',
      ),
      QpUnit(
        unitCode: 'SEW-U2',
        title: 'Balance thread tension and stitch quality',
        description:
            'Sets upper and bobbin thread tension so stitches are balanced, checks stitches per inch and rectifies defects.',
      ),
      QpUnit(
        unitCode: 'SEW-U3',
        title: 'Carry out routine machine maintenance',
        description:
            'Cleans, oils, replaces needles and checks the finger guard before and after shifts.',
      ),
    ],
    sourceNote: demoSourceNote,
  ),
  QualificationPack(
    id: 'qp-elec-01',
    tradeId: 'trade-electrician',
    code: 'DEMO/ELE/Q0001',
    title: 'Residential Wireman & Electrical Maintenance',
    nsqfLevel: 4,
    typicalTools: [
      'Insulated screwdriver set',
      'Multimeter / voltage tester',
      'Insulation resistance tester (megger)',
      'Wire strippers',
      'Earth resistance tester',
      'PPE / 1000V gloves',
    ],
    units: [
      QpUnit(
        unitCode: 'ELE-U1',
        title: 'Isolate supply and verify zero voltage',
        description:
            'Applies Lockout/Tagout, proves the tester, and performs 3-point zero-voltage verification before work.',
      ),
      QpUnit(
        unitCode: 'ELE-U2',
        title: 'Route conduit and size conductors',
        description:
            'Runs conduit safely and selects copper cable cross-section (1.5/2.5/4.0 sq mm) with correct colour codes.',
      ),
      QpUnit(
        unitCode: 'ELE-U3',
        title: 'Wire distribution boards and earthing',
        description:
            'Terminates distribution boards, installs 30mA RCCB protection and tests earth resistance.',
      ),
    ],
    sourceNote: demoSourceNote,
  ),
  QualificationPack(
    id: 'qp-mason-01',
    tradeId: 'trade-mason',
    code: 'DEMO/MAS/Q0001',
    title: 'Masonry, Brickwork & Plastering',
    nsqfLevel: 3,
    typicalTools: [
      'Plumb bob',
      'Spirit level',
      'Mason trowel',
      'Mortar board',
      'Line and pins',
      'Water level tube',
    ],
    units: [
      QpUnit(
        unitCode: 'MAS-U1',
        title: 'Work safely on site',
        description:
            'Inspects scaffolding, uses PPE and keeps the work area safe during masonry operations.',
      ),
      QpUnit(
        unitCode: 'MAS-U2',
        title: 'Build brick walls to bond and plumb',
        description:
            'Prepares mortar and lays English/Flemish bond brickwork with 10mm joints, checked plumb and level.',
      ),
      QpUnit(
        unitCode: 'MAS-U3',
        title: 'Plaster, level and cure surfaces',
        description:
            'Applies 12mm cement plaster using screed buttons and follows the 7-day water curing protocol.',
      ),
    ],
    sourceNote: demoSourceNote,
  ),
];

const List<RubricCriterion> _rubrics = [
  // --- Sewing ---
  RubricCriterion(
    id: 'CRIT-SEW-01',
    tradeId: 'trade-sewing',
    criterionCode: 'CRIT-SEW-01',
    title: 'Thread tension and stitch formation',
    performanceIndicators: [
      'Adjusts upper and bobbin thread tension so stitches are balanced on both sides',
      'Tests on scrap fabric before stitching the garment',
      'Recognises and rectifies looping or tangling stitches',
    ],
    evidenceRequirement:
        'Photographic evidence of balanced stitch samples, or direct assessor observation of tension setting.',
    level4: 'Independently balances tension and produces flawless balanced stitches on first attempt.',
    level3: 'Balances tension with minor trial and error; stitches acceptable.',
    level2: 'Needs prompting to check tension; some unbalanced stitches.',
    level1: 'Unable to set tension; consistent stitch defects.',
  ),
  RubricCriterion(
    id: 'CRIT-SEW-02',
    tradeId: 'trade-sewing',
    criterionCode: 'CRIT-SEW-02',
    title: 'Seam quality inspection and rectification',
    performanceIndicators: [
      'Measures and confirms stitches per inch (SPI 10-12)',
      'Inspects seams for puckering, skipped stitches and uneven margins',
      'Rectsifies visible defects and re-stitches cleanly',
    ],
    evidenceRequirement:
        'Photographic evidence of stitched seams with SPI measurement, or sample garments.',
    level4: 'Consistently meets SPI and inspects/rectifies defects without guidance.',
    level3: 'Meets SPI with occasional minor defects corrected on review.',
    level2: 'Inconsistent SPI; defects sometimes missed.',
    level1: 'No structured inspection; frequent uncorrected defects.',
  ),
  RubricCriterion(
    id: 'CRIT-SEW-03',
    tradeId: 'trade-sewing',
    criterionCode: 'CRIT-SEW-03',
    title: 'Routine machine maintenance and safety',
    performanceIndicators: [
      'Cleans and oils the machine at appropriate intervals',
      'Replaces needles correctly and safely',
      'Checks the finger guard and powers off before maintenance',
    ],
    evidenceRequirement:
        'Assessor observation of maintenance routine, or maintenance log photos.',
    level4: 'Performs full routine maintenance safely and independently.',
    level3: 'Performs core maintenance tasks with minor reminders.',
    level2: 'Partial maintenance; safety steps sometimes skipped.',
    level1: 'No routine maintenance; unsafe practices observed.',
  ),

  // --- Electrician ---
  RubricCriterion(
    id: 'CRIT-ELE-01',
    tradeId: 'trade-electrician',
    criterionCode: 'CRIT-ELE-01',
    title: 'Safe isolation and zero-voltage verification',
    performanceIndicators: [
      'Applies Lockout/Tagout before starting work',
      'Proves the voltage tester on a known live source',
      'Performs 3-point zero-voltage verification and uses correct 1000V PPE',
    ],
    evidenceRequirement:
        'Photographic or video evidence of locked isolator, or direct assessor observation of zero-voltage verification.',
    level4: 'Executes full isolation sequence flawlessly and enforces it on others.',
    level3: 'Executes isolation sequence correctly with minor lapses.',
    level2: 'Isolates but skips some verification steps.',
    level1: 'Works live or omits isolation; unsafe.',
  ),
  RubricCriterion(
    id: 'CRIT-ELE-02',
    tradeId: 'trade-electrician',
    criterionCode: 'CRIT-ELE-02',
    title: 'Conduit routing and conductor sizing',
    performanceIndicators: [
      'Routes conduit without sharp bends or damage',
      'Selects correct copper cross-section (1.5/2.5/4.0 sq mm) for the load',
      'Maintains correct colour code integrity at junctions',
    ],
    evidenceRequirement: 'Photographic evidence of concealed/routed conduit and termination points.',
    level4: 'Routes and sizes correctly and independently to standard.',
    level3: 'Routes and sizes correctly with minor corrections.',
    level2: 'Sizing or routing errors requiring rework.',
    level1: 'Incorrect sizing/routing; unsafe installation.',
  ),
  RubricCriterion(
    id: 'CRIT-ELE-03',
    tradeId: 'trade-electrician',
    criterionCode: 'CRIT-ELE-03',
    title: 'Distribution board, RCCB and earthing',
    performanceIndicators: [
      'Terminates distribution board conductors securely and tidily',
      'Installs/verifies 30mA RCCB shock protection',
      'Performs earth resistance testing and records the value',
    ],
    evidenceRequirement:
        'Photographic evidence of board wiring plus earth pit test log or assessor observation.',
    level4: 'Completes board wiring, RCCB and earth test to standard independently.',
    level3: 'Completes with minor guidance; results acceptable.',
    level2: 'Partial completion; testing skipped or inaccurate.',
    level1: 'Unable to complete safely.',
  ),

  // --- Mason ---
  RubricCriterion(
    id: 'CRIT-MAS-01',
    tradeId: 'trade-mason',
    criterionCode: 'CRIT-MAS-01',
    title: 'Site safety and scaffolding inspection',
    performanceIndicators: [
      'Inspects scaffolding before use',
      'Wears and maintains correct PPE',
      'Keeps the work area clear of hazards',
    ],
    evidenceRequirement: 'Assessor observation of safe practice on site.',
    level4: 'Consistently safe and proactive about site hazards.',
    level3: 'Works safely with occasional reminders.',
    level2: 'Basic safety awareness; lapses.',
    level1: 'Unsafe practices observed.',
  ),
  RubricCriterion(
    id: 'CRIT-MAS-02',
    tradeId: 'trade-mason',
    criterionCode: 'CRIT-MAS-02',
    title: 'Brickwork to bond, plumb and level',
    performanceIndicators: [
      'Prepares mortar to correct consistency',
      'Lays English or Flemish bond brickwork',
      'Checks verticality with plumb bob and maintains 10mm joints',
    ],
    evidenceRequirement: 'Photographic evidence of completed wall, or direct assessor measurement.',
    level4: 'Builds accurate bond and plumb walls independently to standard.',
    level3: 'Builds acceptable walls with minor corrections.',
    level2: 'Noticeable plumb/joint deviations.',
    level1: 'Walls out of plumb; joints unacceptable.',
  ),
  RubricCriterion(
    id: 'CRIT-MAS-03',
    tradeId: 'trade-mason',
    criterionCode: 'CRIT-MAS-03',
    title: 'Plastering, levelling and curing',
    performanceIndicators: [
      'Sets screed buttons to establish uniform 12mm thickness',
      'Applies and levels plaster to a flat even finish',
      'Follows the 7-day water curing protocol',
    ],
    evidenceRequirement: 'Photographic evidence of finished plaster surface and curing record.',
    level4: 'Produces uniform flat plaster and cures correctly, independently.',
    level3: 'Produces acceptable finish with minor unevenness.',
    level2: 'Uneven thickness; curing inconsistent.',
    level1: 'Poor finish; no curing.',
  ),
];
