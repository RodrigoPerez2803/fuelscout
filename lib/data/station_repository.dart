import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'osm_source.dart';
import 'price_sources.dart';
import 'station.dart';

class SourceState {
  PriceSnapshot? snapshot;
  bool loading = false;
  Object? error;
  DateTime? lastTry;
}

/// Combines the official sources (downloaded only when the view touches their country)
/// and OpenStreetMap (for the rest of the world, cell by cell).
class StationRepository extends ChangeNotifier {
  StationRepository({http.Client? client}) : client = client ?? http.Client() {
    osm = OsmSource(this.client);
  }

  final http.Client client;
  late final OsmSource osm;
  final states = {for (final s in officialSources) s.id: SourceState()};

  /// Each station's prices from the previous download, used to flag rises and falls.
  final previous = <String, Map<Fuel, double>>{};
  bool osmLoading = false, osmFailed = false, osmTooWide = false;

  List<PriceSource> sourcesFor(GeoBox view) => officialSources.where((s) => s.covers(view)).toList();
  bool get anyLoading => states.values.any((s) => s.loading) || osmLoading;

  /// Requests whatever is missing for the current view.
  void ensure(GeoBox view) {
    for (final src in sourcesFor(view)) {
      final st = states[src.id]!;
      final retryOk = st.lastTry == null || DateTime.now().difference(st.lastTry!) > const Duration(seconds: 30);
      if (st.snapshot == null && !st.loading && (st.error == null || retryOk)) _load(src);
    }
    osmTooWide = osm.cellsFor(view) == null;
    if (!osmTooWide && !osm.busy && osm.needs(view)) {
      osmLoading = true;
      osm.load(view).then((added) {
        osmFailed = false;
        osmLoading = false;
        notifyListeners();
      }, onError: (_) {
        osmFailed = true;
        osmLoading = false;
        notifyListeners();
      });
    }
  }

  Future<int> _load(PriceSource src) async {
    final st = states[src.id]!;
    st.loading = true;
    st.lastTry = DateTime.now();
    notifyListeners();
    var changed = 0;
    try {
      final snap = await src.fetch(client);
      final old = st.snapshot;
      if (old != null) {
        for (final s in old.stations) {
          previous[s.id] = s.prices;
        }
        final before = {for (final s in old.stations) s.id: s.prices};
        for (final s in snap.stations) {
          final was = before[s.id];
          if (was != null && s.prices.entries.any((e) => was[e.key] != null && (was[e.key]! - e.value).abs() > .0005)) changed++;
        }
      }
      st.snapshot = snap;
      st.error = null;
    } catch (e) {
      st.error = e;
    } finally {
      st.loading = false;
      notifyListeners();
    }
    return changed;
  }

  /// Re-downloads the sources already loaded. Returns how many stations have changed price.
  Future<int> refresh() async {
    final loaded = officialSources.where((s) => states[s.id]!.snapshot != null && !states[s.id]!.loading);
    final results = await Future.wait(loaded.map(_load));
    return results.fold<int>(0, (a, b) => a + b);
  }

  Iterable<Station> official(GeoBox view) sync* {
    for (final src in sourcesFor(view)) {
      final snap = states[src.id]!.snapshot;
      if (snap != null) yield* snap.stations.where((s) => view.contains(s.position));
    }
  }

  PriceSource? sourceOf(Station s) => officialSources.where((src) => src.id == s.source).firstOrNull;
  PriceSnapshot? snapshotOf(Station s) => states[s.source]?.snapshot;
}
