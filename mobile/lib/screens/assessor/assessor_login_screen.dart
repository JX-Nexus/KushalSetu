import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/design.dart';
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
      body: Column(children: [
        HeroHeader(
          title: 'Assessor sign-in',
          subtitle: 'Review evidence, score on the standard rubric and sign off.',
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(22), children: [
            const FadeSlideIn(child: Center(child: Illustration('illus_assessor', height: 150, fallback: Icons.fact_check))),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                TextField(
                  controller: _user,
                  autocorrect: false,
                  decoration: AppTheme.field(labelText: 'Username', prefixIcon: const Icon(Icons.person)),
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
                      tooltip: _hide ? 'Show password' : 'Hide password',
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  InfoBanner(_error!, icon: Icons.error_outline, color: AppTheme.danger, background: AppTheme.dangerSoft),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _login,
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('Sign in'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Server settings'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
            const SizedBox(height: 6),
            const InfoBanner('The AI only suggests. You make every score and the final decision.', icon: Icons.shield_outlined),
          ]),
        ),
      ]),
    );
  }
}
