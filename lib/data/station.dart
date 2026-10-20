import 'package:latlong2/latlong.dart';

/// Fuels that are comparable across countries. Each source maps its own names onto these.
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

  /// Unique across sources: prefixed with the source id (`es:4375`, `osm:node/123`).
  final String id;
  final String brand;
  final String address;
  final String town;
  final String region;
  final String postcode;
  final String schedule;
  final LatLng position;

  /// Empty for OpenStreetMap stations, which have no published prices.
  final Map<Fuel, double> prices;

  /// ISO 3166 country code (`ES`, `FR`…); empty if unknown.
  final String country;

  /// Id of the source it came from (`es`, `fr`, `pt`, `osm`).
  final String source;
  final String currency;

  /// Fuels it sells, even when their prices are unknown (OSM `fuel:*` tags).
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

/// Parses numbers with a decimal comma or point; returns null for empty strings or null.
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
