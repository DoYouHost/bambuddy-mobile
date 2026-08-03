import '../../core/models/api_key.dart';
import '../../l10n/app_localizations.dart';

/// What a scope flag lets a key do, in words. The server sends no labels for
/// these (unlike the permission catalog), so they live here.
String apiKeyScopeLabel(AppLocalizations l10n, ApiKeyScope scope) =>
    switch (scope) {
      ApiKeyScope.readStatus => l10n.apiKeyScopeRead,
      ApiKeyScope.queue => l10n.apiKeyScopeQueue,
      ApiKeyScope.controlPrinter => l10n.apiKeyScopeControl,
      ApiKeyScope.manageLibrary => l10n.apiKeyScopeLibrary,
      ApiKeyScope.manageInventory => l10n.apiKeyScopeInventory,
      ApiKeyScope.manageMaintenance => l10n.apiKeyScopeMaintenance,
      ApiKeyScope.manageArchives => l10n.apiKeyScopeArchives,
      ApiKeyScope.manageProjects => l10n.apiKeyScopeProjects,
      ApiKeyScope.accessCloud => l10n.apiKeyScopeCloud,
      ApiKeyScope.updateEnergyCost => l10n.apiKeyScopeEnergy,
    };

/// The longer line under the switch — what the flag actually reaches, where
/// that is not obvious from its name.
String? apiKeyScopeHint(AppLocalizations l10n, ApiKeyScope scope) =>
    switch (scope) {
      ApiKeyScope.readStatus => l10n.apiKeyScopeReadHint,
      ApiKeyScope.controlPrinter => l10n.apiKeyScopeControlHint,
      ApiKeyScope.accessCloud => l10n.apiKeyScopeCloudHint,
      ApiKeyScope.updateEnergyCost => l10n.apiKeyScopeEnergyHint,
      _ => null,
    };
