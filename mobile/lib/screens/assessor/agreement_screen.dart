import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';

/// Inter-assessor agreement: assisted (rubric + AI hints) vs unassisted (blind) scoring.
class AgreementScreen extends StatefulWidget {
  const AgreementScreen({super.key});
  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await app.api.agreement(app.assessorToken ?? '');
      if (mounted) setState(() => _d = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _f(dynamic v) => v == null ? '–' : v.toString();

  Widget _block(String title, IconData icon, Map? m) {
    final s = m ?? {};
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 18, runSpacing: 10, children: [
          _stat('Score pairs', _f(s['n_pairs'])),
          _stat('Weighted κ', _f(s['weighted_kappa'])),
          _stat('ICC', _f(s['icc'])),
          _stat('Exact', s['exact_agreement_pct'] == null ? '–' : '${s['exact_agreement_pct']}%'),
          _stat('Within ±1', s['within_one_pct'] == null ? '–' : '${s['within_one_pct']}%'),
          _stat('Mean |diff|', _f(s['mean_abs_diff'])),
        ]),
      ]),
    );
  }

  Widget _stat(String k, String v) => SizedBox(
        width: 96,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primaryDark)),
          Text(k, style: const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: const Text('Scoring consistency')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: InfoBanner(_error!, icon: Icons.error_outline, color: AppTheme.danger, background: AppTheme.dangerSoft)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    InfoBanner('Agreement between two assessors scoring the same worker. κ (kappa) of 0.61–0.80 is "substantial", above 0.80 "almost perfect". '
                        'Compare scoring WITH the rubric aids against blind scoring to measure improvement.'),
                    const SizedBox(height: 8),
                    _block('Assisted (rubric + AI hints shown)', Icons.auto_awesome, d?['assisted'] as Map?),
                    _block('Unassisted (blind)', Icons.visibility_off, d?['unassisted'] as Map?),
                    AppCard(
                      color: AppTheme.successSoft,
                      border: AppTheme.successSoft,
                      child: Row(children: [
                        const Icon(Icons.trending_up, color: AppTheme.success),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              d?['kappa_improvement'] == null
                                  ? 'Kappa improvement: needs double-scored items in both modes'
                                  : 'Kappa improvement from assistance: ${d!['kappa_improvement']}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                    _block('AI hint vs assessor score', Icons.smart_toy, d?['ai_vs_assessor'] as Map?),
                    for (final c in ((d?['caveats'] as List?) ?? []))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: InfoBanner(c.toString(), icon: Icons.warning_amber, color: AppTheme.warning, background: AppTheme.warningSoft),
                      ),
                    const SizedBox(height: 20),
                  ]),
                ),
    );
  }
}
