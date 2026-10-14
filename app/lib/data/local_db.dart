// Local-first persistence. Uses Flutter's native SQLite (sqflite).
//
// No server, no network: the database lives in the app documents directory
// on-device and is the single source of truth.

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocalDb {
  LocalDb._();

  static Database? _db;

  static const int _schemaVersion = 1;

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'kaushalsetu.db');
    _db = await openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
    );
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    const statements = <String>[
      '''
      CREATE TABLE trades (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        sector TEXT NOT NULL,
        description TEXT NOT NULL
      )
      ''',
      '''
      CREATE TABLE qualification_packs (
        id TEXT PRIMARY KEY,
        trade_id TEXT NOT NULL,
        code TEXT NOT NULL,
        title TEXT NOT NULL,
        nsqf_level INTEGER NOT NULL,
        typical_tools TEXT NOT NULL,
        units TEXT NOT NULL,
        source_note TEXT NOT NULL,
        FOREIGN KEY (trade_id) REFERENCES trades (id)
      )
      ''',
      '''
      CREATE TABLE rubrics (
        id TEXT PRIMARY KEY,
        trade_id TEXT NOT NULL,
        criterion_code TEXT NOT NULL,
        title TEXT NOT NULL,
        performance_indicators TEXT NOT NULL,
        evidence_requirement TEXT NOT NULL,
        level4 TEXT NOT NULL,
        level3 TEXT NOT NULL,
        level2 TEXT NOT NULL,
        level1 TEXT NOT NULL,
        FOREIGN KEY (trade_id) REFERENCES trades (id)
      )
      ''',
      '''
      CREATE TABLE workers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        preferred_language TEXT NOT NULL,
        primary_trade TEXT NOT NULL,
        years_of_experience REAL NOT NULL,
        location_region TEXT NOT NULL,
        prior_formal_training INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
      ''',
      '''
      CREATE TABLE experiences (
        id TEXT PRIMARY KEY,
        worker_id TEXT NOT NULL,
        trade_context TEXT NOT NULL,
        daily_tasks TEXT NOT NULL,
        tools_used TEXT NOT NULL,
        safety_practices TEXT NOT NULL,
        free_text_description TEXT NOT NULL,
        informal_learning_source TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (worker_id) REFERENCES workers (id)
      )
      ''',
      '''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        worker_id TEXT NOT NULL,
        trade_id TEXT NOT NULL,
        qualification_id TEXT NOT NULL,
        assessor_name TEXT NOT NULL,
        status TEXT NOT NULL,
        recommendation TEXT,
        overall_reasoning TEXT NOT NULL DEFAULT '',
        assessor_final_comments TEXT NOT NULL DEFAULT '',
        assessor_signature_name TEXT NOT NULL DEFAULT '',
        disclaimer_acknowledged INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY (worker_id) REFERENCES workers (id)
      )
      ''',
      '''
      CREATE TABLE evidence (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        source_type TEXT NOT NULL,
        file_path TEXT,
        file_mime TEXT,
        criterion_code TEXT NOT NULL DEFAULT '',
        verification_status TEXT NOT NULL,
        comments TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions (id)
      )
      ''',
      '''
      CREATE TABLE findings (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        criterion_code TEXT NOT NULL,
        status TEXT NOT NULL,
        comments TEXT NOT NULL DEFAULT '',
        gaps TEXT NOT NULL DEFAULT '',
        assessor_override INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions (id)
      )
      ''',
      'CREATE INDEX idx_exp_worker ON experiences (worker_id)',
      'CREATE INDEX idx_sessions_worker ON sessions (worker_id)',
      'CREATE INDEX idx_evidence_session ON evidence (session_id)',
      'CREATE INDEX idx_findings_session ON findings (session_id)',
    ];
    for (final s in statements) {
      await db.execute(s);
    }
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
