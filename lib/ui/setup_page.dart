import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/osm_service.dart';
import '../core/router.dart';
import '../data/profile.dart';
import 'map_view.dart';
import 'session.dart';

/// Einrichtung: Ausrückebereich wählen, Daten laden, Gerätehaus festlegen.
class SetupPage extends StatefulWidget {
  final Session session;
  const SetupPage({super.key, required this.session});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _osm = OsmService();
  final _areaCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _coordCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();

  List<AreaItem>? _areaResults;
  List<AddressResult>? _addrResults;
  bool _searching = false;
  bool _downloading = false;
  String? _progressText;
  double? _progress;
  bool _changedData = false;
  bool _pickOnMap = false;
  bool _pickExit = false;
  int _fitCounter = 0;

  Profile get _p => widget.session.profile;

  @override
  void initState() {
    super.initState();
    _labelCtrl.text = _p.station?.label ?? 'Feuerwehrgerätehaus';
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _searchArea() async {
    final q = _areaCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final r = await _osm.searchAreas(q);
      setState(() => _areaResults = r);
      if (r.isEmpty) _snack('Kein Gebiet mit Umriss gefunden.');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addArea(AreaItem a) async {
    if (_p.areas.any((x) => x.key == a.key)) return;
    setState(() {
      _p.areas.add(a);
      _areaResults = null;
      _areaCtrl.clear();
      _fitCounter++;
    });
    await widget.session.save();
  }

  Future<void> _removeArea(AreaItem a) async {
    setState(() {
      _p.areas.removeWhere((x) => x.key == a.key);
      _fitCounter++;
    });
    await widget.session.save();
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progressText = 'Starte Download …';
      _progress = 0;
    });
    try {
      final (streets, objects) = await _osm.downloadProfileData(
        widget.session.storage,
        _p,
        (t, pr) {
          if (mounted) {
            setState(() {
              _progressText = t;
              _progress = pr;
            });
          }
        },
      );
      _p.dataDate = DateTime.now();
      _p.dataStreets = streets;
      _p.dataObjects = objects;
      _p.dataSignature = _p.areaSignature();
      await widget.session.save();
      await widget.session.loadGraph();
      _changedData = true;
      _snack('Kartendaten geladen: $streets Straßen, $objects Objekte.');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progressText = null;
        });
      }
    }
  }

  Future<void> _importFile() async {
    final PlatformFile? f;
    try {
      f = await FilePicker.pickFile(dialogTitle: 'Kartendatei laden (.json.gz)');
    } catch (e) {
      _snack('Datei konnte nicht geöffnet werden: $e');
      return;
    }
    if (f == null) return;
    setState(() {
      _downloading = true;
      _progressText = 'Lese Kartendatei …';
      _progress = null;
    });
    try {
      final bytes = await f.readAsBytes();
      final g = await widget.session.storage.importGraph(_p, bytes);
      if (_p.areas.isEmpty && g.areaRings.isNotEmpty) {
        _p.areas = [
          AreaItem(g.areaNames.isEmpty ? 'Importiertes Gebiet' : g.areaNames.join(', '),
              'aus Datei', 'datei', 0, g.areaRings)
        ];
      }
      final streets = <int>{
        for (var e = 0; e < g.edgeCount; e++)
          if (g.eInArea[e] == 1 && g.eName[e] >= 0) g.eName[e]
      };
      _p.dataDate = DateTime.now();
      _p.dataStreets = streets.length;
      _p.dataObjects = g.pois.where((x) => x.inArea).length;
      _p.dataSignature = _p.areaSignature();
      await widget.session.save();
      await widget.session.loadGraph();
      _changedData = true;
      _fitCounter++;
      _snack('Kartendatei geladen: ${_p.dataStreets} Straßen, ${_p.dataObjects} Objekte.');
    } catch (e) {
      _snack(e is FormatException ? e.message : '$e');
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _progressText = null;
        });
      }
    }
  }

  Future<void> _exportFile() async {
    final file = widget.session.storage.graphFile(_p);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final base = (_p.areas.isEmpty ? _p.name : _p.areas.first.name.split(',').first)
        .replaceAll(RegExp(r'[^\wäöüÄÖÜß\- ]'), '')
        .trim()
        .replaceAll(' ', '-');
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Kartendatei speichern',
        fileName: 'karte-$base.json.gz',
        bytes: bytes,
      );
      if (uri != null) _snack('Kartendatei gespeichert.');
    } catch (e) {
      _snack('Speichern fehlgeschlagen: $e');
    }
  }

  Future<void> _searchAddress() async {
    final q = _addrCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final r = await _osm.searchAddress(q);
      setState(() => _addrResults = r);
      if (r.isEmpty) _snack('Adresse nicht gefunden.');
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _setStation(double lat, double lon, [String? fallbackLabel]) async {
    var label = _labelCtrl.text.trim();
    if (label.isEmpty) label = fallbackLabel ?? 'Gerätehaus';
    setState(() {
      final old = _p.station;
      _p.station = old == null
          ? StationPoint(label, lat, lon)
          : old.copyWith(label: label, lat: lat, lon: lon);
      _addrResults = null;
      _pickOnMap = false;
    });
    await widget.session.save();
    final g = widget.session.graph;
    if (g != null && !g.bbox.contains(lat, lon)) {
      _snack('Achtung: Der Startpunkt liegt außerhalb der geladenen Karte.');
    } else {
      _snack('Startpunkt gespeichert.');
    }
  }

  Future<void> _addExit(double lat, double lon) async {
    final st = _p.station;
    final g = widget.session.graph;
    if (st == null || g == null) return;
    final e = g.nearestEdge(lat, lon);
    final street = e >= 0 ? (g.label(e) ?? 'Zufahrt') : 'Ausfahrt';
    final isFirst = st.exits.isEmpty;
    setState(() {
      st.exits.add(StationExit(
          isFirst ? 'Hauptausfahrt $street' : 'Ausfahrt $street', lat, lon,
          main: isFirst));
      _pickExit = false;
    });
    await widget.session.save();
    _snack('Ausfahrt auf „$street“ hinzugefügt.');
  }

  Future<void> _setMainExit(StationExit x) async {
    setState(() {
      for (final e in _p.station!.exits) {
        e.main = identical(e, x);
      }
    });
    await widget.session.save();
  }

  Future<void> _renameExit(StationExit x) async {
    final ctrl = TextEditingController(text: x.label);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ausfahrt benennen'),
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
    setState(() => x.label = name.trim());
    await widget.session.save();
  }

  Future<void> _removeExit(StationExit x) async {
    final st = _p.station!;
    setState(() {
      st.exits.remove(x);
      if (x.main && st.exits.isNotEmpty) st.exits.first.main = true;
    });
    await widget.session.save();
  }

  void _setCoords() {
    final m = RegExp(r'(-?\d+(?:[.,]\d+)?)\s*[,;\s]\s*(-?\d+(?:[.,]\d+)?)')
        .firstMatch(_coordCtrl.text.trim());
    final la = m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.'));
    final lo = m == null ? null : double.tryParse(m.group(2)!.replaceAll(',', '.'));
    if (la == null || lo == null || la.abs() > 90 || lo.abs() > 180) {
      _snack('Bitte Koordinaten im Format „50.1234, 8.5678“ eingeben.');
      return;
    }
    _setStation(la, lo);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 980;
    final rings = [for (final a in _p.areas) ...a.rings];
    final st = _p.station;
    final map = MapView(
      graph: widget.session.graph,
      areaRings: rings,
      fitKey: _fitCounter,
      markers: [
        if (st != null)
          MapMarker(st.lat, st.lon, Colors.red.shade700, st.label, Icons.local_fire_department),
        if (st != null)
          for (final x in st.exits)
            MapMarker(x.lat, x.lon, x.main ? Colors.blue.shade800 : Colors.blueGrey,
                x.main ? 'Hauptausfahrt' : x.label, Icons.exit_to_app),
      ],
      onTap: _pickOnMap
          ? (la, lo) => _setStation(la, lo)
          : _pickExit
              ? (la, lo) => _addExit(la, lo)
              : null,
      tapForNames: !_pickOnMap && !_pickExit,
      showNames: true,
    );
    final form = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _areaSection(context),
        const SizedBox(height: 12),
        _dataSection(context),
        const SizedBox(height: 12),
        _stationSection(context),
        const SizedBox(height: 12),
        _exitSection(context),
        if (!wide) ...[
          const SizedBox(height: 12),
          SizedBox(height: 380, child: Card(clipBehavior: Clip.antiAlias, child: map)),
        ],
      ],
    );
    return PopScope(
      canPop: !_downloading,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gebiet & Startpunkt'),
          leading: BackButton(
            onPressed: _downloading ? null : () => Navigator.pop(context, _changedData),
          ),
        ),
        body: wide
            ? Row(children: [
                SizedBox(width: 470, child: form),
                Expanded(child: map),
              ])
            : form,
      ),
    );
  }

  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  Widget _areaSection(BuildContext context) => _section(
        context,
        '1. Ausrückebereich',
        Icons.layers_outlined,
        [
          const Text('Suche nach Stadtteil, Stadt, Gemeinde, Verbandsgemeinde '
              'oder Landkreis. Mehrere Gebiete können kombiniert werden.'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _areaCtrl,
                decoration: const InputDecoration(
                  hintText: 'z. B. „Verbandsgemeinde Musterdorf“',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _searchArea(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _searching ? null : _searchArea,
              icon: const Icon(Icons.search),
              tooltip: 'Suchen',
            ),
          ]),
          if (_areaResults != null)
            for (final a in _areaResults!)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(a.name.split(',').first),
                subtitle: Text('${a.kind} · ${a.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Hinzufügen',
                  onPressed: () => _addArea(a),
                ),
                onTap: () => _addArea(a),
              ),
          const SizedBox(height: 8),
          if (_p.areas.isEmpty)
            const Text('Noch kein Gebiet gewählt.', style: TextStyle(fontStyle: FontStyle.italic))
          else
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final a in _p.areas)
                InputChip(
                  label: Text('${a.name.split(',').first} (${a.kind})'),
                  onDeleted: () => _removeArea(a),
                ),
            ]),
          const SizedBox(height: 12),
          Text('Randbereich: ${(_p.bufferM / 1000).toStringAsFixed(1)} km '
              '(Straßen um das Gebiet herum, damit Wege auch kurz durch '
              'Nachbarorte führen dürfen)'),
          Slider(
            value: _p.bufferM,
            min: 500,
            max: 5000,
            divisions: 9,
            label: '${(_p.bufferM / 1000).toStringAsFixed(1)} km',
            onChanged: (v) => setState(() => _p.bufferM = v),
            onChangeEnd: (_) => widget.session.save(),
          ),
        ],
      );

  Widget _dataSection(BuildContext context) {
    final hasData = widget.session.graph != null;
    final outdated = hasData && _p.dataSignature != _p.areaSignature();
    return _section(context, '2. Kartendaten (OpenStreetMap)', Icons.download_outlined, [
      Text(hasData
          ? 'Geladen: ${_p.dataStreets} Straßen, ${_p.dataObjects} Objekte '
              '(Hotels, Schulen, Alten-/Pflegeheime, Krankenhäuser).'
          : 'Noch keine Daten. Für den Download wird einmalig Internet '
              'benötigt, danach funktioniert alles offline.'),
      if (outdated)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Gebiet oder Randbereich wurde geändert – bitte neu laden.',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      const SizedBox(height: 8),
      if (_downloading) ...[
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: 6),
        Text(_progressText ?? ''),
        const SizedBox(height: 4),
        const Text('Große Gebiete (Landkreis) können einige Minuten dauern.',
            style: TextStyle(fontSize: 12)),
      ] else ...[
        FilledButton.icon(
          onPressed: _p.areas.isEmpty ? null : _download,
          icon: const Icon(Icons.cloud_download_outlined),
          label: Text(hasData ? 'Daten neu laden' : 'Daten herunterladen'),
        ),
        const SizedBox(height: 12),
        const Text('Oder Kartendatei verwenden – z. B. an einem anderen Gerät '
            'geladen und per USB-Stick übertragen:',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _importFile,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Kartendatei laden'),
          ),
          if (hasData)
            OutlinedButton.icon(
              onPressed: _exportFile,
              icon: const Icon(Icons.save_alt),
              label: const Text('Kartendatei speichern'),
            ),
        ]),
      ],
    ]);
  }

  Widget _stationSection(BuildContext context) {
    final st = _p.station;
    return _section(context, '3. Startpunkt (Gerätehaus)', Icons.local_fire_department_outlined, [
      TextField(
        controller: _labelCtrl,
        decoration: const InputDecoration(
          labelText: 'Bezeichnung',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) {
          if (st != null) _setStation(st.lat, st.lon);
        },
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _addrCtrl,
            decoration: const InputDecoration(
              labelText: 'Adresse suchen',
              hintText: 'Straße Hausnummer, Ort',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _searchAddress(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _searching ? null : _searchAddress,
          icon: const Icon(Icons.search),
          tooltip: 'Suchen',
        ),
      ]),
      if (_addrResults != null)
        for (final r in _addrResults!)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.place_outlined),
            title: Text(r.label, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _setStation(r.lat, r.lon, r.label.split(',').first),
          ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _coordCtrl,
            decoration: const InputDecoration(
              labelText: 'oder Koordinaten',
              hintText: '50.1234, 8.5678',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _setCoords(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _setCoords,
          icon: const Icon(Icons.check),
          tooltip: 'Übernehmen',
        ),
      ]),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _pickOnMap = !_pickOnMap;
          _pickExit = false;
        }),
        icon: Icon(_pickOnMap ? Icons.close : Icons.touch_app_outlined),
        label: Text(_pickOnMap ? 'Auswahl auf Karte abbrechen' : 'Auf der Karte antippen'),
      ),
      if (_pickOnMap)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Tippe jetzt auf die Position des Gerätehauses in der Karte.'),
        ),
      const SizedBox(height: 8),
      Text(st == null
          ? 'Noch kein Startpunkt festgelegt.'
          : 'Aktuell: ${st.label} (${st.lat.toStringAsFixed(5)}, ${st.lon.toStringAsFixed(5)})'),
    ]);
  }

  Widget _exitSection(BuildContext context) {
    final st = _p.station;
    final g = widget.session.graph;
    final theme = Theme.of(context);
    return _section(context, '4. Ausfahrten des Gerätehauses', Icons.exit_to_app, [
      const Text('Optional: Lege fest, über welche Ausfahrten die Fahrzeuge '
          'das Gerätehaus verlassen. Die Hauptausfahrt wird in der Regel '
          'benutzt, Nebenausfahrten nur, wenn sie deutlich schneller sind '
          '(z. B. bei einer Sperrung).'),
      const SizedBox(height: 8),
      if (st == null || g == null)
        const Text('Zuerst Kartendaten laden und Gerätehaus festlegen.',
            style: TextStyle(fontStyle: FontStyle.italic))
      else ...[
        if (st.exits.isEmpty)
          const Text('Keine Ausfahrten festgelegt – Start an der nächsten Straße, '
              'beide Richtungen.',
              style: TextStyle(fontStyle: FontStyle.italic)),
        for (final x in st.exits)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: x.main ? theme.colorScheme.primaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconButton(
                    tooltip: x.main ? 'Hauptausfahrt' : 'Als Hauptausfahrt festlegen',
                    icon: Icon(x.main ? Icons.star : Icons.star_border,
                        color: x.main ? Colors.amber.shade800 : null),
                    onPressed: () => _setMainExit(x),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _renameExit(x),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(x.main ? 'Hauptausfahrt' : 'Nebenausfahrt',
                            style: theme.textTheme.bodySmall),
                      ]),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Entfernen',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeExit(x),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(children: [
                    const Text('Abbiegen: '),
                    const SizedBox(width: 8),
                    DropdownButton<ExitTurn>(
                      value: x.turn,
                      isDense: true,
                      items: [
                        for (final t in ExitTurn.values)
                          DropdownMenuItem(value: t, child: Text(t.label)),
                      ],
                      onChanged: (t) {
                        setState(() => x.turn = t!);
                        widget.session.save();
                      },
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _pickExit = !_pickExit;
            _pickOnMap = false;
          }),
          icon: Icon(_pickExit ? Icons.close : Icons.add_location_alt_outlined),
          label: Text(_pickExit ? 'Abbrechen' : 'Ausfahrt auf Karte antippen'),
        ),
        if (_pickExit)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Tippe in der Karte auf die Stelle, an der die Ausfahrt '
                'auf die Straße trifft. „Links/rechts“ gilt in Blickrichtung '
                'beim Herausfahren.'),
          ),
        if (st.exits.length > 1) ...[
          const SizedBox(height: 12),
          Text('Nebenausfahrt nur nutzen, wenn mindestens '
              '${st.sideExitPenaltySec} s schneller'),
          Slider(
            value: st.sideExitPenaltySec.toDouble(),
            min: 0,
            max: 180,
            divisions: 12,
            label: '${st.sideExitPenaltySec} s',
            onChanged: (v) => setState(() => st.sideExitPenaltySec = v.round()),
            onChangeEnd: (_) => widget.session.save(),
          ),
        ],
      ],
    ]);
  }
}

