import 'package:json_annotation/json_annotation.dart';

import 'wled_config.dart';

part 'printer.g.dart';

/// Printer configuration from `GET /printers` (PrinterResponse).
/// Defensive parsing: all except id/name are nullable, unknown keys ignored — API
/// is young and evolving.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class Printer {
  const Printer({
    required this.id,
    required this.name,
    this.model,
    this.ipAddress,
    this.location,
    this.isActive,
    this.serialNumber,
    this.nozzleCount,
    this.autoArchive,
    this.wearCostPerHour,
    this.dispatchPriority,
    this.servedKeys = const {},
    this.wledConfig,
  });

  factory Printer.fromJson(Map<String, dynamic> json) =>
      _$PrinterFromJson(json);

  final int id;
  final String name;
  final String? model;
  final String? ipAddress;
  final String? location;
  final bool? isActive;

  /// Hashed into the tag bambuddy links a spool without RFID by
  /// (`fallbackSpoolTag`).
  final String? serialNumber;

  /// 1 or 2, detected by the server from the printer's reports.
  final int? nozzleCount;

  final bool? autoArchive;

  /// What an hour of printing costs this printer in wear (#694); null = off.
  final double? wearCostPerHour;

  /// Place in the pick order of "Any model" jobs when that order is
  /// `priority` (#2915): lowest first, null last.
  final int? dispatchPriority;

  /// Every key the server sent for this printer, null values included. A field
  /// that landed in a later release is a silent drop on an older server — a
  /// `PATCH` takes it and keeps nothing — so its key being here is the only
  /// proof the server knows it. Read through the getters below.
  @JsonKey(readValue: _keysOf)
  final Set<String> servedKeys;

  /// `wear_cost_per_hour` (#694) is sent, null or not, from 1.2.6.
  bool get servesWearCost => servedKeys.contains(PrinterKey.wearCostPerHour);

  /// `dispatch_priority` (#2915) is sent, null or not, from 1.3.2.
  bool get servesDispatchPriority =>
      servedKeys.contains(PrinterKey.dispatchPriority);

  /// Null both for a printer with no WLED mapping and for a server older than
  /// it; `PrintersRepository.wledCapability` tells the two apart.
  @JsonKey(fromJson: _wledFromJson)
  final WledConfig? wledConfig;
}

WledConfig? _wledFromJson(Object? json) =>
    json is Map<String, dynamic> ? WledConfig.fromJson(json) : null;

Object? _keysOf(Map<dynamic, dynamic> json, String _) =>
    json.keys.cast<String>().toList();

/// Wire keys the editor sends only to a server that served them back: a row's
/// [Printer.servedKeys] says which, and [PrinterUpdate.served] carries it over.
abstract final class PrinterKey {
  static const wearCostPerHour = 'wear_cost_per_hour';
  static const dispatchPriority = 'dispatch_priority';
}

/// The distinct models of [printers], sorted, spelled exactly as the server
/// stores them: `target_model` and a pipeline's printer class are matched
/// against `Printer.model` with plain equality, so a normalised value would
/// match nothing.
List<String> distinctPrinterModels(Iterable<Printer> printers) => {
  for (final p in printers)
    if (p.model != null && p.model!.isNotEmpty) p.model!,
}.toList()..sort();
