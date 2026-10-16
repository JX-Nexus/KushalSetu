import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Shows the signed-off result. Only exists after a human assessor has signed off.
class ResultScreen extends StatefulWidget {
  final Worker worker;
  final String assessmentId;
  const ResultScreen({super.key, required this.worker, required this.assessmentId});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  String? _token;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<AppState>().api;
    try {
      _token = await api.authWorker(widget.worker);
      final d = await api.assessmentDetail(_token!, widget.assessmentId);
      if (!mounted) return;
      setState(() => _data = d);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pdf() async {
    final api = context.read<AppState>().api;
    try {
      final path = await api.download('/api/assessments/${widget.assessmentId}/report.pdf', _token!,
          'rpl_report_${widget.assessmentId.substring(0, 8)}.pdf');
      await OpenFilex.open(path);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = curLang(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'result_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      InfoBanner(_error!, icon: Icons.cloud_off, color: AppTheme.warning, background: AppTheme.warningSoft),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _load, child: Text(tr(context, 'retry'))),
                    ]),
                  ),
                )
              : _body(lang),
    );
  }

  Widget _body(String lang) {
    final d = _data!;
    final result = d['result'] as Map?;
    final profile = d['profile'] as Map?;
    if (result == null || profile == null) {
      return EmptyState(Icons.hourglass_top, tr(context, 'status_submitted'));
    }
    final decision = result['decision'].toString();
    final key = decision == 'certify' ? 'decision_certify' : decision == 'partial' ? 'decision_partial' : 'decision_not_yet';
    final good = decision == 'certify';
    final nos = (profile['nos'] as List?) ?? [];
    final gaps = (profile['gaps'] as List?) ?? [];
    return ListView(padding: const EdgeInsets.all(18), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: good ? AppTheme.successSoft : AppTheme.warningSoft,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: [
          Icon(good ? Icons.verified : Icons.trending_up, size: 52, color: good ? AppTheme.success : AppTheme.warning),
          const SizedBox(height: 10),
          Text(tr(context, key),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: good ? AppTheme.success : AppTheme.warning)),
          const SizedBox(height: 6),
          Text('${profile['overall_pct']}%', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          Text('${profile['qp_title']} • NSQF ${profile['nsqf_level']}', textAlign: TextAlign.center),
        ]),
      ),
      const SizedBox(height: 10),
      InfoBanner(tr(context, 'disclaimer'), icon: Icons.shield_outlined),
      for (final n in nos)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(n['title'].toString(), style: const TextStyle(fontWeight: FontWeight.w700))),
              Icon((n['passed'] == true) ? Icons.check_circle : Icons.info, color: (n['passed'] == true) ? AppTheme.success : AppTheme.warning),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ((n['score_pct'] as num).toDouble() / 100).clamp(0.0, 1.0),
                minHeight: 9,
                backgroundColor: AppTheme.primarySoft,
                color: (n['passed'] == true) ? AppTheme.success : AppTheme.warning,
              ),
            ),
            const SizedBox(height: 4),
            Text('${n['score_pct']}%', style: const TextStyle(color: AppTheme.inkSoft)),
          ]),
        ),
      if (gaps.isNotEmpty) ...[
        const SectionTitle('Areas to improve'),
        for (final g in gaps) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('•  $g')),
      ],
      const SizedBox(height: 18),
      FilledButton.icon(icon: const Icon(Icons.picture_as_pdf), label: Text(tr(context, 'download_report')), onPressed: _pdf),
      const SizedBox(height: 24),
    ]);
  }
}
