import 'package:flutter/material.dart';

import '../core/road_graph.dart';
import '../core/training.dart';
import '../data/profile.dart';
import 'session.dart';
import 'task_widgets.dart';

/// Prüfung: mehrere Ziele nacheinander, ohne Hilfen. Jedes Ziel startet am
/// vorherigen Ziel (das erste am Gerätehaus).
class ExamPage extends StatefulWidget {
  final Session session;
  const ExamPage({super.key, required this.session});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  final _tasks = <Task>[];
  final _evals = <Evaluation>[];
  List<String> _input = [];
  bool _finished = false;
  String? _error;
  int _selected = 0;

  ProfileSettings get _s => widget.session.profile.settings;
  RoadGraph get _g => widget.session.graph!;
  int get _total => _s.examTargets;

  @override
  void initState() {
    super.initState();
    _next();
  }

  void _next() {
    final start = _tasks.isEmpty ? widget.session.stationStart() : _tasks.last.endPoint;
    final used = {for (final t in _tasks) t.target.key};
    final t = widget.session.generator!.next(start, _s.toOptions(), avoid: used);
    setState(() {
      if (t == null) {
        _error = 'Es konnte keine weitere Aufgabe erzeugt werden.';
      } else {
        _tasks.add(t);
        _input = [];
      }
    });
  }

  Future<void> _submit() async {
    if (_input.isEmpty) return;
    final t = _tasks.last;
    final ev = widget.session.generator!.evaluate(t, _input, _s.toleranceSec);
    _evals.add(ev);
    widget.session.profile.recordResult(t.target.key, ev.correct);
    if (_evals.length >= _total) {
      await _finish();
    } else {
      _next();
    }
  }

  Future<void> _finish() async {
    final v = _s.vehicle;
    final rec = ExamRecord(
      DateTime.now(),
      '${v.label} · ${_s.closureLevel.label} · Toleranz ${fmtDuration(_s.toleranceSec.toDouble())}',
      [
        for (var i = 0; i < _evals.length; i++)
          ExamItem(
            _tasks[i].target.title,
            _tasks[i].target.detail,
            _evals[i].correct,
            _evals[i].check.route == null ? null : _evals[i].diffS,
            _evals[i].input,
            _tasks[i].optimal.streetSequence(_g, v),
            [for (final c in _tasks[i].closures) c.description],
          )
      ],
    );
    widget.session.profile.exams.insert(0, rec);
    setState(() {
      _finished = true;
      _selected = 0;
    });
    await widget.session.save();
  }

  Future<bool> _confirmLeave() async {
    if (_finished || _evals.isEmpty && _input.isEmpty) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prüfung abbrechen?'),
        content: const Text('Die laufende Prüfung wird nicht gewertet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Weiter prüfen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abbrechen')),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_finished
              ? 'Prüfung – Ergebnis'
              : 'Prüfung – Ziel ${_tasks.length} von $_total'),
        ),
        body: _error != null
            ? Center(child: Text(_error!))
            : _finished
                ? _results(context)
                : _question(context),
      ),
    );
  }

  Widget _question(BuildContext context) {
    final t = _tasks.last;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LinearProgressIndicator(value: _evals.length / _total),
            const SizedBox(height: 12),
            TaskCard(task: t, header: 'Einsatzziel ${_tasks.length}'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Route in Fahrreihenfolge eingeben',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  RouteInput(
                    labels: widget.session.streetLabels,
                    value: _input,
                    onChanged: (v) => setState(() => _input = v),
                    onSubmitAll: _submit,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _input.isEmpty ? null : _submit,
                    icon: Icon(_evals.length + 1 >= _total ? Icons.flag : Icons.navigate_next),
                    label: Text(_evals.length + 1 >= _total
                        ? 'Prüfung abschließen'
                        : 'Weiter zum nächsten Ziel'),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final correct = _evals.where((e) => e.correct).length;
    final passed = correct == _evals.length;
    final wide = MediaQuery.sizeOf(context).width > 900;
    final t = _tasks[_selected];
    final ev = _evals[_selected];
    final list = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: passed ? Colors.green.shade100 : Colors.orange.shade100,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(passed ? Icons.emoji_events : Icons.assignment_late,
                  size: 40, color: passed ? Colors.green.shade800 : Colors.deepOrange.shade800),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  passed
                      ? 'Bestanden! Alle $correct Ziele richtig.'
                      : '$correct von ${_evals.length} Zielen richtig.',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.black87),
                ),
              ),
            ]),
          ),
        ),
        for (var i = 0; i < _tasks.length; i++)
          Card(
            color: i == _selected ? Theme.of(context).colorScheme.secondaryContainer : null,
            child: ListTile(
              leading: Icon(_evals[i].correct ? Icons.check_circle : Icons.cancel,
                  color: _evals[i].correct ? Colors.green : Colors.deepOrange),
              title: Text('${i + 1}. ${_tasks[i].target.title}'),
              subtitle: Text(_tasks[i].target.detail),
              onTap: () => setState(() => _selected = i),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TaskCard(task: t, showAddress: true, header: 'Ziel ${_selected + 1}'),
              Text('Deine Eingabe: ${ev.input.join(' → ')}'),
              const SizedBox(height: 8),
              EvaluationView(
                  task: t, eval: ev, graph: _g, toleranceSec: _s.toleranceSec),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.done),
          label: const Text('Fertig'),
        ),
      ],
    );
    final map = TaskMap(
      graph: _g,
      task: t,
      showOptimal: true,
      userRoute: ev.check.route,
      fitKey: _selected,
    );
    if (wide) {
      return Row(children: [
        SizedBox(width: 480, child: list),
        Expanded(child: map),
      ]);
    }
    return Column(children: [
      SizedBox(height: MediaQuery.sizeOf(context).height * 0.35, child: map),
      Expanded(child: list),
    ]);
  }
}
