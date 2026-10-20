import 'package:flutter/material.dart';

import 'strings.dart';

const _symbols = {'EUR': '€', 'GBP': '£', 'USD': r'$'};

/// Price per litre to 3 decimal places, in the style of the UI language: "1,529 €" or "€1.529".
String formatPrice(double value, [String currency = 'EUR']) {
  final symbol = _symbols[currency] ?? currency;
  return T.current.es ? '${value.toStringAsFixed(3).replaceAll('.', ',')} $symbol' : '$symbol${value.toStringAsFixed(3)}';
}

/// Price difference in (euro) cents: "1,5 cts" / "1.5 c".
String formatCents(double delta) {
  final c = (delta.abs() * 100).toStringAsFixed(1);
  return T.current.es ? '${c.replaceAll('.', ',')} cts' : '$c c';
}

String formatDistance(double meters) {
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  final km = meters / 1000;
  final text = km.toStringAsFixed(km < 10 ? 1 : 0);
  return '${T.current.es ? text.replaceAll('.', ',') : text} km';
}

String formatClock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Day and month as DD/MM, used in both languages.
String formatDayMonth(DateTime t) => '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return T.current.justNow;
  if (d.inMinutes < 60) return T.current.minutesAgo(d.inMinutes);
  return T.current.hoursAgo(d.inHours);
}

/// Green = among the cheapest in the visible area, amber = mid-range, red = among the most expensive.
const cheapColor = Color(0xFF16A05D);
const midColor = Color(0xFFE29A0E);
const expensiveColor = Color(0xFFD9443F);
const unknownColor = Color(0xFF7C8796);

Color tierColor(double price, double min, double max) {
  if (max - min < 0.001) return cheapColor;
  final r = (price - min) / (max - min);
  if (r <= .33) return cheapColor;
  if (r <= .66) return midColor;
  return expensiveColor;
}
