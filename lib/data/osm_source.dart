import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'price_sources.dart';
import 'station.dart';

/// Petrol stations in any country from OpenStreetMap (Overpass API). They have no prices,
/// but do include brand, opening hours and fuels. Fetched in [cell]-degree cells and cached.
class OsmSource {
  OsmSource(this._client);
  final http.Client _client;

  static const cell = .2;
  static const maxCells = 20;
  static const _servers = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];

  final _cells = <String, List<Station>>{};
  bool _busy = false;

  bool get busy => _busy;

  /// Grid cells that touch the view. Null if the view is too large.
  List<(int, int)>? cellsFor(GeoBox view) {
    final x0 = (view.west / cell).floor(), x1 = (view.east / cell).floor();
    final y0 = (view.south / cell).floor(), y1 = (view.north / cell).floor();
    if ((x1 - x0 + 1) * (y1 - y0 + 1) > maxCells) return null;
    return [for (var x = x0; x <= x1; x++) for (var y = y0; y <= y1; y++) (x, y)];
  }

  bool needs(GeoBox view) => (cellsFor(view) ?? const <(int, int)>[]).any((c) => !_cells.containsKey('${c.$1}:${c.$2}'));

  Iterable<Station> stationsIn(GeoBox view) sync* {
    for (final c in cellsFor(view) ?? const <(int, int)>[]) {
      yield* (_cells['${c.$1}:${c.$2}'] ?? const <Station>[]).where((s) => view.contains(s.position));
    }
  }

  /// Downloads any missing cells. Returns true if anything was added.
  Future<bool> load(GeoBox view) async {
    final cells = cellsFor(view);
    if (cells == null || _busy) return false;
    final missing = cells.where((c) => !_cells.containsKey('${c.$1}:${c.$2}')).toList();
    if (missing.isEmpty) return false;
    _busy = true;
    try {
      final xs = missing.map((c) => c.$1), ys = missing.map((c) => c.$2);
      final box = GeoBox(ys.reduce(math.min) * cell, xs.reduce(math.min) * cell, (ys.reduce(math.max) + 1) * cell, (xs.reduce(math.max) + 1) * cell);
      final query = '[out:json][timeout:25];nwr["amenity"="fuel"](${box.south},${box.west},${box.north},${box.east});out center tags;';
      Object? error;
      for (final server in _servers) {
        try {
          final r = await _client.post(Uri.parse(server), body: {'data': query}).timeout(const Duration(seconds: 35));
          if (r.statusCode != 200) throw Exception('Overpass ${r.statusCode}');
          final stations = parseOverpass(r.bodyBytes);
          for (final c in missing) {
            final cb = GeoBox(c.$2 * cell, c.$1 * cell, (c.$2 + 1) * cell, (c.$1 + 1) * cell);
            _cells['${c.$1}:${c.$2}'] = stations.where((s) => cb.contains(s.position)).toList();
          }
          return true;
        } catch (e) {
          error = e;
        }
      }
      throw error ?? Exception('Overpass unavailable');
    } finally {
      _busy = false;
    }
  }
}

List<Station> parseOverpass(List<int> bytes) {
  final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final out = <Station>[];
  for (final e in ((json['elements'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
    final center = e['center'] is Map ? e['center'] as Map : e;
    final lat = parseNumber(center['lat']), lng = parseNumber(center['lon']);
    if (lat == null || lng == null) continue;
    final t = ((e['tags'] as Map?) ?? const {}).cast<String, dynamic>();
    final fuels = <Fuel>{
      if (t['fuel:octane_95'] == 'yes' || t['fuel:octane_91'] == 'yes' || t['fuel:octane_92'] == 'yes' || t['fuel:e10'] == 'yes') Fuel.regular,
      if (t['fuel:octane_98'] == 'yes' || t['fuel:octane_97'] == 'yes' || t['fuel:octane_100'] == 'yes') Fuel.premium,
      if (t['fuel:diesel'] == 'yes') Fuel.diesel,
      if (t['fuel:GTL_diesel'] == 'yes' || t['fuel:diesel_premium'] == 'yes') Fuel.dieselPremium,
      if (t['fuel:lpg'] == 'yes') Fuel.lpg,
    };
    final street = [t['addr:street'], t['addr:housenumber']].whereType<String>().join(' ');
    out.add(Station(
      id: 'osm:${e['type']}/${e['id']}',
      brand: '${t['brand'] ?? t['name'] ?? t['operator'] ?? ''}',
      address: street,
      town: '${t['addr:city'] ?? t['addr:place'] ?? ''}',
      region: '',
      postcode: '${t['addr:postcode'] ?? ''}',
      schedule: '${t['opening_hours'] ?? ''}',
      position: LatLng(lat, lng),
      prices: const {},
      country: '${t['addr:country'] ?? ''}',
      source: 'osm',
      fuels: fuels,
    ));
  }
  return out;
}

/// Place search via Nominatim (OpenStreetMap).
class Place {
  const Place(this.name, this.detail, this.position, this.box);
  final String name, detail;
  final LatLng position;
  final GeoBox? box;
}

Future<List<Place>> searchPlaces(http.Client client, String query, {String language = 'es'}) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {'q': query, 'format': 'jsonv2', 'limit': '6', 'accept-language': language});
  final r = await client.get(uri, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) throw Exception('Nominatim ${r.statusCode}');
  final list = (jsonDecode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>();
  return [
    for (final p in list)
      if (parseNumber(p['lat']) != null && parseNumber(p['lon']) != null)
        Place(
          '${p['name'] ?? ''}'.isNotEmpty ? '${p['name']}' : '${p['display_name']}'.split(',').first,
          '${p['display_name'] ?? ''}',
          LatLng(parseNumber(p['lat'])!, parseNumber(p['lon'])!),
          p['boundingbox'] is List && (p['boundingbox'] as List).length == 4
              ? GeoBox(parseNumber(p['boundingbox'][0])!, parseNumber(p['boundingbox'][2])!, parseNumber(p['boundingbox'][1])!, parseNumber(p['boundingbox'][3])!)
              : null,
        ),
  ];
}
