// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get printersTitle => 'Imprimantes';

  @override
  String get changeServer => 'Changer de serveur';

  @override
  String get sessionExpired => 'Session expirée — reconnectez-vous';

  @override
  String get signInRequiredTitle => 'Se reconnecter';

  @override
  String get signInRequiredBody =>
      'Le serveur a rejeté votre mot de passe enregistré, l\'application a donc cessé de réessayer — des tentatives répétées risquent de bloquer votre compte. Reconnectez-vous et utilisez un nouveau mot de passe s\'il a été modifié.';

  @override
  String get signInRequiredAction => 'Se connecter';

  @override
  String get signInRequiredTwoFactorBody =>
      'Votre compte requiert désormais un deuxième facteur d\'authentification et l\'application ne peut pas le fournir en arrière-plan — elle a donc cessé de se connecter automatiquement. Reconnectez-vous et saisissez le code.';

  @override
  String get later => 'Plus tard';

  @override
  String get serverUnreachableStale =>
      'Serveur inaccessible — les données peuvent être obsolètes';

  @override
  String get wsReconnecting =>
      'Aucune connexion en direct — actualisation toutes les 5 s';

  @override
  String get connLive => 'En direct';

  @override
  String get connLiveTooltip => 'Mises à jour en temps réel via WebSocket';

  @override
  String get connPolling => 'Interrogation';

  @override
  String get connPollingTooltip =>
      'Aucune connexion en direct — actualisation toutes les 5 s (REST)';

  @override
  String get connectFailed => 'Impossible de se connecter au serveur';

  @override
  String get filePickerFailed =>
      'Impossible d\'ouvrir le sélecteur de fichiers';

  @override
  String get retry => 'Réessayer';

  @override
  String get back => 'Retour';

  @override
  String get searchPrinters => 'Rechercher des imprimantes…';

  @override
  String get noPrinters => 'Aucune imprimante — ajoutez-en sur le serveur';

  @override
  String noSearchResults(String query) {
    return 'Aucun résultat pour « $query »';
  }

  @override
  String get noPrintersMatchFilters =>
      'Aucune imprimante ne correspond aux filtres actuels';

  @override
  String get dashboardFilters => 'Filtres';

  @override
  String get filterStatus => 'Statut';

  @override
  String get filtersClear => 'Effacer';

  @override
  String get hideOffline => 'Masquer les imprimantes hors ligne';

  @override
  String get statusAll => 'Toutes';

  @override
  String get statusPrinting => 'En impression';

  @override
  String get statusIdle => 'Inactive';

  @override
  String get statusPaused => 'En pause';

  @override
  String get statusFinished => 'Terminée';

  @override
  String get statusErrorFilter => 'Erreur';

  @override
  String get statusOfflineFilter => 'Hors ligne';

  @override
  String get addPrinterTitle => 'Ajouter une imprimante';

  @override
  String get addPrinterName => 'Nom';

  @override
  String get addPrinterIp => 'Adresse IP';

  @override
  String get addPrinterSerial => 'Numéro de série';

  @override
  String get addPrinterAccessCode => 'Code d\'accès';

  @override
  String get addPrinterModel => 'Modèle';

  @override
  String get addPrinterModelOptional => 'Facultatif';

  @override
  String get addPrinterModelNone => 'Non défini';

  @override
  String get addPrinterLocation => 'Emplacement';

  @override
  String get addPrinterLocationOptional => 'Facultatif';

  @override
  String get addPrinterSubmit => 'Ajouter l\'imprimante';

  @override
  String get addPrinterConnectionNote =>
      'Le serveur vérifie la connexion avant d\'enregistrer. Une adresse IP ou un code d\'accès incorrect sera donc signalé et rien ne sera créé.';

  @override
  String get addPrinterRequiredField => 'Obligatoire';

  @override
  String get addPrinterSuccess => 'Imprimante ajoutée';

  @override
  String get addPrinterErrConnection =>
      'Impossible de se connecter à l\'imprimante. Vérifiez l\'adresse IP, le numéro de série et le code d\'accès, et assurez-vous que le mode LAN uniquement est activé.';

  @override
  String get addPrinterErrDuplicate =>
      'Une imprimante avec ce numéro de série existe déjà';

  @override
  String get addPrinterErrForbidden =>
      'Vous n\'avez pas l\'autorisation d\'ajouter des imprimantes';

  @override
  String get addPrinterErrGeneric =>
      'Impossible d\'ajouter l\'imprimante. Réessayez.';

  @override
  String get addPrinterAutoArchive =>
      'Archiver automatiquement les impressions terminées';

  @override
  String get addPrinterScanTitle => 'Rechercher des imprimantes sur le réseau';

  @override
  String get addPrinterSubnet => 'Sous-réseau à analyser';

  @override
  String get addPrinterScanButton =>
      'Analyser le sous-réseau pour trouver des imprimantes';

  @override
  String get addPrinterDiscoverNetwork =>
      'Détecter les imprimantes sur le réseau';

  @override
  String addPrinterScanning(int scanned, int total) {
    return 'Analyse en cours… $scanned/$total';
  }

  @override
  String get addPrinterScanningPlain => 'Analyse en cours…';

  @override
  String get addPrinterScanNoResults => 'Aucune imprimante trouvée';

  @override
  String get addPrinterScanError => 'Échec de l\'analyse. Réessayez.';

  @override
  String get addPrinterSubnetCustomOption => 'Sous-réseau personnalisé…';

  @override
  String get addPrinterSubnetCustomLabel => 'Sous-réseau personnalisé (CIDR)';

  @override
  String get addPrinterSubnetDockerNote =>
      'Docker détecté. Saisissez le sous-réseau de votre imprimante en notation CIDR. Nécessite network_mode: host dans le fichier docker-compose.yml.';

  @override
  String get addPrinterSubnetCustomNote =>
      'Utilisez un sous-réseau personnalisé si votre imprimante se trouve sur un réseau différent de celui du serveur. Les ports FTP (990) et MQTT (8883) doivent être accessibles à travers le routage.';

  @override
  String get addPrinterDiagnostic => 'Exécuter le diagnostic';

  @override
  String get addPrinterDiagnosticRunning => 'Diagnostic en cours…';

  @override
  String get addPrinterDiagnosticError => 'Échec du diagnostic. Réessayez.';

  @override
  String get diagOverallOk => 'Tous les contrôles ont réussi';

  @override
  String get diagOverallWarnings => 'Terminé avec des avertissements';

  @override
  String get diagOverallProblems => 'Problèmes détectés';

  @override
  String get diagCheckPortMqtt => 'Port MQTT (8883)';

  @override
  String get diagCheckPortFtps => 'Port FTPS (990)';

  @override
  String get diagCheckPortRtsps => 'Port caméra (322)';

  @override
  String get diagCheckNetworkMode => 'Mode réseau';

  @override
  String get diagCheckSubnet => 'Accessibilité du sous-réseau';

  @override
  String get diagCheckMqttAuth => 'Identifiants MQTT';

  @override
  String get diagCheckDeveloperMode => 'Mode développeur / LAN';

  @override
  String get changeServerQuestion => 'Changer de serveur ?';

  @override
  String get changeServerWarning =>
      'Le profil et les identifiants enregistrés seront supprimés.';

  @override
  String get cancel => 'Annuler';

  @override
  String get clear => 'Effacer';

  @override
  String get change => 'Modifier';

  @override
  String get noActivePrints => 'Aucune impression en cours';

  @override
  String printingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impressions en cours',
      one: '$count impression en cours',
    );
    return '$_temp0';
  }

  @override
  String get nextAvailableLabel => 'Prochaine disponible : ';

  @override
  String get tempNozzle => 'Buse';

  @override
  String get tempBed => 'Plateau';

  @override
  String get tempChamber => 'Chambre';

  @override
  String tempNozzleNumbered(String n) {
    return 'Buse $n';
  }

  @override
  String get ctrlFanPart => 'Ventilateur de pièce';

  @override
  String get ctrlFanAux => 'Ventilateur auxiliaire';

  @override
  String get ctrlFanAux2 => 'Ventilateur auxiliaire gauche';

  @override
  String get ctrlFanChamber => 'Ventilateur de chambre';

  @override
  String get ctrlFanExhaust => 'Ventilateur d\'extraction';

  @override
  String get ctrlFanPartShort => 'Pièce';

  @override
  String get ctrlFanAuxShort => 'Aux';

  @override
  String get ctrlFanAux2Short => 'Aux G';

  @override
  String get ctrlFanChamberShort => 'Chambre';

  @override
  String get ctrlFanExhaustShort => 'Extraction';

  @override
  String get ctrlSpeed => 'Vitesse';

  @override
  String get ctrlLight => 'Éclairage de la chambre';

  @override
  String get ctrlLightOn => 'Allumée';

  @override
  String get ctrlLightOff => 'Éteinte';

  @override
  String get ctrlAirduct => 'Conduit d\'air';

  @override
  String get ctrlAirductCooling => 'Refroidissement';

  @override
  String get ctrlAirductHeating => 'Chauffage';

  @override
  String get ctrlOff => 'Arrêt';

  @override
  String get ctrlSet => 'Définir';

  @override
  String get ctrlActivate => 'Activer';

  @override
  String get ctrlNozzleActive => 'Active';

  @override
  String get ctrlDry => 'Séchage';

  @override
  String get ctrlDrying => 'Séchage en cours';

  @override
  String get ctrlDryStart => 'Démarrer';

  @override
  String get ctrlDryFilament => 'Filament';

  @override
  String get ctrlDryTemp => 'Température';

  @override
  String get ctrlDryDuration => 'Durée';

  @override
  String ctrlDryHours(int h) {
    return '$h h';
  }

  @override
  String get ctrlDryAutoIdle =>
      'Séchage automatique en cas d\'humidité élevée.';

  @override
  String get ctrlDryAutoQueue =>
      'Séchage automatique entre les impressions en file d\'attente.';

  @override
  String get ctrlDryAutoWhilePrinting => 'Pendant les impressions également.';

  @override
  String get ctrlDryStartWhen => 'Heure de début';

  @override
  String get ctrlDryStartNow => 'Maintenant';

  @override
  String get ctrlDryStartAfter => 'Plus tard';

  @override
  String get ctrlDryStartAt => 'À une heure précise';

  @override
  String get ctrlDryPickTime => 'Choisir une heure';

  @override
  String get ctrlDrySchedule => 'Programmer';

  @override
  String get ctrlDryScheduled => 'Séchage programmé';

  @override
  String get ctrlDryScheduleTimePast => 'Choisissez une heure dans le futur';

  @override
  String ctrlDryScheduledFor(String time) {
    return 'Séchage à $time';
  }

  @override
  String get ctrlDryScheduledAsap =>
      'Séchage programmé, en attente de l\'imprimante';

  @override
  String get ctrlDryScheduleCancel => 'Annuler le séchage programmé';

  @override
  String get ctrlDryScheduleDismiss => 'Ignorer';

  @override
  String ctrlDryScheduleFailed(String reason) {
    return 'Échec du séchage programmé : $reason';
  }

  @override
  String get ctrlDryScheduleFailedUnknown => 'erreur inconnue';

  @override
  String get ctrlDryWaitPower => 'Branchez l\'adaptateur secteur de l\'AMS';

  @override
  String get ctrlDryWaitRetract =>
      'Rétractez le filament à la sortie de l\'AMS';

  @override
  String get ctrlDryWaitBlocked =>
      'L\'AMS ne peut pas lancer le séchage pour le moment';

  @override
  String get ctrlDryWaitAmsNotFound => 'En attente de la détection de l\'AMS';

  @override
  String get ctrlDryWaitOffline =>
      'En attente de la connexion de l\'imprimante';

  @override
  String get ctrlDryWaitBusy => 'En attente que l\'imprimante soit disponible';

  @override
  String get ctrlDryWaitAlreadyDrying =>
      'En attente de la fin du cycle en cours';

  @override
  String get ctrlDryWaitInterrupted =>
      'Interrompu, redémarrera lorsque l\'imprimante sera disponible';

  @override
  String get ctrlMove => 'Déplacer';

  @override
  String get ctrlMoveHome => 'Retour à l\'origine';

  @override
  String get ctrlMoveHomeStarted => 'Retour à l\'origine démarré';

  @override
  String get ctrlMoveStep => 'Pas';

  @override
  String get ctrlMoveZ => 'Z (écart du plateau)';

  @override
  String get ctrlMoveZUp => 'Haut';

  @override
  String get ctrlMoveZDown => 'Bas';

  @override
  String get ctrlMoveExtruder => 'Extrudeur';

  @override
  String get ctrlMoveExtrude => 'Extruder';

  @override
  String get ctrlMoveRetract => 'Rétracter';

  @override
  String get ctrlMoveLength => 'Longueur';

  @override
  String ctrlMoveMm(int d) {
    return '$d mm';
  }

  @override
  String get ctrlPause => 'Pause';

  @override
  String get ctrlResume => 'Reprendre';

  @override
  String get ctrlStop => 'Arrêter';

  @override
  String get ctrlStopConfirmTitle => 'Arrêter l\'impression ?';

  @override
  String get ctrlStopConfirmBody =>
      'Cela annule l\'impression en cours. Elle ne pourra pas être reprise.';

  @override
  String get ctrlForbidden =>
      'Aucune autorisation pour contrôler cette imprimante';

  @override
  String get ctrlFailed => 'Impossible d\'envoyer la commande';

  @override
  String get skipObjectsTitle => 'Ignorer des objets';

  @override
  String get skipObjectsSkip => 'Ignorer';

  @override
  String get skipObjectsSkippedTag => 'Ignoré';

  @override
  String skipObjectsSkippedToast(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objets ignorés',
      one: '« $names » ignoré',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ignorer $count objets ?',
      one: 'Ignorer cet objet ?',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '« $names » seront ignorés pour le reste de cette impression. Cette action est irréversible.',
      one:
          '« $names » sera ignoré pour le reste de cette impression. Cette action est irréversible.',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnés',
      one: '$count sélectionné',
    );
    return '$_temp0';
  }

  @override
  String get skipObjectsSelectHint =>
      'Appuyez sur un objet ci-dessus ou ci-dessous pour le sélectionner';

  @override
  String get skipObjectsMatchInfo =>
      'Faites correspondre les identifiants avec l\'écran de l\'imprimante';

  @override
  String get skipObjectsMatchHint =>
      'L\'écran de l\'imprimante affiche les identifiants des objets sur le plateau d\'impression';

  @override
  String skipObjectsCounter(int skipped, int total) {
    return '$skipped/$total ignorés';
  }

  @override
  String skipObjectsActiveCount(int count) {
    return '$count actifs';
  }

  @override
  String skipObjectsWaitForLayer(int layer) {
    return 'Ignorer des objets est possible à partir de la couche 2 (couche actuelle : $layer)';
  }

  @override
  String get skipObjectsEmpty => 'Aucun objet imprimable';

  @override
  String get skipObjectsEmptyHint =>
      'Les objets se chargent au lancement d\'une impression. Rechargez si une impression est en cours.';

  @override
  String get skipObjectsReload => 'Recharger';

  @override
  String get skipObjectsLoadFailed =>
      'Impossible de charger les objets imprimables.';

  @override
  String get speedSilent => 'Silencieux';

  @override
  String get speedStandard => 'Standard';

  @override
  String get speedSport => 'Sport';

  @override
  String get speedLudicrous => 'Insensé';

  @override
  String get smartPlugOn => 'Allumée';

  @override
  String get smartPlugOff => 'Éteinte';

  @override
  String get smartPlugUnreachable => 'Inaccessible';

  @override
  String get smartPlugMonitorOnly => 'Surveillance uniquement';

  @override
  String get smartPlugCantPowerOff =>
      'Impossible de couper l\'alimentation pendant que l\'imprimante imprime';

  @override
  String get smartPlugOffConfirmTitle => 'Couper l\'alimentation ?';

  @override
  String get smartPlugOffConfirmBody =>
      'L\'imprimante perdra immédiatement son alimentation.';

  @override
  String get smartPlugTurnOff => 'Éteindre';

  @override
  String get smartPlugOnConfirmTitle => 'Mettre sous tension ?';

  @override
  String get smartPlugOnConfirmBody => 'L\'imprimante sera mise sous tension.';

  @override
  String get smartPlugTurnOn => 'Allumer';

  @override
  String powerWatts(int watts) {
    return '$watts W';
  }

  @override
  String get totalPowerTooltip => 'Consommation totale de toutes les prises';

  @override
  String get queueEmpty => 'La file d\'attente est vide';

  @override
  String get queueAmsFromSlicer => 'AMS depuis le slicer';

  @override
  String queueAnyOfModels(String models) {
    return 'Au choix parmi : $models';
  }

  @override
  String get queueDeleteTitle => 'Retirer de la file d\'attente ?';

  @override
  String get queueDeleteBody =>
      'Cela retire l\'élément de la file d\'attente d\'impression.';

  @override
  String get queueDeleteConfirm => 'Retirer';

  @override
  String get queueStart => 'Démarrer maintenant';

  @override
  String get queueStartNext => 'Lancer le suivant';

  @override
  String get queueCancel => 'Annuler';

  @override
  String get queueStop => 'Arrêter l\'impression';

  @override
  String get queueStopTitle => 'Arrêter cette impression ?';

  @override
  String get queueStopBody =>
      'L\'imprimante arrête d\'imprimer et l\'élément quitte la file d\'attente. Ce qui a été imprimé jusqu\'à présent ne peut pas être repris.';

  @override
  String get queueStopConfirm => 'Arrêter l\'impression';

  @override
  String get queueRemove => 'Retirer de la file d\'attente';

  @override
  String get queueRemoveStoppedTitle => 'Retirer de la file d\'attente ?';

  @override
  String get queueRemoveStoppedBody =>
      'L\'imprimante n\'affiche pas cette impression comme étant en cours. La retirer efface l\'élément de la file d\'attente.';

  @override
  String get queueStopped => 'Impression arrêtée';

  @override
  String get queueRemoved => 'Retiré de la file d\'attente';

  @override
  String get queueRemovalStatusChanged =>
      'Cet élément n\'est plus dans l\'état affiché. Actualisez la file d\'attente et réessayez.';

  @override
  String get queueNoFreePrinters =>
      'Aucune imprimante disponible pour le moment';

  @override
  String get queuePrintStarted => 'Impression démarrée';

  @override
  String get queueStatusPending => 'En attente';

  @override
  String get queueStatusScheduled => 'Programmé';

  @override
  String get queueStatusPrinting => 'En cours d\'impression';

  @override
  String get queueStatusPaused => 'En pause';

  @override
  String get archiveSearchHint => 'Rechercher dans les archives';

  @override
  String get archiveEmpty => 'Aucune impression archivée';

  @override
  String archiveSearchFailed(String query) {
    return 'Impossible de rechercher « $query ». Essayez un autre terme.';
  }

  @override
  String get archiveNoMatches =>
      'Aucune impression ne correspond à vos filtres';

  @override
  String get archiveFilters => 'Filtres';

  @override
  String get archiveFiltersClear => 'Effacer les filtres';

  @override
  String get archiveSortLabel => 'Trier par';

  @override
  String get archiveSortDateDesc => 'Plus récentes d\'abord';

  @override
  String get archiveSortDateAsc => 'Plus anciennes d\'abord';

  @override
  String get archiveSortNameAsc => 'Nom A–Z';

  @override
  String get archiveSortNameDesc => 'Nom Z–A';

  @override
  String get archiveSortSizeDesc => 'Plus volumineuses d\'abord';

  @override
  String get archiveSortSizeAsc => 'Moins volumineuses d\'abord';

  @override
  String get archiveFilterFileType => 'Fichiers';

  @override
  String get archiveFileTypeAll => 'Tous les fichiers';

  @override
  String get archiveFileTypeGcode => 'Découpés';

  @override
  String get archiveFileTypeSource => 'Source';

  @override
  String get archiveFilterFlags => 'Afficher';

  @override
  String get archiveFilterFavorites => 'Favoris';

  @override
  String get archiveFilterHideFailed => 'Masquer les échecs';

  @override
  String get archiveFilterHideDuplicates => 'Masquer les doublons';

  @override
  String get archiveFilterPrinter => 'Imprimante';

  @override
  String get archiveFilterMaterial => 'Matériau';

  @override
  String get archiveFilterColors => 'Couleurs';

  @override
  String get archiveColorModeAny => 'Au moins une';

  @override
  String get archiveColorModeAll => 'Toutes';

  @override
  String get archiveFavorite => 'Ajouter aux favoris';

  @override
  String get archiveUnfavorite => 'Retirer des favoris';

  @override
  String get archiveFavoriteFailed => 'Impossible de mettre à jour le favori';

  @override
  String get archiveReprint => 'Réimprimer';

  @override
  String get archiveAddToQueue => 'Ajouter à la file d\'attente';

  @override
  String get archiveTimelapse => 'Regarder le timelapse';

  @override
  String archivePhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Voir les photos ($count)',
      one: 'Voir la photo',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaAction => 'Enregistrements et photos';

  @override
  String get archiveMediaOnServer => 'Sur le serveur';

  @override
  String archiveMediaOnPrinter(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sur l\'imprimante ($count)',
      zero: 'Sur l\'imprimante',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaSearching => 'Recherche sur l\'imprimante…';

  @override
  String get archiveMediaNothingOnPrinter => 'Rien sur l\'imprimante';

  @override
  String archiveMediaPhotoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: 'une photo',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaKindTimelapse => 'Timelapse';

  @override
  String get archiveMediaKindIpcam => 'Caméra';

  @override
  String archiveMediaDownloadSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers',
      one: 'un fichier',
      zero: 'la sélection',
    );
    return 'Télécharger $_temp0';
  }

  @override
  String get archiveMediaSaved => 'Vidéo enregistrée';

  @override
  String get archiveMediaNoFilePermission =>
      'Aucune autorisation pour les fichiers de l\'imprimante';

  @override
  String get archiveMediaPrinterMissing =>
      'L\'imprimante n\'est plus disponible';

  @override
  String get archiveMediaTimelapseUnavailable =>
      'Timelapses : aucune réponse de l\'imprimante';

  @override
  String get archiveMediaIpcamUnavailable =>
      'Caméra : aucune réponse de l\'imprimante';

  @override
  String archivePlate(int plate) {
    return 'Plateau $plate';
  }

  @override
  String archivePlateDetail(int plate) {
    return 'Plateau $plate d\'un fichier multi-plateaux';
  }

  @override
  String get archivePhotosTitle => 'Photos';

  @override
  String get archivePhotosEmpty => 'Aucune photo pour cette impression';

  @override
  String get archivePhotoFailed => 'Impossible de charger cette photo.';

  @override
  String get archiveFilamentUsed => 'Filament utilisé';

  @override
  String archiveFilamentGrams(String grams) {
    return '$grams g';
  }

  @override
  String archiveFilamentActual(String grams, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$grams consommés sur $count exécutions',
      one: '$grams consommés',
    );
    return '$_temp0';
  }

  @override
  String get archiveFilamentNoActual => 'Aucune utilisation enregistrée';

  @override
  String get archiveFilamentSaving => 'Enregistrement…';

  @override
  String get archiveFilamentNone => 'Non enregistré';

  @override
  String get archiveFilamentLabel => 'Poids (g)';

  @override
  String get archiveFilamentNotANumber =>
      'Entrez un nombre ou laissez vide pour effacer le poids.';

  @override
  String archiveFilamentOutOfRange(String max) {
    return 'Un poids compris entre 0 et $max g.';
  }

  @override
  String get archiveFilamentSaved => 'Poids du filament enregistré';

  @override
  String get archiveFilamentUnsupported =>
      'Ce serveur ne prend pas encore en charge la saisie manuelle du poids du filament. Mettez à jour bambuddy.';

  @override
  String get archiveHasTimelapse => 'Avec timelapse';

  @override
  String archiveHasPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Avec $count photos',
      one: 'Avec une photo',
    );
    return '$_temp0';
  }

  @override
  String get timelapseTitle => 'Timelapse';

  @override
  String get timelapseError => 'Impossible de lire ce timelapse.';

  @override
  String timelapseHttpError(int status) {
    return 'Le serveur n\'a pas pu fournir ce timelapse ($status).';
  }

  @override
  String get timelapseStalled =>
      'Le serveur transmet la vidéo, mais le lecteur ne l\'a jamais démarrée.';

  @override
  String get timelapsePlay => 'Lire';

  @override
  String get timelapsePause => 'Pause';

  @override
  String get timelapseSave => 'Enregistrer dans la galerie';

  @override
  String get timelapseShare => 'Partager';

  @override
  String get timelapseSaved => 'Enregistré dans la galerie';

  @override
  String get timelapseSaveFailed => 'Impossible d\'enregistrer la vidéo';

  @override
  String get timelapseSaveDenied =>
      'Bambuddy a besoin de l\'autorisation d\'écriture dans la galerie sur cette version d\'Android.';

  @override
  String get timelapseEdit => 'Modifier';

  @override
  String get timelapseEditSave => 'Enregistrer';

  @override
  String get timelapseEditTitle => 'Modifier le timelapse';

  @override
  String get timelapseEditTrim => 'Raccourcir';

  @override
  String get timelapseEditSpeed => 'Vitesse';

  @override
  String timelapseEditOutput(String length) {
    return 'Résultat : $length';
  }

  @override
  String timelapseEditSource(String length, int width, int height) {
    return 'Original : $length en $width×$height';
  }

  @override
  String get timelapseEditSaveTitle => 'Écraser l\'enregistrement ?';

  @override
  String get timelapseEditSaveMessage =>
      'Le serveur encode à nouveau le timelapse et remplace l\'original. Aucune copie ne permettra de revenir en arrière.';

  @override
  String get timelapseEditProcessing =>
      'Le serveur encode à nouveau la vidéo. Sur une machine peu puissante, cela prend plusieurs minutes — quitter cet écran n\'interrompt pas le processus.';

  @override
  String get timelapseEdited => 'Timelapse mis à jour';

  @override
  String get gcodeViewerTitle => 'Aperçu du G-code';

  @override
  String get gcodeViewerOpen => 'Aperçu du G-code';

  @override
  String get gcodeViewerError => 'Impossible de charger l\'aperçu du G-code.';

  @override
  String get gcodeViewerLoading => 'Téléchargement du G-code…';

  @override
  String get gcodeViewerParsing => 'Lecture de la trajectoire d\'outil…';

  @override
  String get gcodeViewerTravels => 'Déplacements à vide';

  @override
  String get gcodeViewerColorByFilament => 'Filament';

  @override
  String get gcodeViewerColorByFeature => 'Type de ligne';

  @override
  String get gcodeViewerColorByHeight => 'Hauteur';

  @override
  String get gcodeViewerColorByWidth => 'Largeur';

  @override
  String get gcodeSingleLayer => 'couche unique';

  @override
  String gcodeViewerFilamentSlot(int n) {
    return 'Filament $n';
  }

  @override
  String get gcodeViewerEmpty =>
      'Ce fichier ne contient aucune trajectoire — il n\'a pas encore été découpé.';

  @override
  String gcodeViewerHttpError(int status) {
    return 'Le serveur n\'a pas pu fournir le G-code pour ce fichier ($status).';
  }

  @override
  String get gcodeFeatureWall => 'Parois';

  @override
  String get gcodeFeatureSparseInfill => 'Remplissage clairsemé';

  @override
  String get gcodeFeatureSolidInfill => 'Remplissage plein';

  @override
  String get gcodeFeatureSkirt => 'Jupe / bordure';

  @override
  String get gcodeFeatureSupport => 'Support';

  @override
  String get gcodeFeatureGapFill => 'Remplissage des espaces';

  @override
  String get gcodeFeatureBridge => 'Pont / surplomb';

  @override
  String get gcodeFeatureIroning => 'Repassage';

  @override
  String get gcodeFeaturePrimeTower => 'Tour d\'amorçage';

  @override
  String get archiveNo3mfTitle =>
      'Certaines impressions récentes ont été archivées sans miniature';

  @override
  String get archiveNo3mfBody =>
      'Le slicer n\'a pas laissé le fichier .gcode.3mf sur la carte de l\'imprimante, Bambuddy n\'a donc pas pu récupérer la miniature ni les métadonnées du slicer. En général, l\'option « Store sent files on external storage » est désactivée dans l\'onglet Device du slicer.';

  @override
  String get archiveNo3mfTitleInternal =>
      'Certaines impressions récentes sont restées sur le stockage interne de l\'imprimante';

  @override
  String get archiveNo3mfBodyInternal =>
      'Bambu Studio a placé le fichier découpé sur le stockage interne de l\'imprimante au lieu de la carte, il n\'y avait donc rien à lire via FTP. Sur les séries H2 et la P2S, le bouton Imprimer fait systématiquement cela — activer le paramètre du slicer ne change rien. Ces impressions sont tout de même archivées avec leur nom et leur durée, mais sans miniature ni métadonnées du slicer. Pour des archives complètes, lancez l\'impression depuis Bambuddy ou découpez dans OrcaSlicer — dans les deux cas avec une carte ou une clé USB dans l\'imprimante.';

  @override
  String get archiveNo3mfTitleNoStorage =>
      'Certaines impressions récentes n\'ont pas pu être archivées — aucun stockage dans l\'imprimante';

  @override
  String get archiveNo3mfBodyNoStorage =>
      'L\'imprimante n\'indique aucune carte ni clé USB dans son logement, le fichier découpé n\'avait donc nulle part où s\'enregistrer et Bambuddy n\'avait rien à lire. Insérez-en une et la prochaine impression sera intégralement archivée.';

  @override
  String get archiveNo3mfDocs => 'Voir l\'étape 4 de l\'installation';

  @override
  String get archiveNo3mfDocsWhy => 'Pourquoi cela se produit';

  @override
  String get archiveNo3mfDismiss => 'Ignorer cet avis';

  @override
  String get archiveNotSliceable =>
      'Cette impression ne dispose d\'aucun fichier source ni modèle, elle ne peut donc pas être redécoupée.';

  @override
  String get archiveDelete => 'Supprimer';

  @override
  String get archiveDeleteTitle => 'Supprimer l\'impression ?';

  @override
  String archiveDeleteBody(String name) {
    return 'Supprimer « $name » de l\'archive.';
  }

  @override
  String get archiveDeletePurgeStats => 'Supprimer aussi des statistiques';

  @override
  String get archiveDeletePurgeStatsHint =>
      'Sinon, l\'impression est conservée dans vos totaux statistiques.';

  @override
  String get archiveDeleted => 'Impression supprimée';

  @override
  String get archiveDeleteFailed => 'Impossible de supprimer l\'impression';

  @override
  String get archiveSelectAll => 'Tout sélectionner';

  @override
  String archiveSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnés',
      one: '1 sélectionné',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer $count impressions ?',
      one: 'Supprimer 1 impression ?',
    );
    return '$_temp0';
  }

  @override
  String get archiveDeleteSelectedBody =>
      'Supprimer les impressions sélectionnées de l\'archive.';

  @override
  String archiveDeletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impressions supprimées',
      one: '1 impression supprimée',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSomeFailed(int ok, int failed) {
    return '$ok supprimées, $failed en échec';
  }

  @override
  String get archivePurgeOlder => 'Purger les anciennes impressions…';

  @override
  String get archivePurgeTitle => 'Purger les anciennes impressions';

  @override
  String get archivePurgeOlderThan => 'Plus anciennes que';

  @override
  String archivePurgeDaysOption(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days jours',
      one: '1 jour',
    );
    return '$_temp0';
  }

  @override
  String archivePurgePreview(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impressions · $size',
      one: '1 impression · $size',
    );
    return '$_temp0';
  }

  @override
  String get archivePurgeNothing => 'Aucune impression plus ancienne que cela.';

  @override
  String get archivePurgePreviewError => 'Impossible de charger l\'aperçu.';

  @override
  String archivePurgeResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impressions purgées',
      one: '1 impression purgée',
      zero: 'Aucune impression purgée',
    );
    return '$_temp0';
  }

  @override
  String get pickPrinterTitle => 'Choisir une imprimante';

  @override
  String get noPrintersAvailable => 'Aucune imprimante disponible';

  @override
  String get detailsShow => 'Détails';

  @override
  String get detailsHide => 'Masquer les détails';

  @override
  String get cameraTooltip => 'Caméra';

  @override
  String get cameraConnecting => 'Connexion à la caméra…';

  @override
  String get cameraError => 'Impossible de charger le flux de la caméra';

  @override
  String get cameraDemoUnavailable =>
      'L\'aperçu de la caméra n\'est pas disponible en mode démo';

  @override
  String amsUnit(int number) {
    return 'AMS $number';
  }

  @override
  String get externalSpool => 'Bobine externe';

  @override
  String get traySlotEmpty => 'Vide';

  @override
  String get amsSlotFilament => 'Filament';

  @override
  String get amsLoad => 'Charger';

  @override
  String get amsUnload => 'Décharger';

  @override
  String get amsRfidReread => 'Relire le tag RFID';

  @override
  String get amsLoadStarted => 'Chargement du filament…';

  @override
  String get amsUnloadStarted => 'Déchargement du filament…';

  @override
  String get amsRfidRereadStarted => 'Relecture du tag RFID…';

  @override
  String amsFeedTitle(String slot) {
    return 'Dans quelle buse charger $slot ?';
  }

  @override
  String get amsFeedPrompt =>
      'Le Filament Track Switch peut acheminer cet emplacement vers l\'une ou l\'autre buse, l\'imprimante ne peut donc pas déterminer où envoyer le filament.';

  @override
  String get amsFeedAlreadyLoaded => 'déjà chargé';

  @override
  String get amsSwitchNotReady =>
      'Le Filament Track Switch n\'est pas encore configuré. Assignez chaque AMS à une entrée sur l\'imprimante, puis réessayez.';

  @override
  String get amsUnloadSlotNotLoaded =>
      'Aucune buse n\'est alimentée depuis cet emplacement';

  @override
  String get amsActionsWhilePrinting => 'Indisponible pendant l\'impression';

  @override
  String get amsSlotConfigure => 'Configurer l\'emplacement';

  @override
  String get amsSlotConfigTitle => 'Configuration de l\'emplacement';

  @override
  String get amsSlotConfigSearch => 'Rechercher des préréglages';

  @override
  String get amsSlotConfigColour => 'Couleur';

  @override
  String get amsSlotConfigApply => 'Écrire sur l\'imprimante';

  @override
  String get amsSlotConfigStarted => 'Configuration de l\'emplacement…';

  @override
  String get amsSlotConfigNameNotSaved =>
      'Emplacement configuré, mais le nom du préréglage n\'a pas pu être enregistré';

  @override
  String get amsSlotConfigEmpty => 'Aucun préréglage de filament disponible';

  @override
  String get amsSlotConfigNoMatch =>
      'Aucun préréglage ne correspond à la recherche';

  @override
  String get amsSlotConfigCloudHint =>
      'Connectez-vous à Bambu Cloud pour choisir parmi vos propres préréglages.';

  @override
  String get amsSlotConfigCloudAction => 'Se connecter';

  @override
  String get amsSlotConfigTierLocal => 'Importés';

  @override
  String get amsSlotConfigTierCloud => 'Bambu Cloud';

  @override
  String get amsSlotConfigTierBuiltin => 'Intégrés';

  @override
  String amsSlotConfigOnlyPrinter(String model) {
    return 'Uniquement pour $model';
  }

  @override
  String amsSlotConfigOnlyPrinterHiding(String model, int hidden) {
    return 'Uniquement pour $model ($hidden masqués)';
  }

  @override
  String get amsSlotConfigModelUnknown =>
      'Modèle d\'imprimante inconnu — affichage de tous les préréglages';

  @override
  String get amsSlotConfigCurrent => 'Actuellement défini';

  @override
  String get amsSlotConfigKProfile => 'Profil K';

  @override
  String amsSlotConfigKProfileDefault(String value) {
    return 'Par défaut (K $value)';
  }

  @override
  String get amsSlotConfigKProfileOther => 'Autres profils';

  @override
  String get amsSlotConfigKProfileNone =>
      'Cette imprimante n\'a aucun profil K enregistré pour cette buse';

  @override
  String get amsSlotConfigKProfileUnavailable =>
      'Impossible de lire les profils K de l\'imprimante';

  @override
  String amsSlotConfigNozzleGuess(String diameter) {
    return 'L\'imprimante n\'a pas indiqué la taille de sa buse — $diameter mm supposé';
  }

  @override
  String amsSlotConfigKProfileValue(String value) {
    return 'K $value';
  }

  @override
  String get amsSlotConfigColourCatalogue => 'Couleurs du catalogue';

  @override
  String get amsSlotConfigColourCustom => 'Couleur personnalisée';

  @override
  String get amsSlotReset => 'Réinitialiser l\'emplacement';

  @override
  String get amsSlotResetConfirmTitle => 'Réinitialiser cet emplacement ?';

  @override
  String get amsSlotResetConfirmMessage =>
      'L\'imprimante oublie le filament configuré ici et bambuddy oublie de quel préréglage il s\'agissait.';

  @override
  String get amsSlotResetStarted => 'Réinitialisation de l\'emplacement…';

  @override
  String get extruderLeft => 'Extrudeur gauche';

  @override
  String get extruderRight => 'Extrudeur droit';

  @override
  String get extruderLeftShort => 'G';

  @override
  String get extruderRightShort => 'D';

  @override
  String get amsHumidityTooltip => 'Humidité de l\'AMS';

  @override
  String get amsTempTooltip => 'Température de l\'AMS';

  @override
  String amsHistoryTitle(String ams) {
    return 'Historique de $ams';
  }

  @override
  String get amsHistoryHumidity => 'Humidité';

  @override
  String get amsHistoryTemperature => 'Température';

  @override
  String get sensorHistoryCurrent => 'Actuel';

  @override
  String get sensorHistoryAverage => 'Moyenne';

  @override
  String get sensorHistoryMin => 'Min';

  @override
  String get sensorHistoryMax => 'Max';

  @override
  String get sensorHistoryRange6h => '6 h';

  @override
  String get sensorHistoryRange24h => '24 h';

  @override
  String get sensorHistoryRange48h => '48 h';

  @override
  String get sensorHistoryRange7d => '7 j';

  @override
  String get amsHistoryGood => 'Bonne';

  @override
  String get amsHistoryFair => 'Correcte';

  @override
  String get sensorHistoryEmpty => 'Aucune donnée pour cette période';

  @override
  String get sensorHistoryError => 'Impossible de charger l\'historique';

  @override
  String get amsHistoryRecordingInfo =>
      'Enregistré toutes les 5 minutes lorsque l\'imprimante est connectée';

  @override
  String get heaterHistoryTitle => 'Historique des températures';

  @override
  String get heaterHistoryOpen => 'Historique des températures';

  @override
  String get heaterHistoryReading => 'Mesure';

  @override
  String get heaterHistoryTarget => 'Cible';

  @override
  String get heaterHistoryRecordingInfo =>
      'Enregistré chaque minute lorsque l\'imprimante est connectée';

  @override
  String get wifiTooltip => 'Signal Wi-Fi';

  @override
  String get doorOpen => 'Porte ouverte';

  @override
  String get doorClosed => 'Porte fermée';

  @override
  String get firmwareUpToDate => 'Firmware à jour';

  @override
  String firmwareUpdateAvailable(String version) {
    return 'Mise à jour du firmware disponible : $version';
  }

  @override
  String get statusUnavailable => 'état non disponible';

  @override
  String get statusOffline => 'HORS LIGNE';

  @override
  String get online => 'en ligne';

  @override
  String get offline => 'hors ligne';

  @override
  String get widgetNoPrinter => 'Aucune imprimante';

  @override
  String get widgetStatusPrinting => 'Impression';

  @override
  String get widgetStatusPaused => 'En pause';

  @override
  String get widgetStatusFinished => 'Terminée';

  @override
  String get widgetStatusFailed => 'Échouée';

  @override
  String get widgetStatusIdle => 'Inactive';

  @override
  String get widgetStatusOffline => 'Hors ligne';

  @override
  String get widgetStatusError => 'Erreur';

  @override
  String get widgetMultiTitle => 'Imprimantes';

  @override
  String widgetMultiActive(int active, int total) {
    return '$active/$total actives';
  }

  @override
  String widgetMultiMore(int count) {
    return '+$count de plus';
  }

  @override
  String get widgetMultiGaugeLabel => 'en impression';

  @override
  String widgetMultiIdleCount(int count) {
    return '$count inactives';
  }

  @override
  String widgetMultiOfflineCount(int count) {
    return '$count hors ligne';
  }

  @override
  String get widgetMultiName => 'Bambuddy · Imprimantes';

  @override
  String get widgetMultiDescription =>
      'Toutes les imprimantes en un coup d\'œil';

  @override
  String remaining(String time) {
    return '$time restant';
  }

  @override
  String eta(String time) {
    return 'Fin $time';
  }

  @override
  String durationMinutes(int minutes) {
    return '${minutes}min';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}min';
  }

  @override
  String durationHours(int hours) {
    return '${hours}h';
  }

  @override
  String durationSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String get connectToServer => 'Se connecter au serveur';

  @override
  String get serverAddressLabel => 'Adresse du serveur bambuddy';

  @override
  String get serverAddressHint => 'ex. 192.168.1.10:8000';

  @override
  String get serverAddressHelper =>
      'Accès distant : utilisez HTTPS via un proxy inverse';

  @override
  String get testConnection => 'Tester la connexion';

  @override
  String get serverRequiresAuth => 'Le serveur requiert une authentification';

  @override
  String get authModeApiKey => 'Clé API (recommandée)';

  @override
  String get authModeLogin => 'Nom d\'utilisateur et mot de passe';

  @override
  String get apiKeyExplain =>
      'Une clé API n\'expire pas et dispose de permissions limitées — créez-en une sur le serveur : Paramètres → Clés API.';

  @override
  String get apiKeyLabel => 'Clé API';

  @override
  String get saveAndConnect => 'Enregistrer et connecter';

  @override
  String get loginExplain =>
      'Une session de connexion expire après 24 h. Cochez « Se souvenir de moi » pour que l\'application se reconnecte automatiquement.';

  @override
  String get usernameLabel => 'Nom d\'utilisateur ou e-mail';

  @override
  String get passwordLabel => 'Mot de passe';

  @override
  String get rememberMe => 'Se souvenir de moi';

  @override
  String get rememberMeSubtitle =>
      'Le mot de passe est stocké dans un espace sécurisé chiffré (Android Keystore)';

  @override
  String get signInAndConnect => 'Se connecter';

  @override
  String get twoFactorTitle => 'Authentification à deux facteurs';

  @override
  String get twoFactorMethodTotp => 'Authenticator';

  @override
  String get twoFactorMethodEmail => 'E-mail';

  @override
  String get twoFactorMethodBackup => 'Code de secours';

  @override
  String get twoFactorExplainTotp =>
      'Saisissez le code à 6 chiffres de votre application d\'authentification.';

  @override
  String get twoFactorExplainEmail =>
      'Demandez au serveur de vous envoyer un code à 6 chiffres par e-mail, puis saisissez-le ici.';

  @override
  String get twoFactorExplainEmailSent =>
      'Un code à 6 chiffres a été envoyé à l\'adresse de votre compte. Il expirera dans 10 minutes.';

  @override
  String get twoFactorExplainBackup =>
      'Saisissez l\'un des codes de secours à 8 caractères enregistrés lors de la configuration de la 2FA. Chaque code ne fonctionne qu\'une seule fois.';

  @override
  String get twoFactorCodeLabel => 'Code';

  @override
  String get twoFactorSendEmail => 'M\'envoyer un code par e-mail';

  @override
  String get twoFactorResendEmail => 'Envoyer un autre code';

  @override
  String get twoFactorVerify => 'Confirmer et se connecter';

  @override
  String get twoFactorBack => 'Utiliser un autre compte';

  @override
  String get twoFactorSessionNote =>
      'L\'application ne peut pas renouveler une session 2FA d\'elle-même et vous redemandera de vous connecter à son expiration. Une clé API n\'expire pas et évite cette étape.';

  @override
  String get tryDemo => 'Essayer la démo';

  @override
  String get scanApiKeyTitle => 'Scanner la clé API';

  @override
  String get scanApiKeyHint =>
      'Pointez l\'appareil photo vers le code QR de la clé API';

  @override
  String get cameraPermissionTitle => 'Accès à l\'appareil photo requis';

  @override
  String get cameraPermissionBody =>
      'Autorisez l\'accès à l\'appareil photo pour scanner des codes QR.';

  @override
  String get errMissingUrl => 'Saisissez l\'adresse du serveur';

  @override
  String get errMissingApiKey => 'Saisissez la clé API';

  @override
  String get errMissingCredentials =>
      'Saisissez le nom d\'utilisateur et le mot de passe';

  @override
  String get errRequiresServerSetup =>
      'Le serveur nécessite une configuration initiale — terminez-la dans un navigateur puis revenez ici.';

  @override
  String get errServerUnreachable => 'Serveur inaccessible';

  @override
  String get errUnauthorized => 'Non autorisé';

  @override
  String get errForbidden => 'Non autorisé — le serveur a refusé cette action';

  @override
  String errForbiddenDetail(String reason) {
    return 'Non autorisé : $reason';
  }

  @override
  String get errApiKeyOwnerDisabled =>
      'Le compte propriétaire de cette clé API a été désactivé ou supprimé — la clé restera refusée tant que ce compte ne sera pas restauré.';

  @override
  String errBadResponse(int code) {
    return 'Le serveur a renvoyé l\'erreur $code';
  }

  @override
  String get errBadCertificate =>
      'Certificat TLS invalide (les certificats auto-signés ne sont pas pris en charge dans la v1)';

  @override
  String get errConnection => 'Erreur de connexion';

  @override
  String get errMalformedResponse => 'Réponse du serveur malformée';

  @override
  String get errInvalidCredentials =>
      'Nom d\'utilisateur ou mot de passe incorrect';

  @override
  String get errTwoFactorUnsupported =>
      'Ce compte nécessite l\'authentification 2FA — non prise en charge dans cette version. Utilisez une clé API (Paramètres → Clés API sur le serveur).';

  @override
  String get errTwoFactorCodeRejected =>
      'Code incorrect — vérifiez-le et réessayez.';

  @override
  String get errTwoFactorChallengeExpired =>
      'La tentative de connexion a expiré — saisissez à nouveau votre mot de passe pour obtenir un nouveau code.';

  @override
  String get errTwoFactorMethodUnavailable =>
      'Cette méthode n\'est pas disponible pour ce compte — choisissez-en une autre.';

  @override
  String get errTwoFactorEmailUnavailable =>
      'Le serveur n\'a pas pu envoyer le code — aucun e-mail n\'est configuré ou votre compte ne possède pas d\'adresse. Utilisez une autre méthode.';

  @override
  String get errMissingTwoFactorCode => 'Saisissez le code';

  @override
  String get errApiKeyRejected =>
      'Clé API refusée — vérifiez la clé et ses autorisations (can_read_status requis)';

  @override
  String get errTooManyAttempts =>
      'Trop de tentatives — le serveur bloque la connexion pendant quelques minutes. Patientez et réessayez ou utilisez une clé API.';

  @override
  String get errSlotTagUnreadable =>
      'Cet emplacement ne comporte pas de tag RFID lisible — Spoolman associe les bobines par tag et ne peut donc pas accepter celle-ci. L\'inventaire intégré les assigne par emplacement.';

  @override
  String get errPrinterOffline =>
      'L\'imprimante est hors ligne, l\'application ne peut donc pas lire le contenu de l\'emplacement. Reconnectez-la et réessayez.';

  @override
  String notifOngoingBody(int percent, String eta) {
    return '$percent % · fin $eta';
  }

  @override
  String notifMorePrints(int count) {
    return '+$count';
  }

  @override
  String get printFinishedTitle => 'Impression terminée';

  @override
  String printFinishedBody(String name) {
    return '$name est terminé';
  }

  @override
  String get printFailedTitle => 'Échec de l\'impression';

  @override
  String printFailedBody(String name) {
    return '$name a échoué';
  }

  @override
  String get notifStartedTitle => 'Impression démarrée';

  @override
  String notifStartedBody(String name) {
    return 'L\'impression de $name a commencé';
  }

  @override
  String get notifFirstLayerTitle => 'Première couche terminée';

  @override
  String notifFirstLayerBody(String name) {
    return '$name a terminé sa première couche';
  }

  @override
  String notifMilestoneTitle(int percent) {
    return '$percent % imprimé';
  }

  @override
  String notifMilestoneBody(String name, int percent) {
    return '$name est terminé à $percent %';
  }

  @override
  String get notifPlateTitle => 'Plateau non vide';

  @override
  String notifPlateBody(String printer) {
    return 'Le plateau de $printer doit être libéré avant la prochaine impression';
  }

  @override
  String get notifOfflineTitle => 'Imprimante hors ligne';

  @override
  String notifOfflineBody(String printer) {
    return '$printer a perdu la connexion';
  }

  @override
  String get notifErrorTitle => 'Erreur de l\'imprimante';

  @override
  String notifErrorBody(String printer, String detail) {
    return '$printer : $detail';
  }

  @override
  String get notifLowFilamentTitle => 'Niveau de filament bas';

  @override
  String notifLowFilamentBody(String printer, int percent) {
    return 'Il reste $percent % de filament sur $printer';
  }

  @override
  String get notifHumidityTitle => 'Humidité AMS élevée';

  @override
  String get notifHumidityHtTitle => 'Humidité AMS-HT élevée';

  @override
  String notifHumidityBody(String printer, int value) {
    return 'L\'humidité de l\'AMS de $printer est de $value %';
  }

  @override
  String get notifBedCooledTitle => 'Plateau refroidi';

  @override
  String notifBedCooledBody(String printer, int temp) {
    return 'Le plateau de $printer a refroidi à $temp °C';
  }

  @override
  String get notifSettingsTitle => 'Notifications';

  @override
  String get notifSettingsHint =>
      'Choisissez les événements qui déclenchent une notification. Les modifications s\'appliqueront au prochain démarrage de la surveillance en arrière-plan.';

  @override
  String get notifMasterTitle => 'Notifications d\'événements';

  @override
  String get notifMasterDesc =>
      'Désactivez cette option pour couper toutes les alertes. La notification de progression de l\'impression en cours sera conservée.';

  @override
  String get notifEventsHeader => 'Événements';

  @override
  String get notifExtrasHeader => 'Détails';

  @override
  String get notifFinishPhotoTitle => 'Photo de l\'impression terminée';

  @override
  String get notifFinishPhotoDesc =>
      'Ajoute la photo prise par le serveur à la fin d\'une impression à la notification de réussite ou d\'échec, dès sa réception';

  @override
  String get notifThresholdsHeader => 'Seuils';

  @override
  String get notifEvtStarted => 'Impression démarrée';

  @override
  String get notifEvtStartedDesc => 'Lorsqu\'une impression commence';

  @override
  String get notifEvtFinished => 'Impression terminée';

  @override
  String get notifEvtFinishedDesc =>
      'Lorsqu\'une impression se termine avec succès';

  @override
  String get notifEvtFailed => 'Échec de l\'impression';

  @override
  String get notifEvtFailedDesc => 'Lorsqu\'une impression échoue';

  @override
  String get notifEvtFirstLayer => 'Première couche terminée';

  @override
  String get notifEvtFirstLayerDesc =>
      'Lorsque la première couche est terminée';

  @override
  String get notifEvtMilestones => 'Paliers de progression';

  @override
  String get notifEvtMilestonesDesc => 'À 25 %, 50 % et 75 %';

  @override
  String get notifEvtPlate => 'Plateau non vide';

  @override
  String get notifEvtPlateDesc =>
      'Lorsque le plateau doit être libéré avant la prochaine tâche';

  @override
  String get notifEvtOffline => 'Imprimante hors ligne';

  @override
  String get notifEvtOfflineDesc => 'Lorsqu\'une imprimante perd la connexion';

  @override
  String get notifEvtError => 'Erreur de l\'imprimante (HMS)';

  @override
  String get notifEvtErrorDesc =>
      'Lorsque l\'imprimante signale une erreur HMS';

  @override
  String get notifEvtLowFilament => 'Niveau de filament bas';

  @override
  String get notifEvtLowFilamentDesc =>
      'Lorsque le filament restant passe en dessous du seuil';

  @override
  String get notifEvtHumidity => 'Humidité AMS élevée';

  @override
  String get notifEvtHumidityDesc =>
      'Lorsque l\'humidité de l\'AMS dépasse le seuil';

  @override
  String get notifEvtBedCooled => 'Plateau refroidi';

  @override
  String get notifEvtBedCooledDesc =>
      'Lorsque le plateau refroidit après une impression';

  @override
  String notifBedCooledThreshold(int temp) {
    return 'Plateau refroidi en dessous de $temp °C';
  }

  @override
  String notifHumidityThreshold(int value) {
    return 'Humidité AMS au-dessus de $value %';
  }

  @override
  String notifLowFilamentThreshold(int percent) {
    return 'Filament bas en dessous de $percent %';
  }

  @override
  String get notifEventsMenu => 'Événements de notification';

  @override
  String get hmsErrorsHeader => 'Erreurs actives';

  @override
  String get hmsViewInWiki => 'Ouvrir dans le wiki Bambu';

  @override
  String hmsErrorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count erreurs',
      one: '1 erreur',
    );
    return '$_temp0';
  }

  @override
  String get hmsDismissAll => 'Tout ignorer';

  @override
  String get hmsDismissed => 'Erreurs effacées sur l\'imprimante';

  @override
  String get hmsDismissFailed => 'Impossible d\'effacer les erreurs';

  @override
  String get hmsActionSent => 'Envoyé à l\'imprimante';

  @override
  String get hmsActionFailed => 'L\'imprimante a refusé l\'action';

  @override
  String get hmsActionNotAcknowledged =>
      'L\'imprimante n\'a pas confirmé l\'action — vérifiez son écran';

  @override
  String get hmsStopConfirmTitle => 'Arrêter l\'impression ?';

  @override
  String hmsStopConfirmBody(String printer) {
    return '$printer va annuler le travail d\'impression. Cette action est irréversible.';
  }

  @override
  String get hmsStopConfirmAction => 'Arrêter l\'impression';

  @override
  String get hmsActionResume => 'Reprendre';

  @override
  String get hmsActionResumeDefects => 'Reprendre quand même';

  @override
  String get hmsActionResumeSolved => 'Résolu, reprendre';

  @override
  String get hmsActionProblemSolvedResume => 'Résolu, reprendre';

  @override
  String get hmsActionFilamentLoadedResume => 'Chargé, reprendre';

  @override
  String get hmsActionProceed => 'Continuer';

  @override
  String get hmsActionStopPrinting => 'Arrêter';

  @override
  String get hmsActionIgnoreResume => 'Ignorer, reprendre';

  @override
  String get hmsActionIgnoreNoReminder => 'Toujours ignorer';

  @override
  String get hmsActionDontRemind => 'Ne plus rappeler';

  @override
  String get hmsActionNoReminder => 'Ignorer';

  @override
  String get hmsActionFilamentExtruded => 'Extrudé';

  @override
  String get hmsActionRetryFilamentExtruded => 'Pas encore, réessayer';

  @override
  String get hmsActionContinue => 'Terminé, continuer';

  @override
  String get hmsActionRetrySolved => 'Résolu, réessayer';

  @override
  String get hmsActionDone => 'Terminé';

  @override
  String get hmsActionRetry => 'Réessayer';

  @override
  String get hmsActionResumePlain => 'Reprendre';

  @override
  String get hmsActionConfirm => 'Confirmer';

  @override
  String get hmsActionAbort => 'Interrompre';

  @override
  String get hmsActionOk => 'OK';

  @override
  String get hmsActionRecheck => 'Revérifier';

  @override
  String get hmsActionTurnOffFireAlarm => 'Désactiver l\'alarme';

  @override
  String get hmsActionStopDrying => 'Arrêter le séchage';

  @override
  String get hmsActionDisablePurification => 'Désactiver la purification';

  @override
  String get batteryOptTitle => 'Notifications fiables en arrière-plan';

  @override
  String get batteryOptBody =>
      'Pour que les notifications d\'impression fonctionnent lorsque l\'application est en arrière-plan, autorisez Bambuddy à s\'exécuter sans restriction de batterie. C\'est indispensable sur les téléphones Samsung.';

  @override
  String get batteryOptAllow => 'Ouvrir les paramètres';

  @override
  String get batteryOptLater => 'Plus tard';

  @override
  String get batteryOptMenu => 'Notifications en arrière-plan';

  @override
  String get notificationsReady => 'Les notifications sont prêtes';

  @override
  String get notificationsBlocked =>
      'Les notifications sont désactivées — activez-les dans les paramètres système';

  @override
  String get bgServiceTitle => 'Bambuddy';

  @override
  String get bgServiceText => 'Surveillance des imprimantes';

  @override
  String get bgMonitoringToggle => 'Surveillance en arrière-plan';

  @override
  String get bgMonitoringSubtitle =>
      'Continuez à surveiller les impressions lorsque l\'application est fermée. Affiche une notification permanente.';

  @override
  String get bgMonitoringOn => 'Surveillance en arrière-plan activée';

  @override
  String get bgMonitoringOff => 'Surveillance en arrière-plan désactivée';

  @override
  String get navDashboard => 'Imprimantes';

  @override
  String get navQueue => 'File d\'attente';

  @override
  String get navArchive => 'Archives';

  @override
  String get navMaintenance => 'Maintenance';

  @override
  String get navFilaments => 'Filaments';

  @override
  String get inventoryEmpty => 'Aucune bobine dans l\'inventaire';

  @override
  String get inventoryNoMatches =>
      'Aucun filament ne correspond à votre recherche';

  @override
  String get inventorySearchHint =>
      'Rechercher un matériau, une marque, une couleur…';

  @override
  String get inventoryShowArchived => 'Afficher les éléments archivés';

  @override
  String get inventoryArchived => 'Archivée';

  @override
  String get inventoryLowStock => 'Faible';

  @override
  String get inventoryFilters => 'Filtres';

  @override
  String get inventoryFilterStatus => 'Statut';

  @override
  String get inventoryStatusActive => 'Actif';

  @override
  String get inventoryStatusArchived => 'Archivé';

  @override
  String get inventoryFilterStock => 'Stock';

  @override
  String get inventoryStockAll => 'Tous';

  @override
  String get inventoryStockLow => 'Stock faible';

  @override
  String get inventoryFilterMaterial => 'Matériau';

  @override
  String get inventoryFilterBrand => 'Marque';

  @override
  String get inventoryFiltersClear => 'Tout effacer';

  @override
  String inventorySpoolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines',
      one: 'bobine',
    );
    return '$count $_temp0';
  }

  @override
  String inventoryRemaining(String grams) {
    return '$grams g restants';
  }

  @override
  String inventoryTotalConsumed(String weight) {
    return '$weight consommés';
  }

  @override
  String inventoryConsumedSinceReset(String weight) {
    return 'Consommé depuis la réinitialisation : $weight';
  }

  @override
  String inventoryOfTotal(int total) {
    return 'sur $total g';
  }

  @override
  String inventoryLoadedIn(String slot) {
    return 'Chargée dans $slot';
  }

  @override
  String get inventoryNotLoaded => 'Non chargée dans un emplacement AMS';

  @override
  String get inventoryLocation => 'Emplacement';

  @override
  String get inventoryNozzleTemp => 'Temp. de la buse';

  @override
  String inventoryCostPerKg(String cost) {
    return '$cost/kg';
  }

  @override
  String get inventoryNote => 'Note';

  @override
  String get inventoryTag => 'Tag';

  @override
  String get inventoryId => 'ID du filament';

  @override
  String get inventoryUsageHistory => 'Historique d\'utilisation';

  @override
  String get inventoryUsageEmpty =>
      'Aucune utilisation enregistrée pour le moment';

  @override
  String inventoryUsageWeight(String grams) {
    return '$grams g';
  }

  @override
  String get inventoryKProfiles => 'Calibrage (K)';

  @override
  String inventoryKProfileLine(String nozzle, String k) {
    return '$nozzle mm · K $k';
  }

  @override
  String get inventoryAddSpool => 'Ajouter une bobine';

  @override
  String inventoryAddSpools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines',
      one: 'bobine',
    );
    return 'Ajouter $count $_temp0';
  }

  @override
  String get inventoryNewSpool => 'Nouvelle bobine';

  @override
  String get inventoryEditSpool => 'Modifier la bobine';

  @override
  String get inventorySave => 'Enregistrer';

  @override
  String get inventoryFieldQuantity => 'Quantité';

  @override
  String get inventoryQuantityHint =>
      'Créer plusieurs bobines identiques à la fois';

  @override
  String get inventoryEdit => 'Modifier';

  @override
  String get inventoryDelete => 'Supprimer';

  @override
  String get inventoryArchive => 'Archiver';

  @override
  String get inventoryRestore => 'Restaurer';

  @override
  String get inventoryResetUsage => 'Réinitialiser l\'utilisation';

  @override
  String get inventoryFieldSlicerPreset => 'Préréglage du slicer';

  @override
  String get inventorySlicerPresetHint =>
      'Préréglage avec lequel cette bobine est ajoutée';

  @override
  String get inventorySlicerPresetNone => 'Aucun préréglage';

  @override
  String get inventorySlicerPresetSearch => 'Rechercher des préréglages…';

  @override
  String get inventorySlicerPresetUnavailable =>
      'Aucun préréglage de slicer disponible. Activez le découpage sur le serveur (et connectez Bambu Cloud pour les préréglages cloud).';

  @override
  String get inventorySectionPrinterPresets =>
      'Préréglages par modèle d\'imprimante';

  @override
  String get inventoryPrinterPresetsHint =>
      'Le choix effectué ici prévaut sur le préréglage de la bobine.';

  @override
  String get inventoryPrinterPresetDefault => 'Comme sur la bobine';

  @override
  String inventoryPrinterPresetNozzle(String model, String diameter) {
    return '$model · buse de $diameter';
  }

  @override
  String get inventoryPrinterPresetsLoadFailed =>
      'Non lus — l\'enregistrement les laissera inchangés.';

  @override
  String get inventoryPrinterPresetsSaveFailed =>
      'Bobine enregistrée, mais ses préréglages par modèle ne l\'ont pas été.';

  @override
  String get inventoryFieldMaterial => 'Matériau';

  @override
  String get inventoryFieldBrand => 'Marque';

  @override
  String get inventoryFieldSubtype => 'Variante';

  @override
  String get inventoryFieldColorName => 'Nom de la couleur';

  @override
  String get inventoryFieldColorHex => 'Couleur (hex)';

  @override
  String get inventoryFieldLabelWeight => 'Poids de la bobine (g)';

  @override
  String get inventoryFieldWeightUsed => 'Utilisé (g)';

  @override
  String get inventoryFieldCostPerKg => 'Coût par kg';

  @override
  String get inventoryFieldLowStock => 'Seuil de stock bas (%)';

  @override
  String get inventoryFieldLocation => 'Lieu de stockage';

  @override
  String get inventoryFieldNozzleMin => 'Buse min (°C)';

  @override
  String get inventoryFieldNozzleMax => 'Buse max (°C)';

  @override
  String get inventoryFieldNote => 'Note';

  @override
  String get inventoryFieldRequired => 'Obligatoire';

  @override
  String get inventoryFieldInvalidNumber => 'Saisissez un nombre';

  @override
  String inventoryFieldRange(int min, int max) {
    return 'Saisissez une valeur comprise entre $min et $max';
  }

  @override
  String get inventoryFieldNegative =>
      'Saisissez une valeur supérieure ou égale à 0';

  @override
  String get inventorySectionBasics => 'Informations générales';

  @override
  String get inventorySectionWeight => 'Poids et coût';

  @override
  String get inventorySectionDetails => 'Détails';

  @override
  String get inventorySectionFilament => 'Filament';

  @override
  String get inventorySectionColor => 'Couleur';

  @override
  String get inventorySectionAdditional => 'Informations complémentaires';

  @override
  String get inventoryFieldEmptySpoolWeight => 'Poids de la bobine vide (g)';

  @override
  String get inventoryCoreWeightSelect => 'Sélectionner…';

  @override
  String get inventoryCoreWeightSearch => 'Rechercher des bobines…';

  @override
  String get inventoryFieldRemainingWeight => 'Poids restant (g)';

  @override
  String get inventoryFieldMeasuredWeight => 'Poids mesuré (g)';

  @override
  String get inventoryFieldCategory => 'Catégorie';

  @override
  String get inventoryFieldExtraColors => 'Couleurs supplémentaires';

  @override
  String get inventoryExtraColorsHint =>
      '2–8 valeurs hex, séparées par des virgules';

  @override
  String get inventoryFieldEffect => 'Effet';

  @override
  String get inventoryEffectNone => 'Aucun';

  @override
  String get inventoryColorCommon => 'Couleurs courantes';

  @override
  String get inventoryColorSearchHint => 'Rechercher des couleurs…';

  @override
  String get inventoryColorPickTitle => 'Choisir une couleur';

  @override
  String get inventoryColorSelect => 'Sélectionner';

  @override
  String get inventoryColorNone => 'Aucune couleur';

  @override
  String get inventoryLowStockHint =>
      'Laisser vide pour utiliser le seuil global';

  @override
  String inventoryRemainingOfLabel(int total) {
    return 'sur $total g';
  }

  @override
  String get inventoryDeleteTitle => 'Supprimer la bobine ?';

  @override
  String inventoryDeleteConfirm(String name) {
    return 'Supprimer définitivement $name ? Cette action est irréversible.';
  }

  @override
  String get inventoryResetUsageConfirm =>
      'Réinitialiser le compteur de filament consommé à zéro ? Les futures impressions repartiront de zéro — le poids restant ne sera pas modifié.';

  @override
  String get inventorySpoolCreated => 'Bobine ajoutée';

  @override
  String inventorySpoolsCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines ajoutées',
      one: 'bobine ajoutée',
    );
    return '$count $_temp0';
  }

  @override
  String get inventorySpoolUpdated => 'Bobine mise à jour';

  @override
  String get inventorySpoolDeleted => 'Bobine supprimée';

  @override
  String get inventorySpoolArchived => 'Bobine archivée';

  @override
  String get inventorySpoolRestored => 'Bobine restaurée';

  @override
  String get inventoryUsageReset => 'Compteur réinitialisé';

  @override
  String get inventorySaveFailed => 'Impossible d\'enregistrer la bobine';

  @override
  String get inventoryActionFailed => 'Échec de l\'action';

  @override
  String get inventoryUnassign => 'Désassigner';

  @override
  String get inventoryAssign => 'Assigner à un emplacement';

  @override
  String get inventoryAssignPrinter => 'Imprimante';

  @override
  String get inventoryAssignNoPrinters => 'Aucune imprimante disponible';

  @override
  String get inventorySlotAms => 'Emplacement AMS';

  @override
  String get inventoryAssignUnit => 'Unité AMS';

  @override
  String get inventoryAssignSlot => 'Emplacement';

  @override
  String get inventoryAssignExtruder => 'Extrudeur';

  @override
  String get inventoryAssignExternalHint =>
      'Assigne au support de bobine externe';

  @override
  String get inventoryAssignConfirm => 'Assigner';

  @override
  String get inventoryAssignTitle => 'Assigner la bobine';

  @override
  String get inventoryAssignCurrent => 'Actuellement dans cet emplacement';

  @override
  String get inventoryAssignPick => 'Choisir une bobine';

  @override
  String get inventoryReassignTitle => 'Déplacer la bobine ?';

  @override
  String inventoryReassignMessage(String slot) {
    return 'Cette bobine est actuellement dans $slot. Elle en sera retirée et assignée à cet emplacement.';
  }

  @override
  String get inventoryReassignAction => 'Déplacer';

  @override
  String get inventorySpoolAssigned => 'Bobine assignée';

  @override
  String get inventorySpoolUnassigned => 'Bobine désassignée';

  @override
  String get inventoryFromSlot => 'Ajouter à l\'inventaire';

  @override
  String get inventoryFromSlotHint =>
      'Enregistre la bobine à tag RFID que l\'imprimante signale dans cet emplacement';

  @override
  String get inventoryFromSlotDone =>
      'Bobine ajoutée et assignée à l\'emplacement';

  @override
  String get inventoryFromSlotNoTag =>
      'L\'imprimante ne signale plus de bobine à tag RFID dans cet emplacement';

  @override
  String get inventoryFromSlotOffline =>
      'L\'imprimante n\'est pas connectée, elle ne peut donc pas indiquer ce qui se trouve dans l\'emplacement';

  @override
  String get inventoryFromSlotUnsupported =>
      'Cette version du serveur ne peut pas ajouter une bobine directement depuis un emplacement';

  @override
  String get inventoryScanSpool => 'Scanner le QR';

  @override
  String get inventoryScanTitle => 'Scanner le QR de la bobine';

  @override
  String get inventoryScanHint =>
      'Pointez l\'appareil photo vers le code QR de la bobine';

  @override
  String get inventoryScanPermissionTitle => 'Accès à l\'appareil photo requis';

  @override
  String get inventoryScanPermissionBody =>
      'Autorisez l\'accès à l\'appareil photo pour scanner les codes QR des bobines.';

  @override
  String get inventoryScanOpenSettings => 'Ouvrir les paramètres';

  @override
  String get inventoryScanInvalid => 'Code QR non reconnu';

  @override
  String inventoryScanNotFound(int id) {
    return 'Bobine #$id introuvable';
  }

  @override
  String inventorySelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnées',
      one: '$count sélectionnée',
    );
    return '$_temp0';
  }

  @override
  String get inventorySelectAll => 'Tout sélectionner';

  @override
  String inventoryBulkArchiveTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines',
      one: 'bobine',
    );
    return 'Archiver $count $_temp0 ?';
  }

  @override
  String get inventoryBulkArchiveBody =>
      'Elles seront masquées de la liste active. Vous pourrez les restaurer plus tard.';

  @override
  String inventoryBulkRestoreTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines',
      one: 'bobine',
    );
    return 'Restaurer $count $_temp0 ?';
  }

  @override
  String get inventoryBulkRestoreBody =>
      'Elles retourneront dans la liste active.';

  @override
  String inventoryBulkDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines',
      one: 'bobine',
    );
    return 'Supprimer $count $_temp0 ?';
  }

  @override
  String get inventoryBulkDeleteBody =>
      'Cette action est permanente et irréversible.';

  @override
  String inventoryBulkResetTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines',
      one: 'bobine',
    );
    return 'Réinitialiser l\'utilisation de $count $_temp0 ?';
  }

  @override
  String get inventoryBulkResetBody =>
      'Leurs compteurs de filament consommé reviennent à zéro. Les poids restants ne sont pas modifiés.';

  @override
  String inventoryBulkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines mises',
      one: 'bobine mise',
    );
    return '$count $_temp0 à jour';
  }

  @override
  String inventoryBulkPartial(int ok, int failed) {
    return '$ok réussies, $failed en échec';
  }

  @override
  String inventoryBulkSkipped(int ok, int skipped) {
    return '$ok réussies, $skipped déjà en place';
  }

  @override
  String inventoryBulkPartialSkipped(int ok, int skipped, int failed) {
    return '$ok réussies, $skipped déjà en place, $failed en échec';
  }

  @override
  String get inventoryBulkEdit => 'Modifier les champs';

  @override
  String inventoryBulkEditTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines',
      one: 'bobine',
    );
    return 'Modifier $count $_temp0';
  }

  @override
  String get inventoryBulkEditHint =>
      'Seuls les champs que vous remplissez seront modifiés. Laissez le reste vide.';

  @override
  String get inventoryBulkEditUnchanged => 'Inchangé';

  @override
  String inventoryBulkEditApply(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines',
      one: 'bobine',
    );
    return 'Appliquer à $count $_temp0';
  }

  @override
  String inventoryBulkEditConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobines',
      one: 'bobine',
    );
    return 'Modifier $count $_temp0 ?';
  }

  @override
  String inventoryBulkEditConfirmBody(int fields) {
    String _temp0 = intl.Intl.pluralLogic(
      fields,
      locale: localeName,
      other: 'champs seront écrasés',
      one: 'champ sera écrasé',
    );
    return '$fields $_temp0 sur chaque bobine sélectionnée.';
  }

  @override
  String get inventoryBulkEditUnsupported =>
      'Ce serveur est trop ancien pour la modification en masse. Modifiez les bobines une par une, ou mettez à jour bambuddy.';

  @override
  String get inventoryApply => 'Appliquer';

  @override
  String get inventoryLabelsTitle => 'Imprimer des étiquettes de bobine';

  @override
  String get inventoryLabelsPrint => 'Imprimer les étiquettes';

  @override
  String get inventoryLabelsPrintAll =>
      'Imprimer les étiquettes de toutes les bobines';

  @override
  String get inventoryClimateTitle => 'Conditions de stockage';

  @override
  String get inventoryClimateTitleAlerting =>
      'Conditions de stockage : hors de la plage d\'alerte';

  @override
  String get inventoryClimateSource =>
      'Le serveur les lit depuis Home Assistant. Les capteurs sont liés à un emplacement dans l\'interface web de Bambuddy.';

  @override
  String get inventoryClimateNoReading => 'aucune mesure';

  @override
  String inventoryClimateReading(String name, String value) {
    return '$name : $value';
  }

  @override
  String inventoryClimateReadingAlerting(String name, String value) {
    return '$name : $value, hors de la plage d\'alerte';
  }

  @override
  String inventoryClimateReadingStale(String name, String value) {
    return '$name : $value, capteur inaccessible';
  }

  @override
  String get inventoryLabelsSearchHint => 'Rechercher par nom, marque ou #ID';

  @override
  String get inventoryLabelsPickSpools =>
      'Choisissez les bobines pour lesquelles imprimer des étiquettes :';

  @override
  String get inventoryLabelsMaterial => 'Matériau :';

  @override
  String get inventoryLabelsAllMaterials => 'Tous';

  @override
  String get inventoryLabelsSort => 'Trier :';

  @override
  String get inventoryLabelsSortById => 'Par ID';

  @override
  String get inventoryLabelsSortByColor => 'Par couleur';

  @override
  String get inventoryLabelsSelectVisible => 'Sélectionner les visibles';

  @override
  String get inventoryLabelsDeselectVisible => 'Désélectionner les visibles';

  @override
  String get inventoryLabelsClearAll => 'Tout effacer';

  @override
  String get inventoryLabelsNoMatches =>
      'Aucune bobine ne correspond à la recherche ou au filtre actuel.';

  @override
  String get inventoryLabelsMonochrome =>
      'Monochrome (imprimante noir et blanc)';

  @override
  String get inventoryLabelsMonochromeHint =>
      'Supprime l\'échantillon de couleur et élargit le texte';

  @override
  String get inventoryLabelsShare => 'Partager le PDF plutôt que d\'imprimer';

  @override
  String get inventoryLabelsPickTemplate =>
      'Choisissez une taille d\'étiquette à imprimer :';

  @override
  String inventoryLabelsTooMany(int max) {
    return 'Sélectionnez au maximum $max bobines par impression';
  }

  @override
  String get inventoryLabelsFailed => 'Impossible de générer les étiquettes';

  @override
  String get inventoryLabelsAmsSmall => 'Support AMS — petit (74 × 33 mm)';

  @override
  String get inventoryLabelsAmsSmallHint =>
      'Une par page ; correspond à l\'étiquette imprimable du modèle MakerWorld 752566.';

  @override
  String get inventoryLabelsAmsLarge => 'Support AMS — grand (75 × 55 mm)';

  @override
  String get inventoryLabelsAmsLargeHint =>
      'Une par page ; convient à la variante avec insert cartonné du même support.';

  @override
  String get inventoryLabelsBox40 => 'Étiquette boîte (40 × 30 mm)';

  @override
  String get inventoryLabelsBox40Hint =>
      'Une par page ; taille de rouleau DK/Brother courante, idéale pour les sacs et bacs.';

  @override
  String get inventoryLabelsBox62 => 'Étiquette boîte (62 × 29 mm)';

  @override
  String get inventoryLabelsBox62Hint =>
      'Une par page ; dimensionnée pour Brother PT/QL et les petites étiquettes Dymo.';

  @override
  String get inventoryLabelsAveryL7160 =>
      'Avery L7160 — feuille A4 (38,1 × 63,5 mm × 21)';

  @override
  String get inventoryLabelsAveryL7160Hint =>
      'Format européen ; 21 étiquettes par page A4.';

  @override
  String get inventoryLabelsAvery5160 =>
      'Avery 5160 — feuille US Letter (25,4 × 66,7 mm × 30)';

  @override
  String get inventoryLabelsAvery5160Hint =>
      'Format américain ; 30 étiquettes par page Letter.';

  @override
  String get inventoryLabelsStartTitle => 'Première étiquette libre';

  @override
  String get inventoryLabelsStartHint =>
      'Appuyez sur la case de la première étiquette à imprimer — celles qui la précèdent restent vides, pour terminer une feuille partiellement utilisée plutôt que d\'en commencer une nouvelle.';

  @override
  String inventoryLabelsStartSlot(int position) {
    return 'Position $position';
  }

  @override
  String get maintenanceEmpty => 'Aucune donnée de maintenance';

  @override
  String maintenanceTotalHours(int hours) {
    return '$hours h au total';
  }

  @override
  String maintenanceDueBadge(int count) {
    return '$count à faire';
  }

  @override
  String maintenanceWarningBadge(int count) {
    return '$count bientôt';
  }

  @override
  String maintenanceDueIn(int hours) {
    return 'À faire dans $hours h';
  }

  @override
  String maintenanceOverdueBy(int hours) {
    return 'En retard de $hours h';
  }

  @override
  String get maintenancePerform => 'Marquer comme effectuée';

  @override
  String get maintenancePerformConfirm =>
      'Réinitialiser le compteur de cette tâche de maintenance ?';

  @override
  String get maintenanceNotesHint => 'Notes (facultatif)';

  @override
  String get maintenanceHistory => 'Historique';

  @override
  String get maintenanceHistoryEmpty => 'Aucun historique pour l\'instant';

  @override
  String get maintenanceDone => 'Maintenance marquée comme effectuée';

  @override
  String get maintenanceFailed => 'Impossible de mettre à jour la maintenance';

  @override
  String get maintenanceSaved => 'Enregistré';

  @override
  String get maintenanceSettingsTitle => 'Paramètres de maintenance';

  @override
  String get maintenanceOverridesTitle => 'Intervalles personnalisés';

  @override
  String get maintenanceOverridesSubtitle =>
      'Mettre en sourdine les tâches ou personnaliser les intervalles par imprimante';

  @override
  String get maintenanceTabStatus => 'Statut';

  @override
  String get maintenanceTabSettings => 'Paramètres';

  @override
  String get maintenanceMute => 'Mettre en sourdine';

  @override
  String get maintenanceUnmute => 'Réactiver';

  @override
  String get maintenanceMuted => 'Tâche mise en sourdine';

  @override
  String get maintenanceUnmuted => 'Tâche réactivée';

  @override
  String get maintenanceEditInterval => 'Modifier l\'intervalle';

  @override
  String get maintenanceResetInterval => 'Rétablir la valeur par défaut';

  @override
  String get maintenanceTypesTitle => 'Types de maintenance';

  @override
  String get maintenanceTypesSubtitle =>
      'Types système et tâches personnalisées';

  @override
  String get maintenanceRestoreDefaults => 'Restaurer les valeurs par défaut';

  @override
  String get maintenanceRestoreConfirm =>
      'Restaurer tous les types de maintenance par défaut masqués ?';

  @override
  String get maintenanceAddType => 'Ajouter un type personnalisé';

  @override
  String get maintenanceEditType => 'Modifier le type';

  @override
  String get maintenanceSystemType => 'Système';

  @override
  String maintenanceEveryHours(int count) {
    return 'Toutes les $count h';
  }

  @override
  String maintenanceEveryDays(int count) {
    return 'Tous les $count jours';
  }

  @override
  String get maintenanceDeleteTypeTitle => 'Supprimer le type de maintenance ?';

  @override
  String maintenanceDeleteTypeConfirm(String name) {
    return 'Supprimer « $name » ? Cette action est irréversible.';
  }

  @override
  String maintenanceHideTypeConfirm(String name) {
    return 'Masquer le type par défaut « $name » ? Vous pourrez le restaurer plus tard.';
  }

  @override
  String get maintenanceFieldName => 'Nom';

  @override
  String get maintenanceFieldNameHint => 'ex. : Remplacer le filtre HEPA';

  @override
  String get maintenanceFieldIntervalType => 'Type d\'intervalle';

  @override
  String get maintenanceFieldInterval => 'Intervalle';

  @override
  String get maintenanceIntervalHours => 'Heures d\'impression';

  @override
  String get maintenanceIntervalDays => 'Jours';

  @override
  String get maintenanceIntervalInvalid => 'Entrez une valeur ≥ 1';

  @override
  String get maintenanceFieldIcon => 'Icône';

  @override
  String get maintenanceFieldDocLink => 'Lien de documentation (facultatif)';

  @override
  String get maintenanceAssignPrinters => 'Assigner aux imprimantes';

  @override
  String get maintenanceSelectPrinter => 'Sélectionnez au moins une imprimante';

  @override
  String get notifEvtMaintenance => 'Maintenance requise';

  @override
  String get notifEvtMaintenanceDesc =>
      'Lorsqu\'une tâche de maintenance est en retard';

  @override
  String get maintenanceNotifTitle => 'Maintenance requise';

  @override
  String maintenanceNotifBody(String printer, String task) {
    return '$printer : $task';
  }

  @override
  String get maintenanceReminderTitle => 'Rappel de maintenance';

  @override
  String maintenanceReminderBody(String printer, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tâches de maintenance en retard',
      one: 'tâche de maintenance en retard',
    );
    return '$count $_temp0 sur $printer';
  }

  @override
  String get maintenanceNotifAction => 'Marquer comme effectuée';

  @override
  String get navMenu => 'Menu';

  @override
  String get menuStatistics => 'Statistiques';

  @override
  String get statsTitle => 'Statistiques';

  @override
  String get statsRangeAllTime => 'Depuis toujours';

  @override
  String get statsRangeLast7Days => '7 derniers jours';

  @override
  String get statsRangeLast30Days => '30 derniers jours';

  @override
  String get statsRangeLast90Days => '90 derniers jours';

  @override
  String get statsRangeThisYear => 'Cette année';

  @override
  String get statsRangeCustom => 'Plage personnalisée';

  @override
  String get statsEmpty => 'Aucune impression sur cette période';

  @override
  String get statsLoadFailed => 'Impossible de charger les statistiques';

  @override
  String get statsOverview => 'Vue d\'ensemble';

  @override
  String get statsTotalPrints => 'Impressions au total';

  @override
  String get statsPrintTime => 'Temps d\'impression';

  @override
  String get statsFilamentUsed => 'Filament utilisé';

  @override
  String get statsFilamentCost => 'Coût du filament';

  @override
  String get statsEnergyUsed => 'Énergie consommée';

  @override
  String get statsEnergyCost => 'Coût de l\'énergie';

  @override
  String get statsTotalCost => 'Coût total';

  @override
  String get statsEnergyWarmingUp =>
      'Les données d\'énergie sont encore en cours de collecte';

  @override
  String get statsSuccessRate => 'Taux de réussite';

  @override
  String statsSuccessful(int count) {
    return 'Réussies : $count';
  }

  @override
  String statsFailed(int count) {
    return 'Échouées : $count';
  }

  @override
  String statsCancelled(int count) {
    return 'Annulées : $count';
  }

  @override
  String get statsAllUsers => 'Tous les utilisateurs';

  @override
  String get statsNoUser => 'Aucun utilisateur (système)';

  @override
  String get statsTimeAccuracy => 'Précision du temps';

  @override
  String get statsTimeAccuracyHint => '100 % = estimation parfaite';

  @override
  String get statsByMaterial => 'Impressions par matériau';

  @override
  String get statsByPrinter => 'Impressions par imprimante';

  @override
  String get statsTimeAccuracyByPrinter => 'Précision du temps par imprimante';

  @override
  String statsPrintsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impressions',
      one: '$count impression',
    );
    return '$_temp0';
  }

  @override
  String statsHours(String hours) {
    return '$hours h';
  }

  @override
  String statsPrinterFallback(String id) {
    return 'Imprimante #$id';
  }

  @override
  String get statsMetricWeight => 'Poids';

  @override
  String get statsMetricPrints => 'Impressions';

  @override
  String get statsMetricTime => 'Temps';

  @override
  String get statsFailureAnalysis => 'Analyse des échecs';

  @override
  String get statsFailureRate => 'Taux d\'échec';

  @override
  String statsFailurePeriod(int days) {
    return '$days derniers jours';
  }

  @override
  String statsFailedOfTotal(int failed, int total) {
    return '$failed / $total impressions échouées';
  }

  @override
  String get statsTopFailureReasons => 'Principales causes d\'échec';

  @override
  String get statsNoFailures => 'Aucun échec sur cette période';

  @override
  String get statsPrintActivity => 'Activité d\'impression';

  @override
  String get statsHeatmapLess => 'Moins';

  @override
  String get statsHeatmapMore => 'Plus';

  @override
  String get statsRecords => 'Records';

  @override
  String get statsLongestPrint => 'Impression la plus longue';

  @override
  String get statsHeaviestPrint => 'Impression la plus lourde';

  @override
  String get statsMostExpensive => 'Impression la plus coûteuse';

  @override
  String get statsBusiestDay => 'Jour le plus actif';

  @override
  String get statsSuccessStreak => 'Série de réussites';

  @override
  String statsConsecutive(int count) {
    return '$count d\'affilée';
  }

  @override
  String get statsFilamentTrends => 'Tendances du filament';

  @override
  String get statsPeriodFilament => 'Filament de la période';

  @override
  String get statsPeriodCost => 'Coût de la période';

  @override
  String get statsAvgPerPrint => 'Moyenne par impression';

  @override
  String get statsUsageOverTime => 'Utilisation dans le temps';

  @override
  String get statsEnergyOverTime => 'Énergie dans le temps';

  @override
  String get statsMostEnergy => 'Plus grande consommation d\'énergie';

  @override
  String statsKwh(String value) {
    return '$value kWh';
  }

  @override
  String get statsByMaterialTitle => 'Par matériau';

  @override
  String get statsSuccessByMaterial => 'Réussite par matériau';

  @override
  String get statsColorDistribution => 'Répartition des couleurs';

  @override
  String get statsColorShareHint => 'Part du filament utilisé, par poids';

  @override
  String statsColorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'couleurs',
      one: 'couleur',
    );
    return '$count $_temp0';
  }

  @override
  String statsMoreCount(int count) {
    return '+$count de plus';
  }

  @override
  String get statsPrintDuration => 'Durée d\'impression';

  @override
  String get statsPrintHabits => 'Habitudes d\'impression';

  @override
  String get statsPrintTimeOfDay => 'Heure d\'impression dans la journée';

  @override
  String get aboutMenu => 'À propos';

  @override
  String get aboutTitle => 'À propos';

  @override
  String get aboutTagline =>
      'Client Android natif pour bambuddy — un gestionnaire d\'imprimantes Bambu Lab auto-hébergé.';

  @override
  String appVersionLabel(String version) {
    return 'Application $version';
  }

  @override
  String serverVersionLabel(String version) {
    return 'Serveur $version';
  }

  @override
  String get serverVersionUnknown => 'Version du serveur inconnue';

  @override
  String get aboutLicenseHeader => 'Licence';

  @override
  String get aboutLicenseBody =>
      'Bambuddy est un logiciel libre publié sous la licence GNU Affero General Public License v3.0 (AGPL-3.0). Vous pouvez l\'utiliser, l\'étudier, le partager et le modifier ; si vous exécutez une version modifiée en tant que service réseau, vous devez en fournir le code source à ses utilisateurs.';

  @override
  String get aboutViewLicense => 'Lire la licence AGPL-3.0';

  @override
  String get aboutSourceHeader => 'Code source';

  @override
  String get aboutSourceBody =>
      'Le code source complet est disponible sur GitHub.';

  @override
  String get aboutSourceLink => 'Ouvrir le dépôt du code source';

  @override
  String get aboutThirdParty => 'Licences open source';

  @override
  String get aboutThirdPartySubtitle => 'Licences des bibliothèques incluses';

  @override
  String get aboutOpenLinkError => 'Impossible d\'ouvrir le lien';

  @override
  String get fileManagerMenu => 'Gestionnaire de fichiers';

  @override
  String get fileManagerTitle => 'Gestionnaire de fichiers';

  @override
  String get fmRoot => 'Tous les fichiers';

  @override
  String get fmSearchHint => 'Rechercher des fichiers…';

  @override
  String get fmEmpty => 'Ce dossier est vide';

  @override
  String get fmNoMatches => 'Aucun fichier ne correspond à vos filtres';

  @override
  String get fmSortBy => 'Trier par';

  @override
  String get fmSortDateNewest => 'Plus récents d\'abord';

  @override
  String get fmSortDateOldest => 'Plus anciens d\'abord';

  @override
  String get fmSortNameAZ => 'Nom A–Z';

  @override
  String get fmSortNameZA => 'Nom Z–A';

  @override
  String get fmSortSizeLargest => 'Plus volumineux d\'abord';

  @override
  String get fmSortSizeSmallest => 'Moins volumineux d\'abord';

  @override
  String get fmFilterType => 'Type de fichier';

  @override
  String get fmAllTypes => 'Tous les types';

  @override
  String get fmNewFolder => 'Nouveau dossier';

  @override
  String get fmFolderName => 'Nom du dossier';

  @override
  String get fmFileName => 'Nom du fichier';

  @override
  String get fmSave => 'Enregistrer';

  @override
  String get fmRename => 'Renommer';

  @override
  String get fmRenameFolder => 'Renommer le dossier';

  @override
  String get fmRenameFile => 'Renommer le fichier';

  @override
  String get fmRenamed => 'Renommé';

  @override
  String get fmFolderCreated => 'Dossier créé';

  @override
  String get fmDelete => 'Supprimer';

  @override
  String get fmDeleted => 'Déplacé vers la corbeille';

  @override
  String get fmDeleteFile => 'Supprimer le fichier';

  @override
  String fmDeleteFileConfirm(String name) {
    return 'Déplacer « $name » vers la corbeille ?';
  }

  @override
  String get fmDeleteFolder => 'Supprimer le dossier';

  @override
  String fmDeleteFolderConfirm(String name) {
    return 'Supprimer le dossier « $name » et tout son contenu ?';
  }

  @override
  String fmDeleteSelectedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fichiers',
      one: 'fichier',
    );
    return 'Déplacer $count $_temp0 vers la corbeille ?';
  }

  @override
  String get fmMoveTo => 'Déplacer vers…';

  @override
  String get fmMoved => 'Déplacé';

  @override
  String fmFolderItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'éléments',
      one: 'élément',
    );
    return '$count $_temp0';
  }

  @override
  String get fmPrint => 'Imprimer';

  @override
  String get fmAddToQueue => 'Ajouter à la file d\'attente';

  @override
  String get fmAddedToQueue => 'Ajouté à la file d\'attente';

  @override
  String get fmGroupAsVariants => 'Regrouper comme alternatives';

  @override
  String get fmQueueAsVariants =>
      'Mettre en file d\'attente comme une seule tâche';

  @override
  String get fmUngroupVariants => 'Dissocier les alternatives';

  @override
  String fmVariantsGrouped(int count) {
    return '$count fichiers regroupés comme alternatives';
  }

  @override
  String get fmVariantsUngrouped => 'Alternatives dissociées';

  @override
  String fmVariantsMemberCount(int count) {
    return '$count alternatives';
  }

  @override
  String get fmVariantsGone => 'Ce groupe n\'existe plus';

  @override
  String get fmUpload => 'Téléverser un fichier';

  @override
  String get fmUploading => 'Téléversement…';

  @override
  String fmUploaded(String name) {
    return 'Téléversement terminé : $name';
  }

  @override
  String get fmUploadFailed => 'Échec du téléversement';

  @override
  String fmSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnés',
      one: '$count sélectionné',
    );
    return '$_temp0';
  }

  @override
  String fmStatsFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fichiers',
      one: 'fichier',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'dossiers',
      one: 'dossier',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFree(String size) {
    return '$size libres';
  }

  @override
  String get fmTrash => 'Corbeille';

  @override
  String get fmTrashTitle => 'Corbeille';

  @override
  String get fmTrashEmpty => 'La corbeille est vide';

  @override
  String get fmRestore => 'Restaurer';

  @override
  String get fmRestored => 'Restauré';

  @override
  String get fmEmptyTrash => 'Vider la corbeille';

  @override
  String get fmEmptyTrashConfirm =>
      'Supprimer définitivement tous les fichiers de la corbeille ? Cette action est irréversible.';

  @override
  String get fmHardDelete => 'Supprimer définitivement';

  @override
  String fmHardDeleteConfirm(String name) {
    return 'Supprimer définitivement « $name » ? Cette action est irréversible.';
  }

  @override
  String get fmDeletedForever => 'Supprimé définitivement';

  @override
  String get fmTags => 'Étiquettes';

  @override
  String get fmTagsFilterTitle => 'Filtrer par étiquettes';

  @override
  String get fmTagsFilterHint =>
      'Les étiquettes recherchent dans toute la bibliothèque — le dossier actuel est ignoré.';

  @override
  String get fmTagsManage => 'Gérer les étiquettes';

  @override
  String get fmTagsEmpty => 'Aucune étiquette pour l\'instant';

  @override
  String get fmTagsNone => 'Aucune étiquette';

  @override
  String get fmTagsApply => 'Appliquer';

  @override
  String get fmTagNew => 'Nouvelle étiquette';

  @override
  String get fmTagName => 'Nom de l\'étiquette';

  @override
  String get fmTagRename => 'Renommer l\'étiquette';

  @override
  String get fmTagDelete => 'Supprimer l\'étiquette';

  @override
  String fmTagDeleteConfirm(String name) {
    return 'Supprimer l\'étiquette « $name » ? Les fichiers conservent tout le reste — ils perdent uniquement cette étiquette.';
  }

  @override
  String get fmTagCreated => 'Étiquette créée';

  @override
  String get fmTagDeleted => 'Étiquette supprimée';

  @override
  String get fmTagExists => 'Une étiquette portant ce nom existe déjà';

  @override
  String get fmTagsSaved => 'Étiquettes mises à jour';

  @override
  String fmTagsPartial(int count, int total) {
    return '$count sur $total fichiers mis à jour — vous n\'avez pas l\'autorisation de modifier le reste';
  }

  @override
  String fmTagsBulkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fichiers',
      one: 'fichier',
    );
    return 'Étiqueter $count $_temp0';
  }

  @override
  String get fmTagsAdd => 'Ajouter';

  @override
  String get fmTagsRemove => 'Retirer';

  @override
  String get fmTagsReplace => 'Remplacer';

  @override
  String fmTagsReplaceConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fichiers',
      one: 'fichier',
    );
    return 'Remplacer toutes les étiquettes de $count $_temp0 par celles sélectionnées ?';
  }

  @override
  String get fmTagsPickSome => 'Sélectionnez au moins une étiquette';

  @override
  String get makerworldMenu => 'MakerWorld';

  @override
  String get makerworldTitle => 'MakerWorld';

  @override
  String get mwIntro =>
      'Collez l\'URL d\'un modèle MakerWorld pour l\'importer et l\'imprimer directement depuis Bambuddy.';

  @override
  String get mwUrlHint =>
      'https://makerworld.com/en/models/… ou tout lien MakerWorld';

  @override
  String get mwResolve => 'Résoudre';

  @override
  String get mwEnterUrl => 'Saisissez une URL MakerWorld';

  @override
  String get mwUntitledModel => 'Modèle sans titre';

  @override
  String mwPlatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plateaux',
      one: '1 plateau',
      zero: 'Aucun plateau',
    );
    return '$_temp0';
  }

  @override
  String get mwNoPlates => 'Aucun plateau trouvé pour ce modèle.';

  @override
  String get mwImport => 'Importer';

  @override
  String mwShowAllPlates(int count) {
    return 'Afficher les $count plateaux';
  }

  @override
  String get mwShowLess => 'Afficher moins';

  @override
  String get mwInLibrary => 'Dans la bibliothèque';

  @override
  String get mwImported => 'Importé dans votre bibliothèque';

  @override
  String get mwAlreadyInLibrary => 'Déjà dans votre bibliothèque';

  @override
  String get mwViewInFiles => 'Afficher dans le gestionnaire de fichiers';

  @override
  String get mwRecentImports => 'Importations récentes';

  @override
  String get mwNoRecent => 'Aucune importation récente pour l\'instant';

  @override
  String get mwOpenOnMakerworld => 'Ouvrir sur MakerWorld';

  @override
  String get mwLoginRequired =>
      'Connectez-vous à votre compte Bambu Cloud pour télécharger des modèles MakerWorld.';

  @override
  String get cloudAccountMenu => 'Compte Bambu Cloud';

  @override
  String get cloudAccountTitle => 'Bambu Cloud';

  @override
  String get cloudCredsNote =>
      'Connectez-vous avec votre compte Bambu Lab. Ces identifiants sont uniquement utilisés pour télécharger des modèles depuis MakerWorld.';

  @override
  String get cloudEmail => 'E-mail';

  @override
  String get cloudPassword => 'Mot de passe';

  @override
  String get cloudRegionGlobal => 'Global';

  @override
  String get cloudRegionChina => 'Chine';

  @override
  String get cloudSignIn => 'Se connecter';

  @override
  String get cloudSignOut => 'Se déconnecter';

  @override
  String get cloudSignedIn => 'Connecté';

  @override
  String get cloudSignedInOk => 'Connecté à Bambu Cloud';

  @override
  String get cloudSignInFailed => 'Échec de la connexion';

  @override
  String get cloudFillCredentials =>
      'Saisissez votre e-mail et votre mot de passe';

  @override
  String get cloudVerify => 'Vérifier';

  @override
  String get cloudVerificationCode => 'Code de vérification';

  @override
  String get cloudVerificationPrompt =>
      'Saisissez le code de vérification pour finaliser la connexion.';

  @override
  String get cloudEnterCode => 'Saisissez le code de vérification';

  @override
  String get swatchCodesMenu => 'Codes d\'échantillons';

  @override
  String get swatchCodesTitle => 'Codes d\'échantillons';

  @override
  String get swatchSearchHint => 'Rechercher par code ou par nom';

  @override
  String get swatchSectionCodes => 'Codes';

  @override
  String get swatchSectionUncoded => 'Filaments de l\'inventaire sans code';

  @override
  String get swatchNoCodes => 'Aucun code d\'échantillon pour l\'instant';

  @override
  String get swatchNoCodesHint =>
      'Créez un code pour étiqueter un échantillon de filament.';

  @override
  String swatchNoMatch(String query) {
    return 'Aucun code ne correspond à « $query »';
  }

  @override
  String get swatchAllCoded =>
      'Tous les filaments de l\'inventaire ont un code';

  @override
  String get swatchNewCode => 'Nouveau code';

  @override
  String get swatchGenerate => 'Générer';

  @override
  String get swatchGenerateCode => 'Générer un code';

  @override
  String get swatchExists => 'Ce filament a déjà un code';

  @override
  String swatchCreatedSnack(String code) {
    return 'Code $code créé';
  }

  @override
  String swatchUpdatedSnack(String code) {
    return 'Code $code mis à jour';
  }

  @override
  String swatchCopied(String code) {
    return '$code copié';
  }

  @override
  String get swatchDelete => 'Supprimer';

  @override
  String get swatchDeleteTitle => 'Supprimer le code ?';

  @override
  String swatchDeleteBody(String code, String name) {
    return 'Le code $code pour $name sera supprimé.';
  }

  @override
  String get swatchExport => 'Exporter';

  @override
  String get swatchImport => 'Importer';

  @override
  String get swatchExportEmpty => 'Aucun code à exporter';

  @override
  String swatchExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count codes exportés',
      one: '1 code exporté',
    );
    return '$_temp0';
  }

  @override
  String get swatchExportFailed => 'Échec de l\'exportation';

  @override
  String get swatchImportTitle => 'Importer les codes ?';

  @override
  String swatchImportWarning(int existing, int incoming) {
    return 'Cette opération remplace les $existing codes existants par les $incoming codes du fichier. Cette action est irréversible.';
  }

  @override
  String get swatchImportConfirm => 'Tout remplacer';

  @override
  String swatchImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count codes importés',
      one: '1 code importé',
    );
    return '$_temp0';
  }

  @override
  String get swatchImportFailed => 'Impossible de lire ce fichier';

  @override
  String get swatchImportEmpty => 'Aucun code trouvé dans le fichier';

  @override
  String get swatchFormTitle => 'Nouveau code d\'échantillon';

  @override
  String get swatchEditTitle => 'Modifier le code';

  @override
  String get swatchSave => 'Enregistrer';

  @override
  String get swatchRegenerate => 'Régénérer';

  @override
  String get swatchFieldCode => 'Code';

  @override
  String get swatchCodeInvalid =>
      'Utilisez 6 caractères : chiffres et lettres, sans 0, 1, I, L ni O';

  @override
  String get swatchCodeTaken => 'Ce code est déjà utilisé';

  @override
  String get swatchFieldBrand => 'Fabricant';

  @override
  String get swatchFieldMaterial => 'Matériau';

  @override
  String get swatchFieldVariant => 'Variante';

  @override
  String get swatchFieldColor => 'Couleur';

  @override
  String get swatchFieldHex => 'Code couleur hex';

  @override
  String get swatchMaterialRequired => 'Le matériau est obligatoire';

  @override
  String get swatchNoCatalogColors =>
      'Aucune couleur disponible dans le catalogue. Saisissez manuellement un nom de couleur et son code hex.';

  @override
  String get projectsMenu => 'Projets';

  @override
  String get projectsTitle => 'Projets';

  @override
  String get projectsEmpty => 'Aucun projet pour l\'instant';

  @override
  String get projectsFilterAll => 'Tous';

  @override
  String get projectCreate => 'Nouveau projet';

  @override
  String get projectEdit => 'Modifier le projet';

  @override
  String get projectDelete => 'Supprimer';

  @override
  String get projectDeleteTitle => 'Supprimer le projet ?';

  @override
  String projectDeleteBody(String name) {
    return '« $name » sera supprimé. Les impressions associées resteront dans les archives.';
  }

  @override
  String get projectDeleted => 'Projet supprimé';

  @override
  String get projectDeleteFailed => 'Impossible de supprimer le projet';

  @override
  String get projectSaved => 'Projet enregistré';

  @override
  String get projectName => 'Nom';

  @override
  String get projectNameRequired => 'Le nom est obligatoire';

  @override
  String get projectDescription => 'Description';

  @override
  String get projectNotes => 'Notes';

  @override
  String get projectStatus => 'Statut';

  @override
  String get projectPriority => 'Priorité';

  @override
  String get projectColor => 'Couleur';

  @override
  String get projectDueDate => 'Date d\'échéance';

  @override
  String get projectDueDateClear => 'Effacer';

  @override
  String get projectBudget => 'Budget';

  @override
  String get projectTargetCount => 'Plateaux cibles';

  @override
  String get projectTargetPartsCount => 'Pièces cibles';

  @override
  String get projectTargetSets => 'Ensembles cibles';

  @override
  String get projectTargetSetsHint =>
      'Nombre de fois où chaque fichier du projet doit être imprimé';

  @override
  String get projectTags => 'Étiquettes (séparées par des virgules)';

  @override
  String get projectUrl => 'Lien';

  @override
  String get projectParent => 'Projet parent';

  @override
  String get projectParentNone => 'Aucun';

  @override
  String get projectSave => 'Enregistrer';

  @override
  String get projectStatusPlanning => 'Planification';

  @override
  String get projectStatusActive => 'Actif';

  @override
  String get projectStatusOnHold => 'En attente';

  @override
  String get projectStatusCompleted => 'Terminé';

  @override
  String get projectStatusArchived => 'Archivé';

  @override
  String get projectPriorityLow => 'Basse';

  @override
  String get projectPriorityNormal => 'Normale';

  @override
  String get projectPriorityHigh => 'Haute';

  @override
  String get projectPriorityUrgent => 'Urgente';

  @override
  String get projectTabOverview => 'Vue d\'ensemble';

  @override
  String get projectTabArchives => 'Archives';

  @override
  String get projectTabBom => 'BOM';

  @override
  String get projectTabQueue => 'File d\'attente';

  @override
  String get projectTabTimeline => 'Chronologie';

  @override
  String get projectTabFiles => 'Fichiers';

  @override
  String get projectTabAttachments => 'Pièces jointes';

  @override
  String get projectStatsTitle => 'Statistiques';

  @override
  String get projectStatProgress => 'Progression';

  @override
  String get projectStatPartsProgress => 'Pièces';

  @override
  String get projectStatSets => 'Ensembles complets';

  @override
  String projectSetsOfTarget(int done, int target) {
    return '$done sur $target';
  }

  @override
  String get projectStatPrints => 'Plateaux';

  @override
  String get projectStatCompleted => 'Terminés';

  @override
  String get projectStatFailed => 'Échoués';

  @override
  String get projectStatQueued => 'En file d\'attente';

  @override
  String get projectStatInProgress => 'En cours';

  @override
  String get projectStatPrintTime => 'Temps d\'impression';

  @override
  String get projectStatFilament => 'Filament';

  @override
  String get projectStatCost => 'Coût estimé';

  @override
  String get projectStatEnergy => 'Énergie';

  @override
  String get projectStatEnergyCost => 'Coût de l\'énergie';

  @override
  String get projectStatRemaining => 'Restant';

  @override
  String get projectStatBom => 'BOM';

  @override
  String get projectChildren => 'Sous-projets';

  @override
  String get projectNoDescription => 'Aucune description';

  @override
  String projectDueOn(String date) {
    return 'Échéance le $date';
  }

  @override
  String get projectAddArchives => 'Ajouter des archives';

  @override
  String get projectRemoveArchive => 'Retirer du projet';

  @override
  String get projectArchivesEmpty => 'Aucune archive associée';

  @override
  String get projectArchiveRemoved => 'Retiré du projet';

  @override
  String get archiveAddToProject => 'Ajouter au projet';

  @override
  String get projectArchivesAdded => 'Ajouté au projet';

  @override
  String get projectPickTitle => 'Sélectionner un projet';

  @override
  String get projectBomEmpty => 'Aucun élément dans la BOM';

  @override
  String get bomAdd => 'Ajouter un élément';

  @override
  String get bomEditTitle => 'Modifier l\'élément';

  @override
  String get bomAddTitle => 'Nouvel élément';

  @override
  String get bomName => 'Nom';

  @override
  String get bomQtyNeeded => 'Quantité';

  @override
  String get bomQtyAcquired => 'Acquis';

  @override
  String get bomUnitPrice => 'Prix unitaire';

  @override
  String get bomSourcingUrl => 'URL d\'approvisionnement';

  @override
  String get bomRemarks => 'Remarques';

  @override
  String get bomComplete => 'Complet';

  @override
  String get bomDelete => 'Supprimer l\'élément';

  @override
  String get bomDeleted => 'Élément supprimé';

  @override
  String get projectQueueEmpty => 'Aucun élément dans la file d\'attente';

  @override
  String get projectTimelineEmpty => 'Aucun événement pour l\'instant';

  @override
  String get projectAttachmentsEmpty => 'Aucune pièce jointe';

  @override
  String get projectFilesEmpty => 'Aucun fichier imprimable';

  @override
  String get projectAttachmentUpload => 'Téléverser un fichier';

  @override
  String get projectAttachmentDownload => 'Télécharger';

  @override
  String get projectAttachmentDelete => 'Supprimer';

  @override
  String get projectAttachmentDeleted => 'Pièce jointe supprimée';

  @override
  String get projectAttachmentUploaded => 'Pièce jointe téléversée';

  @override
  String projectFileSaved(String path) {
    return 'Enregistré dans $path';
  }

  @override
  String get projectDownloadFailed => 'Échec du téléchargement';

  @override
  String get projectCoverUpload => 'Définir l\'image de couverture';

  @override
  String get projectCoverDelete => 'Supprimer l\'image de couverture';

  @override
  String get projectCoverUpdated => 'Couverture mise à jour';

  @override
  String get projectCoverRemoved => 'Couverture supprimée';

  @override
  String get projectMenuExport => 'Exporter';

  @override
  String get projectMenuCreateTemplate => 'Enregistrer comme modèle';

  @override
  String get projectMenuImport => 'Importer un projet';

  @override
  String get projectFromTemplate => 'Créer à partir d\'un modèle';

  @override
  String get projectTemplateNone => 'Aucun modèle';

  @override
  String get projectTemplatePickTitle => 'Choisir un modèle';

  @override
  String get projectTemplateNamePrompt => 'Nom du nouveau projet';

  @override
  String projectExported(String path) {
    return 'Exporté vers $path';
  }

  @override
  String get projectExportFailed => 'Échec de l\'exportation';

  @override
  String get projectTemplateCreated => 'Modèle créé';

  @override
  String get projectImported => 'Projet importé';

  @override
  String get projectImportFailed => 'Échec de l\'importation';

  @override
  String get projectUploading => 'Téléversement…';

  @override
  String get projectLinkFolder => 'Lier un dossier';

  @override
  String get projectNoFoldersToLink => 'Aucun dossier disponible à lier';

  @override
  String get projectUnlinkFolder => 'Délier le dossier';

  @override
  String get projectFolderLinked => 'Dossier lié';

  @override
  String get projectFolderUnlinked => 'Dossier délié';

  @override
  String get projectNotesEmpty => 'Aucune note pour l\'instant';

  @override
  String projectFolderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers',
      one: '$count fichier',
    );
    return '$_temp0';
  }

  @override
  String projectRemainingShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count restants',
      one: '$count restant',
    );
    return '$_temp0';
  }

  @override
  String get sliceAction => 'Découper';

  @override
  String get sliceTitle => 'Découper le fichier';

  @override
  String get slicePrinter => 'Imprimante';

  @override
  String get sliceProcess => 'Processus / Qualité';

  @override
  String get sliceBedType => 'Type de plaque';

  @override
  String get sliceBedDefault => 'Par défaut (du préréglage)';

  @override
  String get sliceFilament => 'Filament';

  @override
  String sliceFilamentNumbered(String n) {
    return 'Filament $n';
  }

  @override
  String get sliceAutoOrient => 'Orientation automatique';

  @override
  String get sliceAutoOrientHint =>
      'Oriente chaque objet sur sa face d\'impression optimale.';

  @override
  String get sliceAutoArrange => 'Disposition automatique';

  @override
  String get sliceAutoArrangeHint => 'Réorganise les objets sur le plateau.';

  @override
  String sliceDesignedFor(String printer) {
    return 'Ce fichier est conçu pour $printer';
  }

  @override
  String get sliceUseDesignedPrinter => 'Changer';

  @override
  String get sliceAsDesigned => 'Utiliser les paramètres d\'origine du fichier';

  @override
  String get sliceAsDesignedHint =>
      'Les paramètres du créateur au lieu des préréglages ci-dessus.';

  @override
  String get sliceAsDesignedInactive => 'Non utilisé — défini par le fichier';

  @override
  String get sliceFilamentUnused => 'Non utilisé sur ce plateau';

  @override
  String get processSettingsTitle => 'Paramètres du processus';

  @override
  String get sliceProcessSettingsNeedsProcess =>
      'Choisissez d\'abord un préréglage de processus';

  @override
  String get sliceProcessSettingsUnchanged => 'Préréglage utilisé tel quel';

  @override
  String sliceProcessSettingsChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modifiés',
      one: '$count modifié',
    );
    return '$_temp0';
  }

  @override
  String get processSettingsModeSimple => 'Simple';

  @override
  String get processSettingsModeAdvanced => 'Avancé';

  @override
  String get processSettingsModeExpert => 'Expert';

  @override
  String get processSettingsSearchHint => 'Rechercher des paramètres';

  @override
  String get processSettingsNoMatches =>
      'Aucun paramètre ne correspond à cette recherche.';

  @override
  String get processSettingsRevert => 'Rétablir la valeur du préréglage';

  @override
  String processSettingsRevertAll(int count) {
    return 'Rétablir $count';
  }

  @override
  String processSettingsOutOfRange(String range) {
    return 'Le slicer accepte $range';
  }

  @override
  String get processSettingsDisabledHint =>
      'Le slicer ignore ce paramètre avec vos réglages actuels.';

  @override
  String get processSettingsUnavailable =>
      'Ce serveur ne peut pas indiquer les paramètres de processus pour le préréglage sélectionné.';

  @override
  String get processSettingsDefaultsOutdatedSidecar =>
      'Valeurs par défaut du slicer affichées : votre sidecar de slicer est antérieur à cette fonctionnalité et ne peut pas lire les valeurs du préréglage. Mettez à jour l\'image du sidecar pour les afficher. Tout ce que vous ne modifiez pas continuera d\'utiliser le préréglage.';

  @override
  String get processSettingsDefaultsNotConfigured =>
      'Valeurs par défaut du slicer affichées : aucun sidecar de slicer n\'est configuré, les valeurs du préréglage ne peuvent donc pas être lues. Tout ce que vous ne modifiez pas continuera d\'utiliser le préréglage.';

  @override
  String get processSettingsDefaultsSidecarUnavailable =>
      'Valeurs par défaut du slicer affichées : le sidecar du slicer n\'a pas répondu, les valeurs du préréglage ne peuvent donc pas être lues. Tout ce que vous ne modifiez pas continuera d\'utiliser le préréglage.';

  @override
  String get processSettingsDefaultsUnavailable =>
      'Valeurs par défaut du slicer affichées : les valeurs du préréglage sélectionné n\'ont pas pu être lues. Tout ce que vous ne modifiez pas continuera d\'utiliser le préréglage.';

  @override
  String get processSettingsFilamentDefault =>
      'Par défaut (le filament de la zone)';

  @override
  String processSettingsFilamentSlot(String slot, String name) {
    return '$slot : $name';
  }

  @override
  String processSettingsFilamentSlotMissing(String slot) {
    return 'Emplacement $slot — ce fichier ne comporte aucun emplacement de ce type';
  }

  @override
  String get sliceSelect => 'Appuyer pour sélectionner';

  @override
  String get sliceStart => 'Découper';

  @override
  String get sliceShowAll => 'Tout';

  @override
  String get sliceSearchHint => 'Rechercher des préréglages';

  @override
  String get sliceOwnedEmpty =>
      'Aucun préréglage correspondant pour votre imprimante et vos filaments. Activez « Tout » pour parcourir le catalogue complet.';

  @override
  String get sliceNoPresets => 'Aucun préréglage disponible';

  @override
  String get sliceInProgress => 'Découpage en cours…';

  @override
  String get sliceDone => 'Découpage terminé';

  @override
  String get sliceFailed => 'Échec du découpage';

  @override
  String get sliceExternalFallback =>
      'Enregistré dans la bibliothèque du serveur — le dossier du fichier n\'a pas pu l\'accueillir.';

  @override
  String get sliceExternalReadonly =>
      'Ce dossier est configuré en lecture seule.';

  @override
  String get sliceExternalNoPath =>
      'Aucun chemin n\'est configuré pour ce dossier.';

  @override
  String get sliceExternalUnreachable =>
      'Le chemin de ce dossier n\'est pas accessible pour le moment.';

  @override
  String get sliceExternalNotWritable =>
      'Le serveur ne peut pas écrire dans ce dossier.';

  @override
  String get sliceExternalInvalidName =>
      'Ce dossier n\'a pas accepté le nom du fichier.';

  @override
  String get sliceClose => 'Fermer';

  @override
  String sliceResultTime(String time) {
    return 'Temps estimé : $time';
  }

  @override
  String get sliceRefusedStep =>
      'Les fichiers STEP ne peuvent pas être découpés. Exportez d\'abord le modèle au format STL ou 3MF depuis votre logiciel de CAO.';

  @override
  String get sliceRefusedFormat =>
      'Le fichier source doit être un STL ou un 3MF.';

  @override
  String get sliceRefusedNoSource =>
      'Cette archive n\'a conservé que le G-code imprimé, pas le modèle — il n\'y a rien à redécouper.';

  @override
  String sliceResultFilament(String grams) {
    return 'Filament : $grams g';
  }

  @override
  String get sliceTierLocal => 'Préréglage local';

  @override
  String get sliceTierCloud => 'Bambu Cloud';

  @override
  String get sliceTierOrcaCloud => 'Orca Cloud';

  @override
  String get sliceTierStandard => 'Intégré';

  @override
  String get pipelineSection => 'Pipeline';

  @override
  String get pipelineApply => 'Appliquer le pipeline…';

  @override
  String get pipelineApplyEmpty => 'Aucun pipeline enregistré';

  @override
  String pipelineApplied(String name) {
    return '« $name » appliqué';
  }

  @override
  String get pipelineSaveAs => 'Enregistrer comme pipeline';

  @override
  String get pipelineNameHint => 'Nom du pipeline';

  @override
  String get pipelineSaveConfirm => 'Enregistrer';

  @override
  String get pipelineSaved => 'Pipeline enregistré';

  @override
  String get pipelineSaveHint =>
      'L\'imprimante, le processus, les filaments et le plateau ci-dessus, réunis sous un nom réutilisable pour le prochain fichier.';

  @override
  String get pipelinesMenu => 'Pipelines';

  @override
  String get pipelinesTitle => 'Pipelines';

  @override
  String get pipelinesEmpty => 'Aucun pipeline pour l\'instant';

  @override
  String get pipelinesEmptyHint =>
      'Enregistrez-en un depuis le formulaire de découpage : imprimante, processus, filaments et plateau regroupés pour les réappliquer en un seul geste.';

  @override
  String get pipelineProfiles => 'Préréglages';

  @override
  String pipelineFilamentsCount(int count) {
    return 'Filaments ($count)';
  }

  @override
  String get pipelineHistory => 'Historique des exécutions';

  @override
  String get pipelineCardActions => 'Actions du pipeline';

  @override
  String pipelineSlotNumbered(int n) {
    return 'Filament $n';
  }

  @override
  String get pipelineBed => 'Plaque';

  @override
  String get pipelinePresetGone => 'Plus disponible dans le catalogue';

  @override
  String get pipelineNeedsTarget =>
      'Définissez une cible avant de lancer ce pipeline.';

  @override
  String get pipelineNoTargetChip => 'Aucune cible';

  @override
  String get pipelineEditTitle => 'Modifier le pipeline';

  @override
  String get pipelineDescriptionHint => 'Description (facultatif)';

  @override
  String get pipelineTargetType => 'Cible';

  @override
  String get pipelineTargetSpecific => 'Une imprimante';

  @override
  String get pipelineTargetClass => 'Modèle d\'imprimante';

  @override
  String get pipelineTargetPickPrinter => 'Choisir une imprimante';

  @override
  String get pipelineTargetPickClass => 'Choisir un modèle';

  @override
  String get pipelineTargetNone => '— aucune cible —';

  @override
  String pipelineTargetPrinterGone(int id) {
    return 'Imprimante #$id (disparue)';
  }

  @override
  String get pipelineFanout => 'Répartition des exemplaires';

  @override
  String get pipelineFanoutMaxParallel =>
      'Parallélisme maximal — sur toute imprimante compatible inactive';

  @override
  String get pipelineFanoutRoundRobin =>
      'Tour de rôle (round-robin) — alterne entre les imprimantes éligibles';

  @override
  String get pipelineFanoutFillOneFirst =>
      'Remplir une imprimante d\'abord — tous les exemplaires sur la même';

  @override
  String get pipelineDelete => 'Supprimer le pipeline';

  @override
  String pipelineDeleteConfirm(String name) {
    return 'Supprimer « $name » ? Les exécutions déjà effectuées conserveront leur nom.';
  }

  @override
  String get pipelineDeleted => 'Pipeline supprimé';

  @override
  String get pipelineDescriptionNoClear =>
      'Une description ne peut plus être vidée une fois enregistrée — ce serveur permet seulement d\'en écrire une nouvelle.';

  @override
  String get pipelineRun => 'Lancer';

  @override
  String pipelineRunTitle(String name) {
    return 'Lancer « $name »';
  }

  @override
  String get pipelineRunCopies => 'Exemplaires';

  @override
  String get pipelineRunStart => 'Démarrer';

  @override
  String get pipelineRunStarted => 'Exécution lancée';

  @override
  String get pipelineRunAnyway => 'Lancer quand même';

  @override
  String pipelineRunMaxCopies(int max) {
    return 'Ce serveur autorise au maximum $max.';
  }

  @override
  String get pipelineCheckingEligibility => 'Vérification des imprimantes…';

  @override
  String get pipelineEligibilityOk => 'Prêt à être lancé.';

  @override
  String pipelineEligibilityClassCount(int ok, int total) {
    return '$ok sur $total imprimantes prêtes';
  }

  @override
  String get pipelineEligibilityBlocked =>
      'Aucune imprimante ne peut prendre cette exécution pour le moment.';

  @override
  String get pipelineEligibilityAdvisory => 'À vérifier avant de lancer.';

  @override
  String get pipelineIssuePrinterNotSet =>
      'Ce pipeline n\'a pas d\'imprimante cible.';

  @override
  String get pipelineIssuePrinterNotFound =>
      'L\'imprimante cible n\'existe plus.';

  @override
  String get pipelineIssuePrinterDisabled =>
      'L\'imprimante cible est désactivée dans bambuddy.';

  @override
  String get pipelineIssuePrinterOffline =>
      'L\'imprimante cible est hors ligne.';

  @override
  String get pipelineIssueFilamentType => 'Type de filament chargé incorrect.';

  @override
  String get pipelineIssueFilamentColor =>
      'Le filament chargé est d\'une couleur différente.';

  @override
  String get pipelineIssueAmsSlotMissing =>
      'L\'AMS a moins d\'emplacements que ce que requiert ce pipeline.';

  @override
  String get pipelineIssueFilamentUnverified =>
      'Ce préréglage de filament ne peut pas être vérifié d\'ici — vérifiez-le vous-même.';

  @override
  String get pipelineIssueNoClassMatches =>
      'Aucune imprimante de ce modèle n\'est installée.';

  @override
  String get pipelineIssueClassNotSet =>
      'Ce pipeline n\'a aucun modèle d\'imprimante défini.';

  @override
  String pipelineIssueSlot(int n) {
    return 'Emplacement $n';
  }

  @override
  String pipelineIssueWantedGot(String expected, String actual) {
    return 'attendu : $expected, chargé : $actual';
  }

  @override
  String pipelineIssueWanted(String expected) {
    return 'attendu : $expected';
  }

  @override
  String get pipelineRunsTitle => 'Exécutions du pipeline';

  @override
  String get pipelineRunsEmpty => 'Aucune exécution pour l\'instant';

  @override
  String get pipelineRunsNoneMatch =>
      'Aucune exécution ne correspond à ces filtres';

  @override
  String get pipelineRunsFilter => 'Filtrer les exécutions';

  @override
  String get pipelineCopiesLess => 'Un exemplaire de moins';

  @override
  String get pipelineCopiesMore => 'Un exemplaire de plus';

  @override
  String get pipelineEligible => 'Prêt';

  @override
  String get pipelineIneligible => 'Non prêt';

  @override
  String pipelineRunsFilterActive(int count) {
    return 'Filtrer les exécutions ($count actifs)';
  }

  @override
  String get pipelineRunsFilterAny => 'Tous';

  @override
  String get pipelineRunsFilterStatus => 'Statut';

  @override
  String get pipelineRunsFilterStatusHint =>
      'Le filtre porte sur le dernier statut enregistré : une exécution peut donc encore correspondre à l\'étape précédant celle où elle se trouve.';

  @override
  String get pipelineRunsFilterTarget => 'Cible';

  @override
  String get pipelineRunsFilterTargetHint =>
      'Là où pointe le pipeline actuellement — changer sa cible déplace tout son historique.';

  @override
  String get pipelineRunsFilterPipelineHint =>
      'Les exécutions d\'un pipeline supprimé ne peuvent pas être filtrées.';

  @override
  String get pipelineRunsFilterClear => 'Effacer les filtres';

  @override
  String get pipelineRunsLoadMore => 'Charger plus';

  @override
  String pipelineRunsShowingAll(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tous les $count affichés',
      one: '$count affiché',
    );
    return '$_temp0';
  }

  @override
  String get pipelineRunsDone => 'Terminé';

  @override
  String get pipelineRunsClear => 'Effacer les terminées';

  @override
  String pipelineRunsCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count supprimées',
      one: '$count supprimée',
    );
    return '$_temp0';
  }

  @override
  String get pipelineRunsClearConfirm =>
      'Supprimer de cette liste toutes les exécutions terminées ?';

  @override
  String pipelineRunCopiesProgress(int done, int total) {
    return '$done sur $total exemplaires';
  }

  @override
  String get pipelineRunCancel => 'Annuler l\'exécution';

  @override
  String get pipelineRunCancelConfirm =>
      'Annuler cette exécution ? Les exemplaires non encore envoyés seront abandonnés ; toute impression déjà en cours doit être arrêtée directement sur l\'imprimante.';

  @override
  String get pipelineRunCancelled => 'Exécution annulée';

  @override
  String get pipelineRunRetry => 'Réessayer les échecs';

  @override
  String pipelineRunRetryStarted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Nouvelle tentative pour $count exemplaires',
      one: 'Nouvelle tentative pour $count exemplaire',
    );
    return '$_temp0';
  }

  @override
  String get pipelineRunOverridden =>
      'Démarré malgré l\'échec d\'une vérification';

  @override
  String get pipelineRunDeletedPipeline => 'Pipeline supprimé';

  @override
  String pipelineRunSource(String name) {
    return 'Depuis $name';
  }

  @override
  String pipelineRunRetryOf(int id) {
    return 'Nouvelle tentative de l\'exécution #$id';
  }

  @override
  String pipelineRunOnPrinter(String printer) {
    return 'Sur $printer';
  }

  @override
  String pipelineRunOnClass(String model) {
    return 'Sur n\'importe quelle $model';
  }

  @override
  String get pipelineStatusQueued => 'En file d\'attente';

  @override
  String get pipelineStatusSlicing => 'Découpage';

  @override
  String get pipelineStatusDispatching => 'Envoi';

  @override
  String get pipelineStatusInProgress => 'Impression';

  @override
  String get pipelineStatusCompleted => 'Terminée';

  @override
  String get pipelineStatusFailed => 'Échouée';

  @override
  String get pipelineStatusPartial => 'Partiellement échouée';

  @override
  String get pipelineStatusCancelled => 'Annulée';

  @override
  String get pipelineStatusUnknown => 'Inconnue';

  @override
  String pipelineJobCopy(int n) {
    return 'Exemplaire $n';
  }

  @override
  String get pipelineJobPending => 'En attente';

  @override
  String get pipelineJobAwaitingPrinter => 'En attente d\'une imprimante';

  @override
  String get pipelineJobQueued => 'En file d\'attente';

  @override
  String get pipelineJobPrinting => 'Impression';

  @override
  String get pipelineJobCompleted => 'Terminé';

  @override
  String get pipelineJobFailed => 'Échoué';

  @override
  String get pipelineJobCancelled => 'Annulé';

  @override
  String get pipelineJobUnknown => 'Inconnu';

  @override
  String get queueFilamentMapping => 'Mappage des filaments';

  @override
  String get mappingNoPrinter =>
      'Attribuez d\'abord une imprimante à cet élément pour mapper ses emplacements AMS.';

  @override
  String get mappingNoSlots =>
      'Aucune information de filament pour ce fichier.';

  @override
  String mappingNoAms(String printer) {
    return 'Aucun filament AMS chargé sur $printer.';
  }

  @override
  String get mappingPickTray => 'Sélectionner un emplacement AMS';

  @override
  String get mappingExternalSpool => 'Bobine externe';

  @override
  String mappingAmsSlot(String unit, String slot) {
    return 'AMS $unit · emplacement $slot';
  }

  @override
  String get mappingSaved => 'Mappage des filaments enregistré';

  @override
  String get plateClearTitle => 'Le plateau est-il dégagé ?';

  @override
  String get plateClearBody =>
      'Assurez-vous que le plateau d\'impression est vide avant de lancer cette impression.';

  @override
  String get plateClearConfirm => 'Le plateau est dégagé';

  @override
  String get plateClearAction => 'Marquer le plateau comme dégagé';

  @override
  String get plateClearBadge => 'Plateau non dégagé';

  @override
  String get plateClearedSnack => 'Plateau marqué comme dégagé';

  @override
  String get plateClearNeedsOnline =>
      'Ce serveur ne libère le plateau que lorsque l\'imprimante est connectée. Mettez à jour bambuddy pour pouvoir le faire sur une imprimante éteinte.';

  @override
  String get pfmTitle => 'Gestionnaire de fichiers';

  @override
  String get pfmTooltip => 'Fichiers sur l\'imprimante';

  @override
  String pfmStorageUsed(String size) {
    return 'Utilisé : $size';
  }

  @override
  String get pfmTabRoot => 'Racine';

  @override
  String get pfmTabCache => 'Cache';

  @override
  String get pfmTabModels => 'Modèles';

  @override
  String get pfmTabTimelapse => 'Timelapse';

  @override
  String get pfmSearchHint => 'Filtrer les fichiers…';

  @override
  String get pfmSortTooltip => 'Trier';

  @override
  String get pfmRefreshTooltip => 'Actualiser';

  @override
  String get pfmSortNameAsc => 'Nom (A–Z)';

  @override
  String get pfmSortNameDesc => 'Nom (Z–A)';

  @override
  String get pfmSortSizeLargest => 'Taille (plus grande)';

  @override
  String get pfmSortSizeSmallest => 'Taille (plus petite)';

  @override
  String get pfmSortDateNewest => 'Date (plus récente)';

  @override
  String get pfmSortDateOldest => 'Date (plus ancienne)';

  @override
  String get pfmUp => 'Dossier parent';

  @override
  String get pfmSelectAll => 'Tout sélectionner';

  @override
  String get pfmDeselectAll => 'Tout désélectionner';

  @override
  String pfmSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnés',
      one: '$count sélectionné',
    );
    return '$_temp0';
  }

  @override
  String get pfmEmpty => 'Ce dossier est vide';

  @override
  String get pfmNoMatches => 'Aucun fichier ne correspond à votre filtre';

  @override
  String get pfmPrinterUnavailable =>
      'L\'imprimante n\'a pas répondu, ses fichiers n\'ont pas pu être listés';

  @override
  String get pfmDownloadTooLarge =>
      'La sélection est trop volumineuse pour être regroupée par le serveur';

  @override
  String get pfmDownloadNoServerSpace =>
      'Le serveur n\'a pas assez d\'espace pour préparer ce téléchargement';

  @override
  String get pfmDownloadTookTooLong =>
      'La préparation du téléchargement a pris trop de temps et le serveur a abandonné';

  @override
  String get pfmPreparingOnServer => 'Préparation sur le serveur…';

  @override
  String get pfmDownloading => 'Téléchargement…';

  @override
  String get pfmDownloadCancelled => 'Téléchargement annulé';

  @override
  String get pfmDownloadPrepareFailed =>
      'Le serveur n\'a pas pu préparer ce téléchargement';

  @override
  String pfmDownloadPartial(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count fichiers n\'ont pas pu être lus depuis l\'imprimante et ont été ignorés',
      one:
          'Un fichier n\'a pas pu être lu depuis l\'imprimante et a été ignoré',
    );
    return '$_temp0';
  }

  @override
  String get pfmDownloadSaved => 'Fichier enregistré';

  @override
  String get pfmDownloadNotSaved =>
      'Le fichier n\'a pas pu être enregistré à l\'emplacement choisi';

  @override
  String get pfmDownload => 'Télécharger';

  @override
  String get pfmDelete => 'Supprimer';

  @override
  String get pfmDeleteConfirmTitle => 'Supprimer les fichiers ?';

  @override
  String pfmDeleteConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fichiers',
      one: 'fichier',
    );
    return 'Supprimer définitivement $count $_temp0 de l\'imprimante ? Cette action est irréversible.';
  }

  @override
  String pfmDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers supprimés',
      one: '$count fichier supprimé',
    );
    return '$_temp0';
  }

  @override
  String get wearConnectionFailed => 'Échec de connexion';

  @override
  String get wearNoPrinters => 'Aucune imprimante';

  @override
  String get wearPrinterUnavailable => 'Imprimante indisponible';

  @override
  String get wearNoActions => 'Aucune action disponible';

  @override
  String get wearClearPlate => 'Vider le plateau';

  @override
  String get wearPlateCleared => 'Plateau vidé';

  @override
  String get wearPlateNeedsOnline =>
      'Ce serveur nécessite l\'imprimante en ligne';

  @override
  String get wearStarted => 'Démarré';

  @override
  String get wearPhoneUnreachable => 'Téléphone injoignable';

  @override
  String get wearPhoneNoResponse => 'Le téléphone n\'a pas répondu';

  @override
  String get wearConfirm => 'Confirmer';

  @override
  String get wearServerUrl => 'URL du serveur';

  @override
  String get wearConnect => 'Se connecter';

  @override
  String get wearAuthKey => 'Clé';

  @override
  String get wearAuthLogin => 'Compte';

  @override
  String get wearUsername => 'Nom d\'utilisateur';

  @override
  String get wearSetupPhoneTitle => 'Configurer depuis le téléphone';

  @override
  String get wearSetupPhoneBody =>
      'Ouvrez Bambuddy sur votre téléphone jumelé — la montre y récupère le serveur et la connexion.';

  @override
  String get wearSetupPhoneCheck => 'Vérifier à nouveau';

  @override
  String get wearSetupPhoneEmpty => 'Rien reçu du téléphone pour l\'instant.';

  @override
  String get wearSetupManual => 'Saisir manuellement';

  @override
  String get wearSetupDemo => 'Démo';

  @override
  String get wearSetupTapToType => 'Appuyer pour saisir';

  @override
  String get wearSettingsTitle => 'Paramètres';

  @override
  String get wearFromPhone => 'Depuis le téléphone';

  @override
  String get wearFromPhoneUse => 'Utiliser ce serveur';

  @override
  String get wearFromPhoneLater => 'Pas maintenant';

  @override
  String get wearAuthNone => 'Sans connexion';

  @override
  String get wearFromPhoneWaiting => 'Le téléphone propose un autre serveur.';

  @override
  String get wearCurrentServer => 'Serveur actuel';

  @override
  String get wearOk => 'OK';

  @override
  String get commonOn => 'Activé';

  @override
  String get commonOff => 'Désactivé';

  @override
  String get commonAuto => 'Auto';

  @override
  String get queueEdit => 'Modifier';

  @override
  String get queueEditTitle => 'Modifier l\'élément de la file';

  @override
  String get queueEditSave => 'Enregistrer';

  @override
  String get queueEditSaved => 'Élément de la file mis à jour';

  @override
  String get queueCreateTitle => 'Imprimer';

  @override
  String get queueCreateSubmit => 'Imprimer';

  @override
  String get queueCreateAdded => 'Ajouté à la file d\'attente';

  @override
  String get queueEditPrintJob => 'Travail d\'impression';

  @override
  String get queueEditTarget => 'Cible';

  @override
  String get queueEditSpecificPrinter => 'Imprimante spécifique';

  @override
  String queueEditAnyModel(String model) {
    return 'N\'importe quelle $model';
  }

  @override
  String get queueEditAnyModelGeneric => 'N\'importe quel modèle';

  @override
  String get queueEditTargetModel => 'Modèle';

  @override
  String get queueEditTargetLocation => 'Emplacement';

  @override
  String get queueEditAnyLocation => 'Tout emplacement';

  @override
  String get queueEditMappingNeedsPrinter =>
      'Sélectionnez une imprimante pour associer les filaments';

  @override
  String queueEditMappingSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'emplacements associés',
      one: 'emplacement associé',
    );
    return '$count $_temp0';
  }

  @override
  String get queueEditMappingAuto => 'Auto (aucune association manuelle)';

  @override
  String get queueEditPlate => 'Plateau';

  @override
  String queueEditPlateSelected(int plate) {
    return 'Plateau $plate';
  }

  @override
  String queueEditPlateNamed(int plate, String name) {
    return 'Plateau $plate · $name';
  }

  @override
  String queueEditPlateFixed(int plate) {
    return 'Ce travail imprime le plateau $plate';
  }

  @override
  String get queuePlatePickTitle => 'Quel plateau ?';

  @override
  String queuePlateObjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objets',
      one: '1 objet',
      zero: 'Aucun objet',
    );
    return '$_temp0';
  }

  @override
  String get queueEditPrintOptions => 'Options d\'impression';

  @override
  String get queueOptBedLevelling => 'Nivellement du plateau';

  @override
  String get queueOptBedLevellingDesc =>
      'Niveler automatiquement le plateau avant l\'impression';

  @override
  String get queueOptFlowCali => 'Calibrage du débit';

  @override
  String get queueOptFlowCaliDesc => 'Calibrer le débit d\'extrusion';

  @override
  String get queueOptVibrationCali => 'Calibrage des vibrations';

  @override
  String get queueOptVibrationCaliDesc => 'Réduire les artefacts de résonance';

  @override
  String get queueOptLayerInspect => 'Inspection de la première couche';

  @override
  String get queueOptLayerInspectDesc =>
      'Inspection de la première couche par IA';

  @override
  String get queueOptTimelapse => 'Timelapse';

  @override
  String get queueOptTimelapseDesc => 'Enregistrer une vidéo timelapse';

  @override
  String get queueOptNozzleOffset => 'Calibrage du décalage de la buse';

  @override
  String get queueOptNozzleOffsetDesc =>
      'Calibrer les décalages de buse entre les extrudeurs';

  @override
  String get queueEditPreheat => 'Préchauffage et stabilisation thermique';

  @override
  String get queueEditPreheatDesc =>
      'Chauffe le plateau et la chambre avant le début de l\'impression. Utilise par défaut le réglage global Paramètres → Flux de travail.';

  @override
  String get queuePreheatInherit => 'Hériter';

  @override
  String get queueEditChamberTarget =>
      'Remplacer la température de chambre (°C, vide = défaut du filament)';

  @override
  String queueEditChamberTargetRange(int max) {
    return '0–$max °C';
  }

  @override
  String get queueEditWhenToPrint => 'Quand imprimer';

  @override
  String get queueScheduleAsap => 'Dès que possible';

  @override
  String get queueScheduleQueue => 'File d\'attente';

  @override
  String get queueScheduleSchedule => 'Planifier';

  @override
  String get queueEditPickTime => 'Choisir la date et l\'heure';

  @override
  String get queueEditRequireManualStart => 'Exiger un démarrage manuel';

  @override
  String get queueEditRequirePrevious =>
      'Démarrer uniquement si l\'impression précédente a réussi';

  @override
  String get queueEditPowerOff => 'Éteindre l\'imprimante une fois terminé';

  @override
  String get queueEditGcodeInjection =>
      'Injecter le G-code d\'impression automatique';

  @override
  String queueEditGcodeInjectionNoSnippet(String model) {
    return 'Aucun extrait G-code pour $model — rien ne sera injecté.';
  }

  @override
  String get queueEditNoModel => 'Sélectionnez un modèle cible';

  @override
  String get queueEditNoPrinter => 'Sélectionnez une imprimante';

  @override
  String get queueEditFilamentOverride => 'Substitution de filament';

  @override
  String get queueEditFilamentOverrideDesc =>
      'Remplacez éventuellement les filaments pour l\'attribution basée sur le modèle. Le planificateur utilisera vos filaments sélectionnés au lieu des valeurs initiales du 3MF.';

  @override
  String get queueEditNoFilamentReqs =>
      'Aucune exigence de filament pour ce travail.';

  @override
  String get queueEditOriginal => 'Original';

  @override
  String queueEditSlotLabel(String slot, String type) {
    return 'Emplacement $slot · $type';
  }

  @override
  String get queueEditForceColorMatch => 'Forcer la correspondance de couleur';

  @override
  String get queueEditNozzleRack => 'Rack de buses';

  @override
  String get queueEditNozzleRackDesc =>
      'Choisissez depuis quelle buse du rack chaque filament s\'imprime. Si laissé en automatique, une position adaptée sera choisie au lancement de l\'impression.';

  @override
  String queueEditRackGroupLabel(String slots, String nozzle) {
    return 'Filament $slots · $nozzle';
  }

  @override
  String get queueEditRackAuto => 'Automatique';

  @override
  String queueEditRackPosition(int position, String nozzle) {
    return 'Position $position · $nozzle';
  }

  @override
  String queueEditRackPositionTaken(int position, String nozzle) {
    return 'Position $position · $nozzle — déjà choisie';
  }

  @override
  String queueEditRackPositionUnfit(int position, String nozzle) {
    return 'Position $position · $nozzle — incompatible';
  }

  @override
  String get queueEditRackEmpty => 'vide';

  @override
  String get queueEditRackPickStale =>
      'La position choisie ne convient plus à ce filament — choisissez-en une autre, sinon l\'impression sera refusée au démarrage.';

  @override
  String queueEditRackNoFit(String nozzle) {
    return 'Aucune position du rack ne contient de buse $nozzle — installez-en une, sinon l\'imprimante décidera d\'elle-même.';
  }

  @override
  String get nozzleFlowStandard => 'Standard';

  @override
  String get nozzleFlowHigh => 'Haut débit';

  @override
  String get bugReportMenu => 'Signaler un bug ou proposer une idée';

  @override
  String get bugReportTitle => 'Signaler un bug ou proposer une idée';

  @override
  String get bugReportIntroHeader => 'Comment ça fonctionne';

  @override
  String get bugReportStepRecord => 'Lancer l\'enregistrement';

  @override
  String get bugReportStepReproduce => 'Reproduire le problème';

  @override
  String get bugReportStepFinish => 'Revenir et terminer';

  @override
  String get bugReportLogScreens =>
      'Les écrans que vous ouvrez et les boutons sur lesquels vous appuyez';

  @override
  String get bugReportLogRequests => 'Les requêtes au serveur et ses réponses';

  @override
  String get bugReportLogService =>
      'La vue en direct, et les notifications envoyées ou ignorées par le service d\'arrière-plan';

  @override
  String get bugReportLogErrors =>
      'Les erreurs et les plantages, y compris ceux que vous ne voyez jamais';

  @override
  String get bugReportLogSetup =>
      'Version de l\'application et du serveur, votre téléphone, votre langue';

  @override
  String get bugReportLogNoKey => 'Votre clé API ou mot de passe';

  @override
  String get bugReportLogNoTyping => 'Le texte que vous saisissez';

  @override
  String get bugReportLogNoAddress =>
      'L\'adresse de votre serveur — uniquement http ou https, nom ou IP, et le port';

  @override
  String get bugReportLogNoData =>
      'Les numéros de série de l\'imprimante, ou les noms de vos fichiers, modèles et bobines';

  @override
  String get bugReportReviewFirst =>
      'Vous pouvez tout relire avant que cela ne quitte le téléphone.';

  @override
  String get bugReportPrivacyHeader => 'Ce qui figure dans le journal';

  @override
  String get bugReportStart => 'Lancer l\'enregistrement';

  @override
  String get bugReportRecordingHeader => 'Enregistrement';

  @override
  String get bugReportRecordingBody =>
      'Revenez dans l\'application et reproduisez le problème. La barre d\'enregistrement reste visible — faites-la glisser sur le côté ou réduisez-la si elle vous gêne, et utilisez-la pour marquer l\'instant du problème et terminer.';

  @override
  String get bugReportMark => 'Marquer ce moment';

  @override
  String get bugReportMarked => 'Moment marqué';

  @override
  String get bugReportStop => 'Terminer l\'enregistrement';

  @override
  String get bugReportStopShort => 'Terminer';

  @override
  String get bugReportBannerLabel => 'Enregistrement';

  @override
  String get bugReportBarMove => 'Déplacer la barre d\'enregistrement';

  @override
  String get bugReportBarCollapse => 'Réduire la barre d\'enregistrement';

  @override
  String get bugReportBarExpand => 'Développer la barre d\'enregistrement';

  @override
  String get bugReportReviewHeader => 'Vérifier avant d\'envoyer';

  @override
  String get bugReportReviewBody =>
      'Voici tout ce qui a été enregistré. Relisez-le attentivement — vous pouvez choisir ci-dessous de le conserver sur le téléphone ou de le publier sous forme de ticket public.';

  @override
  String bugReportSummary(int records, int errors, int warnings) {
    return '$records entrées · $errors erreurs · $warnings avertissements';
  }

  @override
  String bugReportMarkers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count moments marqués',
      one: '1 moment marqué',
    );
    return '$_temp0';
  }

  @override
  String get bugReportTruncated =>
      'La session était longue — les entrées les plus anciennes ont été supprimées.';

  @override
  String get bugReportEmpty => 'Rien n\'a été enregistré.';

  @override
  String get bugReportShowRaw => 'Afficher le journal brut';

  @override
  String get bugReportHideRaw => 'Masquer le journal brut';

  @override
  String bugReportRawClipped(int kb) {
    return 'Les $kb premiers ko ne sont pas affichés ici. Le fichier enregistré contiendra toute la session.';
  }

  @override
  String get bugReportSave => 'Enregistrer dans un fichier';

  @override
  String get bugReportSaveShort => 'Enregistrer';

  @override
  String get bugReportSaved => 'Journal enregistré dans le fichier';

  @override
  String get bugReportSaveFailed => 'Le journal n\'a pas pu être enregistré.';

  @override
  String get bugReportDiscard => 'Abandonner';

  @override
  String get bugReportDiscardQuestion => 'Abandonner cet enregistrement ?';

  @override
  String get bugReportDiscardBody => 'Le journal sera supprimé du téléphone.';

  @override
  String get bugReportDiscardBodyQueued =>
      'Le journal sera supprimé du téléphone et le signalement en attente sera annulé.';

  @override
  String bugReportLimit(int minutes) {
    return 'Un enregistrement s\'arrête automatiquement au bout de $minutes minutes.';
  }

  @override
  String bugReportLimitReached(int minutes) {
    return 'Enregistrement terminé — la limite de $minutes minutes a été atteinte.';
  }

  @override
  String bugReportSizeLimitReached(int megabytes) {
    return 'Enregistrement terminé — le journal a atteint sa limite de $megabytes Mo.';
  }

  @override
  String get bugReportShow => 'Afficher';

  @override
  String get bugReportRecoveredHeader =>
      'Un enregistrement a survécu à un plantage';

  @override
  String get bugReportRecoveredBody =>
      'L\'application s\'est fermée pendant l\'enregistrement. Ce qui a été enregistré est toujours sur le téléphone — examinez-le ou supprimez-le.';

  @override
  String get bugReportDestinationHeader => 'Que devient ce journal';

  @override
  String get bugReportDestinationFile => 'Enregistrer dans un fichier';

  @override
  String get bugReportDestinationIssue => 'Signaler sur GitHub';

  @override
  String get bugReportDestinationFileBody =>
      'Le journal est enregistré à l\'emplacement choisi et reste sur votre téléphone. Vous décidez de le partager ou non.';

  @override
  String get bugReportDestinationIssueBody =>
      'Le journal et votre description sont publiés sous la forme d\'un ticket public sur GitHub, où tout le monde peut les lire et où ils resteront définitivement. Consultez d\'abord le journal ci-dessous.';

  @override
  String get bugReportDescriptionLabel => 'Quel est le problème ?';

  @override
  String get bugReportDescriptionHint =>
      'Ce que vous faisiez, ce que vous attendiez et ce qui s\'est passé à la place.';

  @override
  String get bugReportDescriptionRequired =>
      'Décrivez le problème — un journal sans description est presque inutilisable.';

  @override
  String get bugReportSend => 'Signaler';

  @override
  String get bugReportSending => 'Envoi en cours…';

  @override
  String bugReportSendWaiting(String clock) {
    return 'Envoi dans $clock';
  }

  @override
  String get bugReportSendWaitingBody =>
      'Le relais espace les signalements. Vous pouvez quitter cet écran — l\'envoi se fera automatiquement.';

  @override
  String get bugReportSent => 'Signalement envoyé';

  @override
  String get bugReportSentBody =>
      'Merci. Le ticket est ouvert et le journal y est joint.';

  @override
  String get bugReportOpenIssue => 'Ouvrir le ticket';

  @override
  String get bugReportDone => 'Terminé';

  @override
  String get bugReportSendFailedNotYet =>
      'Le relais n\'accepte pas de signalements pour le moment. Réessayez plus tard ou enregistrez le journal dans un fichier.';

  @override
  String get bugReportSendFailedRefused =>
      'Le relais a refusé ce signalement. Enregistrez le journal dans un fichier et joignez-le vous-même.';

  @override
  String get bugReportSendFailedDuplicate => 'Ce problème a déjà été signalé.';

  @override
  String get bugReportSendFailedUnreachable =>
      'Impossible de joindre le relais. Vérifiez votre connexion ou enregistrez le journal dans un fichier.';

  @override
  String get bugReportSendFailedRejected =>
      'Le relais a rejeté ce signalement. Enregistrez le journal dans un fichier et joignez-le vous-même.';

  @override
  String get bugReportSendFailedDemo =>
      'Le mode démo ne publie pas de signalements. Enregistrez plutôt le journal dans un fichier.';

  @override
  String get bugReportKindQuestion => 'Que souhaitez-vous signaler ?';

  @override
  String get bugReportKindBug => 'Bug';

  @override
  String get bugReportKindChange => 'Modification';

  @override
  String get bugReportKindFeature => 'Nouvelle fonctionnalité';

  @override
  String get bugReportChangeHeader => 'Demander une modification';

  @override
  String get bugReportChangeBody =>
      'Quelque chose fonctionne, mais pas comme il le devrait.';

  @override
  String get bugReportChangeLabel => 'Que faudrait-il modifier ?';

  @override
  String get bugReportChangeHint =>
      'Ce que l\'application fait actuellement, et ce qu\'elle devrait faire à la place.';

  @override
  String get bugReportFeatureHeader => 'Proposer une fonctionnalité';

  @override
  String get bugReportFeatureBody =>
      'Quelque chose que l\'application ne sait pas encore faire.';

  @override
  String get bugReportFeatureLabel => 'Que manque-t-il ?';

  @override
  String get bugReportFeatureHint =>
      'Ce que vous souhaitez faire, et pourquoi l\'application ne vous le permet pas.';

  @override
  String get bugReportRequestPrivacyHeader => 'Ce qui est envoyé';

  @override
  String get bugReportRequestWhatYouWrite => 'Ce que vous écrivez';

  @override
  String get bugReportRequestVersions =>
      'Version de l\'application et du serveur';

  @override
  String get bugReportRequestNoLog => 'Aucun journal, aucun enregistrement';

  @override
  String get bugReportRequestNoData =>
      'Rien sur vos imprimantes ni votre téléphone';

  @override
  String get bugReportRequestPublic =>
      'La demande devient un ticket public sur GitHub — tout le monde peut la lire, et elle restera définitivement.';

  @override
  String get bugReportRequestRequired =>
      'Précisez votre demande — une requête vide ne peut pas être traitée.';

  @override
  String get bugReportRequestSentBody => 'Merci. Le ticket est ouvert.';

  @override
  String get bugReportCancelSend => 'Annuler l\'envoi';

  @override
  String get bugReportRequestFailedNotYet =>
      'Le relais n\'accepte pas de demandes pour l\'instant. Réessayez plus tard.';

  @override
  String get bugReportRequestFailedRefused =>
      'Le relais a refusé cette demande. Vous pouvez ouvrir le ticket vous-même sur GitHub.';

  @override
  String get bugReportRequestFailedUnreachable =>
      'Impossible de joindre le relais. Vérifiez votre connexion et réessayez.';

  @override
  String get bugReportRequestFailedDemo =>
      'Le mode démo ne publie pas de signalements.';

  @override
  String get bugReportRequestNotPrepared =>
      'L\'application n\'a pas pu préparer le signalement. Rien n\'a été envoyé — réessayez.';

  @override
  String get usersTitle => 'Utilisateurs';

  @override
  String get usersMenu => 'Utilisateurs';

  @override
  String get usersEmpty => 'Aucun compte sur ce serveur.';

  @override
  String get usersYou => 'vous';

  @override
  String get usersRoleAdmin => 'Administrateur';

  @override
  String get usersRoleUser => 'Utilisateur';

  @override
  String get usersInactive => 'Inactif';

  @override
  String get usersEmailLabel => 'E-mail';

  @override
  String get usersEmailNone => 'aucun';

  @override
  String get usersGroupsLabel => 'Groupes';

  @override
  String get usersNoGroups => 'aucun';

  @override
  String get usersPermissionsLabel => 'Permissions';

  @override
  String usersPermissionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count permissions',
      one: '1 permission',
      zero: 'aucune',
    );
    return '$_temp0';
  }

  @override
  String get usersPermissionsUnknown => 'non communiqué par le serveur';

  @override
  String get usersAuthSourceLabel => 'Connexion';

  @override
  String get usersAuthSourceLocal => 'Compte local';

  @override
  String get usersCreatedLabel => 'Créé';

  @override
  String get usersOwnedTitle => 'CRÉÉ PAR CE COMPTE';

  @override
  String get usersOwnedArchives => 'Impressions';

  @override
  String get usersOwnedQueue => 'File d\'attente';

  @override
  String get usersOwnedLibrary => 'Fichiers';

  @override
  String get usersOwnedFailed =>
      'Impossible de lire le contenu appartenant à ce compte.';

  @override
  String get usersCreate => 'Ajouter un compte';

  @override
  String get usersCreateTitle => 'Nouveau compte';

  @override
  String get usersEdit => 'Modifier';

  @override
  String get usersEditTitle => 'Modifier le compte';

  @override
  String get usersDelete => 'Supprimer';

  @override
  String get usersSave => 'Enregistrer';

  @override
  String get usersSaved => 'Compte enregistré';

  @override
  String get usersSaveFailed => 'Impossible d\'enregistrer le compte.';

  @override
  String get usersDeleted => 'Compte supprimé';

  @override
  String get usersFieldUsername => 'Nom d\'utilisateur';

  @override
  String get usersFieldEmail => 'E-mail (facultatif)';

  @override
  String get usersFieldEmailRequired => 'E-mail';

  @override
  String get usersFieldPassword => 'Mot de passe';

  @override
  String get usersFieldNewPassword => 'Nouveau mot de passe';

  @override
  String get usersFieldConfirmPassword => 'Répéter le mot de passe';

  @override
  String get usersFieldActive => 'Actif';

  @override
  String get usersFieldGroups => 'Groupes';

  @override
  String get usersGroupSystem => '(intégré)';

  @override
  String get usersFieldRequired => 'Veuillez remplir ce champ';

  @override
  String get usersPasswordsDoNotMatch =>
      'Les deux mots de passe sont différents.';

  @override
  String get usersGroupsAdminHint =>
      'L\'appartenance au groupe Administrators est ce qui confère à un compte les droits d\'administrateur.';

  @override
  String get usersActiveHint => 'Un compte inactif ne peut pas se connecter.';

  @override
  String get usersEmailAdvancedHint =>
      'Ce serveur envoie le mot de passe par e-mail, il a donc besoin d\'une adresse.';

  @override
  String get usersPasswordMailed =>
      'Le serveur génère lui-même le mot de passe et l\'envoie à cette adresse. Personne, y compris vous, ne pourra le voir.';

  @override
  String get usersNoSmtpWarning =>
      'Aucun serveur de messagerie n\'est configuré, le message n\'arrivera donc pas — le compte serait créé avec un mot de passe que personne ne connaît.';

  @override
  String get usersLdapPasswordNote =>
      'Ce compte se connecte via l\'annuaire (LDAP). Son mot de passe y est géré et ne peut pas être défini ici.';

  @override
  String get usersPasswordKeepHint =>
      'Laisser vide pour conserver le mot de passe actuel.';

  @override
  String get usersPasswordRulesHint =>
      'Au moins 8 caractères, avec une majuscule, une minuscule, un chiffre et un symbole.';

  @override
  String get usersPasswordTooShort => 'Au moins 8 caractères.';

  @override
  String get usersPasswordNoUppercase => 'Ajoutez une majuscule.';

  @override
  String get usersPasswordNoLowercase => 'Ajoutez une minuscule.';

  @override
  String get usersPasswordNoDigit => 'Ajoutez un chiffre.';

  @override
  String get usersPasswordNoSpecial => 'Ajoutez un symbole.';

  @override
  String usersDeleteTitle(String username) {
    return 'Supprimer $username ?';
  }

  @override
  String get usersDeleteBody =>
      'Le compte, ses clés API et son état de connexion seront supprimés. Cette action est irréversible.';

  @override
  String usersDeleteOwnsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ce compte a créé $count éléments',
      one: 'Ce compte a créé 1 élément',
    );
    return '$_temp0';
  }

  @override
  String get usersDeleteItemsToo => 'Les supprimer aussi';

  @override
  String get usersDeleteItemsTooHint =>
      'Ses impressions, éléments en file d\'attente et fichiers seront supprimés avec le compte.';

  @override
  String get usersDeleteItemsKeepHint =>
      'Ses impressions, éléments en file d\'attente et fichiers seront conservés, sans propriétaire.';

  @override
  String get usersDeleteConfirm => 'Supprimer';

  @override
  String get usersErrLastAdmin =>
      'Il s\'agit du dernier administrateur — le serveur doit en conserver un.';

  @override
  String get usersErrLastAdminDelete =>
      'Le dernier administrateur ne peut pas être supprimé — le serveur se retrouverait sans personne pour le gérer.';

  @override
  String get usersErrLastAdminDeactivate =>
      'Le dernier administrateur ne peut pas être désactivé — le serveur se retrouverait sans personne pour le gérer.';

  @override
  String get usersErrLastAdminRole =>
      'Le dernier administrateur ne peut pas être rétrogradé — le serveur se retrouverait sans personne pour le gérer.';

  @override
  String get usersErrSelfDelete =>
      'Vous ne pouvez pas supprimer le compte avec lequel vous êtes connecté.';

  @override
  String get usersErrUsernameTaken => 'Ce nom d\'utilisateur est déjà pris.';

  @override
  String get usersErrEmailTaken =>
      'Cet e-mail est déjà associé à un autre compte.';

  @override
  String get usersErrLdapPassword =>
      'Le mot de passe d\'un compte d\'annuaire (LDAP) ne peut pas être défini ici.';

  @override
  String get usersErrEmailRequired =>
      'Ce serveur requiert une adresse e-mail pour un nouveau compte.';

  @override
  String get usersErrPasswordRequired =>
      'Ce serveur requiert un mot de passe pour un nouveau compte.';

  @override
  String get usersErrGroupsInvalid =>
      'L\'un des groupes n\'existe plus — rouvrez le formulaire.';

  @override
  String get groupsTitle => 'Groupes';

  @override
  String get groupsMenu => 'Groupes';

  @override
  String get groupsEmpty => 'Aucun groupe sur ce serveur.';

  @override
  String get groupsNoDescription => 'Aucune description';

  @override
  String get groupsSystemPill => 'Intégré';

  @override
  String get groupsSystemNote =>
      'Un groupe intégré ne peut pas être renommé et ses permissions sont fixes — seuls ses membres peuvent changer.';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comptes',
      one: '1 compte',
      zero: 'aucun compte',
    );
    return '$_temp0';
  }

  @override
  String groupsPermissionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count permissions',
      one: '1 permission',
      zero: 'aucune permission',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembersHeader => 'MEMBRES';

  @override
  String get groupsNoMembers => 'Personne ne fait partie de ce groupe.';

  @override
  String get groupsAddMember => 'Ajouter un membre';

  @override
  String groupsAddMemberTitle(String group) {
    return 'Ajouter à $group';
  }

  @override
  String get groupsEveryoneIsIn =>
      'Tous les comptes font déjà partie de ce groupe.';

  @override
  String get groupsRemoveMember => 'Retirer';

  @override
  String groupsRemoveMemberQuestion(String username, String group) {
    return 'Retirer $username de $group ?';
  }

  @override
  String get groupsRemoveMemberBody =>
      'Le compte est conservé et perd ce que ce groupe lui accordait.';

  @override
  String get groupsCreate => 'Nouveau groupe';

  @override
  String get groupsCreateTitle => 'Nouveau groupe';

  @override
  String get groupsEditTitle => 'Modifier le groupe';

  @override
  String get groupsDelete => 'Supprimer le groupe';

  @override
  String get groupsSaved => 'Groupe enregistré';

  @override
  String get groupsDeleted => 'Groupe supprimé';

  @override
  String groupsDeleteQuestion(String group) {
    return 'Supprimer $group ?';
  }

  @override
  String get groupsDeleteBody =>
      'Les permissions qu\'il accorde disparaîtront avec lui.';

  @override
  String groupsDeleteBodyWithMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count comptes en font partie et seront conservés — ils perdront simplement ce que ce groupe leur accordait.',
      one:
          '1 compte en fait partie et sera conservé — il perdra simplement ce que ce groupe lui accordait.',
    );
    return '$_temp0';
  }

  @override
  String get groupsFieldName => 'Nom';

  @override
  String get groupsFieldDescription => 'À quoi il sert';

  @override
  String get groupsSystemFormNote =>
      'Groupe intégré : son nom et ses permissions sont fixés par le serveur. Seule la description peut être modifiée ici.';

  @override
  String get groupsPermissionsHeader => 'PERMISSIONS';

  @override
  String groupsPermissionsSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnées',
      one: '$count sélectionnée',
    );
    return '$_temp0';
  }

  @override
  String get groupsAdvancedPermissions => 'Administration du serveur';

  @override
  String get groupsAdvancedHint =>
      'Utilisateurs, clés API, paramètres, sauvegardes — tout ce pour quoi l\'application n\'a pas d\'écran dédié.';

  @override
  String get serverSettingsMenu => 'Paramètres du serveur';

  @override
  String get serverSettingsTitle => 'Paramètres du serveur';

  @override
  String get serverSettingsQueueSubtitle =>
      'Planification, préchauffage et maintien du plateau chaud entre les impressions';

  @override
  String get serverSettingsMaintenanceSubtitle =>
      'Types de tâches et intervalles par imprimante';

  @override
  String get serverSettingsAdminSubtitle => 'Comptes, groupes et clés API';

  @override
  String get serverSettingsCloudSubtitle =>
      'Le compte Bambu avec lequel le serveur effectue les téléchargements';

  @override
  String get queueSettingsTitle => 'File d\'attente et préchauffage';

  @override
  String get queueSettingsReadOnlyApiKey =>
      'Une clé API ne peut jamais modifier les paramètres du serveur. Connectez-vous avec un compte pour les changer.';

  @override
  String get queueSettingsReadOnlyPermission =>
      'Votre compte peut consulter ces paramètres, mais pas les modifier.';

  @override
  String get queueSettingsUnavailable =>
      'Ce serveur ne signale aucun de ces paramètres. Soit sa version est antérieure à leur prise en charge, soit ils n\'ont pas pu être lus — glissez vers le bas pour réessayer.';

  @override
  String get queueSettingsQueueHeader => 'File d\'attente';

  @override
  String get queueSettingsPlateClearTitle =>
      'Confirmer que le plateau est vide';

  @override
  String get queueSettingsPlateClearDesc =>
      'Après une impression, l\'imprimante attend que quelqu\'un confirme que le plateau est vide.';

  @override
  String get queueSettingsShortestFirstTitle =>
      'Travail le plus court en premier';

  @override
  String get queueSettingsShortestFirstDesc =>
      'Prendre le travail en attente le plus court plutôt que celui qui attend depuis le plus longtemps.';

  @override
  String queueSettingsMaxUploads(int count) {
    return 'Fichiers téléversés simultanément : $count';
  }

  @override
  String get queueSettingsPreheatHeader => 'Préchauffage';

  @override
  String get queueSettingsPreheatTitle => 'Préchauffer avant un travail';

  @override
  String get queueSettingsPreheatDesc =>
      'Chauffe la chambre avant l\'envoi du fichier. Un travail en file d\'attente peut l\'outrepasser individuellement.';

  @override
  String queueSettingsPreheatMaxWait(String duration) {
    return 'Limite d\'attente de la chambre : $duration';
  }

  @override
  String queueSettingsPreheatSoak(String duration) {
    return 'Stabilisation après atteinte de la température : $duration';
  }

  @override
  String get queueSettingsNoSoak => 'aucune stabilisation';

  @override
  String get queueSettingsPreheatOffNote =>
      'Le préchauffage est désactivé, les paramètres ci-dessous n\'ont donc aucun effet.';

  @override
  String get queueSettingsKeepWarmHeader => 'Maintien au chaud';

  @override
  String get queueSettingsKeepWarmTitle =>
      'Maintenir le plateau chaud entre les impressions';

  @override
  String get queueSettingsKeepWarmDesc =>
      'Tant que personne ne retire l\'impression terminée, le plateau reste chaud afin que le prochain travail nécessitant une chambre chaude ne démarre pas à froid. Ignoré pour le PLA et le PETG.';

  @override
  String queueSettingsKeepWarmTemp(int temp) {
    return 'Température du plateau pour chauffer la chambre : $temp °C';
  }

  @override
  String queueSettingsKeepWarmMax(String duration) {
    return 'Durée maximale de maintien du plateau : $duration';
  }

  @override
  String get queueSettingsMaxUploadsDesc =>
      'Avant qu\'un travail en file d\'attente ne démarre, son fichier est envoyé à l\'imprimante par FTP, ce qui peut prendre des minutes. Cela définit le nombre de transferts simultanés — cela n\'a d\'effet qu\'avec plusieurs imprimantes.';

  @override
  String get queueSettingsPreheatMaxWaitDesc =>
      'Une X1C ou P2S n\'a pas de chauffage de chambre — la chambre chauffe grâce au plateau, ce qui peut prendre 15 à 30 minutes. Passé ce délai, la file d\'attente cesse d\'attendre et passe à la stabilisation.';

  @override
  String get queueSettingsPreheatSoakDesc =>
      'Durée de maintien à température une fois celle-ci atteinte par la chambre, ou après expiration du délai d\'attente ci-dessus. Zéro pour ignorer.';

  @override
  String get queueSettingsKeepWarmTempDesc =>
      '90 maintient la chaleur de la chambre sur une imprimante fermée et déclenche les chauffages de chambre d\'appoint, qui s\'activent généralement lorsque le plateau est à 80. Une température de plateau plus élevée définie dans le fichier prévaut toujours.';

  @override
  String get queueSettingsKeepWarmMaxDesc =>
      'Réglez cette valeur en fonction du temps qu\'il vous faut raisonnablement pour vous rendre à l\'imprimante. Une durée trop courte obligera seulement l\'impression suivante à une stabilisation à froid ; en l\'absence de limite, un plateau non dégagé resterait chaud indéfiniment.';

  @override
  String get queueSettingsKeepWarmOffNote =>
      'Le maintien au chaud est désactivé. La température de plateau ci-dessus s\'applique toujours au préchauffage.';

  @override
  String get adminMenu => 'Administration';

  @override
  String get adminTitle => 'Administration';

  @override
  String adminSignedInAs(String username) {
    return 'Connecté en tant que $username';
  }

  @override
  String get adminUsersSubtitle =>
      'Qui dispose d\'un compte et ce que chacun peut faire';

  @override
  String get adminGroupsSubtitle =>
      'Ensembles de permissions et utilisateurs qui les détiennent';

  @override
  String get adminApiKeysSubtitle =>
      'Identifiants pour tout ce qui n\'est pas cette application';

  @override
  String get apiKeysTitle => 'Clés API';

  @override
  String get apiKeysEmpty => 'Aucune clé n\'a été générée.';

  @override
  String get apiKeysCreate => 'Nouvelle clé';

  @override
  String get apiKeysCreateTitle => 'Nouvelle clé API';

  @override
  String get apiKeysEditTitle => 'Modifier la clé';

  @override
  String get apiKeysSaved => 'Clé enregistrée';

  @override
  String get apiKeysRevoke => 'Révoquer';

  @override
  String get apiKeysRevoked => 'Clé révoquée';

  @override
  String apiKeysRevokeQuestion(String name) {
    return 'Révoquer $name ?';
  }

  @override
  String get apiKeysRevokeBody =>
      'Tout ce qui utilise cette clé cessera immédiatement de fonctionner. Cette action est irréversible — une nouvelle clé devra être générée.';

  @override
  String apiKeysLastUsed(String date) {
    return 'dernière utilisation le $date';
  }

  @override
  String get apiKeysNeverUsed => 'jamais utilisée';

  @override
  String get apiKeysDisabled => 'Désactivée';

  @override
  String get apiKeysExpired => 'Expirée';

  @override
  String apiKeysExpiresOn(String date) {
    return 'jusqu\'au $date';
  }

  @override
  String apiKeysPrinterLimited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imprimantes',
      one: '1 imprimante',
    );
    return '$_temp0';
  }

  @override
  String get apiKeysLegacy => 'Sans propriétaire';

  @override
  String get apiKeysFieldName => 'Nom';

  @override
  String get apiKeysFieldNameHint =>
      'Ce qui utilise cette clé — « Home Assistant », « SpoolBuddy ».';

  @override
  String get apiKeysFieldEnabled => 'Active';

  @override
  String get apiKeysFieldEnabledHint =>
      'La désactiver empêche la clé de fonctionner sans la supprimer.';

  @override
  String get apiKeysScopesHeader => 'CE QU\'ELLE PEUT FAIRE';

  @override
  String get apiKeysScopesHint =>
      'Une clé ne peut jamais gérer les comptes, les groupes, les clés ou les paramètres — le serveur refuse ces actions à toutes les clés.';

  @override
  String get apiKeysPrintersHeader => 'IMPRIMANTES';

  @override
  String get apiKeysAllPrinters => 'Toutes les imprimantes';

  @override
  String get apiKeysAllPrintersHint =>
      'Désactivé : choisissez les imprimantes auxquelles cette clé peut accéder.';

  @override
  String get apiKeysExpiryHeader => 'EXPIRATION';

  @override
  String get apiKeysNoExpiry => 'N\'expire jamais';

  @override
  String get apiKeysExpiryHint =>
      'Appuyez pour choisir une date après laquelle la clé cessera de fonctionner.';

  @override
  String get apiKeysExpiryClear => 'Aucune expiration';

  @override
  String get apiKeysCreatedTitle => 'Clé créée';

  @override
  String get apiKeysCreatedWarning =>
      'Copiez-la maintenant. Le serveur ne conserve qu\'un hash — c\'est la dernière fois qu\'elle pourra être affichée.';

  @override
  String get apiKeysCopy => 'Copier';

  @override
  String get apiKeysCopied => 'Clé copiée';

  @override
  String get apiKeysCreatedDone => 'Terminé';

  @override
  String get apiKeyScopeRead => 'Lecture de l\'état';

  @override
  String get apiKeyScopeReadHint =>
      'Imprimantes, file d\'attente, archives, bibliothèque, statistiques — lecture seule.';

  @override
  String get apiKeyScopeQueue => 'File d\'attente';

  @override
  String get apiKeyScopeControl => 'Contrôler les imprimantes';

  @override
  String get apiKeyScopeControlHint =>
      'Pause, arrêt, températures, AMS, prises connectées.';

  @override
  String get apiKeyScopeLibrary => 'Fichiers';

  @override
  String get apiKeyScopeInventory => 'Filaments';

  @override
  String get apiKeyScopeMaintenance => 'Maintenance';

  @override
  String get apiKeyScopeArchives => 'Archives';

  @override
  String get apiKeyScopeProjects => 'Projets';

  @override
  String get apiKeyScopeCloud => 'Bambu Cloud';

  @override
  String get apiKeyScopeCloudHint =>
      'Consulte le cloud au nom du compte qui a créé la clé. Nécessite que l\'authentification soit activée côté serveur.';

  @override
  String get apiKeyScopeEnergy => 'Prix de l\'énergie';

  @override
  String get apiKeyScopeEnergyHint =>
      'La seule valeur de paramètre qu\'une clé peut modifier — pour une tarification dynamique.';

  @override
  String get printLogTitle => 'Historique des impressions';

  @override
  String get printLogSearchHint => 'Rechercher des impressions';

  @override
  String get printLogEmpty => 'Aucune impression enregistrée pour le moment';

  @override
  String get printLogNoMatches =>
      'Aucune impression ne correspond à vos filtres';

  @override
  String get printLogLoadFailed =>
      'Impossible de charger l\'historique des impressions';

  @override
  String get printLogFilters => 'Filtres';

  @override
  String get printLogFilterPrinter => 'Imprimante';

  @override
  String get printLogFilterUser => 'Utilisateur';

  @override
  String get printLogFilterStatus => 'Statut';

  @override
  String get printLogFilterDates => 'Plage de dates';

  @override
  String get printLogAnyPrinter => 'Toutes les imprimantes';

  @override
  String get printLogAnyUser => 'Tous les utilisateurs';

  @override
  String get printLogAnyStatus => 'Tous les statuts';

  @override
  String get printLogNoUser => 'Aucun utilisateur';

  @override
  String get printLogOrphan => 'Archive supprimée';

  @override
  String printLogShowing(int loaded, int total) {
    return '$loaded sur $total';
  }

  @override
  String get printLogLoadMore => 'Charger plus';

  @override
  String get printLogSort => 'Trier par';

  @override
  String get printLogSortDate => 'Date';

  @override
  String get printLogSortName => 'Nom';

  @override
  String get printLogSortPrinter => 'Imprimante';

  @override
  String get printLogSortUser => 'Utilisateur';

  @override
  String get printLogSortStatus => 'Statut';

  @override
  String get printLogSortDuration => 'Durée';

  @override
  String get printLogSortFilament => 'Filament utilisé';

  @override
  String get printLogSortCost => 'Coût';

  @override
  String get printLogSortEnergy => 'Énergie';

  @override
  String get printLogSortDirection => 'Ordre';

  @override
  String get printLogSortDescending => 'Décroissant';

  @override
  String get printLogSortAscending => 'Croissant';

  @override
  String get printLogStatusCompleted => 'Terminée';

  @override
  String get printLogStatusFailed => 'Échouée';

  @override
  String get printLogStatusStopped => 'Arrêtée';

  @override
  String get printLogStatusCancelled => 'Annulée';

  @override
  String get printLogStatusSkipped => 'Ignorée';

  @override
  String get printLogStatusAborted => 'Interrompue';

  @override
  String printLogEnergy(String value) {
    return '$value kWh';
  }

  @override
  String get printLogClassifyTitle => 'Classifier cette impression';

  @override
  String get printLogDetailStarted => 'Début';

  @override
  String get printLogDetailFinished => 'Fin';

  @override
  String get printLogDetailDuration => 'Durée';

  @override
  String get printLogDetailFilament => 'Filament';

  @override
  String get printLogDetailCost => 'Coût';

  @override
  String get printLogDetailEnergy => 'Énergie';

  @override
  String get printLogFailureCause => 'Cause de l\'échec';

  @override
  String get printLogNoClassification => 'Non classée';

  @override
  String get printLogStatusLabel => 'Statut';

  @override
  String get printLogCountsAsFailure =>
      'Comptabilisé comme un échec — cette impression et sa cause apparaîtront dans l\'analyse des échecs.';

  @override
  String get printLogNotCountedAsFailure =>
      'Non comptabilisé comme un échec, la cause est donc exclue de l\'analyse des échecs.';

  @override
  String printLogStatusOneWay(String status) {
    return 'Ce serveur ne peut pas rétablir « $status ». Si vous le modifiez, il sera définitivement perdu.';
  }

  @override
  String get printLogSave => 'Enregistrer';

  @override
  String get printLogSaveFailed =>
      'Impossible d\'enregistrer la classification';

  @override
  String get printLogDelete => 'Supprimer l\'impression';

  @override
  String get printLogDeleteTitle => 'Supprimer cette impression ?';

  @override
  String get printLogDeleteBody =>
      'Elle sera retirée de l\'historique, et son filament, son coût et sa durée quitteront les statistiques. L\'archive vers laquelle elle pointe sera conservée.';

  @override
  String get printLogDeleteFailed => 'Impossible de supprimer l\'impression';

  @override
  String get printLogClear => 'Effacer l\'historique des impressions';

  @override
  String get printLogClearTitle =>
      'Effacer tout l\'historique des impressions ?';

  @override
  String printLogClearBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Toutes les $count impressions seront supprimées',
      one: 'L\'unique impression de l\'historique sera supprimée',
    );
    return '$_temp0 — celles de tous les utilisateurs, pas seulement les vôtres — et leur filament, leur coût et leur durée seront retirés des statistiques. Les archives et la file d\'attente ne sont pas affectées. Cette action est irréversible.';
  }

  @override
  String get printLogClearBodyFiltered =>
      'Toutes les impressions de l\'historique seront supprimées — celles de tous les utilisateurs, pas seulement les vôtres, et le filtre appliqué ne les limite pas — et leur filament, leur coût et leur durée seront retirés des statistiques. Les archives et la file d\'attente ne sont pas affectées. Cette action est irréversible.';

  @override
  String printLogCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impressions supprimées',
      one: '$count impression supprimée',
    );
    return '$_temp0';
  }

  @override
  String get printLogClearFailed =>
      'Impossible d\'effacer l\'historique des impressions';

  @override
  String get failureReasonAdhesion => 'Défaut d\'adhérence';

  @override
  String get failureReasonSpaghetti => 'Spaghetti / impression décollée';

  @override
  String get failureReasonLayerShift => 'Décalage de couches';

  @override
  String get failureReasonCloggedNozzle => 'Buse bouchée';

  @override
  String get failureReasonFilamentRunout => 'Fin de filament';

  @override
  String get failureReasonWarping => 'Déformation (warping)';

  @override
  String get failureReasonStringing => 'Fils (stringing)';

  @override
  String get failureReasonUnderExtrusion => 'Sous-extrusion';

  @override
  String get failureReasonPowerFailure => 'Coupure de courant';

  @override
  String get failureReasonUserCancelled => 'Annulée par l\'utilisateur';

  @override
  String get failureReasonOther => 'Autre';

  @override
  String get failureReasonUnknown => 'Inconnu';

  @override
  String get appSettingsMenu => 'Paramètres de l\'application';

  @override
  String get appSettingsTitle => 'Paramètres de l\'application';

  @override
  String get appSettingsNotificationsSubtitle =>
      'Quels événements envoient une notification, et à partir de quels seuils';

  @override
  String get collapsePrinterCardsTitle => 'Cartes d\'imprimante réduites';

  @override
  String get collapsePrinterCardsDesc =>
      'Les cartes s\'ouvrent en n\'affichant que le nom, l\'état et la progression de l\'impression. Chaque carte peut toujours être développée.';

  @override
  String get printerCardExpand => 'Développer la carte';

  @override
  String get printerCardCollapse => 'Réduire la carte';
}
