import 'dart:ui' show PlatformDispatcher;

import '../data/station.dart';

/// Textos de la interfaz en español o inglés, según el idioma del dispositivo.
class T {
  T._(this.es);
  final bool es;

  static final T current = T._(PlatformDispatcher.instance.locale.languageCode == 'es');
  String get lang => es ? 'es' : 'en';

  String _(String spanish, String english) => es ? spanish : english;

  String fuel(Fuel f) => switch (f) {
        Fuel.regular => _('Gasolina 95', 'Regular 95'),
        Fuel.premium => _('Gasolina 98', 'Premium 98'),
        Fuel.diesel => _('Diésel', 'Diesel'),
        Fuel.dieselPremium => _('Diésel+', 'Premium diesel'),
        Fuel.lpg => _('GLP', 'LPG'),
      };

  String get appName => 'FuelScout';
  String get tagline => _('Gasolineras baratas en todo el mundo', 'Cheap fuel, anywhere in the world');
  String get searchHint => _('Buscar ciudad o dirección', 'Search a city or address');
  String get noResults => _('Sin resultados', 'No results');
  String get searchError => _('No se pudo buscar. Revisa tu conexión.', 'Search failed. Check your connection.');

  String loadingSources(List<String> names) => _('Descargando precios: ${names.join(', ')}…', 'Downloading prices: ${names.join(', ')}…');
  String officialPrices(List<String> countries, String clock, String ago) =>
      _('Precios oficiales (${countries.join(' · ')}) de las $clock · $ago', 'Official prices (${countries.join(' · ')}) from $clock · $ago');
  String get noOfficialHere => _('Aquí no hay precios oficiales abiertos: se muestran las gasolineras de OpenStreetMap.',
      'No open price data here: showing stations from OpenStreetMap.');
  String get zoomIn => _('Acerca el mapa para ver las gasolineras.', 'Zoom in to see stations.');
  String get osmLoading => _('Buscando gasolineras en OpenStreetMap…', 'Looking up stations on OpenStreetMap…');
  String get osmError => _('OpenStreetMap no responde; vuelve a intentarlo en un momento.', 'OpenStreetMap is not responding; try again shortly.');
  String get pricesError => _('No se pudieron descargar los precios. Revisa tu conexión.', 'Could not download prices. Check your connection.');
  String get retry => _('Reintentar', 'Retry');
  String pricesChanged(int n, Fuel f) => _('Precios actualizados: $n gasolineras han cambiado el precio de ${fuel(f).toLowerCase()}.',
      'Prices updated: $n stations changed their ${fuel(f).toLowerCase()} price.');

  String get justNow => _('ahora mismo', 'just now');
  String minutesAgo(int m) => _('hace $m min', '$m min ago');
  String hoursAgo(int h) => _('hace $h h', '$h h ago');
  String checked(String ago) => _('comprobado $ago', 'checked $ago');
  String get updating => _('actualizando…', 'updating…');

  String get locationOff => _('Activa la ubicación para ver las gasolineras más cercanas.', 'Turn on location to see the nearest stations.');
  String get locationDenied => _('Sin permiso de ubicación: busca una ciudad o mueve el mapa.', 'No location permission: search a city or move the map.');
  String get locationFailed => _('No se pudo obtener tu ubicación.', 'Could not get your location.');
  String get myLocation => _('Mi ubicación', 'My location');
  String get refresh => _('Actualizar precios', 'Refresh prices');
  String get navFailed => _('No se pudo abrir la navegación.', 'Could not open navigation.');

  String get loading => _('Cargando gasolineras…', 'Loading stations…');
  String countHere(int n) => _('$n gasolineras con precio en esta zona', '$n stations with prices in this area');
  String noneWithFuel(Fuel f) => _('Ninguna gasolinera con precio de ${fuel(f).toLowerCase()} aquí', 'No ${fuel(f).toLowerCase()} prices in this area');
  String cheapestRange(String min, String max) => _('Más barata: $min · más cara: $max', 'Cheapest: $min · most expensive: $max');
  String get zoomForAll => _(' · acerca el mapa para verlas todas', ' · zoom in to see them all');
  String get moveMap => _('Mueve o aleja el mapa para buscar en otra zona.', 'Move or zoom out the map to search elsewhere.');
  String otherStations(int n) => _('Otras $n gasolineras (sin precio publicado)', '$n more stations (no published price)');
  String get noPrice => _('Sin precio', 'No price');
  String get station => _('Gasolinera', 'Fuel station');

  String get cheapestHere => _('La más barata de la zona', 'Cheapest in this area');
  String rankOf(int r, int n) => _('Puesto $r de $n en la zona', '#$r of $n in this area');
  String away(String d) => _('A $d', '$d away');
  String wentDown(String c) => _('Ha bajado $c', 'Down $c');
  String wentUp(String c) => _('Ha subido $c', 'Up $c');
  String get directions => _('Cómo llegar', 'Directions');
  String get prices => _('Precios', 'Prices');
  String get fuels => _('Combustibles', 'Fuels');
  String get hours => _('Horario', 'Opening hours');
  String get open247 => _('Abierta 24 horas', 'Open 24/7');
  String get noPriceNote => _('Esta gasolinera viene de OpenStreetMap: su país no publica precios abiertos, así que solo se muestran sus datos y cómo llegar.',
      'This station comes from OpenStreetMap: its country does not publish open price data, so only its details and directions are shown.');
  String publishedBy(String who, String when) => _('Precios oficiales publicados por $who · $when.', 'Official prices published by $who · $when.');
  String get mapCredit => _('Mapa © colaboradores de OpenStreetMap', 'Map © OpenStreetMap contributors');
  String sourcesCredit(List<String> who) => _('Precios: ${who.join('; ')}. Gasolineras sin precio: OpenStreetMap (ODbL).',
      'Prices: ${who.join('; ')}. Stations without prices: OpenStreetMap (ODbL).');

  String country(String code) => switch (code) {
        'ES' => _('España', 'Spain'),
        'FR' => _('Francia', 'France'),
        'PT' => 'Portugal',
        _ => code,
      };
}
