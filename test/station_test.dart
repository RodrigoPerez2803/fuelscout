import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuelscout/data/osm_source.dart';
import 'package:fuelscout/data/price_sources.dart';
import 'package:fuelscout/data/station.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// Real entry from the Spanish API (trimmed), with decimal commas and empty fields.
const _spain = {
  'C.P.': '02250',
  'Dirección': 'AVENIDA CASTILLA LA MANCHA, 26',
  'Horario': 'L-D: 07:00-22:00',
  'Latitud': '39,211417',
  'Longitud (WGS84)': '-1,539167',
  'Municipio': 'Abengibre',
  'Provincia': 'ALBACETE',
  'Rótulo': 'REPSOL',
  'IDEESS': '4375',
  'Precio Gasolina 95 E5': '1,699',
  'Precio Gasolina 98 E5': '',
  'Precio Gasoleo A': '1,799',
  'Precio Gasoleo Premium': '',
  'Precio Gases licuados del petróleo': '',
};

void main() {
  group('Spain', () {
    test('reads prices with a decimal comma and ignores empty ones', () {
      final s = spainStation(Map<String, dynamic>.from(_spain))!;
      expect(s.price(Fuel.regular), 1.699);
      expect(s.price(Fuel.diesel), 1.799);
      expect(s.price(Fuel.premium), isNull);
      expect(s.position.latitude, closeTo(39.211417, 1e-9));
      expect(s.position.longitude, closeTo(-1.539167, 1e-9));
      expect(s.brand, 'Repsol');
      expect(s.address, 'Avenida Castilla La Mancha, 26');
      expect(s.id, 'es:4375');
      expect(s.country, 'ES');
    });

    test('discards stations without coordinates', () {
      expect(spainStation({..._spain, 'Latitud': ''}), isNull);
    });

    test('parses the publication date', () {
      expect(parseSpainDate('17/10/2026 13:39:53'), DateTime(2026, 10, 17, 13, 39, 53));
      expect(parseSpainDate('rubbish'), isNull);
    });

    test('parses the full response', () {
      final body = utf8.encode(jsonEncode({
        'Fecha': '17/10/2026 13:39:53',
        'ListaEESSPrecio': [_spain, {..._spain, 'IDEESS': '2', 'Latitud': ''}],
      }));
      final snap = parseSpain(body);
      expect(snap.stations.length, 1);
      expect(snap.publishedAt, DateTime(2026, 10, 17, 13, 39, 53));
    });
  });

  test('France: falls back to E10 when there is no SP95 and keeps lower-case addresses as they are', () {
    final body = utf8.encode(jsonEncode([
      {
        'id': 40500002, 'geom': {'lon': -0.567, 'lat': 43.773}, 'adresse': 'Route de Mont de Marsan', 'ville': 'SAINT-SEVER', 'cp': '40500',
        'gazole_prix': 2.399, 'sp95_prix': null, 'e10_prix': 2.149, 'sp98_prix': 2.349, 'gplc_prix': null, 'horaires_automate_24_24': 'Oui',
        'gazole_maj': '2026-10-13T11:41:26+00:00',
      },
      {'id': 1, 'geom': null},
    ]));
    final s = parseFrance(body).stations.single;
    expect(s.price(Fuel.regular), 2.149);
    expect(s.price(Fuel.diesel), 2.399);
    expect(s.price(Fuel.lpg), isNull);
    expect(s.address, 'Route de Mont de Marsan');
    expect(s.town, 'Saint-Sever');
    expect(s.schedule, '24/7');
  });

  test('Portugal: merges the per-fuel lists', () {
    List<int> part(String price) => utf8.encode(jsonEncode({
          'resultado': [
            {'Id': 94684, 'Marca': 'PLENERGY', 'Morada': 'Avenida Dom João I', 'Localidade': 'Abrantes', 'Preco': '$price €', 'Latitude': 39.47, 'Longitude': -8.19},
          ],
        }));
    final snap = parsePortugal([(Fuel.regular.index, part('1,919')), (Fuel.diesel.index, part('1,759'))]);
    final s = snap.stations.single;
    expect(s.prices, {Fuel.regular: 1.919, Fuel.diesel: 1.759});
    expect(s.brand, 'Plenergy');
    expect(s.country, 'PT');
  });

  test('OpenStreetMap: reads brand, opening hours and fuels from nodes and ways', () {
    final body = utf8.encode(jsonEncode({
      'elements': [
        {'type': 'node', 'id': 1, 'lat': 52.5, 'lon': 13.4, 'tags': {'amenity': 'fuel', 'brand': 'Aral', 'opening_hours': '24/7', 'fuel:diesel': 'yes', 'fuel:octane_95': 'yes'}},
        {'type': 'way', 'id': 2, 'center': {'lat': 52.6, 'lon': 13.5}, 'tags': {'amenity': 'fuel', 'name': 'Tankstelle'}},
      ],
    }));
    final list = parseOverpass(body);
    expect(list.length, 2);
    expect(list[0].brand, 'Aral');
    expect(list[0].fuels, {Fuel.regular, Fuel.diesel});
    expect(list[0].hasPrices, isFalse);
    expect(list[1].id, 'osm:way/2');
    expect(list[1].position, const LatLng(52.6, 13.5));
  });

  test('each source only covers its own country', () {
    const madrid = GeoBox(40.3, -3.8, 40.5, -3.6), berlin = GeoBox(52.4, 13.3, 52.6, 13.5), paris = GeoBox(48.8, 2.2, 48.9, 2.4);
    expect(officialSources.where((s) => s.covers(madrid)).map((s) => s.id), ['es']);
    expect(officialSources.where((s) => s.covers(paris)).map((s) => s.id), ['fr']);
    expect(officialSources.where((s) => s.covers(berlin)), isEmpty);
    const lisbon = GeoBox(38.70, -9.17, 38.74, -9.11), barcelona = GeoBox(41.36, 2.13, 41.42, 2.21);
    expect(officialSources.where((s) => s.covers(lisbon)).map((s) => s.id), ['pt']);
    expect(officialSources.where((s) => s.covers(barcelona)).map((s) => s.id), ['es']);
  });

  test('OSM cells are capped when the view is huge', () {
    final osm = OsmSource(_NoClient());
    expect(osm.cellsFor(const GeoBox(40.3, -3.8, 40.5, -3.6)), isNotNull);
    expect(osm.cellsFor(const GeoBox(30, -10, 50, 10)), isNull);
  });
}

class _NoClient extends Fake implements http.Client {}
