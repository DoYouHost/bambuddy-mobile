import 'package:app_util/app_util.dart';

import 'json_utils.dart';

/// Shapes of `GET /announcements` (`routes/announcements.py`,
/// `services/announcements.py::list_for`): messages from the Bambuddy
/// maintainers, fetched by the server from a signed feed on GitHub.

enum AnnouncementLevel {
  info,
  important,
  critical;

  /// The server stores anything else as `info` already; this only guards a
  /// newer level arriving at an older app.
  static AnnouncementLevel parse(Object? raw) => switch (raw) {
    'critical' => critical,
    'important' => important,
    _ => info,
  };
}

class AnnouncementText {
  const AnnouncementText({
    required this.title,
    required this.body,
    this.linkLabel,
  });

  factory AnnouncementText.fromJson(Map<String, dynamic> json) =>
      AnnouncementText(
        title: toStringOrNull(json['title']) ?? '',
        body: toStringOrNull(json['body']) ?? '',
        linkLabel: toStringOrNull(json['link_label']),
      );

  final String title;
  final String body;

  /// The button text for the link; `null` reads "Read more".
  final String? linkLabel;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.level,
    required this.texts,
    this.linkUrl,
    this.publishedAt,
    this.archived = false,
    this.read = false,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    final raw = json['texts'];
    return Announcement(
      id: toStringOrNull(json['id']) ?? '',
      level: AnnouncementLevel.parse(json['level']),
      texts: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is Map<String, dynamic>)
              e.key.toString(): AnnouncementText.fromJson(e.value),
      },
      linkUrl: toStringOrNull(json['link_url']),
      publishedAt: dateTimeFromJson(json['published_at']),
      archived: json['archived'] == true,
      read: json['read'] == true,
    );
  }

  /// The feed's own string id, used in `POST /announcements/{id}/read`.
  final String id;
  final AnnouncementLevel level;

  /// Keyed by language tag as the feed wrote it ("en", "pt-BR"); `en` is the
  /// one every entry carries.
  final Map<String, AnnouncementText> texts;
  final String? linkUrl;
  final DateTime? publishedAt;

  /// Past its expiry: history, never unread and never a banner.
  final bool archived;

  /// Per user, on the server — read on the web is read here too.
  final bool read;

  bool get unread => !read && !archived;

  Announcement asRead() => Announcement(
    id: id,
    level: level,
    texts: texts,
    linkUrl: linkUrl,
    publishedAt: publishedAt,
    archived: archived,
    read: true,
  );

  /// The web's `announcementText`: the exact tag, then the same tag in another
  /// case, then the same base language ("pt" finds "pt-BR"), then English.
  AnnouncementText textFor(String language) {
    final lower = language.toLowerCase();
    final base = lower.split(RegExp('[-_]')).first;
    String? key;
    for (final k in texts.keys) {
      if (k.toLowerCase() == lower) return texts[k]!;
      if (key == null && k.toLowerCase().split('-').first == base) key = k;
    }
    return texts[key] ??
        texts['en'] ??
        (texts.isEmpty
            ? const AnnouncementText(title: '', body: '')
            : texts.values.first);
  }

  /// The web's `isAllowedAnnouncementLink`, mirroring the server's
  /// `link_allowed`: https only, on github.com or bambuddy.cool. The server
  /// already drops any other link; this keeps a changed server from widening
  /// what the app opens.
  Uri? get safeLink {
    final uri = Uri.tryParse(linkUrl ?? '');
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      return null;
    }
    if (uri.hasPort && uri.port != 443) return null;
    final host = uri.host.toLowerCase();
    const allowed = ['github.com', 'bambuddy.cool'];
    return allowed.any((a) => host == a || host.endsWith('.$a')) ? uri : null;
  }
}

/// `{visible, announcements}`. `visible: false` is the server saying this
/// session gets no inbox at all — an API key, or a non-admin while
/// `announcements_all_users` is off — which hides the entry, unlike an empty
/// list, which is an empty inbox.
class AnnouncementFeed {
  const AnnouncementFeed({required this.visible, this.items = const []});

  factory AnnouncementFeed.fromJson(Map<String, dynamic> json) =>
      AnnouncementFeed(
        visible: json['visible'] == true,
        items: parseJsonList(json['announcements'], Announcement.fromJson),
      );

  static const hidden = AnnouncementFeed(visible: false);

  final bool visible;

  /// Newest first, as the server sorts them.
  final List<Announcement> items;

  int get unreadCount => items.where((a) => a.unread).length;

  /// The banner's pick: unread important or critical, most severe first.
  List<Announcement> get bannerItems => [
    for (final level in const [
      AnnouncementLevel.critical,
      AnnouncementLevel.important,
    ])
      ...items.where((a) => a.unread && a.level == level),
  ];

  AnnouncementFeed markedRead(String id) => AnnouncementFeed(
    visible: visible,
    items: [for (final a in items) a.id == id ? a.asRead() : a],
  );
}
