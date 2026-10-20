import 'package:flutter/material.dart';

import 'dev/extra_ca_stub.dart' if (dart.library.io) 'dev/extra_ca_io.dart';
import 'ui/map_screen.dart';

void main() {
  installExtraCertificate();
  runApp(const FuelScoutApp());
}

class FuelScoutApp extends StatelessWidget {
  const FuelScoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F8A5F), brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'FuelScout',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const MapScreen(),
    );
  }
}
