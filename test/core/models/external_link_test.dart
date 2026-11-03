import 'package:bambuddy_mobile/core/models/external_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> row({Object? badge = 3, Object? icon, String? url}) => {
    'id': 7,
    'name': 'Orders',
    'url': url ?? 'http://orders.lan:8080/todo',
    'icon': 'link',
    'custom_icon': icon,
    'badge_count': badge,
  };

  group('ExternalLink.fromJson', () {
    test('reads the fields the sidebar shows', () {
      final link = ExternalLink.fromJson(row(icon: 'abc.png'));
      expect(link.id, 7);
      expect(link.name, 'Orders');
      expect(link.hasCustomIcon, isTrue);
      expect(link.badgeCount, 3);
    });

    test('an older server sends no badge_count and no uploaded icon', () {
      final link = ExternalLink.fromJson({
        'id': 1,
        'name': 'Wiki',
        'url': 'https://wiki.lan',
      });
      expect(link.badgeCount, isNull);
      expect(link.badge, 0);
      expect(link.hasCustomIcon, isFalse);
    });

    test('nonsense in every field is survived', () {
      final link = ExternalLink.fromJson({
        'id': 'x',
        'name': null,
        'url': 5,
        'badge_count': 'many',
      });
      expect(link.name, '');
      expect(link.url, '');
      expect(link.badgeCount, isNull);
      expect(link.initial, '?');
      expect(link.address, '');
    });
  });

  group('badge', () {
    test('is hidden at 0, negative and null, as the web hides it', () {
      expect(ExternalLink.fromJson(row(badge: 0)).badge, 0);
      expect(ExternalLink.fromJson(row(badge: -2)).badge, 0);
      expect(ExternalLink.fromJson(row(badge: null)).badge, 0);
    });

    test('is capped at 99+ in the label, not in the number', () {
      expect(externalLinkBadgeLabel(99), '99');
      expect(externalLinkBadgeLabel(100), '99+');
      expect(ExternalLink.fromJson(row(badge: 1000000)).badge, 1000000);
    });

    test('totals what every link reports', () {
      final links = [
        ExternalLink.fromJson(row(badge: 3)),
        ExternalLink.fromJson(row(badge: null)),
        ExternalLink.fromJson(row(badge: 12)),
      ];
      expect(externalLinksBadgeTotal(links), 15);
      expect(externalLinksBadgeTotal(const []), 0);
    });
  });

  group('address', () {
    String of(String url) => ExternalLink.fromJson(row(url: url)).address;

    test('is host and port without scheme or path', () {
      expect(of('http://orders.lan:8080/todo?x=1'), 'orders.lan:8080');
      expect(of('https://wiki.lan/'), 'wiki.lan');
    });

    test('never carries a login from the URL', () {
      expect(of('http://admin:secret@orders.lan:8080'), 'orders.lan:8080');
    });

    test('is empty for a string that is not a URL', () {
      expect(of('not a url'), '');
      expect(of(''), '');
    });
  });

  group('initial', () {
    String of(String name) =>
        ExternalLink.fromJson({'id': 1, 'name': name, 'url': ''}).initial;

    test('is the first letter, upper-cased', () {
      expect(of('orders'), 'O');
      expect(of('  spoolman'), 'S');
    });

    test('keeps an emoji whole', () {
      expect(of('🖨 Farm'), '🖨');
    });
  });
}
