import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../widgets/common.dart';

class IntakeScreen extends ConsumerStatefulWidget {
  const IntakeScreen({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();

  int _step = 0;
  bool _saving = false;

  late final TextEditingController _name;
  late final TextEditingController _years;
  late final TextEditingController _region;
  late final TextEditingController _tradeContext;
  late final TextEditingController _freeText;
  late final TextEditingController _learningSource;

  late final List<TextEditingController> _dailyTasks;
  late final List<TextEditingController> _toolsUsed;
  late final List<TextEditingController> _safetyPractices;

  LanguageCode _language = LanguageCode.en;
  String? _selectedTrade;
  bool _priorTraining = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _years = TextEditingController();
    _region = TextEditingController();
    _tradeContext = TextEditingController();
    _freeText = TextEditingController();
    _learningSource = TextEditingController();
    _dailyTasks = [TextEditingController()];
    _toolsUsed = [TextEditingController()];
    _safetyPractices = [TextEditingController()];
  }

  @override
  void dispose() {
    _name.dispose();
    _years.dispose();
    _region.dispose();
    _tradeContext.dispose();
    _freeText.dispose();
    _learningSource.dispose();
    for (final c in _dailyTasks) {
      c.dispose();
    }
    for (final c in _toolsUsed) {
      c.dispose();
    }
    for (final c in _safetyPractices) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _clean(List<TextEditingController> controllers) => controllers
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList(growable: false);

  void _addRow(List<TextEditingController> list) {
    setState(() => list.add(TextEditingController()));
  }

  void _removeRow(List<TextEditingController> list, int index) {
    setState(() {
      final removed = list.removeAt(index);
      removed.dispose();
      if (list.isEmpty) list.add(TextEditingController());
    });
  }

  void _fail(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateStep1() {
    final ok = _step1Key.currentState?.validate() ?? false;
    if (!ok) {
      _fail('Please fix the highlighted fields before continuing.');
      return false;
    }
    if (_selectedTrade == null || _selectedTrade!.isEmpty) {
      _fail('Please select a primary trade.');
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    final step1Ok = _step1Key.currentState?.validate() ?? false;
    final step2Ok = _step2Key.currentState?.validate() ?? false;
    if (!step1Ok || !step2Ok) {
      _fail('Please fix the highlighted fields before submitting.');
      if (!step1Ok) setState(() => _step = 0);
      return;
    }
    if (_selectedTrade == null || _selectedTrade!.isEmpty) {
      setState(() => _step = 0);
      _fail('Please select a primary trade.');
      return;
    }
    final years = double.tryParse(_years.text.trim());
    if (years == null || years < 0) {
      setState(() => _step = 0);
      _fail('Years of experience must be a valid non-negative number.');
      return;
    }

    setState(() => _saving = true);
    try {
      final workerId = const Uuid().v4();
      final worker = Worker(
        id: workerId,
        name: _name.text.trim(),
        preferredLanguage: _language,
        primaryTrade: _selectedTrade!,
        yearsOfExperience: years,
        locationRegion: _region.text.trim(),
        priorFormalTraining: _priorTraining,
        createdAt: DateTime.now(),
      );
      final exp = ExperienceDeclaration(
        id: const Uuid().v4(),
        workerId: workerId,
        tradeContext: _tradeContext.text.trim(),
        dailyTasks: _clean(_dailyTasks),
        toolsUsed: _clean(_toolsUsed),
        safetyPractices: _clean(_safetyPractices),
        freeTextDescription: _freeText.text,
        informalLearningSource: _learningSource.text.trim(),
        createdAt: DateTime.now(),
      );
      final repo = await ref.read(repositoryProvider.future);
      await repo.createWorker(worker);
      await repo.saveExperience(exp);
      ref.invalidate(workersProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _fail('Could not save worker: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New worker', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            Text('Onboarding & experience declaration',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DisclaimerBanner(),
            const SizedBox(height: 12),
            _StepHeader(step: _step),
            const SizedBox(height: 12),
            if (_step == 0) _buildStep1() else _buildStep2(),
            const SizedBox(height: 16),
            _buildNavBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    final trades = ref.watch(tradesProvider);
    return Form(
      key: _step1Key,
      child: Column(
        children: [
          SectionCard(
            title: 'Worker profile',
            subtitle: 'Step 1 of 2 — basic details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name *',
                    hintText: 'e.g. Ramesh Kumar',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 2) {
                      return 'Enter a name with at least 2 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Text('Preferred language',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<LanguageCode>(
                  segments: const [
                    ButtonSegment(value: LanguageCode.en, label: Text('English')),
                    ButtonSegment(value: LanguageCode.hi, label: Text('हिन्दी')),
                    ButtonSegment(value: LanguageCode.mr, label: Text('मराठी')),
                  ],
                  selected: {_language},
                  onSelectionChanged: (s) => setState(() => _language = s.first),
                ),
                const SizedBox(height: 12),
                trades.when(
                  loading: () => const LinearProgressIndicator(color: AppColors.forest),
                  error: (e, _) => Text('Could not load trades: $e',
                      style: const TextStyle(color: AppColors.danger)),
                  data: (list) => DropdownButtonFormField<String>(
                    initialValue: _selectedTrade,
                    decoration: const InputDecoration(labelText: 'Primary trade *'),
                    items: [
                      for (final t in list)
                        DropdownMenuItem(value: t.name, child: Text(t.name)),
                    ],
                    onChanged: (v) => setState(() => _selectedTrade = v),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Select a primary trade.' : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _years,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true, signed: false),
                  decoration: const InputDecoration(
                    labelText: 'Years of experience *',
                    hintText: 'e.g. 2.5',
                  ),
                  validator: (v) {
                    final parsed = double.tryParse((v ?? '').trim());
                    if (parsed == null || parsed < 0) {
                      return 'Enter a valid non-negative number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _region,
                  decoration: const InputDecoration(
                    labelText: 'Location region',
                    hintText: 'Village / town / district',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Prior formal training',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Has the worker completed any formal course?',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  value: _priorTraining,
                  activeThumbColor: AppColors.forest,
                  onChanged: (v) => setState(() => _priorTraining = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Form(
      key: _step2Key,
      child: Column(
        children: [
          SectionCard(
            title: 'Prior experience declaration',
            subtitle: 'Step 2 of 2 — self-declared informal experience',
            child: Column(
              children: [
                TextFormField(
                  controller: _tradeContext,
                  decoration: const InputDecoration(
                    labelText: 'Trade context',
                    hintText: 'Where and with whom this work was done',
                  ),
                ),
                const SizedBox(height: 16),
                _DynamicList(
                  label: 'Daily tasks',
                  controllers: _dailyTasks,
                  hint: 'e.g. Brick laying',
                  onAdd: () => _addRow(_dailyTasks),
                  onRemove: (i) => _removeRow(_dailyTasks, i),
                ),
                const SizedBox(height: 16),
                _DynamicList(
                  label: 'Tools used',
                  controllers: _toolsUsed,
                  hint: 'e.g. Trowel',
                  onAdd: () => _addRow(_toolsUsed),
                  onRemove: (i) => _removeRow(_toolsUsed, i),
                ),
                const SizedBox(height: 16),
                _DynamicList(
                  label: 'Safety practices',
                  controllers: _safetyPractices,
                  hint: 'e.g. Wear helmet on site',
                  onAdd: () => _addRow(_safetyPractices),
                  onRemove: (i) => _removeRow(_safetyPractices, i),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _freeText,
                  maxLines: 5,
                  minLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Describe your work (any language)',
                    hintText: 'अपने काम के बारे में लिखें…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _learningSource,
                  decoration: const InputDecoration(
                    labelText: 'How did you learn this work?',
                    hintText: 'e.g. Learned from father on site',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    return Row(
      children: [
        if (_step == 1)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saving ? null : () => setState(() => _step = 0),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ),
        if (_step == 1) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _saving
                ? null
                : () {
                    if (_step == 0) {
                      if (_validateStep1()) setState(() => _step = 1);
                    } else {
                      _submit();
                    }
                  },
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(_step == 0 ? Icons.arrow_forward : Icons.check),
            label: Text(_step == 0
                ? 'Continue'
                : (_saving ? 'Saving…' : 'Save worker')),
          ),
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int step;
  const _StepHeader({required this.step});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dot(0, 'Profile', step),
        Expanded(
          child: Container(height: 2, color: AppColors.line, margin: const EdgeInsets.symmetric(horizontal: 8)),
        ),
        _dot(1, 'Experience', step),
      ],
    );
  }

  Widget _dot(int index, String label, int current) {
    final active = index <= current;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: active ? AppColors.forest : AppColors.line,
          foregroundColor: active ? Colors.white : AppColors.muted,
          child: Text('${index + 1}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.ink : AppColors.muted,
            )),
      ],
    );
  }
}

class _DynamicList extends StatelessWidget {
  final String label;
  final List<TextEditingController> controllers;
  final String hint;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  const _DynamicList({
    required this.label,
    required this.controllers,
    required this.hint,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controllers[i],
                    decoration: InputDecoration(hintText: hint),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: controllers.length <= 1 && controllers[i].text.isEmpty
                      ? null
                      : () => onRemove(i),
                  icon: const Icon(Icons.remove_circle_outline),
                  color: AppColors.danger,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
