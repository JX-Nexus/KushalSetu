import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/catalogue_service.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'checklist_screen.dart';
import 'declaration_screen.dart';
import 'result_screen.dart';

class _Row {
  final Assessment a;
  final int answered;
  final int total;
  const _Row(this.a, this.answered, this.total);
}

class WorkerAssessmentsScreen extends StatefulWidget {
  final Worker worker;
  const WorkerAssessmentsScreen({super.key, required this.worker});
  @override
  State<WorkerAssessmentsScreen> createState() => _WorkerAssessmentsScreenState();
}

class _WorkerAssessmentsScreenState extends State<WorkerAssessmentsScreen> {
  List<_Row> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<LocalDb>();
    final cat = context.read<CatalogueService>();
    final list = await db.assessmentsFor(widget.worker.id);
    final rows = <_Row>[];
    for (final a in list) {
      final rs = await db.responses(a.id);
      final pack = cat.byCode(a.qpCode);
      rows.add(_Row(a, rs.where((r) => r.answerText.trim().isNotEmpty).length, pack?.allCriteria.length ?? 0));
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _open(Assessment a) async {
    Widget next;
    if (a.status == 'signed_off') {
      next = ResultScreen(worker: widget.worker, assessmentId: a.id);
    } else if (a.qpCode == null) {
      next = DeclarationScreen(worker: widget.worker, existing: a);
    } else {
      next = ChecklistScreen(worker: widget.worker, assessmentId: a.id);
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => next));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lang = curLang(context);
    final cat = context.watch<CatalogueService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.worker.name),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: ConnectionChip())],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'new_assessment')),
        onPressed: () async {
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => DeclarationScreen(worker: widget.worker)));
          _load();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? EmptyState(Icons.assignment_outlined, tr(context, 'no_assessments'))
              : RefreshIndicator(
                  onRefresh: () async {
                    await context.read<SyncService>().syncAll();
                    await _load();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: _rows.length,
                    itemBuilder: (ctx, i) {
                      final r = _rows[i];
                      final pack = cat.byCode(r.a.qpCode);
                      final progress = r.total == 0 ? 0.0 : r.answered / r.total;
                      return AppCard(
                        onTap: () => _open(r.a),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text(pack?.title.get(lang) ?? tr(context, 'declaration_title'),
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            ),
                            statusPill(context, r.a.status),
                          ]),
                          const SizedBox(height: 10),
                          if (r.total > 0) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                  value: progress, minHeight: 8, backgroundColor: AppTheme.primarySoft),
                            ),
                            const SizedBox(height: 6),
                            Text('${r.answered}/${r.total} ${tr(context, 'tasks_done')}',
                                style: const TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
                          ],
                          if (r.a.dirty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(children: [
                                const Icon(Icons.sync, size: 14, color: AppTheme.warning),
                                const SizedBox(width: 4),
                                Text(tr(context, 'pending_sync'),
                                    style: const TextStyle(color: AppTheme.warning, fontSize: 12.5)),
                              ]),
                            ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
