import 'dart:convert';
import 'dart:io';

/// Certificado raíz adicional (PEM en base64) que solo se inyecta en compilaciones de desarrollo con
/// `--dart-define-from-file=dev_ca.json`. Sirve para PCs cuyo antivirus re-firma el HTTPS
/// (p. ej. Norton), algo que el emulador hereda. Sin esa opción no hace nada.
const _extraCaB64 = String.fromEnvironment('EXTRA_CA_PEM_B64');

void installExtraCertificate() {
  if (_extraCaB64.isEmpty) return;
  HttpOverrides.global = _ExtraCaOverrides(base64Decode(_extraCaB64));
}

class _ExtraCaOverrides extends HttpOverrides {
  _ExtraCaOverrides(this.pem);
  final List<int> pem;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final ctx = SecurityContext(withTrustedRoots: true)..setTrustedCertificatesBytes(pem);
    return super.createHttpClient(ctx);
  }
}
