import 'package:app_util/app_util.dart';

/// The next pause the slicer put into the running print (`next_pause`, server
/// #2984): the layer it is on and the minutes until the printer gets there.
///
/// [minutes] is null while the server cannot say: at the start of a print the
/// printer reports no time left, and in a speed mode other than standard the
/// slicer's times do not apply. The layer is known all the same.
class NextPause {
  const NextPause({required this.layer, this.minutes});

  final int layer;
  final int? minutes;

  @override
  bool operator ==(Object other) =>
      other is NextPause && other.layer == layer && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(layer, minutes);
}

/// `next_pause` out of a status frame: null for the key's absence (an older
/// server), for the JSON null the server sends when no pause is ahead, and for
/// an object without a layer, which says nothing a card could show.
NextPause? nextPauseFromJson(Object? value) {
  if (value is! Map) return null;
  final layer = toIntOrNull(value['layer']);
  if (layer == null) return null;
  return NextPause(layer: layer, minutes: toIntOrNull(value['minutes']));
}
