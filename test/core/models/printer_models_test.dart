import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:flutter_test/flutter_test.dart';

Printer _p(int id, String? model) =>
    Printer(id: id, name: 'p$id', model: model);

void main() {
  test('distinct, sorted, and spelled as the server stores them', () {
    expect(
      distinctPrinterModels([
        _p(1, 'X1C'),
        _p(2, 'P1S'),
        _p(3, 'X1C'),
        _p(4, 'x1c'),
      ]),
      ['P1S', 'X1C', 'x1c'],
    );
  });

  test('a printer with no model has nothing to contribute', () {
    expect(distinctPrinterModels([_p(1, null), _p(2, '')]), isEmpty);
    expect(distinctPrinterModels(const []), isEmpty);
  });
}
