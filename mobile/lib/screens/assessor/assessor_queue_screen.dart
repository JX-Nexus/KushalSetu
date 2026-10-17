import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/design.dart';
import '../../widgets/ui.dart';
import 'agreement_screen.dart';
import 'assessor_login_screen.dart';
import 'assessor_review_screen.dart';

class AssessorQueueScreen extends StatefulWidget {
  const AssessorQueueScreen({super.key});
  @override
  State<AssessorQueueScreen> createState() => _AssessorQueueScreenState();
}

class _AssessorQueueScreenState extends State<AssessorQueueScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  static const Map<String, String> _filters = {
    'all': 'All',
    'submitted': 'Waiting',
    'under_review': 'Reviewing',
    'needs_evidence': 'Needs evidence',
    'signed_off': 'Signed off',
  };

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
      final list = await app.api.queue(app.assessorToken ?? '');
      if (!mounted) return;
      app.setReachable(true);
      setState(() => _items = list.map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } on ApiException catch (e) {
      if (e.status == 401) {
        await app.assessorLogout();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AssessorLoginScreen()));
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _count(String st) => _items.where((i) => i['status'] == st).length;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shown = _filter == 'all' ? _items : _items.where((i) => i['status'] == _filter).toList();
    return Scaffold(
      body: Column(children: [
        HeroHeader(
          title: 'Review queue',
          subtitle: app.assessorName.isEmpty ? null : 'Signed in as ${app.assessorName}',
          onBack: () => Navigator.of(context).pop(),
          actions: [
            IconButton(
              tooltip: 'Agreement statistics',
              icon: const Icon(Icons.insights, color: Colors.white),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AgreementScreen())),
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () async {
                await app.assessorLogout();
                if (!mounted) return;
                Navigator.of(context).pop();
              },
            ),
          ],
          child: Row(children: [
            Expanded(child: StatTile(value: '${_count('submitted')}', caption: 'Waiting', color: AppTheme.warning)),
            const SizedBox(width: 8),
            Expanded(child: StatTile(value: '${_count('under_review')}', caption: 'Reviewing', color: AppTheme.info)),
            const SizedBox(width: 8),
            Expanded(child: StatTile(value: '${_count('signed_off')}', caption: 'Signed off', color: AppTheme.success)),
          ]),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final e in _filters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _filter == e.key,
                    onSelected: (_) => setState(() => _filter = e.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Illustration('illus_offline', height: 140, fallback: Icons.cloud_off),
                          const SizedBox(height: 10),
                          InfoBanner(_error!, icon: Icons.cloud_off, color: AppTheme.warning, background: AppTheme.warningSoft),
                          const SizedBox(height: 14),
                          FilledButton(onPressed: _load, child: const Text('Retry')),
                        ]),
                      ),
                    )
                  : shown.isEmpty
                      ? const EmptyState(Icons.inbox_outlined, 'Nothing here yet. Submitted assessments appear after workers sync.', image: 'illus_queue_empty')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: shown.length,
                            itemBuilder: (ctx, i) {
                              final it = shown[i];
                              final total = (it['total_criteria'] ?? 0) as int;
                              final name = it['worker_name'].toString();
                              return AppCard(
                                onTap: () async {
                                  await Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => AssessorReviewScreen(assessmentId: it['id'].toString())));
                                  _load();
                                },
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: AppTheme.primarySoft,
                                      child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                                          style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w800)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                        Text((it['qp_title'] ?? 'No pack selected').toString(),
                                            style: const TextStyle(color: AppTheme.inkSoft, fontSize: 13)),
                                      ]),
                                    ),
                                    statusPill(context, it['status'].toString()),
                                  ]),
                                  const SizedBox(height: 10),
                                  Wrap(spacing: 8, runSpacing: 4, children: [
                                    Pill('${it['answered']}/$total answered',
                                        color: AppTheme.primary, background: AppTheme.primarySoft, icon: Icons.edit_note),
                                    Pill('${it['evidence_count']} evidence',
                                        color: AppTheme.inkSoft, background: const Color(0xFFEDEAE2), icon: Icons.photo_library),
                                    Pill('you scored ${it['scored_by_me']}/$total',
                                        color: AppTheme.accent, background: AppTheme.accentSoft, icon: Icons.rule),
                                  ]),
                                ]),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
