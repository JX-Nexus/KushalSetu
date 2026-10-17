import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/catalogue_service.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/design.dart';
import '../../widgets/ui.dart';
import 'checklist_screen.dart';

class _Candidate {
  final String code;
  final double share;
  final List<String> terms;
  const _Candidate(this.code, this.share, this.terms);
}

/// Structured self-declaration -> mapped NSQF qualification pack(s) -> worker confirms one.
class DeclarationScreen extends StatefulWidget {
  final Worker worker;
  final Assessment? existing;
  const DeclarationScreen({super.key, required this.worker, this.existing});
  @override
  State<DeclarationScreen> createState() => _DeclarationScreenState();
}

class _DeclarationScreenState extends State<DeclarationScreen> {
  final _text = TextEditingController();
  final _tools = TextEditingController();
  double _years = 3;
  String _setting = 'residential';
  List<_Candidate> _candidates = [];
  String _confidence = 'none';
  bool _searched = false;
  bool _browseAll = false;
  bool _busy = false;
  bool _fromServer = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _text.text = e.rawText;
      _tools.text = e.tools;
      _years = e.years ?? 3;
      _setting = e.setting.isEmpty ? 'residential' : e.setting;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _tools.dispose();
    super.dispose();
  }

  String get _composed => '${_text.text.trim()} ${_tools.text.trim()}'.trim();

  Future<void> _find() async {
    final cat = context.read<CatalogueService>();
    final app = context.read<AppState>();
    if (_text.text.trim().isEmpty) {
      toast(context, tr(context, 'describe_required'), error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    // 1. instant on-device mapping (works offline)
    final local = cat.engine?.rank(_composed);
    var cands = <_Candidate>[];
    var conf = 'none';
    if (local != null && local.matches.isNotEmpty) {
      final total = local.matches.fold<double>(0, (s, m) => s + m.score);
      cands = [
        for (final m in local.matches.take(4))
          _Candidate(m.code, total > 0 ? m.score / total : 0, m.terms)
      ];
      conf = local.confidence;
    }
    var server = false;
    // 2. authoritative server mapping when reachable
    if (await app.checkServer()) {
      try {
        final token = await app.api.authWorker(widget.worker);
        final out = await app.api.mapDeclaration(token, _composed, app.lang);
        final ms = (out['matches'] as List?) ?? [];
        if (ms.isNotEmpty) {
          cands = [
            for (final m in ms)
              _Candidate(
                (m as Map)['qp_code'].toString(),
                ((m['share'] ?? 0) as num).toDouble(),
                ((m['matched_terms'] ?? []) as List).map((e) => e.toString()).toList(),
              )
          ];
          conf = (out['confidence'] ?? conf).toString();
          server = true;
        }
      } on ApiException catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _candidates = cands.where((c) => cat.byCode(c.code) != null).toList();
      _confidence = conf;
      _searched = true;
      _browseAll = false;
      _fromServer = server;
      _busy = false;
    });
  }

  Future<void> _choose(String code) async {
    final db = context.read<LocalDb>();
    final sync = context.read<SyncService>();
    final e = widget.existing;
    final a = Assessment(
      id: e?.id ?? const Uuid().v4(),
      workerId: widget.worker.id,
      language: context.read<AppState>().lang,
      declarationText: _composed,
      rawText: _text.text.trim(),
      years: _years,
      setting: _setting,
      tools: _tools.text.trim(),
      qpCode: code,
      status: e?.status ?? 'in_progress',
      dirty: true,
      createdAt: e?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
      matchJson: jsonEncode({
        'source': _fromServer ? 'server' : 'device',
        'confidence': _confidence,
        'candidates': [for (final c in _candidates) {'qp_code': c.code, 'share': c.share}],
      }),
    );
    await db.saveAssessment(a);
    sync.syncAll(silent: true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChecklistScreen(worker: widget.worker, assessmentId: a.id)));
  }

  Widget _settingTile(String key, IconData icon) {
    final sel = _setting == key;
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 36 - 24) / 4,
      child: ActionTile(
        icon: icon,
        label: tr(context, 'setting_$key'),
        color: sel ? Colors.white : AppTheme.primary,
        background: sel ? AppTheme.primary : AppTheme.primarySoft,
        onTap: () => setState(() => _setting = key),
      ),
    );
  }

  Widget _packCard(QualPack p, {_Candidate? cand, bool top = false}) {
    final lang = curLang(context);
    final icon = iconForTrade('${p.sector} ${p.title.get('en')}');
    Widget? footer;
    if (cand != null) {
      footer = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  value: cand.share.clamp(0.0, 1.0), minHeight: 8, backgroundColor: AppTheme.primarySoft, color: AppTheme.accent),
            ),
          ),
          const SizedBox(width: 10),
          Text('${(cand.share * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        if (cand.terms.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final t in cand.terms.take(5)) Pill(t, color: AppTheme.primary, background: AppTheme.primarySoft),
            ]),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: top ? AppTheme.accent : AppTheme.primary),
            onPressed: () => _choose(p.code),
            child: Text(tr(context, 'select_this')),
          ),
        ),
      ]);
    }
    return TradeCard(
      icon: icon,
      artCode: p.code,
      title: p.title.get(lang),
      subtitle: '${p.sector} • NSQF ${p.nsqfLevel}',
      highlighted: top,
      onTap: cand == null ? () => _choose(p.code) : null,
      trailing: top
          ? Pill(
              tr(context, _confidence == 'high'
                  ? 'confidence_high'
                  : _confidence == 'medium'
                      ? 'confidence_medium'
                      : 'confidence_low'),
              color: _confidence == 'low' ? AppTheme.warning : AppTheme.success,
              background: _confidence == 'low' ? AppTheme.warningSoft : AppTheme.successSoft,
            )
          : (cand == null ? const Icon(Icons.chevron_right, color: AppTheme.inkSoft) : null),
      footer: footer,
    );
  }

  Widget _section(String title, Widget child) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = context.watch<CatalogueService>();
    return Scaffold(
      body: Column(children: [
        HeroHeader(
          title: tr(context, 'declaration_title'),
          subtitle: tr(context, 'declaration_help'),
          onBack: () => Navigator.of(context).pop(),
          art: const Illustration('illus_step1', height: 120, fallback: Icons.edit_note),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
            StepProgressBar(
              current: _searched ? 2 : 1,
              total: 2,
              label: trf(context, 'step_n_of', {'n': _searched ? '2' : '1', 'm': '2'}),
            ),
            const SizedBox(height: 12),
            _section(
              tr(context, 'describe_work'),
              TextField(
                controller: _text,
                minLines: 3,
                maxLines: 6,
                maxLength: 1500,
                decoration: AppTheme.field(hintText: tr(context, 'describe_hint')),
              ),
            ),
            _section(
              '${tr(context, 'years_exp')}: ${_years.round()}',
              Slider(
                value: _years,
                min: 0,
                max: 40,
                divisions: 40,
                label: _years.round().toString(),
                onChanged: (v) => setState(() => _years = v),
              ),
            ),
            _section(
              tr(context, 'work_setting'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _settingTile('residential', Icons.home),
                _settingTile('commercial', Icons.storefront),
                _settingTile('industrial', Icons.factory),
                _settingTile('site', Icons.construction),
              ]),
            ),
            _section(
              tr(context, 'tools_used'),
              TextField(controller: _tools, decoration: AppTheme.field(hintText: tr(context, 'tools_hint'))),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search),
              label: Text(tr(context, 'find_qualification')),
              onPressed: _busy ? null : _find,
            ),
            if (_searched) ...[
              SectionTitle(_browseAll ? tr(context, 'choose_trade') : tr(context, 'best_matches')),
              Text(tr(context, _fromServer ? 'matched_on_server' : 'matched_on_phone'),
                  style: const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5)),
              const SizedBox(height: 6),
              if (!_browseAll)
                for (var i = 0; i < _candidates.length; i++)
                  _packCard(cat.byCode(_candidates[i].code)!, cand: _candidates[i], top: i == 0),
              if (_browseAll)
                for (final p in cat.packs) _packCard(p),
              if (!_browseAll)
                TextButton(onPressed: () => setState(() => _browseAll = true), child: Text(tr(context, 'browse_all'))),
            ],
          ]),
        ),
      ]),
    );
  }
}
