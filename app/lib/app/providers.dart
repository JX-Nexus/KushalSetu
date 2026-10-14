// Riverpod wiring for the on-device database and repositories.
//
// The database is opened once and seeded on first launch; everything else
// derives from it. No network providers exist by design.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local_db.dart';
import '../data/repository.dart';
import '../data/seed.dart';
import '../domain/matching.dart';
import '../domain/models.dart';

/// Opens the local SQLite database and applies reference seed data on first run.
final databaseProvider = FutureProvider<Database>((ref) async {
  final db = await LocalDb.instance();
  await seedIfEmpty(db);
  return db;
});

final repositoryProvider = FutureProvider<Repository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return Repository(db);
});

final matchingEngineProvider = Provider<MatchingEngine>((ref) => const MatchingEngine());

// -- Reference data ---------------------------------------------------------

final tradesProvider = FutureProvider<List<Trade>>((ref) async {
  final repo = await ref.watch(repositoryProvider.future);
  return repo.trades();
});

final rubricsProvider = FutureProvider.family<List<RubricCriterion>, String>((ref, tradeId) async {
  final repo = await ref.watch(repositoryProvider.future);
  return repo.rubricsForTrade(tradeId);
});

final qualificationPacksProvider =
    FutureProvider.family<List<QualificationPack>, String?>((ref, tradeId) async {
  final repo = await ref.watch(repositoryProvider.future);
  return repo.qualificationPacks(tradeId: tradeId);
});

// -- Workers / sessions -----------------------------------------------------

final workersProvider = FutureProvider<List<Worker>>((ref) async {
  final repo = await ref.watch(repositoryProvider.future);
  return repo.listWorkers();
});

final workerProvider = FutureProvider.family<Worker?, String>((ref, id) async {
  final repo = await ref.watch(repositoryProvider.future);
  return repo.getWorker(id);
});

final experienceProvider = FutureProvider.family<ExperienceDeclaration?, String>((ref, workerId) async {
  final repo = await ref.watch(repositoryProvider.future);
  return repo.experienceForWorker(workerId);
});

final sessionProvider = FutureProvider.family<AssessmentSession?, String>((ref, id) async {
  final repo = await ref.watch(repositoryProvider.future);
  return repo.getSession(id);
});

final evidenceProvider = FutureProvider.family<List<Evidence>, String>((ref, sessionId) async {
  final repo = await ref.watch(repositoryProvider.future);
  return repo.evidenceForSession(sessionId);
});

final findingsProvider = FutureProvider.family<List<CriterionFinding>, String>((ref, sessionId) async {
  final repo = await ref.watch(repositoryProvider.future);
  return repo.findingsForSession(sessionId);
});

/// Ranked qualification-pack suggestions for a worker based on their declaration.
final matchesProvider =
    FutureProvider.family<List<QualificationMatch>, String>((ref, workerId) async {
  final repo = await ref.watch(repositoryProvider.future);
  final engine = ref.watch(matchingEngineProvider);
  final worker = await repo.getWorker(workerId);
  if (worker == null) return const [];
  final exp = await repo.experienceForWorker(workerId);
  final packs = await repo.qualificationPacks();
  return engine.match(worker: worker, experience: exp, packs: packs);
});
