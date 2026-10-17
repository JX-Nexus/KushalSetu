import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../services/catalogue_service.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/design.dart';
import '../../widgets/ui.dart';

class TaskScreen extends StatefulWidget {
  final Worker worker;
  final Assessment assessment;
  final Criterion criterion;
  final bool readOnly;
  const TaskScreen({
    super.key,
    required this.worker,
    required this.assessment,
    required this.criterion,
    required this.readOnly,
  });
  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final _answer = TextEditingController();
  late final LocalDb _db;
  int? _rating;
  List<EvidenceRow> _evidence = [];
  Timer? _debounce;
  bool _loaded = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _db = context.read<LocalDb>();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_loaded && !widget.readOnly) {
      _persist(); // fire-and-forget: leaving the screen never loses typed text
    }
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = context.read<LocalDb>();
    final rs = await db.responses(widget.assessment.id);
    for (final r in rs) {
      if (r.criterionId == widget.criterion.id) {
        _answer.text = r.answerText;
        _rating = r.selfRating;
      }
    }
    final ev = await db.evidence(widget.assessment.id);
    if (!mounted) return;
    setState(() {
      _evidence = ev.where((e) => e.criterionId == widget.criterion.id).toList();
      _loaded = true;
    });
  }

  Future<void> _persist() async {
    final db = _db;
    final text = _answer.text.trim();
    if (text.isEmpty && _rating == null) return;
    await db.saveResponse(ResponseRow(
      id: const Uuid().v4(),
      assessmentId: widget.assessment.id,
      criterionId: widget.criterion.id,
      answerText: text,
      selfRating: _rating,
      answeredAt: DateTime.now().toUtc().toIso8601String(),
    ));
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _persist);
  }

  Future<void> _addEvidence(ImageSource source, String kind) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picker = ImagePicker();
      XFile? x;
      if (kind == 'video') {
        x = await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60));
      } else {
        x = await picker.pickImage(source: source, imageQuality: 75, maxWidth: 1600);
      }
      if (x == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final evDir = Directory(p.join(dir.path, 'evidence'));
      if (!await evDir.exists()) await evDir.create(recursive: true);
      var ext = p.extension(x.path).toLowerCase();
      if (ext.isEmpty) ext = kind == 'video' ? '.mp4' : '.jpg';
      final id = const Uuid().v4();
      final dest = p.join(evDir.path, '$id$ext');
      await File(x.path).copy(dest);
      final row = EvidenceRow(
        id: id,
        assessmentId: widget.assessment.id,
        criterionId: widget.criterion.id,
        kind: kind,
        localPath: dest,
        capturedAt: DateTime.now().toUtc().toIso8601String(),
        uploaded: false,
      );
      await context.read<LocalDb>().saveEvidence(row);
      await _persist();
      if (!mounted) return;
      setState(() => _evidence = [..._evidence, row]);
      context.read<SyncService>().syncAll(silent: true);
    } catch (e) {
      if (mounted) toast(context, 'Could not use the camera/gallery: $e', error: true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _remove(EvidenceRow e) async {
    if (e.uploaded) {
      toast(context, 'Already sent to the assessor', error: true);
      return;
    }
    await context.read<LocalDb>().deleteEvidence(e.id);
    try {
      await File(e.localPath).delete();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _evidence = _evidence.where((x) => x.id != e.id).toList());
  }

  Future<void> _save({Criterion? next}) async {
    await _persist();
    if (!mounted) return;
    context.read<SyncService>().syncAll(silent: true);
    toast(context, tr(context, 'saved'));
    if (next != null) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => TaskScreen(
              worker: widget.worker, assessment: widget.assessment, criterion: next, readOnly: widget.readOnly)));
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _evidenceTile(EvidenceRow e) {
    return Stack(children: [
      Container(
        width: 96,
        height: 96,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
            color: AppTheme.primarySoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.line)),
        clipBehavior: Clip.antiAlias,
        child: e.kind == 'photo'
            ? Image.file(File(e.localPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))
            : const Icon(Icons.videocam, size: 36, color: AppTheme.primary),
      ),
      Positioned(
        right: 12,
        top: 2,
        child: Icon(e.uploaded ? Icons.cloud_done : Icons.cloud_upload_outlined,
            size: 18, color: e.uploaded ? AppTheme.success : AppTheme.warning),
      ),
      if (!widget.readOnly && !e.uploaded)
        Positioned(
          right: 4,
          bottom: 0,
          child: GestureDetector(
            onTap: () => _remove(e),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: AppTheme.danger),
            ),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final lang = curLang(context);
    final c = widget.criterion;
    final pack = context.read<CatalogueService>().byCode(widget.assessment.qpCode);
    final all = pack?.allCriteria ?? <Criterion>[c];
    var idx = all.indexWhere((x) => x.id == c.id);
    if (idx < 0) idx = 0;
    final Criterion? next = idx + 1 < all.length ? all[idx + 1] : null;
    final ratingKeys = [0, 1, 2, 3];
    return Scaffold(
      body: Column(children: [
        HeroHeader(
          title: c.text.get(lang),
          titleSize: 19,
          subtitle: trf(context, 'task_n_of', {'n': '${idx + 1}', 'm': '${all.length}'}),
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
                  StepProgressBar(
                    current: idx + 1,
                    total: all.length,
                    label: trf(context, 'task_n_of', {'n': '${idx + 1}', 'm': '${all.length}'}),
                  ),
                  const SizedBox(height: 12),
                  if (widget.readOnly)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InfoBanner(tr(context, 'read_only'), icon: Icons.lock_outline),
                    ),
                  if (c.critical)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InfoBanner(tr(context, 'safety_first'),
                          icon: Icons.health_and_safety, color: AppTheme.danger, background: AppTheme.dangerSoft),
                    ),
                  AppCard(
                    color: AppTheme.primarySoft,
                    border: AppTheme.primarySoft,
                    padding: const EdgeInsets.all(16),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.help_outline, color: AppTheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(c.task.get(lang), style: const TextStyle(fontSize: 16.5, height: 1.45, color: AppTheme.primaryDark))),
                    ]),
                  ),
                  SectionTitle(tr(context, 'your_answer')),
                  TextField(
                    controller: _answer,
                    readOnly: widget.readOnly,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 4000,
                    onChanged: (_) => _changed(),
                    decoration: AppTheme.field(hintText: tr(context, 'answer_hint')),
                  ),
                  SectionTitle(tr(context, 'self_rating')),
                  for (final i in ratingKeys)
                    OptionTile(
                      label: tr(context, 'rating_$i'),
                      selected: _rating == i,
                      onTap: widget.readOnly
                          ? null
                          : () {
                              setState(() => _rating = i);
                              _changed();
                            },
                    ),
                  SectionTitle(tr(context, 'evidence')),
                  if (c.evidence != 'none')
                    InfoBanner(tr(context, c.evidence == 'video' ? 'evidence_wanted_video' : 'evidence_wanted_photo'),
                        icon: c.evidence == 'video' ? Icons.videocam : Icons.photo_camera,
                        color: AppTheme.warning,
                        background: AppTheme.warningSoft),
                  if (_evidence.isEmpty && !widget.readOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Center(child: Illustration('illus_step2', height: 120, fallback: Icons.photo_camera)),
                    ),
                  const SizedBox(height: 10),
                  if (_evidence.isNotEmpty)
                    SizedBox(
                        height: 100,
                        child: ListView(scrollDirection: Axis.horizontal, children: [for (final e in _evidence) _evidenceTile(e)])),
                  if (!widget.readOnly) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: ActionTile(
                          icon: Icons.photo_camera,
                          label: tr(context, 'add_photo'),
                          onTap: _picking ? null : () => _addEvidence(ImageSource.camera, 'photo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ActionTile(
                          icon: Icons.videocam,
                          label: tr(context, 'add_video'),
                          onTap: _picking ? null : () => _addEvidence(ImageSource.camera, 'video'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ActionTile(
                          icon: Icons.photo_library,
                          label: tr(context, 'from_gallery'),
                          onTap: _picking ? null : () => _addEvidence(ImageSource.gallery, 'photo'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                      icon: Icon(next == null ? Icons.check : Icons.arrow_forward),
                      label: Text(tr(context, next == null ? 'save_finish' : 'save_next')),
                      onPressed: () => _save(next: next),
                    ),
                  ],
                ]),
        ),
      ]),
    );
  }
}
