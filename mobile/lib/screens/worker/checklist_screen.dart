import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/catalogue_service.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/design.dart';
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
    final all = pack.allCriteria;
    final total = all.length;
    final done = all.where(_answered).length;
    final needEvidence = all.where((c) => c.evidence != 'none' && (_ev[c.id] ?? 0) == 0).length;
    var taskNo = 0;
    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: _a!.status == 'signed_off'
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                  icon: const Icon(Icons.verified),
                  label: Text(tr(context, 'view_result')),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ResultScreen(worker: widget.worker, assessmentId: _a!.id))),
                )
              : _editable
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
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
      body: Column(children: [
        HeroHeader(
          title: pack.title.get(lang),
          subtitle: '${pack.sector} • NSQF ${pack.nsqfLevel}',
          art: TradeArt(code: pack.code, hint: '${pack.sector} ${pack.title.get('en')}', size: 78, background: Colors.white),
          onBack: () => Navigator.of(context).pop(),
          actions: const [Padding(padding: EdgeInsets.only(right: 8), child: ConnectionChip())],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await context.read<SyncService>().syncAll();
              await _load();
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  ProgressRing(value: total == 0 ? 0 : done / total, label: '$done/$total', caption: tr(context, 'tasks_done')),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(context, 'checklist_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(tr(context, 'tap_to_open'), style: const TextStyle(color: AppTheme.inkSoft)),
                      const SizedBox(height: 8),
                      statusPill(context, _a!.status),
                    ]),
                  ),
                ]),
              ),
              if (_a!.status == 'needs_evidence')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InfoBanner(tr(context, 'status_needs_evidence'),
                      icon: Icons.add_a_photo, color: AppTheme.danger, background: AppTheme.dangerSoft),
                ),
              if (_editable && needEvidence > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InfoBanner('$needEvidence ${tr(context, 'evidence_missing')}',
                      icon: Icons.photo_camera, color: AppTheme.warning, background: AppTheme.warningSoft),
                ),
              for (var ni = 0; ni < pack.nos.length; ni++) ...[
                NosHeader(index: ni, title: pack.nos[ni].title.get(lang)),
                for (final c in pack.nos[ni].criteria)
                  Builder(builder: (ctx) {
                    taskNo += 1;
                    final no = taskNo;
                    final answered = _answered(c);
                    final evCount = _ev[c.id] ?? 0;
                    return AppCard(
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => TaskScreen(
                                worker: widget.worker, assessment: _a!, criterion: c, readOnly: !_editable)));
                        _load();
                      },
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: answered ? AppTheme.accent : AppTheme.sectionColors[ni % AppTheme.sectionColors.length][1], shape: BoxShape.circle),
                          child: answered
                              ? const Icon(Icons.check, color: Colors.white)
                              : Text('$no', style: TextStyle(color: AppTheme.sectionColors[ni % AppTheme.sectionColors.length][0], fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.text.get(lang), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.3)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              if (c.critical)
                                Pill(tr(context, 'critical'),
                                    color: AppTheme.danger, background: AppTheme.dangerSoft, icon: Icons.health_and_safety),
                              if (!answered)
                                Pill(tr(context, 'no_answer_yet'),
                                    color: AppTheme.inkSoft, background: const Color(0xFFEDEAE2)),
                              if (c.evidence != 'none')
                                Pill(
                                    evCount > 0
                                        ? '$evCount ${tr(context, 'attached')}'
                                        : tr(context, c.evidence == 'video' ? 'add_video' : 'add_photo'),
                                    color: evCount > 0 ? AppTheme.success : AppTheme.warning,
                                    background: evCount > 0 ? AppTheme.successSoft : AppTheme.warningSoft,
                                    icon: c.evidence == 'video' ? Icons.videocam : Icons.photo_camera),
                            ]),
                          ]),
                        ),
                        const Icon(Icons.chevron_right, color: AppTheme.inkSoft),
                      ]),
                    );
                  }),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
