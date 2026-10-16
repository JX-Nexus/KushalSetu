import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'assessor/assessor_login_screen.dart';
import 'assessor/assessor_queue_screen.dart';
import 'settings_screen.dart';
import 'worker/worker_home_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().checkServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 18, 24, 30),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.primaryDark, AppTheme.primary]),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const ConnectionChip(),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.handyman, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            Text(tr(context, 'app_name'),
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(tr(context, 'tagline'),
                style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 15, height: 1.35)),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(tr(context, 'language'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.inkSoft)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'en', label: Text('English')),
                ButtonSegment<String>(value: 'hi', label: Text('हिन्दी')),
                ButtonSegment<String>(value: 'mr', label: Text('मराठी')),
              ],
              selected: {app.lang},
              onSelectionChanged: (s) => app.setLang(s.first),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              icon: const Icon(Icons.person),
              label: Text(tr(context, 'i_am_worker')),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const WorkerHomeScreen())),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.fact_check),
              label: Text(tr(context, 'i_am_assessor')),
              onPressed: () {
                final next = app.assessorToken == null
                    ? const AssessorLoginScreen()
                    : const AssessorQueueScreen();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => next));
              },
            ),
            const SizedBox(height: 24),
            InfoBanner(tr(context, 'disclaimer'), icon: Icons.shield_outlined),
          ]),
        ),
      ]),
    );
  }
}
