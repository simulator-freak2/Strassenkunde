import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../core/road_graph.dart';
import '../core/router.dart';
import '../core/text_norm.dart';
import '../core/training.dart';
import 'map_view.dart';

String fmtDuration(double s) {
  if (s.isInfinite || s.isNaN) return '–';
  final t = s.round();
  final m = t ~/ 60, r = t % 60;
  if (m == 0) return '$r s';
  return '$m:${r.toString().padLeft(2, '0')} min';
}

String fmtDistance(double m) =>
    m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

/// Eingabe der Straßenfolge mit Autovervollständigung.
class RouteInput extends StatefulWidget {
  final List<String> labels;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  final VoidCallback? onSubmitAll;

  const RouteInput({
    super.key,
    required this.labels,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.onSubmitAll,
  });

  @override
  State<RouteInput> createState() => RouteInputState();
}

class RouteInputState extends State<RouteInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  late Map<String, String> _byNorm;

  @override
  void initState() {
    super.initState();
    _index();
  }

  @override
  void didUpdateWidget(covariant RouteInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labels != widget.labels) _index();
  }

  void _index() {
    _byNorm = {for (final l in widget.labels) normalizeStreet(l): l};
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Fügt eine Straße hinzu (auch von außen, z. B. über Vorschläge).
  void add(String label) {
    widget.onChanged([...widget.value, label]);
    _ctrl.clear();
    _focus.requestFocus();
  }

  void _submitText(String text) {
    final t = text.trim();
    if (t.isEmpty) {
      widget.onSubmitAll?.call();
      return;
    }
    final match = _byNorm[normalizeStreet(t)];
    if (match != null) {
      add(match);
      return;
    }
    final opts = _options(t);
    if (opts.length == 1) {
      add(opts.first);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('„$t“ ist im Gebiet nicht bekannt. Bitte aus der '
            'Vorschlagsliste wählen.')));
  }

  List<String> _options(String q) {
    final n = normalizeStreet(q);
    if (n.isEmpty) return const [];
    final starts = <String>[], contains = <String>[];
    for (final l in widget.labels) {
      final ln = normalizeStreet(l);
      if (ln.startsWith(n)) {
        starts.add(l);
      } else if (ln.contains(n)) {
        contains.add(l);
      }
    }
    return [...starts, ...contains].take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.value.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < widget.value.length; i++)
            InputChip(
              avatar: CircleAvatar(
                backgroundColor: theme.colorScheme.primary,
                child: Text('${i + 1}',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onPrimary)),
              ),
              label: Text(widget.value[i]),
              onDeleted: widget.enabled
                  ? () {
                      final l = [...widget.value]..removeAt(i);
                      widget.onChanged(l);
                    }
                  : null,
            ),
        ]),
      if (widget.value.isNotEmpty) const SizedBox(height: 8),
      if (widget.enabled)
        RawAutocomplete<String>(
          textEditingController: _ctrl,
          focusNode: _focus,
          optionsBuilder: (v) => _options(v.text),
          onSelected: add,
          fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
            controller: ctrl,
            focusNode: focus,
            decoration: InputDecoration(
              labelText: widget.value.isEmpty
                  ? 'Erste Straße eingeben'
                  : 'Nächste Straße eingeben',
              hintText: 'Straßenname oder z. B. „B 9“',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Hinzufügen',
                onPressed: () => _submitText(ctrl.text),
              ),
            ),
            // Fokus nach Enter behalten, damit man direkt weitertippen kann
            onEditingComplete: () {},
            onSubmitted: (t) {
              _submitText(t);
              _focus.requestFocus();
            },
          ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280, maxWidth: 380),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(dense: true, title: Text(o), onTap: () => onSelected(o)),
                  ],
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Aufgabenkarte: Start, Ziel, Sperrungen.
class TaskCard extends StatelessWidget {
  final Task task;
  final bool showAddress;
  final String? header;
  const TaskCard({super.key, required this.task, this.showAddress = false, this.header});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = task.target;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (header != null)
            Text(header!, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          Row(children: [
            const Icon(Icons.trip_origin, size: 18, color: Colors.green),
            const SizedBox(width: 6),
            Expanded(child: Text('Start: ${task.start.label}')),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(t.type == TargetType.object ? Icons.apartment : Icons.signpost_outlined,
                color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, style: theme.textTheme.titleLarge),
                Text(t.detail, style: theme.textTheme.bodyMedium),
                if (showAddress && t.address.isNotEmpty)
                  Text(t.address, style: theme.textTheme.bodySmall),
              ]),
            ),
          ]),
          if (task.closures.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.block, size: 18, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 6),
                  Text('Aktuelle Sperrungen',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onErrorContainer)),
                ]),
                const SizedBox(height: 4),
                for (final c in task.closures)
                  Text('• ${c.description}',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Auswertung einer Aufgabe.
class EvaluationView extends StatelessWidget {
  final Task task;
  final Evaluation? eval; // null = nur Lösung anzeigen
  final RoadGraph graph;
  final int toleranceSec;
  const EvaluationView({
    super.key,
    required this.task,
    required this.eval,
    required this.graph,
    required this.toleranceSec,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = task.router.vehicle;
    final legs = task.optimal.legs(graph, v);
    final ev = eval;
    final ok = ev?.correct ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (ev != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ok ? Colors.green.shade100 : Colors.orange.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(ok ? Icons.check_circle : Icons.cancel,
                  color: ok ? Colors.green.shade800 : Colors.deepOrange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok
                      ? (ev.diffS < 1 ? 'Richtig – schnellste Route!' : 'Richtig – innerhalb der Toleranz')
                      : 'Leider nicht richtig',
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.black87),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            if (ev.check.route != null)
              Text(
                'Deine Route: ${fmtDuration(ev.check.route!.timeS)} '
                '(${fmtDistance(ev.check.route!.lengthM(graph))}) – '
                '${ev.diffS < 1 ? 'gleich schnell' : '${fmtDuration(ev.diffS)} langsamer'}'
                '${!ok ? ' (erlaubt: ${fmtDuration(toleranceSec.toDouble())})' : ''}',
                style: const TextStyle(color: Colors.black87),
              )
            else
              Text(ev.check.error ?? 'Route nicht befahrbar.',
                  style: const TextStyle(color: Colors.black87)),
          ]),
        ),
      const SizedBox(height: 10),
      Text('Schnellste Route: ${fmtDuration(task.optimal.timeS)} '
          '(${fmtDistance(task.optimal.lengthM(graph))}, ${v.label})',
          style: theme.textTheme.titleSmall),
      if (task.closures.isNotEmpty && task.timeWithoutClosures < task.optimal.timeS - 0.5)
        Text('Ohne Sperrungen: ${fmtDuration(task.timeWithoutClosures)}',
            style: theme.textTheme.bodySmall),
      const SizedBox(height: 4),
      for (var i = 0; i < legs.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            SizedBox(width: 26, child: Text('${i + 1}.')),
            Expanded(
                child: Text(legs[i].label ?? '(namenlose Straße/Zufahrt)',
                    style: legs[i].label == null
                        ? const TextStyle(fontStyle: FontStyle.italic)
                        : null)),
            Text('${fmtDistance(legs[i].lengthM)} · ${fmtDuration(legs[i].timeS)}',
                style: theme.textTheme.bodySmall),
          ]),
        ),
      const SizedBox(height: 6),
      const _Legend(),
    ]);
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 18, height: 5, color: c),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(fontSize: 12)),
        ]);
    return Wrap(spacing: 14, runSpacing: 4, children: [
      item(routeColorOptimal, 'Schnellste Route'),
      item(routeColorUser, 'Deine Route'),
      item(Colors.red.shade700, 'Sperrung'),
    ]);
  }
}

const routeColorOptimal = Color(0xCC1565C0);
const routeColorUser = Color(0xDDFF8F00);

/// Karte für eine Aufgabe.
class TaskMap extends StatelessWidget {
  final RoadGraph graph;
  final Task task;
  final bool showTarget;
  final bool showOptimal;
  final RouteResult? userRoute;
  final bool showNames;
  final Object? fitKey;
  const TaskMap({
    super.key,
    required this.graph,
    required this.task,
    this.showTarget = true,
    this.showOptimal = false,
    this.userRoute,
    this.showNames = true,
    this.fitKey,
  });

  @override
  Widget build(BuildContext context) {
    final box = BBox.empty()
      ..extend(task.start.lat, task.start.lon);
    if (showTarget || showOptimal) box.extend(task.target.lat, task.target.lon);
    if (showOptimal) {
      for (final d in task.optimal.directedEdges) {
        final (la, lo) = graph.edgeMid(d >> 1);
        box.extend(la, lo);
      }
    }
    final fit = box.expanded(showTarget || showOptimal ? 250 : 900);
    return MapView(
      graph: graph,
      areaRings: graph.areaRings,
      fitKey: fitKey ?? task,
      fitBox: fit,
      closedEdges: {for (final c in task.closures) ...c.edges},
      routes: [
        if (showOptimal) MapRoute(task.optimal.directedEdges, routeColorOptimal, width: 8),
        if (userRoute != null) MapRoute(userRoute!.directedEdges, routeColorUser, width: 4),
      ],
      markers: [
        MapMarker(task.start.lat, task.start.lon, Colors.green.shade700, 'Start',
            Icons.trip_origin),
        if (showTarget)
          MapMarker(task.target.lat, task.target.lon, Colors.red.shade700,
              task.target.title, Icons.flag),
      ],
      showNames: showNames,
      tapForNames: showNames,
    );
  }
}
