import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/design.dart';
import '../../widgets/ui.dart';

/// Assessor workspace: evidence + AI hints + anchored 0-3 rubric -> profile -> sign-off.
/// The AI only suggests; every score and the final decision are the assessor's.
class AssessorReviewScreen extends StatefulWidget {
  final String assessmentId;
  const AssessorReviewScreen({super.key, required this.assessmentId});
  @override
  State<AssessorReviewScreen> createState() => _AssessorReviewScreenState();
}

class _AssessorReviewScreenState extends State<AssessorReviewScreen> {
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _anchors = [];
  final Map<String, int> _scores = {};
  final Map<String, TextEditingController> _comments = {};
  Map<String, dynamic>? _profile;
  String _source = '';
  bool _blind = false;
  bool _loading = true;
  bool _saving = false;
  bool _unsaved = false;
  String? _error;

  AppState get _app => context.read<AppState>();
  String get _token => _app.assessorToken ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _comments.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _app.api.assessmentDetail(_token, widget.assessmentId);
      if (!mounted) return;
      List<Map<String, dynamic>> anchors = [];
      try {
        final r = await _app.api.rubric();
        anchors = ((r['scale'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
      if (!mounted) return;
      final mine = (d['my_scores'] as Map?) ?? {};
      _scores.clear();
      mine.forEach((k, v) {
        _scores[k.toString()] = ((v as Map)['score'] as num).toInt();
        final ctl = _comments.putIfAbsent(k.toString(), () => TextEditingController());
        ctl.text = (v['comment'] ?? '').toString();
      });
      setState(() {
        _d = d;
        _anchors = anchors;
        _profile = d['profile'] == null ? null : Map<String, dynamic>.from(d['profile'] as Map);
        _source = (d['scores_source'] ?? '').toString();
        _unsaved = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _criteria() {
    final out = <Map<String, dynamic>>[];
    final cl = _d?['checklist'] as Map?;
    for (final n in ((cl?['nos'] ?? []) as List)) {
      for (final c in (n['criteria'] as List)) {
        out.add(Map<String, dynamic>.from(c as Map));
      }
    }
    return out;
  }

  bool get _allScored {
    final cs = _criteria();
    return cs.isNotEmpty && cs.every((c) => _scores.containsKey(c['id']));
  }

  Future<bool> _save({bool quiet = false}) async {
    if (_scores.isEmpty) {
      if (!quiet) toast(context, 'Score at least one criterion first', error: true);
      return false;
    }
    setState(() => _saving = true);
    try {
      final r = await _app.api.saveScores(
        _token,
        widget.assessmentId,
        [
          for (final e in _scores.entries)
            {'criterion_id': e.key, 'score': e.value, 'comment': _comments[e.key]?.text.trim().isEmpty ?? true ? null : _comments[e.key]!.text.trim()}
        ],
        !_blind,
      );
      if (!mounted) return false;
      setState(() {
        _profile = Map<String, dynamic>.from(r['profile'] as Map);
        _source = (r['scores_source'] ?? '').toString();
        _unsaved = false;
      });
      if (!quiet) toast(context, 'Scores saved');
      return true;
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOff() async {
    if (!_allScored) {
      toast(context, 'Score every criterion before signing off', error: true);
      return;
    }
    if (_unsaved || _profile == null || _source != 'assessor') {
      if (!await _save(quiet: true)) return;
    }
    if (!mounted) return;
    final rec = (_profile?['recommendation'] as Map?)?['code']?.toString() ?? 'incomplete';
    final res = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _SignOffDialog(recommendation: rec, label: ((_profile?['recommendation'] as Map?)?['label'] ?? '').toString()),
    );
    if (res == null) return;
    try {
      final out = await _app.api.signOff(_token, widget.assessmentId, res['decision']!, res['reasoning'] ?? '');
      if (!mounted) return;
      toast(context, out['status'] == 'needs_evidence' ? 'Worker asked for more evidence' : 'Signed off');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _pdf() async {
    try {
      final path = await _app.api.download('/api/assessments/${widget.assessmentId}/report.pdf', _token,
          'rpl_report_${widget.assessmentId.substring(0, 8)}.pdf');
      await OpenFilex.open(path);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _openVideo(Map ev) async {
    try {
      final path = await _app.api.download(ev['url'].toString(), _token, '${ev['id']}.mp4');
      await OpenFilex.open(path);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  void _showImage(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(child: Image.network(url, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(24), child: Text('Could not load image')))),
      ),
    );
  }

  // ------------------------------------------------------------ pieces
  Widget _evidenceStrip(List<Map<String, dynamic>> evs) {
    if (evs.isEmpty) {
      return const Text('No evidence uploaded for this task.', style: TextStyle(color: AppTheme.inkSoft));
    }
    return SizedBox(
      height: 96,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final e in evs)
          GestureDetector(
            onTap: () => e['kind'] == 'video' ? _openVideo(e) : _showImage(_app.api.evidenceUrl(e['url'].toString(), _token)),
            child: Container(
              width: 96,
              height: 96,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: e['kind'] == 'video'
                  ? const Icon(Icons.play_circle_fill, size: 40, color: AppTheme.primary)
                  : Image.network(_app.api.evidenceUrl(e['url'].toString(), _token),
                      fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
            ),
          ),
      ]),
    );
  }

  Widget _aiBox(Map? resp, List<Map<String, dynamic>> evs) {
    final ai = resp?['ai'] as Map?;
    final rule = ai?['rule'] as Map?;
    if (rule == null) {
      return const Text('No AI hint (no answer yet).', style: TextStyle(color: AppTheme.inkSoft));
    }
    final s = (rule['suggested_score'] as num).toInt();
    final llm = ai?['llm'] as Map?;
    final matched = ((rule['matched'] ?? []) as List).map((e) => e.toString()).toList();
    final missing = ((rule['missing'] ?? []) as List).map((e) => e.toString()).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.infoSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 18, color: AppTheme.info),
          const SizedBox(width: 6),
          const Text('AI hint', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.info)),
          const Spacer(),
          Pill('suggests $s • conf ${((rule['confidence'] as num) * 100).round()}%',
              color: AppTheme.scoreColor(s), background: Colors.white),
        ]),
        const SizedBox(height: 8),
        for (final m in matched)
          Padding(padding: const EdgeInsets.only(bottom: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.check, size: 16, color: AppTheme.success), const SizedBox(width: 6), Expanded(child: Text(m, style: const TextStyle(fontSize: 13))),
          ])),
        for (final m in missing)
          Padding(padding: const EdgeInsets.only(bottom: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.close, size: 16, color: AppTheme.danger), const SizedBox(width: 6), Expanded(child: Text(m, style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft))),
          ])),
        if (rule['capped'] == true)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Capped: a written answer alone cannot earn level 3 without practical evidence.',
                style: TextStyle(fontSize: 12.5, color: AppTheme.warning)),
          ),
        if (llm != null) ...[
          const Divider(height: 18),
          Text('${llm['provider']} says ${llm['suggested_score']}: ${llm['rationale']}', style: const TextStyle(fontSize: 13)),
          if ((llm['follow_up_question'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Ask: ${llm['follow_up_question']}', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
            ),
          if (ai?['llm_disagrees'] == true)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('The two AI views differ by 2+ points: look closely.', style: TextStyle(fontSize: 12.5, color: AppTheme.warning)),
            ),
        ],
        for (final e in evs)
          if (e['ai'] != null) ...[
            const Divider(height: 18),
            Text('Photo check: ${((e['ai']['observations'] ?? []) as List).join('; ')}', style: const TextStyle(fontSize: 13)),
          ],
      ]),
    );
  }

  Widget _scorePicker(String cid) {
    final cur = _scores[cid];
    final anchors = _anchors.isEmpty
        ? [for (var i = 0; i < 4; i++) {'score': i, 'label': 'Level $i', 'descriptor': ''}]
        : _anchors;
    String desc = '';
    for (final a in anchors) {
      if (a['score'] == cur) desc = (a['descriptor'] ?? '').toString();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Your score', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
      const SizedBox(height: 8),
      Row(children: [
        for (final a in anchors)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _scoreTile(cid, (a['score'] as num).toInt(), (a['label'] ?? '').toString(), cur == a['score']),
            ),
          ),
      ]),
      if (desc.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(desc, style: const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5))),
      const SizedBox(height: 10),
      TextField(
        controller: _comments.putIfAbsent(cid, () => TextEditingController()),
        onChanged: (_) => _unsaved = true,
        maxLines: 2,
        minLines: 1,
        decoration: AppTheme.field(hintText: 'Comment (optional)', isDense: true),
      ),
    ]);
  }

  Widget _scoreTile(String cid, int score, String label, bool selected) {
    final color = AppTheme.scoreColor(score);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Score $score $label',
      child: Material(
        color: selected ? color : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _scores[cid] = score;
            _unsaved = true;
          }),
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? color : AppTheme.line, width: selected ? 2 : 1),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$score',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: selected ? Colors.white : color)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, color: selected ? Colors.white : AppTheme.inkSoft)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _profileCard() {
    final p = _profile;
    if (p == null) return const SizedBox.shrink();
    final rec = (p['recommendation'] as Map?) ?? {};
    final code = (rec['code'] ?? '').toString();
    final good = code == 'recommend_certification';
    final src = _source == 'assessor'
        ? 'from your scores'
        : _source == 'assessor_consensus'
            ? 'consensus of assessors'
            : 'AI-provisional, not yet scored by an assessor';
    return AppCard(
      color: good ? AppTheme.successSoft : AppTheme.warningSoft,
      border: good ? AppTheme.successSoft : AppTheme.warningSoft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NSQF competency profile • $src', style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
        const SizedBox(height: 4),
        Text('${p['overall_pct']}%  •  ${p['scored']}/${p['total']} scored', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text((rec['label'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        if (((p['nos'] ?? []) as List).length >= 3)
          RadarChart(
            height: 230,
            labels: [for (final n in (p['nos'] as List)) n['title'].toString()],
            values: [for (final n in (p['nos'] as List)) ((n['score_pct'] ?? 0) as num).toDouble() / 100],
          ),
        for (final n in ((p['nos'] ?? []) as List))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(n['passed'] == true ? Icons.check_circle : (n['critical_failure'] == true ? Icons.error : Icons.radio_button_unchecked),
                  size: 18, color: n['passed'] == true ? AppTheme.success : AppTheme.warning),
              const SizedBox(width: 8),
              Expanded(child: Text('${n['title']}', style: const TextStyle(fontSize: 13.5))),
              Text('${n['score_pct']}%', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        const SizedBox(height: 4),
        const Text('Decision support only. You make the final decision.', style: TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final scored = _scores.length;
    final totalCriteria = _criteria().length;
    return Scaffold(
      bottomNavigationBar: d == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(18), blurRadius: 10, offset: const Offset(0, -2))],
                ),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                      label: Text(_unsaved ? 'Save scores •' : 'Save scores'),
                      onPressed: _saving ? null : () => _save(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                      icon: const Icon(Icons.draw),
                      label: const Text('Sign off'),
                      onPressed: _saving ? null : _signOff,
                    ),
                  ),
                ]),
              ),
            ),
      body: Column(children: [
        HeroHeader(
          title: d == null ? 'Review' : (d['worker']?['name'] ?? 'Review').toString(),
          subtitle: d == null ? null : '$scored of $totalCriteria criteria scored',
          titleSize: 22,
          onBack: () => Navigator.of(context).pop(),
          actions: [
            IconButton(
              tooltip: 'PDF report',
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              onPressed: d == null ? null : _pdf,
            ),
          ],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          InfoBanner(_error!, icon: Icons.error_outline, color: AppTheme.danger, background: AppTheme.dangerSoft),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Retry')),
                        ]),
                      ),
                    )
                  : _content(d!),
        ),
      ]),
    );
  }

  Widget _content(Map<String, dynamic> d) {
    final a = d['assessment'] as Map;
    final w = (d['worker'] as Map?) ?? {};
    final cl = d['checklist'] as Map?;
    final resp = (d['responses'] as Map?) ?? {};
    final evAll = ((d['evidence'] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final others = (d['other_assessors'] as List?) ?? [];
    final signOffs = (d['sign_offs'] as List?) ?? [];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text((w['name'] ?? '').toString(), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            statusPill(context, a['status'].toString()),
          ]),
          Text([if ((w['phone'] ?? '').toString().isNotEmpty) w['phone'], if ((w['village'] ?? '').toString().isNotEmpty) w['village']].join(' • '),
              style: const TextStyle(color: AppTheme.inkSoft)),
          const SizedBox(height: 8),
          Text('Mapped to: ${cl?['title'] ?? 'not selected'}  (NSQF ${cl?['nsqf_level'] ?? '-'})', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (cl != null && cl['verified'] != true)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Demo qualification data: not an official NCVET pack.', style: TextStyle(fontSize: 12.5, color: AppTheme.warning)),
            ),
          const SizedBox(height: 8),
          Text('Self-declaration (${a['declared_years'] ?? '?'} yrs):', style: const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5)),
          Text((a['declaration_text'] ?? '').toString(), style: const TextStyle(height: 1.35)),
          if (others.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Also scored by: ${others.map((o) => '${o['assessor']} (${o['scored']})').join(', ')}', style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft)),
            ),
          if (signOffs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Sign-off: ${signOffs.map((s) => '${s['assessor']} → ${s['decision']}${s['overridden'] == true ? ' (override)' : ''}').join('; ')}',
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.success)),
            ),
        ]),
      ),
      InfoBanner('AI hints are advisory. You make every score and the final decision; overrides are logged.', icon: Icons.shield_outlined),
      const SizedBox(height: 6),
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: const Text('Blind mode (hide AI hints)', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Scores saved in blind mode are used to measure how much the aids improve agreement.', style: TextStyle(fontSize: 12.5)),
        value: _blind,
        onChanged: (v) => setState(() {
          _blind = v;
          _unsaved = true;
        }),
      ),
      _profileCard(),
      for (final n in ((cl?['nos'] ?? []) as List)) ...[
        SectionTitle('${n['title']}  •  ${((n['weight'] as num) * 100).round()}%'),
        for (final c in (n['criteria'] as List)) _criterionCard(Map<String, dynamic>.from(c as Map), resp[c['id']] as Map?, evAll),
      ],
    ]);
  }

  Widget _criterionCard(Map<String, dynamic> c, Map? resp, List<Map<String, dynamic>> evAll) {
    final cid = c['id'].toString();
    final evs = evAll.where((e) => e['criterion_id'] == cid).toList();
    final answer = (resp?['answer_text'] ?? '').toString();
    final rating = resp?['self_rating'];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(c['text'].toString(), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.3))),
          if (c['critical'] == true)
            const Pill('critical', color: AppTheme.danger, background: AppTheme.dangerSoft, icon: Icons.health_and_safety),
        ]),
        const SizedBox(height: 4),
        Text(c['task'].toString(), style: const TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(10)),
          child: Text(answer.isEmpty ? 'No written answer.' : answer,
              style: TextStyle(height: 1.35, color: answer.isEmpty ? AppTheme.inkSoft : AppTheme.ink)),
        ),
        if (rating != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Worker self-rating: $rating / 3', style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft))),
        const SizedBox(height: 10),
        _evidenceStrip(evs),
        if (!_blind) ...[
          const SizedBox(height: 10),
          _aiBox(resp, evs),
          if (((c['indicators'] ?? []) as List).isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Observable indicators (look-fors)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                children: [
                  for (final i in (c['indicators'] as List))
                    Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  $i', style: const TextStyle(fontSize: 13)))),
                ],
              ),
            ),
        ],
        const Divider(height: 22),
        _scorePicker(cid),
      ]),
    );
  }
}

class _SignOffDialog extends StatefulWidget {
  final String recommendation;
  final String label;
  const _SignOffDialog({required this.recommendation, required this.label});
  @override
  State<_SignOffDialog> createState() => _SignOffDialogState();
}

class _SignOffDialogState extends State<_SignOffDialog> {
  late String _decision;
  final _reason = TextEditingController();
  String? _err;

  static const Map<String, String> _labels = {
    'certify': 'Recommend certification',
    'partial': 'Partial – bridge training',
    'not_yet': 'Not yet competent',
    'more_evidence': 'Request more evidence',
  };

  @override
  void initState() {
    super.initState();
    _decision = widget.recommendation == 'recommend_certification'
        ? 'certify'
        : widget.recommendation == 'partial_gap_training'
            ? 'partial'
            : 'not_yet';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String get _expected => widget.recommendation == 'recommend_certification'
      ? 'certify'
      : widget.recommendation == 'partial_gap_training'
          ? 'partial'
          : 'not_yet';

  @override
  Widget build(BuildContext context) {
    final overriding = _decision != _expected && _decision != 'more_evidence';
    final needsReason = overriding || _decision == 'more_evidence';
    return AlertDialog(
      title: const Text('Assessor sign-off'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('System recommendation: ${widget.label}', style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final e in _labels.entries)
              ChoiceChip(label: Text(e.value), selected: _decision == e.key, onSelected: (_) => setState(() => _decision = e.key)),
          ]),
          const SizedBox(height: 12),
          if (overriding)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('You are overriding the system recommendation. This is logged.', style: TextStyle(color: AppTheme.warning, fontSize: 13)),
            ),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: AppTheme.field(labelText: needsReason ? 'Reasoning (required)' : 'Reasoning (optional)', errorText: _err),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
          onPressed: () {
            if (needsReason && _reason.text.trim().length < 10) {
              setState(() => _err = 'Write at least 10 characters');
              return;
            }
            Navigator.pop(context, {'decision': _decision, 'reasoning': _reason.text.trim()});
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
