import 'package:flutter/material.dart';

import '../data/profile.dart';
import 'session.dart';
import 'task_widgets.dart';

class HistoryPage extends StatefulWidget {
  final Session session;
  const HistoryPage({super.key, required this.session});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Profile get _p => widget.session.profile;

  Future<void> _resetStats() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lernstand zurücksetzen?'),
        content: const Text('Statistik und Prüfungsergebnisse dieses Profils '
            'werden gelöscht. Kartendaten und Einstellungen bleiben erhalten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zurücksetzen')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _p.stats.clear();
      _p.exams.clear();
      _p.trainedTasks = 0;
      _p.trainedCorrect = 0;
    });
    await widget.session.save();
  }

  @override
  Widget build(BuildContext context) {
    final weak = _p.stats.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    String keyLabel(String k) {
      final parts = k.split(':');
      if (parts.first == 's') {
        return parts.length > 2 && parts[2].isNotEmpty
            ? '${parts[1]} (${parts[2]})'
            : parts[1];
      }
      return parts.sublist(2).join(':');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lernstand & Prüfungen'),
        actions: [
          IconButton(
            tooltip: 'Zurücksetzen',
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetStats,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Übungsaufgaben', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(_p.trainedTasks == 0
                        ? 'Noch keine Aufgaben bearbeitet.'
                        : '${_p.trainedTasks} bearbeitet, ${_p.trainedCorrect} richtig '
                            '(${(_p.trainedCorrect * 100 / _p.trainedTasks).round()} %)'),
                    if (weak.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Diese Ziele solltest du noch üben '
                          '(werden häufiger abgefragt):'),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final e in weak.take(30)) Chip(label: Text(keyLabel(e.key))),
                      ]),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Text('Prüfungen', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_p.exams.isEmpty) const Text('Noch keine Prüfung abgelegt.'),
              for (final ex in _p.exams)
                Card(
                  child: ExpansionTile(
                    leading: Icon(ex.passed ? Icons.emoji_events : Icons.assignment_late,
                        color: ex.passed ? Colors.green : Colors.deepOrange),
                    title: Text('${_fmt(ex.date)} – ${ex.correctCount} von ${ex.items.length} richtig'),
                    subtitle: Text(ex.settingsLabel),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < ex.items.length; i++) _item(context, i, ex.items[i]),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i, ExamItem it) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(it.correct ? Icons.check : Icons.close,
                size: 18, color: it.correct ? Colors.green : Colors.deepOrange),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${i + 1}. ${it.title} (${it.detail})',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          if (it.closures.isNotEmpty) Text('Sperrungen: ${it.closures.join('; ')}'),
          Text('Eingabe: ${it.input.join(' → ')}'
              '${it.diffS == null ? ' (nicht befahrbar)' : it.diffS! < 1 ? '' : ' (+${fmtDuration(it.diffS!)})'}'),
          Text('Schnellste: ${it.optimal.join(' → ')}'),
        ]),
      );
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
