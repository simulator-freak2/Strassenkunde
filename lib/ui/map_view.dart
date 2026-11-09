import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../core/road_graph.dart';

class MapRoute {
  final List<int> directedEdges;
  final Color color;
  final double width;
  const MapRoute(this.directedEdges, this.color, {this.width = 6});
}

class MapMarker {
  final double lat, lon;
  final Color color;
  final String label;
  final IconData icon;
  const MapMarker(this.lat, this.lon, this.color, this.label, this.icon);
}

/// Offline-Kartenansicht: zeichnet das Straßennetz direkt aus den
/// geladenen Daten (keine Kartenkacheln nötig).
class MapView extends StatefulWidget {
  final RoadGraph? graph;
  final List<List<double>> areaRings;
  final List<MapRoute> routes;
  final Set<int> closedEdges;
  final List<MapMarker> markers;
  final bool showNames;
  final bool tapForNames;

  /// Ändert sich dieser Wert, wird der Kartenausschnitt neu eingepasst.
  final Object? fitKey;

  /// Optionaler Ausschnitt, auf den eingepasst wird (sonst gesamtes Gebiet).
  final BBox? fitBox;
  final void Function(double lat, double lon)? onTap;

  const MapView({
    super.key,
    this.graph,
    this.areaRings = const [],
    this.routes = const [],
    this.closedEdges = const {},
    this.markers = const [],
    this.showNames = false,
    this.tapForNames = false,
    this.fitKey,
    this.fitBox,
    this.onTap,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _Projection {
  final double lat0, lon0, kx, ky;
  _Projection(this.lat0, this.lon0)
      : kx = math.cos(lat0 * math.pi / 180) * 111320.0,
        ky = 110540.0;
  Offset toWorld(double lat, double lon) =>
      Offset((lon - lon0) * kx, -(lat - lat0) * ky);
  (double, double) toLatLon(Offset w) => (lat0 - w.dy / ky, lon0 + w.dx / kx);
}

/// Vorberechnete Pfade je Kachel und Straßenklasse.
class _RoadCache {
  static final _cache = Expando<_RoadCache>();
  static const tileM = 1500.0;
  final _Projection proj;
  final Map<int, List<Path?>> tiles = {};
  final Map<int, Rect> tileBounds = {};

  _RoadCache(RoadGraph g, this.proj) {
    for (var e = 0; e < g.edgeCount; e++) {
      final s = g.eGeomStart[e], t = g.eGeomStart[e + 1];
      final first = proj.toWorld(g.gLat[s], g.gLon[s]);
      final key = _tileKey(first);
      final group = _group(RoadClass.values[g.eCls[e]]);
      final paths = tiles.putIfAbsent(key, () => List<Path?>.filled(4, null));
      final path = paths[group] ??= Path();
      path.moveTo(first.dx, first.dy);
      var bounds = tileBounds[key] ?? Rect.fromLTWH(first.dx, first.dy, 0, 0);
      for (var k = s + 1; k < t; k++) {
        final w = proj.toWorld(g.gLat[k], g.gLon[k]);
        path.lineTo(w.dx, w.dy);
        bounds = bounds.expandToInclude(Rect.fromLTWH(w.dx, w.dy, 0, 0));
      }
      tileBounds[key] = bounds;
    }
  }

  static _RoadCache of(RoadGraph g, _Projection proj) =>
      _cache[g] ??= _RoadCache(g, proj);

  static int _tileKey(Offset w) {
    final x = (w.dx / tileM).floor() + 50000;
    final y = (w.dy / tileM).floor() + 50000;
    return x * 100000 + y;
  }

  /// 0 = Hauptstraßen, 1 = Verbindungsstraßen, 2 = Wohnstraßen, 3 = Zufahrten
  static int _group(RoadClass c) => switch (c) {
        RoadClass.motorway ||
        RoadClass.trunk ||
        RoadClass.primary ||
        RoadClass.motorwayLink ||
        RoadClass.trunkLink ||
        RoadClass.primaryLink =>
          0,
        RoadClass.secondary ||
        RoadClass.tertiary ||
        RoadClass.secondaryLink ||
        RoadClass.tertiaryLink =>
          1,
        RoadClass.service => 3,
        _ => 2,
      };
}

class _MapViewState extends State<MapView> {
  _Projection? _proj;
  double _scale = 0.1; // Pixel pro Meter
  Offset _offset = Offset.zero;
  Size _size = Size.zero;
  Object? _fittedFor;
  bool _fitted = false;
  double _startScale = 1;
  Offset _startFocal = Offset.zero;
  Offset _startOffset = Offset.zero;
  String? _tapLabel;
  Offset? _tapPos;

  _Projection _projection() {
    if (_proj != null) return _proj!;
    // Mit Straßennetz immer dessen Mitte verwenden (die gezeichneten Pfade
    // werden pro Karte zwischengespeichert).
    final box = widget.graph?.bbox ?? _contentBox();
    final lat0 = box.isEmpty ? 50.0 : (box.north + box.south) / 2;
    final lon0 = box.isEmpty ? 8.0 : (box.east + box.west) / 2;
    return _proj = _Projection(lat0, lon0);
  }

  BBox _contentBox() {
    final b = BBox.empty();
    for (final r in widget.areaRings) {
      for (var i = 0; i + 1 < r.length; i += 2) {
        b.extend(r[i], r[i + 1]);
      }
    }
    if (b.isEmpty && widget.graph != null) return widget.graph!.bbox;
    for (final m in widget.markers) {
      b.extend(m.lat, m.lon);
    }
    return b;
  }

  @override
  void didUpdateWidget(covariant MapView old) {
    super.didUpdateWidget(old);
    if (old.graph != widget.graph ||
        (widget.graph == null && old.areaRings != widget.areaRings)) {
      _proj = null;
      _fitted = false;
    }
    if (old.fitKey != widget.fitKey) _fitted = false;
  }

  void _fit() {
    if (_size.isEmpty) return;
    final proj = _projection();
    final box = widget.fitBox ?? _contentBox();
    if (box.isEmpty) return;
    final a = proj.toWorld(box.north, box.west);
    final b = proj.toWorld(box.south, box.east);
    final w = math.max((b.dx - a.dx).abs(), 100.0);
    final h = math.max((b.dy - a.dy).abs(), 100.0);
    _scale = math.min(_size.width / w, _size.height / h) * 0.9;
    final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    _offset = Offset(_size.width / 2, _size.height / 2) - center * _scale;
    _fitted = true;
    _fittedFor = widget.fitKey;
  }

  void _zoomAt(Offset focal, double factor) {
    final newScale = (_scale * factor).clamp(0.002, 20.0);
    final world = (focal - _offset) / _scale;
    setState(() {
      _scale = newScale;
      _offset = focal - world * _scale;
    });
  }

  void _handleTap(Offset pos) {
    final proj = _projection();
    final (lat, lon) = proj.toLatLon((pos - _offset) / _scale);
    widget.onTap?.call(lat, lon);
    if (widget.tapForNames && widget.graph != null) {
      final e = widget.graph!.nearestEdge(lat, lon);
      setState(() {
        _tapLabel = e >= 0 ? (widget.graph!.label(e) ?? 'namenlose Straße') : null;
        _tapPos = pos;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      if (size != _size) {
        _size = size;
        if (!_fitted) _fit();
      }
      if (!_fitted || _fittedFor != widget.fitKey) _fit();
      return ClipRect(
        child: Stack(children: [
          Listener(
            onPointerSignal: (ev) {
              if (ev is PointerScrollEvent) {
                _zoomAt(ev.localPosition, ev.scrollDelta.dy > 0 ? 1 / 1.2 : 1.2);
              }
            },
            child: GestureDetector(
              onScaleStart: (d) {
                _startScale = _scale;
                _startFocal = d.localFocalPoint;
                _startOffset = _offset;
              },
              onScaleUpdate: (d) {
                setState(() {
                  final newScale = (_startScale * d.scale).clamp(0.002, 20.0);
                  final world = (_startFocal - _startOffset) / _startScale;
                  _scale = newScale;
                  _offset = d.localFocalPoint - world * newScale;
                });
              },
              onTapUp: (d) => _handleTap(d.localPosition),
              onDoubleTapDown: (d) => _zoomAt(d.localPosition, 2),
              onDoubleTap: () {},
              child: CustomPaint(
                size: size,
                painter: _MapPainter(
                  graph: widget.graph,
                  proj: _projection(),
                  scale: _scale,
                  offset: _offset,
                  areaRings: widget.areaRings,
                  routes: widget.routes,
                  closed: widget.closedEdges,
                  markers: widget.markers,
                  showNames: widget.showNames,
                  dark: dark,
                ),
              ),
            ),
          ),
          if (_tapLabel != null && _tapPos != null)
            Positioned(
              left: (_tapPos!.dx + 8).clamp(0, math.max(0, size.width - 200)),
              top: (_tapPos!.dy - 36).clamp(0, math.max(0, size.height - 40)),
              child: GestureDetector(
                onTap: () => setState(() => _tapLabel = null),
                child: Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(6),
                  color: Theme.of(context).colorScheme.inverseSurface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(_tapLabel!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onInverseSurface)),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Column(children: [
              _MapButton(Icons.add, () => _zoomAt(size.center(Offset.zero), 1.5)),
              const SizedBox(height: 6),
              _MapButton(Icons.remove, () => _zoomAt(size.center(Offset.zero), 1 / 1.5)),
              const SizedBox(height: 6),
              _MapButton(Icons.fit_screen, () => setState(_fit)),
            ]),
          ),
          Positioned(
            left: 6,
            bottom: 4,
            child: Text('© OpenStreetMap-Mitwirkende',
                style: TextStyle(fontSize: 10, color: dark ? Colors.white54 : Colors.black54)),
          ),
        ]),
      );
    });
  }
}

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapButton(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => Material(
        elevation: 2,
        shape: const CircleBorder(),
        color: Theme.of(context).colorScheme.surface,
        child: IconButton(icon: Icon(icon), onPressed: onTap, iconSize: 20),
      );
}

class _MapPainter extends CustomPainter {
  final RoadGraph? graph;
  final _Projection proj;
  final double scale;
  final Offset offset;
  final List<List<double>> areaRings;
  final List<MapRoute> routes;
  final Set<int> closed;
  final List<MapMarker> markers;
  final bool showNames;
  final bool dark;

  _MapPainter({
    required this.graph,
    required this.proj,
    required this.scale,
    required this.offset,
    required this.areaRings,
    required this.routes,
    required this.closed,
    required this.markers,
    required this.showNames,
    required this.dark,
  });

  Offset _screen(double lat, double lon) => proj.toWorld(lat, lon) * scale + offset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size,
        Paint()..color = dark ? const Color(0xFF1E2124) : const Color(0xFFF2EFE9));
    final viewWorld = Rect.fromLTWH(-offset.dx / scale, -offset.dy / scale,
        size.width / scale, size.height / scale);

    // Gebietsgrenze
    final areaPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.deepPurple.withValues(alpha: 0.7);
    final areaFill = Paint()
      ..color = Colors.deepPurple.withValues(alpha: dark ? 0.10 : 0.05);
    final areaPath = Path()..fillType = PathFillType.evenOdd;
    for (final r in areaRings) {
      for (var i = 0; i + 1 < r.length; i += 2) {
        final p = _screen(r[i], r[i + 1]);
        if (i == 0) {
          areaPath.moveTo(p.dx, p.dy);
        } else {
          areaPath.lineTo(p.dx, p.dy);
        }
      }
      areaPath.close();
    }
    canvas.drawPath(areaPath, areaFill);
    canvas.drawPath(areaPath, areaPaint);

    final g = graph;
    if (g != null) {
      final cache = _RoadCache.of(g, proj);
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.scale(scale);
      final colors = dark
          ? const [Color(0xFFE0A050), Color(0xFFC8B060), Color(0xFF8A8F96), Color(0xFF5A5F66)]
          : const [Color(0xFFE8923A), Color(0xFFF2D46B), Color(0xFFFFFFFF), Color(0xFFFFFFFF)];
      final widths = [5.0, 4.0, 3.0, 1.8];
      final casing = dark ? const Color(0xFF101214) : const Color(0xFFB9B4AA);
      final visibleGroups = <int>[
        if (scale > 0.12) 3,
        if (scale > 0.025) 2,
        1,
        0,
      ];
      final margin = 300.0;
      final view = viewWorld.inflate(margin);
      for (final pass in [0, 1]) {
        for (final grp in visibleGroups) {
          final px = widths[grp] * (scale > 0.5 ? 1.6 : (scale > 0.15 ? 1.2 : 0.8));
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
          if (pass == 0) {
            if (scale < 0.08) continue; // Ränder nur bei Nahansicht
            paint
              ..color = casing
              ..strokeWidth = (px + 1.6) / scale;
          } else {
            paint
              ..color = colors[grp]
              ..strokeWidth = px / scale;
          }
          cache.tiles.forEach((key, paths) {
            final path = paths[grp];
            if (path == null) return;
            if (!cache.tileBounds[key]!.overlaps(view)) return;
            canvas.drawPath(path, paint);
          });
        }
      }
      canvas.restore();

      // Sperrungen
      if (closed.isNotEmpty) {
        final cp = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = Colors.red.shade700;
        for (final e in closed) {
          canvas.drawPath(_edgePath(g, e * 2), cp);
        }
        for (final e in closed) {
          final (la, lo) = g.edgeMid(e);
          final p = _screen(la, lo);
          canvas.drawCircle(p, 9, Paint()..color = Colors.white);
          canvas.drawCircle(p, 9, Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = Colors.red.shade700);
          final bar = Paint()
            ..strokeWidth = 3
            ..color = Colors.red.shade700;
          canvas.drawLine(p + const Offset(-5, 0), p + const Offset(5, 0), bar);
        }
      }

      // Routen
      for (final r in routes) {
        final path = Path();
        for (final d in r.directedEdges) {
          path.addPath(_edgePath(g, d), Offset.zero);
        }
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r.width
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = r.color);
      }

      if (showNames && scale > 0.35) _drawLabels(canvas, size, g, viewWorld);
    }

    // Markierungen
    for (final m in markers) {
      final p = _screen(m.lat, m.lon);
      canvas.drawCircle(p, 13, Paint()..color = Colors.white);
      canvas.drawCircle(p, 11, Paint()..color = m.color);
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(m.icon.codePoint),
          style: TextStyle(
              fontSize: 15,
              fontFamily: m.icon.fontFamily,
              package: m.icon.fontPackage,
              color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      if (m.label.isNotEmpty) {
        final lp = TextPainter(
          text: TextSpan(
              text: m.label,
              style: const TextStyle(
                  fontSize: 12, color: Colors.black, fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: 220);
        final r = Rect.fromLTWH(p.dx + 15, p.dy - lp.height / 2 - 3,
            lp.width + 10, lp.height + 6);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
            Paint()..color = Colors.white.withValues(alpha: 0.9));
        lp.paint(canvas, Offset(r.left + 5, r.top + 3));
      }
    }
  }

  Path _edgePath(RoadGraph g, int d) {
    final e = d >> 1;
    final s = g.eGeomStart[e], t = g.eGeomStart[e + 1];
    final path = Path();
    final fwd = (d & 1) == 0;
    for (var i = 0; i < t - s; i++) {
      final k = fwd ? s + i : t - 1 - i;
      final p = _screen(g.gLat[k], g.gLon[k]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path;
  }

  void _drawLabels(Canvas canvas, Size size, RoadGraph g, Rect viewWorld) {
    final placed = <Rect>[];
    final screenRect = Offset.zero & size;
    var count = 0;
    final style = TextStyle(
      fontSize: 11,
      color: dark ? Colors.white : const Color(0xFF333333),
      fontWeight: FontWeight.w500,
      shadows: [
        Shadow(color: dark ? Colors.black : Colors.white, blurRadius: 3),
        Shadow(color: dark ? Colors.black : Colors.white, blurRadius: 3),
      ],
    );
    final seenNear = <String, List<Offset>>{};
    for (var e = 0; e < g.edgeCount && count < 250; e++) {
      final label = g.label(e);
      if (label == null) continue;
      final (mla, mlo) = g.edgeMid(e);
      if (!viewWorld.contains(proj.toWorld(mla, mlo))) continue;
      final s = g.eGeomStart[e], t = g.eGeomStart[e + 1];
      // längstes Teilstück der Kante
      var bestLen = 0.0;
      Offset? a, b;
      for (var k = s; k + 1 < t; k++) {
        final p1 = _screen(g.gLat[k], g.gLon[k]);
        final p2 = _screen(g.gLat[k + 1], g.gLon[k + 1]);
        final len = (p2 - p1).distance;
        if (len > bestLen) {
          bestLen = len;
          a = p1;
          b = p2;
        }
      }
      if (a == null || b == null) continue;
      final mid = (a + b) / 2;
      if (!screenRect.contains(mid)) continue;
      final prev = seenNear[label];
      if (prev != null && prev.any((o) => (o - mid).distance < 220)) continue;
      final tp = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr)
        ..layout();
      if (tp.width + 8 > bestLen) continue;
      final r = Rect.fromCenter(center: mid, width: tp.width, height: tp.height);
      if (placed.any((x) => x.overlaps(r))) continue;
      placed.add(r);
      (seenNear[label] ??= []).add(mid);
      var angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      if (angle > math.pi / 2) angle -= math.pi;
      if (angle < -math.pi / 2) angle += math.pi;
      canvas.save();
      canvas.translate(mid.dx, mid.dy);
      canvas.rotate(angle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      count++;
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}
