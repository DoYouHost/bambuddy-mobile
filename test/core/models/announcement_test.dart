import 'package:bambuddy_mobile/core/models/announcement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> raw({
    String id = 'a1',
    String level = 'info',
    Map<String, dynamic>? texts,
    String? link,
    bool archived = false,
    bool read = false,
  }) => {
    'id': id,
    'level': level,
    'texts':
        texts ??
        {
          'en': {'title': 'Hello', 'body': 'Body'},
        },
    'link_url': link,
    'published_at': '2026-10-01T10:00:00',
    'expires_at': null,
    'archived': archived,
    'read': read,
  };

  test('parses the server row, the time as UTC without its Z', () {
    final a = Announcement.fromJson(raw(level: 'critical', link: 'x'));
    expect(a.level, AnnouncementLevel.critical);
    expect(a.texts['en']!.title, 'Hello');
    expect(a.publishedAt?.toUtc(), DateTime.utc(2026, 10, 1, 10));
    expect(a.unread, isTrue);
  });

  test('an unknown level reads as info, missing texts as none', () {
    final a = Announcement.fromJson({'id': 'x', 'level': 'shouting'});
    expect(a.level, AnnouncementLevel.info);
    expect(a.texts, isEmpty);
    expect(a.textFor('pl').title, '');
  });

  group('textFor', () {
    final a = Announcement.fromJson(
      raw(
        texts: {
          'en': {'title': 'en', 'body': ''},
          'pt-BR': {'title': 'pt-BR', 'body': ''},
          'de': {'title': 'de', 'body': ''},
        },
      ),
    );

    test('the exact tag, in any case', () {
      expect(a.textFor('de').title, 'de');
      expect(a.textFor('PT-br').title, 'pt-BR');
    });

    test('the same base language before English', () {
      expect(a.textFor('pt').title, 'pt-BR');
      expect(a.textFor('de-AT').title, 'de');
    });

    test('English when nothing matches', () {
      expect(a.textFor('pl').title, 'en');
    });
  });

  group('safeLink', () {
    Uri? link(String? url) => Announcement.fromJson(raw(link: url)).safeLink;

    test('https on the two allowed hosts and their subdomains', () {
      expect(link('https://github.com/maziggy/bambuddy'), isNotNull);
      expect(link('https://wiki.bambuddy.cool/x'), isNotNull);
    });

    test('refuses anything else', () {
      expect(link(null), isNull);
      expect(link(''), isNull);
      expect(link('http://github.com/x'), isNull);
      expect(link('https://evilgithub.com/x'), isNull);
      expect(link('https://github.com.evil.io/x'), isNull);
      expect(link('https://user@github.com/x'), isNull);
      expect(link('https://github.com:8443/x'), isNull);
    });
  });

  group('feed', () {
    final feed = AnnouncementFeed.fromJson({
      'visible': true,
      'announcements': [
        raw(id: 'i', level: 'info'),
        raw(id: 'imp', level: 'important'),
        raw(id: 'crit', level: 'critical'),
        raw(id: 'old', level: 'critical', archived: true),
        raw(id: 'done', level: 'critical', read: true),
      ],
    });

    test('counts what is unread and not history', () {
      expect(feed.unreadCount, 3);
    });

    test('marking read changes that one row only', () {
      final next = feed.markedRead({'crit'});
      expect(next.unreadCount, 2);
      expect(next.items.firstWhere((a) => a.id == 'crit').read, isTrue);
      expect(next.visible, isTrue);
    });

    test('visible:false is no inbox at all', () {
      final hidden = AnnouncementFeed.fromJson({
        'visible': false,
        'announcements': <Object>[],
      });
      expect(hidden.visible, isFalse);
    });
  });
}
