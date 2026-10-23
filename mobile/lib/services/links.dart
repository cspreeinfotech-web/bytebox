import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

class Links {
  static String privacy = '${AppConfig.websiteUrl}/privacy';
  static String terms = '${AppConfig.websiteUrl}/terms';
  static String refund = '${AppConfig.websiteUrl}/terms#refund';
  static String community = '${AppConfig.websiteUrl}/terms#community';
  static String post(String id) => '${AppConfig.websiteUrl}/p/$id';

  static Future<void> open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  static Future<void> mailSupport({String subject = 'Bytebox support'}) => launchUrl(
        Uri(scheme: 'mailto', path: AppConfig.supportEmail, queryParameters: {'subject': subject}),
      );
}
