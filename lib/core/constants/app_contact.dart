/// Who made the app, and how to reach them.
///
/// Shown on the home screen. Kept as constants rather than settings because it is
/// the publisher's own details, not the teacher's — nothing here should be
/// editable on the device.
abstract final class AppContact {
  /// Shown in the footer.
  static const String publisherName = 'Thiran Technologies';

  /// One short line under the name. Empty hides it.
  static const String tagline = 'The Power to Build Smarter';

  /// Support address. Empty hides the email button.
  static const String email = 'ramkinalin@gmail.com';

  /// Full international form, digits only — no `+`, spaces or dashes. Empty hides
  /// the WhatsApp button.
  ///
  /// `91` is India's country code, prefixed to the 10-digit mobile. `wa.me`
  /// requires the country code; without it the link resolves to the wrong number
  /// or to nothing.
  static const String whatsappNumber = '917010957597';

  static bool get hasEmail => email.trim().isNotEmpty;
  static bool get hasWhatsapp => whatsappNumber.trim().isNotEmpty;
  static bool get hasAnyContact => hasEmail || hasWhatsapp;

  /// `mailto:` with a subject prefilled, so support mail arrives sorted.
  static Uri get emailUri => Uri(
        scheme: 'mailto',
        path: email.trim(),
        queryParameters: <String, String>{'subject': 'TeachTrack'},
      );

  /// The `wa.me` web link rather than the `whatsapp://` scheme.
  ///
  /// A web link opens the app when WhatsApp is installed and falls back to the
  /// browser when it is not, whereas the custom scheme simply fails and there is
  /// no reliable way to detect that before trying.
  static Uri get whatsappUri =>
      Uri.parse('https://wa.me/${whatsappNumber.trim()}');
}
