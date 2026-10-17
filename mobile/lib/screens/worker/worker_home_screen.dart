import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/design.dart';
import '../../widgets/ui.dart';
import 'worker_assessments_screen.dart';

class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({super.key});
  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen> {
  List<Worker> _workers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await context.read<LocalDb>().workers();
    if (!mounted) return;
    setState(() {
      _workers = list;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final w = await Navigator.of(context).push<Worker>(MaterialPageRoute(builder: (_) => const RegisterWorkerScreen()));
    if (w != null) {
      await _load();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => WorkerAssessmentsScreen(worker: w)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: Text(tr(context, 'register_worker')),
        onPressed: _add,
      ),
      body: Column(children: [
        HeroHeader(
          title: tr(context, 'my_workers'),
          subtitle: tr(context, 'home_sub'),
          onBack: () => Navigator.of(context).pop(),
          actions: const [Padding(padding: EdgeInsets.only(right: 8), child: ConnectionChip())],
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _workers.isEmpty
                  ? EmptyState(Icons.groups_2_outlined, tr(context, 'no_workers'), image: 'illus_empty_workers')
                  : RefreshIndicator(
                      onRefresh: () async {
                        await context.read<SyncService>().syncAll();
                        await _load();
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                        itemCount: _workers.length,
                        itemBuilder: (ctx, i) {
                          final w = _workers[i];
                          return AppCard(
                            onTap: () async {
                              await Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => WorkerAssessmentsScreen(worker: w)));
                              _load();
                            },
                            child: Row(children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppTheme.primarySoft,
                                child: Text(w.name.isEmpty ? '?' : w.name.substring(0, 1).toUpperCase(),
                                    style: const TextStyle(
                                        color: AppTheme.primary, fontWeight: FontWeight.w800, fontSize: 20)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(w.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                      [if (w.phone.isNotEmpty) w.phone, if (w.village.isNotEmpty) w.village]
                                          .join(' • '),
                                      style: const TextStyle(color: AppTheme.inkSoft)),
                                ]),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'delete') {
                                    final ok = await confirm(
                                        context, '${tr(context, 'delete')} ${w.name}?', yes: tr(context, 'delete'));
                                    if (ok) {
                                      await context.read<LocalDb>().deleteWorker(w.id);
                                      _load();
                                    }
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem<String>(value: 'delete', child: Text(tr(context, 'delete'))),
                                ],
                              ),
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

class RegisterWorkerScreen extends StatefulWidget {
  const RegisterWorkerScreen({super.key});
  @override
  State<RegisterWorkerScreen> createState() => _RegisterWorkerScreenState();
}

class _RegisterWorkerScreenState extends State<RegisterWorkerScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _village = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _village.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final w = Worker(
      id: const Uuid().v4(),
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      village: _village.text.trim(),
      language: context.read<AppState>().lang,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await context.read<LocalDb>().saveWorker(w);
    if (!mounted) return;
    Navigator.of(context).pop(w);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'register_worker'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: AppTheme.field(labelText: tr(context, 'full_name'), prefixIcon: const Icon(Icons.person)),
            validator: (v) => (v == null || v.trim().isEmpty) ? tr(context, 'name_required') : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: AppTheme.field(labelText: tr(context, 'phone'), prefixIcon: const Icon(Icons.phone)),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _village,
            decoration: AppTheme.field(labelText: tr(context, 'village'), prefixIcon: const Icon(Icons.location_on)),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(tr(context, 'continue'))),
        ]),
      ),
    );
  }
}
