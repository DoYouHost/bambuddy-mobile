import 'package:app_util/app_util.dart';
import 'inventory.dart' show StockStats;

/// Where filament is bought (`SupplierResponse`, server #2988) — not
/// `Spool.brand`, which is who made it. One supplier carries many brands, and a
/// product can be bought from several, hence the per-spool
/// [SpoolSupplierLink]s instead of one field on the spool.
///
/// The master list lives on `/inventory/suppliers` in both inventory modes:
/// Spoolman's `vendor` is the manufacturer, so the server keeps suppliers
/// Bambuddy-side even for Spoolman spools.
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.website,
    this.customerNumber,
    this.note,
    this.spoolCount = 0,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: toInt(json['id']),
    name: toStringOrNull(json['name']) ?? '',
    website: toStringOrNull(json['website']),
    customerNumber: toStringOrNull(json['customer_number']),
    note: toStringOrNull(json['note']),
    spoolCount: toInt(json['spool_count']),
  );

  final int id;

  /// Unique case-insensitively (`Supplier.name_key`): a create or rename onto
  /// an existing name is a 409.
  final String name;
  final String? website;

  /// The user's own customer number *at* this supplier.
  final String? customerNumber;
  final String? note;

  /// Spools referencing this supplier, Spoolman ones included. Non-zero is why
  /// a delete answers 409 (`inventory.py::delete_supplier`).
  final int spoolCount;
}

/// The editable half of a [Supplier] — the body of both `POST` and `PATCH`.
class SupplierDraft {
  const SupplierDraft({
    required this.name,
    this.website,
    this.customerNumber,
    this.note,
  });

  /// Refused by the server with a 422: the CSV export joins supplier names
  /// with it (`schemas/supplier.py::SUPPLIER_NAME_SEPARATOR`).
  static const nameSeparator = ';';

  static const maxName = 200;
  static const maxWebsite = 500;
  static const maxCustomerNumber = 100;
  static const maxNote = 500;

  final String name;
  final String? website;
  final String? customerNumber;
  final String? note;

  /// Every key always, so a `PATCH` clears a field the user emptied —
  /// `SupplierUpdate` takes `null` for the optional three.
  Map<String, dynamic> toJson() => {
    'name': name,
    'website': website,
    'customer_number': customerNumber,
    'note': note,
  };
}

/// One spool-to-supplier assignment (`SpoolSupplierResponse`, and the
/// `SpoolSupplierLinkInput` it is written back as). The Spoolman routes send
/// the same shape (`spoolman_inventory.py::_supplier_link_to_dict`).
class SpoolSupplierLink {
  const SpoolSupplierLink({
    required this.supplierId,
    this.supplierName = '',
    this.articleNumber,
    this.quotedPricePerKg,
    this.isPurchaseSource = false,
  });

  factory SpoolSupplierLink.fromJson(Map<String, dynamic> json) =>
      SpoolSupplierLink(
        supplierId: toInt(json['supplier_id']),
        supplierName: toStringOrNull(json['supplier_name']) ?? '',
        articleNumber: toStringOrNull(json['supplier_article_number']),
        quotedPricePerKg: toDoubleOrNull(json['quoted_price_per_kg']),
        isPurchaseSource: toBoolOrFalse(json['is_purchase_source']),
      );

  static const maxArticleNumber = 100;

  final int supplierId;
  final String supplierName;

  /// The supplier's own article number for the product, not the internal
  /// material number.
  final String? articleNumber;

  /// A price quoted at this supplier, for comparing sources. Never a cost
  /// basis: the server keeps `cost_per_kg` on the spool and never writes it
  /// from here.
  final double? quotedPricePerKg;

  /// Where this spool was actually bought; at most one per spool, or the
  /// replace answers 400. The others are alternative sources.
  final bool isPurchaseSource;

  Map<String, dynamic> toJson() => {
    'supplier_id': supplierId,
    'supplier_article_number': articleNumber,
    'quoted_price_per_kg': quotedPricePerKg,
    'is_purchase_source': isPurchaseSource,
  };
}

/// The purchase source first, the alternatives after it in the order the
/// server stored them — how the web lists a spool's suppliers.
List<SpoolSupplierLink> purchaseSourceFirst(List<SpoolSupplierLink> links) => [
  ...links.where((l) => l.isPurchaseSource),
  ...links.where((l) => !l.isPurchaseSource),
];

/// [existing] with [added] merged in, as the mass edit writes it: nothing is
/// removed, a supplier already on the spool keeps whatever [added] leaves
/// blank, and a purchase source in [added] takes the flag from the old one —
/// the replace route allows only one.
List<SpoolSupplierLink> mergeSupplierLinks(
  List<SpoolSupplierLink> existing,
  List<SpoolSupplierLink> added,
) {
  final byId = {for (final l in existing) l.supplierId: l};
  for (final a in added) {
    final old = byId[a.supplierId];
    byId[a.supplierId] = SpoolSupplierLink(
      supplierId: a.supplierId,
      supplierName: a.supplierName.isEmpty
          ? old?.supplierName ?? ''
          : a.supplierName,
      articleNumber: a.articleNumber ?? old?.articleNumber,
      quotedPricePerKg: a.quotedPricePerKg ?? old?.quotedPricePerKg,
      isPurchaseSource: old?.isPurchaseSource ?? false,
    );
  }
  final source = added.where((l) => l.isPurchaseSource).firstOrNull;
  return [
    for (final l in byId.values)
      source == null
          ? l
          : SpoolSupplierLink(
              supplierId: l.supplierId,
              supplierName: l.supplierName,
              articleNumber: l.articleNumber,
              quotedPricePerKg: l.quotedPricePerKg,
              isPurchaseSource: l.supplierId == source.supplierId,
            ),
  ];
}

/// One row of `GET /inventory/stats/suppliers` (`SupplierStats`), grouped by
/// the supplier a spool was **bought** from — alternative sources count
/// nowhere. The server sorts it by consumption, heaviest first.
///
/// Built-in inventory only: the aggregate reads the local spool table, which
/// is empty in Spoolman mode.
class SupplierStats implements StockStats {
  const SupplierStats({
    required this.supplierId,
    required this.supplierName,
    this.spoolCount = 0,
    this.remainingGrams = 0,
    this.consumedGrams = 0,
    this.cost = 0,
  });

  factory SupplierStats.fromJson(Map<String, dynamic> json) => SupplierStats(
    supplierId: toInt(json['supplier_id']),
    supplierName: toStringOrNull(json['supplier_name']) ?? '',
    spoolCount: toInt(json['spool_count']),
    remainingGrams: toDouble(json['remaining_g']),
    consumedGrams: toDouble(json['consumed_g']),
    cost: toDouble(json['cost']),
  );

  final int supplierId;
  final String supplierName;
  @override
  final int spoolCount;
  @override
  final double remainingGrams;
  @override
  final double consumedGrams;
  @override
  final double cost;

  @override
  String get label => supplierName;
}
