import 'package:collection/collection.dart';

const _deepEquality = DeepCollectionEquality();

/// Value equality from one list: a class declares [props] and gets `==` and
/// `hashCode` that cannot drift apart.
///
/// Two hand-written lists of fields (one in `==`, one in `hashCode`) are kept in
/// step by review alone; a field forgotten in one of them compares unequal
/// values equal, or hashes equal values apart. A list or map in [props] is
/// compared and hashed by its contents, anything else by its own `==`. A class
/// that compares only a subset of its fields lists just that subset.
///
/// Equal means the same `runtimeType` and equal [props], so a subclass never
/// equals its parent.
mixin ValueEquality {
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValueEquality &&
          other.runtimeType == runtimeType &&
          _deepEquality.equals(other.props, props);

  @override
  int get hashCode =>
      Object.hashAll([for (final prop in props) _deepEquality.hash(prop)]);
}
