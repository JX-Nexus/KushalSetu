import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/catalogue_service.dart';
import '../services/sync_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  bool _busy = false;
  Map<String, dynamic>? _ai;
  String? _msg;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<AppState>().serverUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final app = context.read<AppState>();
    final cat = context.read<CatalogueService>();
    final sync = context.read<SyncService>();
    setState(() {
      _busy = true;
      _msg = null;
      _ai = null;
    });
    await app.setServer(_url.text);
    try {
      final h = await app.api.health();
      app.setReachable(true);
      Map<String, dynamic>? ai;
      try {
        ai = await app.api.aiStatus();
      } catch (_) {}
      final updated = await cat.refresh(app.api);
      setState(() {
        _ok = true;
        _ai = ai;
        _msg = 'Connected. ${h['packs']} qualification packs, ${h['criteria']} criteria'
            '${updated ? ' (catalogue updated on this phone)' : ''}.';
      });
      sync.syncAll(silent: true);
    } catch (e) {
      app.setReachable(false);
      setState(() {
        _ok = false;
        _msg = e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final llm = _ai?['llm'] as Map?;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'settings'))),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Text(tr(context, 'server_url'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: AppTheme.field(hintText: 'http://10.0.2.2:8000'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Emulator: http://10.0.2.2:8000   •   Real phone: http://<your-PC-IP>:8000 (same Wi-Fi)',
          style: TextStyle(color: AppTheme.inkSoft, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.wifi_tethering),
          label: Text(tr(context, 'test_connection')),
          onPressed: _busy ? null : _test,
        ),
        if (_msg != null) ...[
          const SizedBox(height: 14),
          InfoBanner(_msg!,
              icon: _ok ? Icons.check_circle : Icons.error_outline,
              color: _ok ? AppTheme.success : AppTheme.danger,
              background: _ok ? AppTheme.successSoft : AppTheme.dangerSoft),
        ],
        if (_ai != null) ...[
          const SectionTitle('AI engines on the server'),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mapping: ${_ai!['mapping_engine']?['name']} '
                  '(${_ai!['mapping_engine']?['packs_indexed']} packs, '
                  '${_ai!['mapping_engine']?['example_declarations']} example declarations)'),
              const SizedBox(height: 6),
              Text('Scoring hints: ${_ai!['scoring_engine']?['name']}'),
              const SizedBox(height: 6),
              Text(llm != null && llm['available'] == true
                  ? 'LLM: ${llm['provider']} / ${llm['model']} (advisory only)'
                  : 'LLM: not configured (rule-based engines only)'),
              const SizedBox(height: 8),
              Text(_ai!['note']?.toString() ?? '', style: const TextStyle(color: AppTheme.inkSoft, fontSize: 12.5)),
            ]),
          ),
        ],
        const SectionTitle('Catalogue on this phone'),
        Consumer<CatalogueService>(
          builder: (_, c, __) => AppCard(
            child: Text('${c.packs.length} qualification packs • version ${c.version.isEmpty ? 'bundled' : c.version}'),
          ),
        ),
      ]),
    );
  }
}
