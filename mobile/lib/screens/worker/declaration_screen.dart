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

  Widget _settingChip(String key) {
    return ChoiceChip(
      label: Text(tr(context, 'setting_$key')),
      selected: _setting == key,
      onSelected: (_) => setState(() => _setting = key),
    );
  }

  Widget _packCard(QualPack p, {_Candidate? cand, bool top = false}) {
    final lang = curLang(context);
    return AppCard(
      border: top ? AppTheme.primary : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(p.title.get(lang), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          if (top)
            Pill(
              tr(context, _confidence == 'high'
                  ? 'confidence_high'
                  : _confidence == 'medium'
                      ? 'confidence_medium'
                      : 'confidence_low'),
              color: _confidence == 'low' ? AppTheme.warning : AppTheme.success,
              background: _confidence == 'low' ? AppTheme.warningSoft : AppTheme.successSoft,
            ),
        ]),
        const SizedBox(height: 4),
        Text('${p.sector} • NSQF ${p.nsqfLevel}', style: const TextStyle(color: AppTheme.inkSoft)),
        const SizedBox(height: 6),
        Text(p.description.get(lang), style: const TextStyle(height: 1.35)),
        if (cand != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: cand.share.clamp(0.0, 1.0), minHeight: 8, backgroundColor: AppTheme.primarySoft),
          ),
          const SizedBox(height: 4),
          Text('${(cand.share * 100).round()}%', style: const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5)),
          if (cand.terms.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final t in cand.terms.take(5))
                  Pill(t, color: AppTheme.primary, background: AppTheme.primarySoft),
              ]),
            ),
        ],
        const SizedBox(height: 12),
        FilledButton(onPressed: () => _choose(p.code), child: Text(tr(context, 'select_this'))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = context.watch<CatalogueService>();
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'declaration_title'))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Text(tr(context, 'declaration_help'), style: const TextStyle(color: AppTheme.inkSoft, height: 1.4)),
        const SizedBox(height: 16),
        Text(tr(context, 'describe_work'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          minLines: 3,
          maxLines: 6,
          maxLength: 1500,
          decoration: AppTheme.field(hintText: tr(context, 'describe_hint')),
        ),
        const SizedBox(height: 10),
        Text('${tr(context, 'years_exp')}: ${_years.round()}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Slider(
          value: _years,
          min: 0,
          max: 40,
          divisions: 40,
          label: _years.round().toString(),
          onChanged: (v) => setState(() => _years = v),
        ),
        Text(tr(context, 'work_setting'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          _settingChip('residential'),
          _settingChip('commercial'),
          _settingChip('industrial'),
          _settingChip('site'),
        ]),
        const SizedBox(height: 16),
        Text(tr(context, 'tools_used'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(controller: _tools, decoration: AppTheme.field(hintText: tr(context, 'tools_hint'))),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.search),
          label: Text(tr(context, 'find_qualification')),
          onPressed: _busy ? null : _find,
        ),
        if (_searched) ...[
          SectionTitle(tr(context, 'best_matches')),
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
        const SizedBox(height: 24),
      ]),
    );
  }
}
