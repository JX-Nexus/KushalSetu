import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/catalogue_service.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/design.dart';
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

/// Candidate home: greeting, the assessment to continue, a clear next action, and history.
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

  Future<void> _startNew() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeclarationScreen(worker: widget.worker)));
    _load();
  }

  Widget _activeCard(_Row r, CatalogueService cat, String lang) {
    final pack = cat.byCode(r.a.qpCode);
    final progress = r.total == 0 ? 0.0 : r.answered / r.total;
    final done = r.a.status == 'signed_off';
    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: () => _open(r.a),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProgressRing(value: progress, label: '${r.answered}/${r.total == 0 ? '-' : r.total}', caption: tr(context, 'tasks_done')),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pack?.title.get(lang) ?? tr(context, 'declaration_title'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink)),
              const SizedBox(height: 6),
              statusPill(context, r.a.status),
              if (r.a.dirty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    const Icon(Icons.sync, size: 14, color: AppTheme.warning),
                    const SizedBox(width: 4),
                    Text(tr(context, 'waiting_to_send'), style: const TextStyle(color: AppTheme.warning, fontSize: 12.5)),
                  ]),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: done ? AppTheme.accent : AppTheme.primary),
          icon: Icon(done ? Icons.verified : Icons.play_arrow),
          label: Text(done ? tr(context, 'view_result') : tr(context, 'continue_assessment')),
          onPressed: () => _open(r.a),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = curLang(context);
    final cat = context.watch<CatalogueService>();
    _Row? active;
    for (final r in _rows) {
      if (r.a.status != 'signed_off') {
        active = r;
        break;
      }
    }
    final others = _rows.where((r) => r != active).toList();
    return Scaffold(
      body: Column(children: [
        HeroHeader(
          title: '${tr(context, 'namaste')}, ${widget.worker.name}',
          subtitle: tr(context, 'home_sub'),
          onBack: () => Navigator.of(context).pop(),
          actions: const [Padding(padding: EdgeInsets.only(right: 8), child: ConnectionChip())],
          art: active == null
              ? null
              : TradeArt(
                  code: active.a.qpCode ?? '',
                  hint: '${cat.byCode(active.a.qpCode)?.sector ?? ''} ${cat.byCode(active.a.qpCode)?.title.get('en') ?? ''}',
                  size: 78,
                  background: Colors.white,
                ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async {
                    await context.read<SyncService>().syncAll();
                    await _load();
                  },
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
                    if (active != null) _activeCard(active, cat, lang),
                    if (active == null)
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        FadeSlideIn(child: HowItWorksStep(image: 'illus_step1', number: 1, text: tr(context, 'hiw_1'), color: AppTheme.saffronDeep, soft: AppTheme.saffronSoft)),
                        FadeSlideIn(delayMs: 120, child: HowItWorksStep(image: 'illus_step2', number: 2, text: tr(context, 'hiw_2'), color: AppTheme.teal, soft: AppTheme.tealSoft)),
                        FadeSlideIn(delayMs: 240, child: HowItWorksStep(image: 'illus_assessor', number: 3, text: tr(context, 'hiw_3'), color: AppTheme.plum, soft: AppTheme.plumSoft)),
                      ]),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(tr(context, 'new_assessment')),
                      onPressed: _startNew,
                    ),
                    if (others.isNotEmpty) SectionTitle(tr(context, 'assessments')),
                    for (final r in others)
                      AppCard(
                        onTap: () => _open(r.a),
                        child: Row(children: [
                          TradeArt(
                            code: r.a.qpCode ?? '',
                            hint: '${cat.byCode(r.a.qpCode)?.sector ?? ''} ${cat.byCode(r.a.qpCode)?.title.get('en') ?? ''}',
                            size: 52,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(cat.byCode(r.a.qpCode)?.title.get(lang) ?? tr(context, 'declaration_title'),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              statusPill(context, r.a.status),
                            ]),
                          ),
                          const Icon(Icons.chevron_right, color: AppTheme.inkSoft),
                        ]),
                      ),
                    if (_rows.isEmpty) const SizedBox(height: 4),
                  ]),
                ),
        ),
      ]),
    );
  }
}
