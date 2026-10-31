import 'package:app_util/app_util.dart';

/// One sidebar link of the web UI (`ExternalLinkResponse`,
/// `schemas/external_link.py`): another app the server's owner keeps next to
/// Bambuddy, and the count that app reports for itself.
class ExternalLink {
  const ExternalLink({
    required this.id,
    required this.name,
    required this.url,
    this.hasCustomIcon = false,
    this.badgeCount,
  });

  factory ExternalLink.fromJson(Map<String, dynamic> json) => ExternalLink(
    id: toInt(json['id']),
    name: toStringOrNull(json['name']) ?? '',
    url: toStringOrNull(json['url']) ?? '',
    hasCustomIcon: toStringOrNull(json['custom_icon']) != null,
    badgeCount: toIntOrNull(json['badge_count']),
  );

  final int id;
  final String name;

  /// As the server stores it. It may carry a login (`http://user:pass@host`),
  /// so it is opened but never shown or logged — [address] is what to show.
  final String url;

  /// An uploaded picture, served by `GET /external-links/{id}/icon`. Without
  /// one the web draws a Lucide glyph by name, which has no counterpart here.
  final bool hasCustomIcon;

  /// What the app behind the link last reported. `null` from an older server,
  /// and for an app that has not reported for ten minutes
  /// (`BADGE_FRESH_FOR` in `routes/external_links.py`).
  final int? badgeCount;

  /// The count to show: none at 0 or when nothing was reported, as the web does.
  int get badge => badgeCount != null && badgeCount! > 0 ? badgeCount! : 0;

  /// `host` or `host:port`, without the scheme, a login or a path.
  String get address {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '';
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  /// The glyph for the tile when there is no picture. The first code point, not
  /// the first UTF-16 unit, so a name that opens with an emoji is not cut in half.
  String get initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }
}

/// The caption of a count, capped as the web's sidebar caps it.
String externalLinkBadgeLabel(int count) => count > 99 ? '99+' : '$count';

/// What every link together reports, for the drawer's one tile.
int externalLinksBadgeTotal(Iterable<ExternalLink> links) =>
    links.fold(0, (sum, link) => sum + link.badge);
