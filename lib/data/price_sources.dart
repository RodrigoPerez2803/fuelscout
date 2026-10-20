import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'station.dart';

/// Simple geographic bounding box (degrees).
class GeoBox {
  const GeoBox(this.south, this.west, this.north, this.east);
  final double south, west, north, east;

  bool intersects(GeoBox o) => !(o.west > east || o.east < west || o.south > north || o.north < south);
  bool contains(LatLng p) => p.latitude >= south && p.latitude <= north && p.longitude >= west && p.longitude <= east;
}

class PriceSnapshot {
  const PriceSnapshot({required this.stations, required this.publishedAt, required this.fetchedAt});
  final List<Station> stations;
  final DateTime publishedAt;
  final DateTime fetchedAt;
}

/// A country's official price source. Only downloaded when the map is looking at its area.
abstract class PriceSource {
  const PriceSource();
  String get id;
  String get country;

  /// Name of the body that publishes the data, for attribution.
  String get publisher;
  List<GeoBox> get coverage;
  Future<PriceSnapshot> fetch(http.Client client);

  bool covers(GeoBox view) => coverage.any((b) => b.intersects(view));
}

const officialSources = <PriceSource>[SpainSource(), FranceSource(), PortugalSource()];

/// Addresses that arrive in capitals are converted to title case; anything else is left as is.
String _tidy(Object? raw) {
  final text = (raw ?? '').toString().trim();
  return text == text.toUpperCase() ? titleCase(text) : text;
}

Future<List<int>> _get(http.Client client, String url, {Duration timeout = const Duration(seconds: 60)}) async {
  final response = await client.get(Uri.parse(url), headers: const {'Accept': 'application/json'}).timeout(timeout);
  if (response.statusCode != 200) throw Exception('$url responded with ${response.statusCode}');
  return response.bodyBytes;
}

// ---------- Spain: Ministry for the Ecological Transition (MITECO) ----------
class SpainSource extends PriceSource {
  const SpainSource();
  @override
  String get id => 'es';
  @override
  String get country => 'ES';
  @override
  String get publisher => 'Ministerio para la Transición Ecológica (España)';
  @override
  /// The mainland minus Portugal, then Galicia, the Balearic Islands, the Canary Islands and Ceuta/Melilla.
  List<GeoBox> get coverage => const [
        GeoBox(35.9, -7.55, 43.85, 3.35), GeoBox(41.8, -9.35, 43.8, -7.5), GeoBox(38.6, 1.1, 40.1, 4.4),
        GeoBox(27.5, -18.3, 29.5, -13.3), GeoBox(35.1, -5.45, 35.95, -2.9),
      ];

  static const endpoint =
      'https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/';

  @override
  Future<PriceSnapshot> fetch(http.Client client) async {
    // It's ~12 MB of JSON, so it's parsed off the UI thread (on the web, compute doesn't use an isolate).
    return compute(parseSpain, await _get(client, endpoint));
  }
}

const spainFields = {
  Fuel.regular: 'Precio Gasolina 95 E5',
  Fuel.premium: 'Precio Gasolina 98 E5',
  Fuel.diesel: 'Precio Gasoleo A',
  Fuel.dieselPremium: 'Precio Gasoleo Premium',
  Fuel.lpg: 'Precio Gases licuados del petróleo',
};

/// Converts one `ListaEESSPrecio` entry. Returns null if it has no valid coordinates.
Station? spainStation(Map<String, dynamic> json, {DateTime? publishedAt}) {
  final lat = parseNumber(json['Latitud']);
  final lng = parseNumber(json['Longitud (WGS84)']);
  if (lat == null || lng == null) return null;
  final prices = <Fuel, double>{};
  spainFields.forEach((fuel, field) {
    final value = parseNumber(json[field]);
    if (value != null && value > 0) prices[fuel] = value;
  });
  return Station(
    id: 'es:${json['IDEESS']}',
    brand: titleCase('${json['Rótulo'] ?? ''}'),
    address: titleCase('${json['Dirección'] ?? ''}'),
    town: titleCase('${json['Municipio'] ?? json['Localidad'] ?? ''}'),
    region: titleCase('${json['Provincia'] ?? ''}'),
    postcode: '${json['C.P.'] ?? ''}',
    schedule: '${json['Horario'] ?? ''}',
    position: LatLng(lat, lng),
    prices: prices,
    country: 'ES',
    source: 'es',
    updatedAt: publishedAt,
  );
}

PriceSnapshot parseSpain(List<int> bytes) {
  final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  final published = parseSpainDate('${json['Fecha']}') ?? DateTime.now();
  final stations = <Station>[];
  for (final item in (json['ListaEESSPrecio'] as List).cast<Map<String, dynamic>>()) {
    final s = spainStation(item, publishedAt: published);
    if (s != null && s.hasPrices) stations.add(s);
  }
  return PriceSnapshot(stations: stations, publishedAt: published, fetchedAt: DateTime.now());
}

/// Date format used by the Spanish API: "17/10/2026 13:39:53".
DateTime? parseSpainDate(String text) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2}):(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  int p(int i) => int.parse(m[i]!);
  return DateTime(p(3), p(2), p(1), p(4), p(5), p(6));
}

// ---------- France: prix-carburants (data.economie.gouv.fr) ----------
class FranceSource extends PriceSource {
  const FranceSource();
  @override
  String get id => 'fr';
  @override
  String get country => 'FR';
  @override
  String get publisher => 'Ministère de l’Économie (France), prix-carburants';
  @override
  /// Mainland France and Corsica.
  List<GeoBox> get coverage => const [GeoBox(42.3, -5.2, 51.2, 8.3), GeoBox(41.3, 8.5, 43.1, 9.6)];

  static const endpoint = 'https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/'
      'prix-des-carburants-en-france-flux-instantane-v2/exports/json'
      '?select=id,geom,adresse,ville,cp,gazole_prix,sp95_prix,e10_prix,sp98_prix,gplc_prix,'
      'horaires_automate_24_24,gazole_maj,e10_maj,sp95_maj,sp98_maj';

  @override
  Future<PriceSnapshot> fetch(http.Client client) async => compute(parseFrance, await _get(client, endpoint));
}

Station? franceStation(Map<String, dynamic> j) {
  final geom = j['geom'];
  if (geom is! Map) return null;
  final lat = parseNumber(geom['lat']), lng = parseNumber(geom['lon']);
  if (lat == null || lng == null) return null;
  final prices = <Fuel, double>{};
  void put(Fuel f, Object? v) {
    final n = parseNumber(v);
    if (n != null && n > 0) prices[f] = n;
  }
  put(Fuel.regular, j['sp95_prix'] ?? j['e10_prix']);
  put(Fuel.premium, j['sp98_prix']);
  put(Fuel.diesel, j['gazole_prix']);
  put(Fuel.lpg, j['gplc_prix']);
  DateTime? updated;
  for (final k in const ['gazole_maj', 'e10_maj', 'sp95_maj', 'sp98_maj']) {
    final d = DateTime.tryParse('${j[k] ?? ''}');
    if (d != null && (updated == null || d.isAfter(updated))) updated = d;
  }
  return Station(
    id: 'fr:${j['id']}',
    brand: '',
    address: _tidy(j['adresse']),
    town: _tidy(j['ville']),
    region: '',
    postcode: '${j['cp'] ?? ''}',
    schedule: j['horaires_automate_24_24'] == 'Oui' ? '24/7' : '',
    position: LatLng(lat, lng),
    prices: prices,
    country: 'FR',
    source: 'fr',
    updatedAt: updated?.toLocal(),
  );
}

PriceSnapshot parseFrance(List<int> bytes) {
  final list = (jsonDecode(utf8.decode(bytes)) as List).cast<Map<String, dynamic>>();
  final stations = [for (final j in list) franceStation(j)].whereType<Station>().where((s) => s.hasPrices).toList();
  return PriceSnapshot(stations: stations, publishedAt: DateTime.now(), fetchedAt: DateTime.now());
}

// ---------- Portugal: DGEG ----------
class PortugalSource extends PriceSource {
  const PortugalSource();
  @override
  String get id => 'pt';
  @override
  String get country => 'PT';
  @override
  String get publisher => 'Direção-Geral de Energia e Geologia (Portugal)';
  @override
  List<GeoBox> get coverage => const [GeoBox(36.9, -9.6, 42.2, -6.9), GeoBox(40.8, -7.0, 42.0, -6.15),GeoBox(32.5, -17.4, 33.2, -16.2), GeoBox(36.8, -31.4, 39.8, -24.9)];

  /// DGEG fuel type codes.
  static const fuelIds = {Fuel.regular: 3201, Fuel.premium: 3400, Fuel.diesel: 2101, Fuel.dieselPremium: 2105, Fuel.lpg: 1120};

  @override
  Future<PriceSnapshot> fetch(http.Client client) async {
    final bodies = await Future.wait(fuelIds.entries.map((e) => _get(client,
        'https://precoscombustiveis.dgeg.gov.pt/api/PrecoComb/PesquisarPostos?idsTiposComb=${e.value}&qtdPorPagina=6000&pagina=1')));
    return compute(parsePortugal, [for (final (i, f) in fuelIds.keys.indexed) (f.index, bodies[i])]);
  }
}

/// The DGEG returns one list per fuel; they are merged per station.
PriceSnapshot parsePortugal(List<(int, List<int>)> parts) {
  final byId = <String, Map<String, dynamic>>{};
  final prices = <String, Map<Fuel, double>>{};
  for (final (fuelIndex, bytes) in parts) {
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    for (final r in ((json['resultado'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final id = '${r['Id']}';
      final p = parseNumber('${r['Preco'] ?? ''}'.replaceAll('€', ''));
      if (p == null || p <= 0) continue;
      byId[id] = r;
      (prices[id] ??= {})[Fuel.values[fuelIndex]] = p;
    }
  }
  final stations = <Station>[];
  byId.forEach((id, r) {
    final lat = parseNumber(r['Latitude']), lng = parseNumber(r['Longitude']);
    if (lat == null || lng == null) return;
    stations.add(Station(
      id: 'pt:$id',
      brand: _tidy(r['Marca'] ?? r['Nome']),
      address: _tidy(r['Morada']),
      town: _tidy(r['Localidade'] ?? r['Municipio']),
      region: _tidy(r['Distrito']),
      postcode: '${r['CodPostal'] ?? ''}',
      schedule: '',
      position: LatLng(lat, lng),
      prices: prices[id]!,
      country: 'PT',
      source: 'pt',
      updatedAt: DateTime.tryParse('${r['DataAtualizacao'] ?? ''}'),
    ));
  });
  return PriceSnapshot(stations: stations, publishedAt: DateTime.now(), fetchedAt: DateTime.now());
}
