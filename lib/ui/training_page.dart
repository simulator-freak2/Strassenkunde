import 'package:flutter/material.dart';

import '../core/road_graph.dart';
import '../core/training.dart';
import '../data/profile.dart';
import 'session.dart';
import 'task_widgets.dart';

/// Lernmodus leicht (Hilfen) bzw. schwer (erst am Ende Auswertung).
class TrainingPage extends StatefulWidget {
  final Session session;
  final bool easy;
  const TrainingPage({super.key, required this.session, required this.easy});

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  Task? _task;
  List<String> _input = [];
  Evaluation? _eval;
  bool _solutionShown = false;
  bool _showMapHard = false;
  List<String> _options = [];
  final _inputKey = GlobalKey<RouteInputState>();
  final _recent = <String>[];
  int _count = 0, _correct = 0;

  RoadGraph get _g => widget.session.graph!;
  ProfileSettings get _settings => widget.session.profile.settings;

  @override
  void initState() {
    super.initState();
    _newTask(fromStation: true);
  }

  void _newTask({bool fromStation = false}) {
    final start = (!fromStation && _settings.startFromLast && _task != null)
        ? _task!.endPoint
        : widget.session.stationStart();
    final t = widget.session.generator!.next(start, _settings.toOptions(),
        stats: widget.session.profile.stats, avoid: _recent.toSet());
    setState(() {
      _task = t;
      _input = [];
      _eval = null;
      _solutionShown = false;
      _showMapHard = false;
      if (t != null) {
        _recent.add(t.target.key);
        if (_recent.length > 15) _recent.removeAt(0);
      }
    });
    _updateOptions();
  }

  void _updateOptions() {
    final t = _task;
    if (!widget.easy || t == null) return;
    setState(() => _options = t.router.nextStreetOptions(t.start, _input));
  }

  void _setInput(List<String> v) {
    setState(() => _input = v);
    _updateOptions();
  }

  Future<void> _evaluate() async {
    final t = _task;
    if (t == null || _input.isEmpty) return;
    final ev = widget.session.generator!.evaluate(t, _input, _settings.toleranceSec);
    setState(() {
      _eval = ev;
      _count++;
      if (ev.correct) _correct++;
    });
    if (!_solutionShown) {
      widget.session.profile.recordResult(t.target.key, ev.correct);
      await widget.session.save();
    }
  }

  void _showSolution() {
    setState(() => _solutionShown = true);
    widget.session.profile.recordResult(_task!.target.key, false);
    widget.session.save();
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;
    final title = widget.easy ? 'Lernmodus leicht' : 'Lernmodus schwer';
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Es konnte keine Aufgabe erzeugt werden. Bitte prüfe die '
                'Einstellungen (Zieltypen) und ob das Gerätehaus im Kartenbereich liegt.'),
          ),
        ),
      );
    }
    final done = _eval != null || _solutionShown;
    final wide = MediaQuery.sizeOf(context).width > 900;
    final mapVisible = widget.easy || done || _showMapHard;
    final map = TaskMap(
      graph: _g,
      task: t,
      showTarget: widget.easy || done,
      showOptimal: done,
      userRoute: _eval?.check.route,
      showNames: widget.easy || done,
      fitKey: Object.hash(t, done),
    );
    final panel = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TaskCard(task: t, showAddress: widget.easy || done),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Deine Route (Straßen in Fahrreihenfolge)',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              RouteInput(
                key: _inputKey,
                labels: widget.session.streetLabels,
                value: _input,
                onChanged: _setInput,
                enabled: !done,
                onSubmitAll: _evaluate,
              ),
              if (widget.easy && !done) ...[
                const SizedBox(height: 10),
                if (_input.isNotEmpty) _hint(context, t),
                const SizedBox(height: 6),
                Text(
                    _input.isEmpty
                        ? 'Vom Start aus erreichbar:'
                        : 'Von „${_input.last}“ kannst du abbiegen in:',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                if (_options.isEmpty)
                  const Text('– keine (Eingabe prüfen) –')
                else
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final o in _options)
                      ActionChip(
                        label: Text(o),
                        onPressed: () => _inputKey.currentState?.add(o),
                      ),
                  ]),
              ],
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (!done)
                  FilledButton.icon(
                    onPressed: _input.isEmpty ? null : _evaluate,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Auswerten'),
                  ),
                if (!done && widget.easy)
                  OutlinedButton.icon(
                    onPressed: _showSolution,
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Lösung zeigen'),
                  ),
                if (!done && !widget.easy && !_showMapHard)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _showMapHard = true),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Karte ohne Namen'),
                  ),
                if (done)
                  FilledButton.icon(
                    onPressed: () => _newTask(),
                    icon: const Icon(Icons.navigate_next),
                    label: Text(_settings.startFromLast
                        ? 'Nächste Aufgabe (ab hier)'
                        : 'Nächste Aufgabe'),
                  ),
                if (done && _settings.startFromLast)
                  OutlinedButton.icon(
                    onPressed: () => _newTask(fromStation: true),
                    icon: const Icon(Icons.local_fire_department_outlined),
                    label: const Text('Neu ab Gerätehaus'),
                  ),
              ]),
            ]),
          ),
        ),
        if (done) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: EvaluationView(
                task: t,
                eval: _eval,
                graph: _g,
                toleranceSec: _settings.toleranceSec,
              ),
            ),
          ),
        ],
      ],
    );

    final body = wide
        ? Row(children: [
            SizedBox(width: 460, child: panel),
            Expanded(child: mapVisible ? map : const _MapHidden()),
          ])
        : Column(children: [
            if (mapVisible)
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.38, child: map),
            Expanded(child: panel),
          ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('$_correct / $_count richtig'),
            ),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _hint(BuildContext context, Task t) {
    final on = widget.session.generator!.isOnOptimalPath(t, _input);
    return Row(children: [
      Icon(on ? Icons.thumb_up_alt_outlined : Icons.info_outline,
          size: 18, color: on ? Colors.green.shade700 : Colors.orange.shade800),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          on
              ? 'Bisher auf der schnellsten Route.'
              : 'Weicht von der schnellsten Route ab (kann trotzdem in der '
                  'Toleranz liegen).',
          style: TextStyle(color: on ? Colors.green.shade800 : Colors.orange.shade900),
        ),
      ),
    ]);
  }
}

class _MapHidden extends StatelessWidget {
  const _MapHidden();
  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: const Text(
          'Die Karte wird nach der Auswertung angezeigt.',
          textAlign: TextAlign.center,
        ),
      );
}
