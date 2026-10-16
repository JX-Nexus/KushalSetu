import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/catalogue_service.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import 'result_screen.dart';
import 'task_screen.dart';

/// Practical task checklist generated from the chosen qualification pack's NOS / criteria.
class ChecklistScreen extends StatefulWidget {
  final Worker worker;
  final String assessmentId;
  const ChecklistScreen({super.key, required this.worker, required this.assessmentId});
  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  Assessment? _a;
  Map<String, ResponseRow> _resp = {};
  Map<String, int> _ev = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<LocalDb>();
    final a = await db.assessment(widget.assessmentId);
    final rs = await db.responses(widget.assessmentId);
    final evs = await db.evidence(widget.assessmentId);
    final ev = <String, int>{};
    for (final e in evs) {
      ev[e.criterionId] = (ev[e.criterionId] ?? 0) + 1;
    }
    if (!mounted) return;
    setState(() {
      _a = a;
      _resp = {for (final r in rs) r.criterionId: r};
      _ev = ev;
      _loading = false;
    });
  }

  bool get _editable => _a != null && (_a!.status == 'in_progress' || _a!.status == 'needs_evidence');

  bool _answered(Criterion c) => (_resp[c.id]?.answerText.trim().isNotEmpty ?? false);

  Future<void> _submit(QualPack pack) async {
    final missing = pack.allCriteria.where((c) => !_answered(c)).length;
    final msg = missing > 0
        ? '$missing ${tr(context, 'unanswered')}.\n\n${tr(context, 'submit_confirm')}'
        : tr(context, 'submit_confirm');
    if (!await confirm(context, msg, yes: tr(context, 'submit_assessment'))) return;
    final db = context.read<LocalDb>();
    final sync = context.read<SyncService>();
    final a = _a!;
    await db.saveAssessment(a.copyWith(status: 'submitted', dirty: true));
    sync.syncAll(silent: true);
    if (!mounted) return;
    toast(context, tr(context, 'submitted_ok'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cat = context.watch<CatalogueService>();
    final lang = curLang(context);
    if (_loading || _a == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final pack = cat.byCode(_a!.qpCode);
    if (pack == null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(Icons.error_outline, 'Qualification pack ${_a!.qpCode} is not in this phone\'s catalogue. Connect to the server and sync.'));
    }
    final total = pack.allCriteria.length;
    final done = pack.allCriteria.where(_answered).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'checklist_title')),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: ConnectionChip())],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _a!.status == 'signed_off'
              ? FilledButton.icon(
                  icon: const Icon(Icons.verified),
                  label: Text(tr(context, 'result_title')),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ResultScreen(worker: widget.worker, assessmentId: _a!.id))),
                )
              : _editable
                  ? FilledButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text(tr(context, 'review_submit')),
                      onPressed: () => _submit(pack),
                    )
                  : Align(
                      alignment: Alignment.center,
                      heightFactor: 1.2,
                      child: statusPill(context, _a!.status),
                    ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await context.read<SyncService>().syncAll();
          await _load();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          AppCard(
            color: AppTheme.primarySoft,
            border: AppTheme.primarySoft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pack.title.get(lang), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primaryDark)),
              const SizedBox(height: 2),
              Text('${pack.sector} • NSQF ${pack.nsqfLevel}', style: const TextStyle(color: AppTheme.primaryDark)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total, minHeight: 10, backgroundColor: Colors.white, color: AppTheme.primary),
              ),
              const SizedBox(height: 6),
              Text('$done/$total ${tr(context, 'tasks_done')}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
          if (_a!.status == 'needs_evidence')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InfoBanner(tr(context, 'status_needs_evidence'),
                  icon: Icons.add_a_photo, color: AppTheme.danger, background: AppTheme.dangerSoft),
            ),
          for (final n in pack.nos) ...[
            SectionTitle(n.title.get(lang)),
            for (final c in n.criteria)
              AppCard(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TaskScreen(
                          worker: widget.worker, assessment: _a!, criterion: c, readOnly: !_editable)));
                  _load();
                },
                child: Row(children: [
                  Icon(_answered(c) ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: _answered(c) ? AppTheme.success : AppTheme.line, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.text.get(lang), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.3)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        if (c.critical)
                          Pill(tr(context, 'critical'),
                              color: AppTheme.danger, background: AppTheme.dangerSoft, icon: Icons.health_and_safety),
                        if (c.evidence != 'none')
                          Pill(
                              (_ev[c.id] ?? 0) > 0
                                  ? '${_ev[c.id]} ${c.evidence}'
                                  : tr(context, c.evidence == 'video' ? 'add_video' : 'add_photo'),
                              color: (_ev[c.id] ?? 0) > 0 ? AppTheme.success : AppTheme.inkSoft,
                              background: (_ev[c.id] ?? 0) > 0 ? AppTheme.successSoft : const Color(0xFFEDEAE2),
                              icon: c.evidence == 'video' ? Icons.videocam : Icons.photo_camera),
                      ]),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: AppTheme.inkSoft),
                ]),
              ),
          ],
        ]),
      ),
    );
  }
}
