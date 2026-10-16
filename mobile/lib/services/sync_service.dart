import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../state/app_state.dart';
import 'api_service.dart';
import 'local_db.dart';

/// Pushes locally captured work to the server whenever it is reachable.
/// Every push is idempotent (client UUIDs), so retries after a dropped connection are safe.
class SyncService extends ChangeNotifier {
  final LocalDb db;
  final AppState app;
  bool syncing = false;
  int pending = 0;
  String? lastError;
  DateTime? lastSync;
  StreamSubscription<dynamic>? _sub;

  SyncService(this.db, this.app);

  void start() {
    _sub = Connectivity().onConnectivityChanged.listen((_) {
      syncAll(silent: true);
    });
    refreshPending();
    syncAll(silent: true);
  }

  Future<void> refreshPending() async {
    pending = await db.pendingCount();
    notifyListeners();
  }

  Future<void> syncAll({bool silent = false}) async {
    if (syncing) return;
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      final reachable = await app.checkServer();
      if (!reachable) {
        if (!silent) lastError = 'Cannot reach the server';
        return;
      }
      final api = app.api;
      for (final a in await db.dirtyAssessments()) {
        final w = await db.worker(a.workerId);
        if (w == null) continue;
        try {
          final token = await api.authWorker(w);
          final responses = await db.responses(a.id);
          final out = await api.push(token, w, a, responses, a.status == 'in_progress' ? 'in_progress' : 'submitted');
          var updated = a;
          final match = out['match'];
          if (match != null) updated = updated.copyWith(matchJson: jsonEncode(match));
          final locked = out['locked'] == true;
          if (locked) {
            updated = updated.copyWith(status: (out['status'] ?? a.status).toString());
          }
          // upload evidence for this assessment (only possible when a pack is chosen)
          var allUploaded = true;
          if (a.qpCode != null && !locked) {
            for (final e in await db.evidence(a.id)) {
              if (e.uploaded) continue;
              try {
                await api.uploadEvidence(token, e);
                await db.markEvidenceUploaded(e.id);
              } on ApiException catch (ex) {
                if (ex.status == 409 || ex.status == 415 || ex.status == 413 || ex.status == 422) {
                  // permanent rejection: do not retry forever
                  await db.markEvidenceUploaded(e.id);
                  lastError = 'Evidence rejected: ${ex.message}';
                } else {
                  allUploaded = false;
                  rethrow;
                }
              }
            }
          }
          await db.saveAssessment(updated.copyWith(dirty: !allUploaded));
        } on ApiException catch (ex) {
          lastError = ex.message;
          if (ex.isNetwork) break; // server vanished mid-sync; stop and retry later
        }
      }
      // pick up assessor progress / results
      for (final a in await db.activeRemoteAssessments()) {
        final w = await db.worker(a.workerId);
        if (w == null) continue;
        try {
          final token = await api.authWorker(w);
          final d = await api.assessmentDetail(token, a.id);
          final st = (d['assessment']?['status'] ?? a.status).toString();
          if (st != a.status) await db.saveAssessment(a.copyWith(status: st));
        } on ApiException catch (_) {}
      }
      lastSync = DateTime.now();
    } finally {
      syncing = false;
      pending = await db.pendingCount();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
