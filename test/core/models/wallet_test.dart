import 'package:bambuddy_mobile/core/models/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePrintCharge', () {
    test('lifts the partial tag out, whichever way the print ended', () {
      for (final kind in PartialPrint.values) {
        final parsed = parsePrintCharge('Cube [${kind.name}: bed adhesion]');
        expect(parsed.partial, kind);
        expect(parsed.text, 'Cube');
      }
    });

    test('is not case sensitive about the tag, as the web is not', () {
      expect(parsePrintCharge('Cube [FAILED: x]').partial, PartialPrint.failed);
    });

    test('leaves a plain description alone', () {
      final parsed = parsePrintCharge('Cube');
      expect(parsed.partial, isNull);
      expect(parsed.text, 'Cube');
    });

    test('a description that was only the tag has no text left', () {
      final parsed = parsePrintCharge('[aborted: power cut]');
      expect(parsed.partial, PartialPrint.aborted);
      expect(parsed.text, isNull);
    });

    test('nothing in, nothing out', () {
      expect(parsePrintCharge(null), (partial: null, text: null));
    });

    test('a tag the server does not use is not one', () {
      expect(parsePrintCharge('Cube [paused: x]').partial, isNull);
    });
  });

  group('WalletTransaction', () {
    test('reads a ledger row, the amount signed', () {
      final tx = WalletTransaction.fromJson({
        'id': 7,
        'user_id': 1,
        'cost_center_id': 3,
        'transaction_type': 'print_charge',
        'amount': -1.25,
        'balance_after': 8.75,
        'description': 'Cube',
        'created_at': '2026-10-01T12:00:00',
      });

      expect(tx.type, WalletTransactionType.printCharge);
      expect(tx.amount, -1.25);
      expect(tx.balanceAfter, 8.75);
      expect(tx.costCenterId, 3);
      // A server timestamp is UTC even without its `Z`.
      expect(
        tx.createdAt!.isAtSameMomentAs(DateTime.utc(2026, 10, 1, 12)),
        isTrue,
      );
    });

    test('a kind from a newer server keeps its own name', () {
      final tx = WalletTransaction.fromJson({
        'id': 1,
        'user_id': 1,
        'transaction_type': 'refund',
        'amount': 2,
      });

      expect(tx.type, WalletTransactionType.other);
      expect(tx.typeWire, 'refund');
      expect(tx.balanceAfter, isNull);
    });

    test('a page carries the total beside the rows', () {
      final page = WalletTransactionPage.fromJson({
        'items': [
          {'id': 1, 'user_id': 1, 'transaction_type': 'deposit', 'amount': 5},
        ],
        'total': 61,
        'limit': 50,
        'offset': 0,
      });

      expect(page.items, hasLength(1));
      expect(page.total, 61);
    });
  });
}
