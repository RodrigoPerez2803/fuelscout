import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';

import '../data/osm_source.dart';
import '../data/price_sources.dart';
import '../data/station.dart';
import '../data/station_repository.dart';
import 'format.dart';
import 'station_sheet.dart';
import 'strings.dart';

const _madrid = LatLng(40.4168, -3.7038);
const _refreshEvery = Duration(minutes: 10);
const _maxMarkers = 160;
const _maxOsmMarkers = 140;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final t = T.current;
  final _repo = StationRepository();
  final _map = MapController();
  final _distance = const Distance();

  /// En web se puede abrir en un sitio concreto: `?lat=48.85&lng=2.35&z=13`. Entonces no se salta a la ubicación.
  static final _start = () {
    final q = Uri.base.queryParameters;
    final lat = double.tryParse(q['lat'] ?? ''), lng = double.tryParse(q['lng'] ?? '');
    if (lat == null || lng == null) return null;
    return (LatLng(lat, lng), double.tryParse(q['z'] ?? '') ?? 13.0);
  }();

  Fuel _fuel = Fuel.regular;
  LatLng? _me;
  String? _locationNote;
  bool _mapReady = false;
  GeoBox? _view;

  /// Con precio del combustible elegido, de más barata a más cara.
  List<Station> _visible = const [];

  /// Sin precio publicado (OpenStreetMap), de más cercana a más lejana.
  List<Station> _others = const [];
  String? _selectedId;

  /// Marcas que faltan en una fuente oficial (Francia) y se completan con OpenStreetMap.
  final _brandFill = <String, String>{};

  Timer? _refreshTimer, _clockTimer, _moveDebounce, _loadDebounce;
  StreamSubscription<Position>? _positionSub;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_recompute);
    _initLocation();
    _refreshTimer = Timer.periodic(_refreshEvery, (_) => _refresh(silent: true));
    // Refresca el "hace X min" del indicador de estado.
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _repo.removeListener(_recompute);
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    _moveDebounce?.cancel();
    _loadDebounce?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  // ---------- Datos ----------
  Future<void> _refresh({bool silent = false}) async {
    final changed = await _repo.refresh();
    if (!mounted) return;
    if (changed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.pricesChanged(changed, _fuel))));
    }
  }

  void _retry() {
    for (final st in _repo.states.values) {
      st.lastTry = null;
    }
    _repo.osmFailed = false;
    if (_view != null) _repo.ensure(_view!);
  }

  // ---------- Ubicación ----------
  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _locationNote = t.locationOff);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _locationNote = t.locationDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      setState(() {
        _me = LatLng(pos.latitude, pos.longitude);
        _locationNote = null;
      });
      if (_mapReady && _start == null) _map.move(_me!, 14);
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25),
      ).listen((p) {
        setState(() => _me = LatLng(p.latitude, p.longitude));
        _recompute();
      });
      _recompute();
    } catch (_) {
      if (mounted) setState(() => _locationNote = t.locationFailed);
    }
  }

  // ---------- Vista: se recalcula cada vez que se mueve el mapa ----------
  GeoBox _currentView() {
    final b = _map.camera.visibleBounds;
    return GeoBox(b.south, b.west, b.north, b.east);
  }

  void _onMapMoved() {
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 120), _recompute);
    // Las descargas esperan a que el mapa se quede quieto, para no saturar OpenStreetMap.
    _loadDebounce?.cancel();
    _loadDebounce = Timer(const Duration(milliseconds: 650), () {
      if (_mapReady) _repo.ensure(_currentView());
    });
  }

  void _recompute() {
    if (!_mapReady || !mounted) return;
    final view = _view = _currentView();
    final priced = _repo.official(view).toList();

    // Cuadrícula de ~120 m para emparejar cada gasolinera de OSM con su equivalente oficial.
    String key(int y, int x) => '$y:$x';
    final grid = <String, List<Station>>{};
    for (final s in priced) {
      (grid[key((s.position.latitude * 900).floor(), (s.position.longitude * 900).floor())] ??= []).add(s);
    }
    final others = <Station>[];
    for (final o in _repo.osm.stationsIn(view)) {
      final y = (o.position.latitude * 900).floor(), x = (o.position.longitude * 900).floor();
      Station? twin;
      for (var dy = -1; dy <= 1 && twin == null; dy++) {
        for (var dx = -1; dx <= 1 && twin == null; dx++) {
          for (final p in grid[key(y + dy, x + dx)] ?? const <Station>[]) {
            if (_distance.as(LengthUnit.Meter, p.position, o.position) < 150) {
              twin = p;
              break;
            }
          }
        }
      }
      if (twin != null) {
        if (twin.brand.isEmpty && o.brand.isNotEmpty) _brandFill[twin.id] = o.brand;
      } else if (o.fuels.isEmpty || o.fuels.contains(_fuel)) {
        others.add(o);
      }
    }
    final from = _me ?? _map.camera.center;
    double dist(Station s) => _distance.as(LengthUnit.Meter, from, s.position);
    final withFuel = [
      for (final s in priced)
        if (s.prices.containsKey(_fuel)) _brandFill[s.id] != null && s.brand.isEmpty ? s.copyWith(brand: _brandFill[s.id]) : s,
    ]..sort((a, b) {
        final byPrice = a.prices[_fuel]!.compareTo(b.prices[_fuel]!);
        return byPrice != 0 ? byPrice : dist(a).compareTo(dist(b));
      });
    others.sort((a, b) => dist(a).compareTo(dist(b)));
    setState(() {
      _visible = withFuel;
      _others = others;
    });
  }

  double? _distanceTo(Station s) => _me == null ? null : _distance.as(LengthUnit.Meter, _me!, s.position);

  ({double min, double max}) get _range {
    if (_visible.isEmpty) return (min: 0, max: 0);
    return (min: _visible.first.prices[_fuel]!, max: _visible.last.prices[_fuel]!);
  }

  double? _change(Station s) {
    final was = _repo.previous[s.id]?[_fuel], now = s.prices[_fuel];
    if (was == null || now == null || (was - now).abs() < .0005) return null;
    return now - was;
  }

  // ---------- Acciones ----------
  void _openStation(Station s) {
    setState(() => _selectedId = s.id);
    _map.move(s.position, math.max(_map.camera.zoom, 15));
    final rank = _visible.indexWhere((v) => v.id == s.id);
    final src = _repo.sourceOf(s);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StationSheet(
        station: s,
        fuel: _fuel,
        distance: _distanceTo(s),
        rank: rank < 0 ? null : rank + 1,
        total: _visible.length,
        change: _change(s),
        publisher: src?.publisher,
        updatedAt: s.updatedAt ?? _repo.snapshotOf(s)?.publishedAt,
        onDirections: () => _launch('https://www.google.com/maps/dir/?api=1&destination='
            '${s.position.latitude},${s.position.longitude}&travelmode=driving'),
        onWaze: () => _launch('https://waze.com/ul?ll=${s.position.latitude},${s.position.longitude}&navigate=yes'),
      ),
    );
  }

  Future<void> _launch(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.navFailed)));
  }

  void _goToMe() {
    if (_me != null) {
      _map.move(_me!, 14);
    } else {
      _initLocation();
    }
  }

  void _goToPlace(Place p) {
    final b = p.box;
    if (b != null && (b.north - b.south) > .005) {
      // Las ciudades enteras se encuadran con un tope de zoom para que se vean gasolineras.
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(LatLng(b.south, b.west), LatLng(b.north, b.east)),
        padding: const EdgeInsets.all(40),
        maxZoom: 15,
        minZoom: 11,
      ));
    } else {
      _map.move(p.position, 15);
    }
    _onMapMoved();
  }

  // ---------- Interfaz ----------
  @override
  Widget build(BuildContext context) {
    final range = _range;
    final currency = _visible.isEmpty ? 'EUR' : _visible.first.currency;
    final zoom = _mapReady ? _map.camera.zoom : 13.0;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _start?.$1 ?? _me ?? _madrid,
              initialZoom: _start?.$2 ?? 13,
              minZoom: 3,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onMapReady: () {
                _mapReady = true;
                if (_me != null && _start == null) _map.move(_me!, 14);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _recompute();
                  _repo.ensure(_currentView());
                });
              },
              onPositionChanged: (_, _) => _onMapMoved(),
              onTap: (_, _) => setState(() => _selectedId = null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rodrigoperez.gasolineras',
                maxZoom: 19,
              ),
              if (_me != null) MarkerLayer(markers: [Marker(point: _me!, width: 26, height: 26, child: const _MeDot())]),
              if (zoom >= 11)
                MarkerLayer(markers: [
                  for (final s in _others.take(_maxOsmMarkers))
                    Marker(
                      point: s.position,
                      width: 30,
                      height: 30,
                      child: _OsmPin(selected: s.id == _selectedId, onTap: () => _openStation(s)),
                    ),
                ]),
              MarkerLayer(
                markers: [
                  for (final s in _markerStations())
                    Marker(
                      point: s.position,
                      width: 84,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: _PricePin(
                        price: s.prices[_fuel]!,
                        currency: s.currency,
                        color: tierColor(s.prices[_fuel]!, range.min, range.max),
                        cheapest: _visible.isNotEmpty && s.id == _visible.first.id,
                        selected: s.id == _selectedId,
                        onTap: () => _openStation(s),
                      ),
                    ),
                ],
              ),
            ],
          ),
          _TopBar(
            fuel: _fuel,
            onFuel: (f) {
              setState(() => _fuel = f);
              _recompute();
            },
            status: _status(),
            busy: _repo.anyLoading,
            error: _errorText(),
            locationNote: _locationNote,
            onRetry: _retry,
            client: _repo,
            onPlace: _goToPlace,
          ),
          Positioned(
            right: 14,
            bottom: MediaQuery.sizeOf(context).height * .24 + 12,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'refresh',
                  tooltip: t.refresh,
                  onPressed: _repo.anyLoading ? null : () => _refresh(),
                  child: _repo.anyLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(heroTag: 'me', tooltip: t.myLocation, onPressed: _goToMe, child: const Icon(Icons.my_location)),
              ],
            ),
          ),
          _ResultsSheet(
            stations: _visible,
            others: _others,
            fuel: _fuel,
            range: range,
            currency: currency,
            ready: _view != null,
            distanceTo: _distanceTo,
            changeOf: _change,
            onTap: _openStation,
            credits: [for (final s in officialSources) s.publisher],
          ),
        ],
      ),
    );
  }

  String _status() {
    final view = _view;
    if (view == null) return t.loading;
    final srcs = _repo.sourcesFor(view);
    final loading = [for (final s in srcs) if (_repo.states[s.id]!.loading) t.country(s.country)];
    if (loading.isNotEmpty) return t.loadingSources(loading);
    final loaded = [for (final s in srcs) if (_repo.states[s.id]!.snapshot != null) s];
    if (loaded.isNotEmpty) {
      final snaps = loaded.map((s) => _repo.states[s.id]!.snapshot!);
      final published = snaps.map((s) => s.publishedAt).reduce((a, b) => a.isAfter(b) ? a : b);
      final fetched = snaps.map((s) => s.fetchedAt).reduce((a, b) => a.isBefore(b) ? a : b);
      return t.officialPrices([for (final s in loaded) t.country(s.country)], formatClock(published), t.checked(timeAgo(fetched)));
    }
    if (_repo.osmTooWide) return t.zoomIn;
    if (_repo.osmLoading) return t.osmLoading;
    return t.noOfficialHere;
  }

  String? _errorText() {
    final view = _view;
    if (view == null) return null;
    final srcs = _repo.sourcesFor(view);
    if (srcs.any((s) => _repo.states[s.id]!.error != null && _repo.states[s.id]!.snapshot == null)) return t.pricesError;
    if (_repo.osmFailed && srcs.isEmpty) return t.osmError;
    return null;
  }

  /// Con mucho zoom se ven todas; alejado, solo las más baratas para que el mapa siga legible.
  List<Station> _markerStations() {
    final list = _visible.take(_maxMarkers).toList();
    if (_selectedId != null && !list.any((s) => s.id == _selectedId)) list.addAll(_visible.where((s) => s.id == _selectedId));
    // Las más baratas se dibujan encima.
    return list.reversed.toList();
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2F7BF6),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x552F7BF6), blurRadius: 12, spreadRadius: 4)],
        ),
      );
}

class _OsmPin extends StatelessWidget {
  const _OsmPin({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF14202B) : unknownColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 5, offset: Offset(0, 2))],
          ),
          child: const Icon(Icons.local_gas_station_rounded, size: 15, color: Colors.white),
        ),
      );
}

class _PricePin extends StatelessWidget {
  const _PricePin({required this.price, required this.currency, required this.color, required this.cheapest, required this.selected, required this.onTap});

  final double price;
  final String currency;
  final Color color;
  final bool cheapest, selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF14202B) : color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.18 : 1,
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (cheapest) const Padding(padding: EdgeInsets.only(right: 3), child: Icon(Icons.star_rounded, size: 13, color: Colors.white)),
                Text(formatPrice(price, currency).replaceAll(' ', ''),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ]),
            ),
            CustomPaint(size: const Size(12, 7), painter: _TrianglePainter(bg)),
          ],
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

class _TopBar extends StatefulWidget {
  const _TopBar({
    required this.fuel,
    required this.onFuel,
    required this.status,
    required this.busy,
    required this.error,
    required this.locationNote,
    required this.onRetry,
    required this.client,
    required this.onPlace,
  });

  final Fuel fuel;
  final ValueChanged<Fuel> onFuel;
  final String status;
  final bool busy;
  final String? error, locationNote;
  final VoidCallback onRetry;
  final StationRepository client;
  final ValueChanged<Place> onPlace;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  List<Place>? _results;
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _run(String q) async {
    if (q.trim().length < 2) return;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final r = await searchPlaces(widget.client.client, q.trim(), language: T.current.lang);
      if (mounted) setState(() => _results = r);
    } catch (_) {
      if (mounted) setState(() => _searchError = T.current.searchError);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(Place p) {
    _focus.unfocus();
    setState(() => _results = null);
    widget.onPlace(p);
  }

  @override
  Widget build(BuildContext context) {
    final t = T.current;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(18),
                  color: scheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.local_gas_station_rounded, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(t.appName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(t.tagline, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                        ]),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _search,
                          focusNode: _focus,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _run,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: t.searchHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searching
                                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                                : (_search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () => setState(() {
                                          _search.clear();
                                          _results = null;
                                        }),
                                      )),
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_results != null || _searchError != null) ...[
                          const SizedBox(height: 6),
                          if (_searchError != null) Padding(padding: const EdgeInsets.all(8), child: Text(_searchError!)),
                          if (_results != null && _results!.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(t.noResults)),
                          for (final p in _results ?? const <Place>[])
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                              leading: const Icon(Icons.place_outlined),
                              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(p.detail, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => _pick(p),
                            ),
                        ],
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            for (final f in Fuel.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(t.fuel(f)),
                                  selected: f == widget.fuel,
                                  onSelected: (_) => widget.onFuel(f),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          if (widget.busy)
                            const Padding(padding: EdgeInsets.only(right: 6), child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6)))
                          else
                            Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 7), decoration: const BoxDecoration(color: cheapColor, shape: BoxShape.circle)),
                          Expanded(child: Text(widget.status, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ]),
                      ],
                    ),
                  ),
                ),
                if (widget.error != null) _Banner(text: widget.error!, icon: Icons.wifi_off_rounded, action: t.retry, onAction: widget.onRetry),
                if (widget.locationNote != null) _Banner(text: widget.locationNote!, icon: Icons.location_off_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.icon, this.action, this.onAction});
  final String text;
  final IconData icon;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(14),
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
              if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
            ]),
          ),
        ),
      );
}

class _ResultsSheet extends StatelessWidget {
  const _ResultsSheet({
    required this.stations,
    required this.others,
    required this.fuel,
    required this.range,
    required this.currency,
    required this.ready,
    required this.distanceTo,
    required this.changeOf,
    required this.onTap,
    required this.credits,
  });

  final List<Station> stations, others;
  final Fuel fuel;
  final ({double min, double max}) range;
  final String currency;
  final bool ready;
  final double? Function(Station) distanceTo;
  final double? Function(Station) changeOf;
  final ValueChanged<Station> onTap;
  final List<String> credits;

  @override
  Widget build(BuildContext context) {
    final t = T.current;
    final theme = Theme.of(context);
    final title = !ready
        ? t.loading
        : stations.isEmpty
            ? (others.isEmpty ? t.noneWithFuel(fuel) : t.otherStations(others.length))
            : t.countHere(stations.length);
    final subtitle = stations.isEmpty
        ? t.moveMap
        : t.cheapestRange(formatPrice(range.min, currency), formatPrice(range.max, currency)) + (stations.length > _maxMarkers ? t.zoomForAll : '');
    final shownOthers = others.take(200).toList();
    return DraggableScrollableSheet(
      initialChildSize: .24,
      minChildSize: .12,
      maxChildSize: .86,
      snap: true,
      snapSizes: const [.24, .55],
      builder: (context, controller) => Material(
        elevation: 10,
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(4)))),
                  const SizedBox(height: 12),
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ]),
              ),
            ),
            SliverList.builder(
              itemCount: stations.length,
              itemBuilder: (context, i) {
                final s = stations[i];
                final price = s.prices[fuel]!;
                final d = distanceTo(s);
                final change = changeOf(s);
                final color = tierColor(price, range.min, range.max);
                return ListTile(
                  onTap: () => onTap(s),
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: .15),
                    foregroundColor: color,
                    child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  title: Text(s.brand.isEmpty ? t.station : s.brand, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([if (d != null) formatDistance(d), s.address, s.town].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatPrice(price, s.currency), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      if (change != null)
                        Text('${change < 0 ? '▼' : '▲'} ${formatCents(change)}',
                            style: TextStyle(fontSize: 11, color: change < 0 ? cheapColor : expensiveColor, fontWeight: FontWeight.w700)),
                    ],
                  ),
                );
              },
            ),
            if (stations.isNotEmpty && shownOthers.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                  child: Text(t.otherStations(others.length), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            SliverList.builder(
              itemCount: shownOthers.length,
              itemBuilder: (context, i) {
                final s = shownOthers[i];
                final d = distanceTo(s);
                return ListTile(
                  onTap: () => onTap(s),
                  leading: CircleAvatar(
                    backgroundColor: unknownColor.withValues(alpha: .15),
                    foregroundColor: unknownColor,
                    child: const Icon(Icons.local_gas_station_rounded, size: 20),
                  ),
                  title: Text(s.brand.isEmpty ? t.station : s.brand, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([if (d != null) formatDistance(d), s.address, s.town].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(t.noPrice, style: theme.textTheme.bodySmall),
                );
              },
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: Text('${t.mapCredit} · ${t.sourcesCredit(credits)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
