import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui.dart';
import '../settings_screen.dart';
import 'assessor_queue_screen.dart';

class AssessorLoginScreen extends StatefulWidget {
  const AssessorLoginScreen({super.key});
  @override
  State<AssessorLoginScreen> createState() => _AssessorLoginScreenState();
}

class _AssessorLoginScreenState extends State<AssessorLoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Enter username and password');
      return;
    }
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.assessorLogin(_user.text.trim(), _pass.text);
      app.setReachable(true);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AssessorQueueScreen()));
    } on ApiException catch (e) {
      setState(() => _error = e.isNetwork ? '${e.message}. Assessor sign-in needs a connection to the server.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assessor sign-in')),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        const SizedBox(height: 12),
        const Icon(Icons.fact_check, size: 56, color: AppTheme.primary),
        const SizedBox(height: 16),
        const Text('Review evidence, score on the standard rubric and sign off.',
            textAlign: TextAlign.center, style: TextStyle(color: AppTheme.inkSoft, fontSize: 15)),
        const SizedBox(height: 24),
        TextField(
          controller: _user,
          autocorrect: false,
          decoration: AppTheme.field(labelText: 'Username', prefixIcon: Icon(Icons.person)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pass,
          obscureText: _hide,
          onSubmitted: (_) => _login(),
          decoration: AppTheme.field(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          InfoBanner(_error!, icon: Icons.error_outline, color: AppTheme.danger, background: AppTheme.dangerSoft),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : const Text('Sign in'),
        ),
        TextButton.icon(
          icon: const Icon(Icons.settings),
          label: const Text('Server settings'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      ]),
    );
  }
}
