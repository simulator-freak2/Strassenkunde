import 'package:flutter/material.dart';

import '../core/road_graph.dart';
import '../core/training.dart';
import '../data/profile.dart';
import '../data/storage.dart';
import 'exam_page.dart';
import 'history_page.dart';
import 'session.dart';
import 'setup_page.dart';
import 'training_page.dart';

class ProfileHomePage extends StatefulWidget {
  final Storage storage;
  final Profile profile;
  const ProfileHomePage({super.key, required this.storage, required this.profile});

  @override
  State<ProfileHomePage> createState() => _ProfileHomePageState();
}

class _ProfileHomePageState extends State<ProfileHomePage> {
  late final Session _session = Session(widget.storage, widget.profile);
  bool _loading = true;
  String? _error;

  Profile get _p => widget.profile;

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
    try {
      await _session.loadGraph();
    } catch (e) {
      _error = 'Kartendaten konnten nicht geladen werden: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setup() async {
    final changed = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => SetupPage(session: _session)));
    if (changed == true) await _load();
    setState(() {});
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    setState(() {});
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profil umbenennen'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Speichern')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    setState(() => _p.name = name.trim());
    await _session.save();
  }

  void _changed() {
    setState(() {});
    _session.save();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _session.ready && !_loading;
    final s = _p.settings;
    final gen = _session.generator;
    final targetCount = gen == null
        ? 0
        : (s.objects ? gen.objectCountFor(s.categories) : 0) +
            (s.streets ? gen.streetCount : 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(_p.name),
        actions: [
          IconButton(
              tooltip: 'Umbenennen', icon: const Icon(Icons.edit), onPressed: _rename),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusCard(context),
              const SizedBox(height: 12),
              if (_error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                      padding: const EdgeInsets.all(12), child: Text(_error!)),
                ),
              if (ready && targetCount == 0)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Mit den aktuellen Einstellungen gibt es keine '
                        'Ziele. Bitte Zieltypen/Kategorien prüfen.'),
                  ),
                ),
              Text('Üben', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _ModeCard(
                  icon: Icons.school_outlined,
                  title: 'Lernmodus leicht',
                  text: 'Karte mit Straßennamen, Vorschläge für die nächste '
                      'Straße und Hinweise unterwegs.',
                  enabled: ready && targetCount > 0,
                  onTap: () => _open(TrainingPage(session: _session, easy: true)),
                ),
                _ModeCard(
                  icon: Icons.route_outlined,
                  title: 'Lernmodus schwer',
                  text: 'Kompletten Weg eingeben – erst danach siehst du, ob er '
                      'richtig ist.',
                  enabled: ready && targetCount > 0,
                  onTap: () => _open(TrainingPage(session: _session, easy: false)),
                ),
                _ModeCard(
                  icon: Icons.assignment_turned_in_outlined,
                  title: 'Prüfung',
                  text: '${s.examTargets} Ziele nacheinander anfahren, ohne '
                      'Hilfen. Auswertung am Ende.',
                  enabled: ready && targetCount > 0,
                  onTap: () => _open(ExamPage(session: _session)),
                ),
              ]),
              const SizedBox(height: 20),
              _settingsCard(context),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bar_chart),
                  title: const Text('Lernstand & Prüfungen'),
                  subtitle: Text(_p.trainedTasks == 0
                      ? 'Noch keine Aufgaben bearbeitet'
                      : '${_p.trainedTasks} Aufgaben, davon '
                          '${(_p.trainedCorrect * 100 / _p.trainedTasks).round()} % '
                          'richtig · ${_p.exams.length} Prüfung(en)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(HistoryPage(session: _session)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final theme = Theme.of(context);
    final areaText = _p.areas.isEmpty
        ? 'nicht festgelegt'
        : _p.areas.map((a) => '${a.name.split(',').first} (${a.kind})').join(', ');
    final dataText = _loading
        ? 'wird geladen …'
        : _session.graph == null
            ? 'noch nicht heruntergeladen'
            : '${_p.dataStreets} Straßen, ${_p.dataObjects} Objekte '
                '(Stand ${_fmtDate(_p.dataDate)})';
    final outdated = _session.graph != null &&
        _p.dataSignature != null &&
        _p.dataSignature != _p.areaSignature();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.map_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(child: Text('Ausrückebereich & Startpunkt', style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: 12),
          _kv('Gebiet', areaText),
          _kv('Puffer', '${(_p.bufferM / 1000).toStringAsFixed(1)} km um das Gebiet'),
          _kv('Kartendaten', dataText),
          _kv('Gerätehaus', _p.station?.label ?? 'nicht festgelegt'),
          if (outdated)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Das Gebiet wurde geändert – bitte Daten neu laden.',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _loading ? null : _setup,
            icon: const Icon(Icons.settings_outlined),
            label: Text(_session.ready ? 'Ändern' : 'Jetzt einrichten'),
          ),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ]),
      );

  Widget _settingsCard(BuildContext context) {
    final s = _p.settings;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.tune, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(child: Text('Einstellungen', style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: 12),
          const Text('Fahrzeug'),
          const SizedBox(height: 4),
          SegmentedButton<Vehicle>(
            segments: const [
              ButtonSegment(value: Vehicle.pkw, label: Text('PKW'), icon: Icon(Icons.directions_car)),
              ButtonSegment(value: Vehicle.lkw, label: Text('LKW'), icon: Icon(Icons.fire_truck)),
            ],
            selected: {s.vehicle},
            onSelectionChanged: (v) {
              s.vehicle = v.first;
              _changed();
            },
          ),
          const SizedBox(height: 4),
          Text(
              s.vehicle == Vehicle.lkw
                  ? 'LKW: langsamere Geschwindigkeiten, Straßen mit Gewichts-, '
                      'Höhen- oder Breitenbeschränkung (16 t / 3,5 m / 2,55 m) '
                      'und LKW-Verbot werden gemieden.'
                  : 'PKW: normale Geschwindigkeiten.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          const Text('Sperrungen (gelten für Lernmodi und Prüfung)'),
          RadioGroup<ClosureLevel>(
            groupValue: s.closureLevel,
            onChanged: (v) {
              s.closureLevel = v!;
              _changed();
            },
            child: Column(children: [
              for (final l in ClosureLevel.values)
                RadioListTile<ClosureLevel>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: l,
                  title: Text(l.label),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('Start jeder Lernaufgabe'),
          RadioGroup<bool>(
            groupValue: s.startFromLast,
            onChanged: (v) {
              s.startFromLast = v!;
              _changed();
            },
            child: const Column(children: [
              RadioListTile<bool>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: false,
                title: Text('Immer neu ab Gerätehaus'),
              ),
              RadioListTile<bool>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: true,
                title: Text('Vom letzten Ziel weiterfahren'),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('Ziele'),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Objekte'),
            value: s.objects,
            onChanged: (v) {
              s.objects = v;
              if (!v && !s.streets) s.streets = true;
              _changed();
            },
          ),
          if (s.objects)
            Wrap(spacing: 8, children: [
              for (final c in PoiCategory.values)
                FilterChip(
                  label: Text(c.label),
                  selected: s.categories.contains(c),
                  onSelected: (on) {
                    if (on) {
                      s.categories.add(c);
                    } else if (s.categories.length > 1) {
                      s.categories.remove(c);
                    }
                    _changed();
                  },
                ),
            ]),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Straßen'),
            value: s.streets,
            onChanged: (v) {
              s.streets = v;
              if (!v && !s.objects) s.objects = true;
              _changed();
            },
          ),
          const SizedBox(height: 8),
          Text('Toleranz: Route darf ${_fmtTol(s.toleranceSec)} länger dauern '
              'als die schnellste'),
          Slider(
            value: s.toleranceSec.toDouble(),
            min: 0,
            max: 300,
            divisions: 10,
            label: _fmtTol(s.toleranceSec),
            onChanged: (v) => setState(() => s.toleranceSec = v.round()),
            onChangeEnd: (_) => _changed(),
          ),
        ]),
      ),
    );
  }
}

String _fmtTol(int s) {
  if (s == 0) return '0 s';
  final m = s ~/ 60, r = s % 60;
  if (r == 0) return '$m min';
  if (m == 0) return '$r s';
  return '$m min $r s';
}

String _fmtDate(DateTime? d) {
  if (d == null) return '-';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title, text;
  final bool enabled;
  final VoidCallback onTap;
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 250,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 32, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(text, style: theme.textTheme.bodySmall),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
