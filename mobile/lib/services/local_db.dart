import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/models.dart';

/// Offline store. Every record has a client-generated UUID so syncing is idempotent.
class LocalDb {
  Database? _db;

  Database get db {
    final d = _db;
    if (d == null) throw StateError('LocalDb not initialised');
    return d;
  }

  Future<void> init() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'kaushalsetu_v2.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''CREATE TABLE workers (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, village TEXT,
          language TEXT, created_at TEXT)''');
        await d.execute('''CREATE TABLE assessments (
          id TEXT PRIMARY KEY, worker_id TEXT NOT NULL, language TEXT,
          declaration_text TEXT, raw_text TEXT, years REAL, setting TEXT, tools TEXT,
          qp_code TEXT, status TEXT, dirty INTEGER DEFAULT 1, created_at TEXT, match_json TEXT)''');
        await d.execute('''CREATE TABLE responses (
          id TEXT PRIMARY KEY, assessment_id TEXT NOT NULL, criterion_id TEXT NOT NULL,
          answer_text TEXT, self_rating INTEGER, answered_at TEXT,
          UNIQUE(assessment_id, criterion_id))''');
        await d.execute('''CREATE TABLE evidence (
          id TEXT PRIMARY KEY, assessment_id TEXT NOT NULL, criterion_id TEXT NOT NULL,
          kind TEXT, local_path TEXT, captured_at TEXT, uploaded INTEGER DEFAULT 0)''');
      },
    );
  }

  // ---- workers
  Future<List<Worker>> workers() async {
    final rows = await db.query('workers', orderBy: 'created_at DESC');
    return rows.map(Worker.fromMap).toList();
  }

  Future<Worker?> worker(String id) async {
    final rows = await db.query('workers', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Worker.fromMap(rows.first);
  }

  Future<void> saveWorker(Worker w) async {
    await db.insert('workers', w.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWorker(String id) async {
    final as = await db.query('assessments', columns: ['id'], where: 'worker_id = ?', whereArgs: [id]);
    for (final a in as) {
      final aid = a['id'] as String;
      await db.delete('responses', where: 'assessment_id = ?', whereArgs: [aid]);
      await db.delete('evidence', where: 'assessment_id = ?', whereArgs: [aid]);
    }
    await db.delete('assessments', where: 'worker_id = ?', whereArgs: [id]);
    await db.delete('workers', where: 'id = ?', whereArgs: [id]);
  }

  // ---- assessments
  Future<List<Assessment>> assessmentsFor(String workerId) async {
    final rows = await db.query('assessments',
        where: 'worker_id = ?', whereArgs: [workerId], orderBy: 'created_at DESC');
    return rows.map(Assessment.fromMap).toList();
  }

  Future<Assessment?> assessment(String id) async {
    final rows = await db.query('assessments', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Assessment.fromMap(rows.first);
  }

  Future<void> saveAssessment(Assessment a) async {
    await db.insert('assessments', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Assessment>> dirtyAssessments() async {
    final rows = await db.query('assessments', where: 'dirty = 1');
    return rows.map(Assessment.fromMap).toList();
  }

  Future<List<Assessment>> activeRemoteAssessments() async {
    final rows = await db.query('assessments',
        where: "dirty = 0 AND status IN ('submitted','under_review','needs_evidence')");
    return rows.map(Assessment.fromMap).toList();
  }

  Future<int> pendingCount() async {
    final a = await db.rawQuery('SELECT COUNT(*) c FROM assessments WHERE dirty = 1');
    final e = await db.rawQuery(
        'SELECT COUNT(*) c FROM evidence e JOIN assessments a ON a.id = e.assessment_id WHERE e.uploaded = 0');
    return ((a.first['c'] ?? 0) as int) + ((e.first['c'] ?? 0) as int);
  }

  // ---- responses
  Future<List<ResponseRow>> responses(String assessmentId) async {
    final rows = await db.query('responses', where: 'assessment_id = ?', whereArgs: [assessmentId]);
    return rows.map(ResponseRow.fromMap).toList();
  }

  Future<void> saveResponse(ResponseRow r) async {
    // Keep the existing row id for a criterion so retries stay idempotent.
    final existing = await db.query('responses',
        where: 'assessment_id = ? AND criterion_id = ?', whereArgs: [r.assessmentId, r.criterionId]);
    if (existing.isNotEmpty) {
      await db.update(
          'responses',
          {'answer_text': r.answerText, 'self_rating': r.selfRating, 'answered_at': r.answeredAt},
          where: 'id = ?',
          whereArgs: [existing.first['id']]);
    } else {
      await db.insert('responses', r.toMap());
    }
    await db.update('assessments', {'dirty': 1}, where: 'id = ?', whereArgs: [r.assessmentId]);
  }

  // ---- evidence
  Future<List<EvidenceRow>> evidence(String assessmentId) async {
    final rows = await db.query('evidence',
        where: 'assessment_id = ?', whereArgs: [assessmentId], orderBy: 'captured_at');
    return rows.map(EvidenceRow.fromMap).toList();
  }

  Future<void> saveEvidence(EvidenceRow e) async {
    await db.insert('evidence', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await db.update('assessments', {'dirty': 1}, where: 'id = ?', whereArgs: [e.assessmentId]);
  }

  Future<void> markEvidenceUploaded(String id) async {
    await db.update('evidence', {'uploaded': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteEvidence(String id) async {
    await db.delete('evidence', where: 'id = ?', whereArgs: [id]);
  }
}
