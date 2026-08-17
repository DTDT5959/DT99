/// Centralized branding/ownership information. Referenced by AppSignature,
/// the splash screen, and the About section — change values here once
/// rather than hard-coding strings throughout the app.
class AppBranding {
  AppBranding._();

  static const String owner = 'SALS CO';
  static const String developer = '\nIbrahim Saleh\nEman Saleh\nAhmad Saleh';

  /// The subtle signature shown on every main screen.
  static const String signature = 'Ibrahim • SALS CO';

  static const String copyright = '© 2026 SALS CO. All rights reserved.';

  static const String ownershipStatement =
      'This application, including its original software, interface design, '
      'graphics, branding, and original content, is the property of SALS CO '
      'unless otherwise stated.';
}
