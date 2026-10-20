import 'dart:convert';
import 'dart:io';

/// Extra root certificate (base64-encoded PEM), injected only into development builds with
/// `--dart-define-from-file=dev_ca.json`. Needed on PCs whose antivirus re-signs HTTPS traffic
/// (e.g. Norton), which the emulator inherits. Without that option it does nothing.
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
