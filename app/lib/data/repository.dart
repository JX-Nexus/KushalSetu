// Thin repository over the local SQLite database. All reads/writes are
// on-device; there is no remote data source.

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

class Repository {
  final Database db;
  Repository(this.db);

  // -- Reference data -------------------------------------------------------

  Future<List<Trade>> trades() async {
    final rows = await db.query('trades', orderBy: 'name');
    return rows.map(Trade.fromMap).toList();
  }

  Future<List<QualificationPack>> qualificationPacks({String? tradeId}) async {
    final rows = await db.query(
      'qualification_packs',
      where: tradeId == null ? null : 'trade_id = ?',
      whereArgs: tradeId == null ? null : [tradeId],
    );
    return rows.map(QualificationPack.fromMap).toList();
  }

  Future<QualificationPack?> qualificationPackById(String id) async {
    final rows = await db.query('qualification_packs', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return QualificationPack.fromMap(rows.first);
  }

  Future<List<RubricCriterion>> rubricsForTrade(String tradeId) async {
    final rows = await db.query('rubrics', where: 'trade_id = ?', whereArgs: [tradeId]);
    return rows.map(RubricCriterion.fromMap).toList();
  }

  // -- Workers --------------------------------------------------------------

  Future<void> createWorker(Worker worker) async {
    await db.insert('workers', worker.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Worker>> listWorkers() async {
    final rows = await db.query('workers', orderBy: 'created_at DESC');
    return rows.map(Worker.fromMap).toList();
  }

  Future<Worker?> getWorker(String id) async {
    final rows = await db.query('workers', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Worker.fromMap(rows.first);
  }

  // -- Experience declarations ---------------------------------------------

  Future<void> saveExperience(ExperienceDeclaration exp) async {
    await db.insert('experiences', exp.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ExperienceDeclaration?> experienceForWorker(String workerId) async {
    final rows = await db.query(
      'experiences',
      where: 'worker_id = ?',
      whereArgs: [workerId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : ExperienceDeclaration.fromMap(rows.first);
  }

  // -- Assessment sessions --------------------------------------------------

  Future<void> createSession(AssessmentSession session) async {
    await db.insert('sessions', session.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AssessmentSession?> getSession(String id) async {
    final rows = await db.query('sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : AssessmentSession.fromMap(rows.first);
  }

  Future<List<AssessmentSession>> sessionsForWorker(String workerId) async {
    final rows = await db.query(
      'sessions',
      where: 'worker_id = ?',
      whereArgs: [workerId],
      orderBy: 'created_at DESC',
    );
    return rows.map(AssessmentSession.fromMap).toList();
  }

  Future<void> updateSession(AssessmentSession session) async {
    await db.update('sessions', session.toMap(), where: 'id = ?', whereArgs: [session.id]);
  }

  // -- Evidence -------------------------------------------------------------

  Future<void> addEvidence(Evidence evidence) async {
    await db.insert('evidence', evidence.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Evidence>> evidenceForSession(String sessionId) async {
    final rows = await db.query(
      'evidence',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Evidence.fromMap).toList();
  }

  Future<void> updateEvidence(Evidence evidence) async {
    await db.update('evidence', evidence.toMap(), where: 'id = ?', whereArgs: [evidence.id]);
  }

  // -- Criterion findings ---------------------------------------------------

  Future<void> upsertFinding(CriterionFinding finding) async {
    final existing = await db.query(
      'findings',
      where: 'session_id = ? AND criterion_code = ?',
      whereArgs: [finding.sessionId, finding.criterionCode],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('findings', finding.toMap());
    } else {
      await db.update(
        'findings',
        finding.toMap(),
        where: 'session_id = ? AND criterion_code = ?',
        whereArgs: [finding.sessionId, finding.criterionCode],
      );
    }
  }

  Future<List<CriterionFinding>> findingsForSession(String sessionId) async {
    final rows = await db.query('findings', where: 'session_id = ?', whereArgs: [sessionId]);
    return rows.map(CriterionFinding.fromMap).toList();
  }
}
