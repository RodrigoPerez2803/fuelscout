import 'package:latlong2/latlong.dart';

/// Combustibles comparables entre países. Cada fuente traduce sus nombres a estos.
enum Fuel { regular, premium, diesel, dieselPremium, lpg }

class Station {
  const Station({
    required this.id,
    required this.brand,
    required this.address,
    required this.town,
    required this.region,
    required this.postcode,
    required this.schedule,
    required this.position,
    required this.prices,
    required this.country,
    required this.source,
    this.currency = 'EUR',
    this.fuels = const {},
    this.updatedAt,
  });

  /// Único entre fuentes: lleva el prefijo de la fuente (`es:4375`, `osm:node/123`).
  final String id;
  final String brand;
  final String address;
  final String town;
  final String region;
  final String postcode;
  final String schedule;
  final LatLng position;

  /// Vacío en las gasolineras de OpenStreetMap, que no publican precios.
  final Map<Fuel, double> prices;

  /// Código ISO 3166 del país (`ES`, `FR`…); vacío si se desconoce.
  final String country;

  /// Identificador de la fuente que la ha aportado (`es`, `fr`, `pt`, `osm`).
  final String source;
  final String currency;

  /// Combustibles que vende, aunque no se sepa su precio (etiquetas `fuel:*` de OSM).
  final Set<Fuel> fuels;
  final DateTime? updatedAt;

  bool get hasPrices => prices.isNotEmpty;
  double? price(Fuel fuel) => prices[fuel];
  Set<Fuel> get availableFuels => {...prices.keys, ...fuels};

  Station copyWith({String? brand}) => Station(
        id: id, brand: brand ?? this.brand, address: address, town: town, region: region, postcode: postcode,
        schedule: schedule, position: position, prices: prices, country: country, source: source,
        currency: currency, fuels: fuels, updatedAt: updatedAt,
      );
}

/// Números con coma o punto decimal, cadenas vacías o null.
double? parseNumber(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  return double.tryParse(text.replaceAll(',', '.'));
}

String titleCase(String text) {
  final lower = text.trim().toLowerCase();
  return lower.replaceAllMapped(RegExp(r"(^|[\s\-/(.'])(\p{L})", unicode: true),
      (m) => '${m[1]}${m[2]!.toUpperCase()}');
}
