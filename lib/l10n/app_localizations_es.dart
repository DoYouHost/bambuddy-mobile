// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get printersTitle => 'Impresoras';

  @override
  String get changeServer => 'Cambiar de servidor';

  @override
  String get sessionExpired => 'Sesión caducada — inicia sesión de nuevo';

  @override
  String get signInRequiredTitle => 'Iniciar sesión de nuevo';

  @override
  String get signInRequiredBody =>
      'El servidor rechazó tu contraseña guardada, por lo que la aplicación dejó de intentarlo — los intentos repetidos pueden bloquear la cuenta. Inicia sesión de nuevo y usa una nueva contraseña si se ha cambiado.';

  @override
  String get signInRequiredAction => 'Iniciar sesión';

  @override
  String get signInRequiredTwoFactorBody =>
      'Tu cuenta ahora solicita un segundo factor y la aplicación no puede proporcionarlo en segundo plano — por lo que dejó de iniciar sesión automáticamente. Inicia sesión de nuevo e introduce el código.';

  @override
  String get later => 'Más tarde';

  @override
  String get serverUnreachableStale =>
      'Servidor inaccesible — los datos pueden estar desactualizados';

  @override
  String get wsReconnecting =>
      'Sin conexión en tiempo real — actualizando cada 5 s';

  @override
  String get connLive => 'En directo';

  @override
  String get connLiveTooltip =>
      'Actualizaciones en tiempo real a través de WebSocket';

  @override
  String get connPolling => 'Sondeo';

  @override
  String get connPollingTooltip =>
      'Sin enlace en tiempo real — actualizando cada 5 s (REST)';

  @override
  String get connectFailed => 'No se pudo conectar al servidor';

  @override
  String get filePickerFailed => 'No se pudo abrir el selector de archivos';

  @override
  String get retry => 'Reintentar';

  @override
  String get back => 'Atrás';

  @override
  String get searchPrinters => 'Buscar impresoras…';

  @override
  String get noPrinters => 'No hay impresoras — añádelas en el servidor';

  @override
  String noSearchResults(String query) {
    return 'No hay resultados para “$query”';
  }

  @override
  String get noPrintersMatchFilters =>
      'Ninguna impresora coincide con los filtros actuales';

  @override
  String get dashboardFilters => 'Filtros';

  @override
  String get filterStatus => 'Estado';

  @override
  String get filtersClear => 'Borrar';

  @override
  String get hideOffline => 'Ocultar desconectadas';

  @override
  String get statusAll => 'Todas';

  @override
  String get statusPrinting => 'Imprimiendo';

  @override
  String get statusIdle => 'Inactiva';

  @override
  String get statusPaused => 'En pausa';

  @override
  String get statusFinished => 'Finalizada';

  @override
  String get statusErrorFilter => 'Error';

  @override
  String get statusOfflineFilter => 'Desconectada';

  @override
  String get addPrinterTitle => 'Añadir impresora';

  @override
  String get addPrinterName => 'Nombre';

  @override
  String get addPrinterIp => 'Dirección IP';

  @override
  String get addPrinterSerial => 'Número de serie';

  @override
  String get addPrinterAccessCode => 'Código de acceso';

  @override
  String get addPrinterModel => 'Modelo';

  @override
  String get addPrinterModelOptional => 'Opcional';

  @override
  String get addPrinterModelNone => 'Sin definir';

  @override
  String get addPrinterLocation => 'Ubicación';

  @override
  String get addPrinterLocationOptional => 'Opcional';

  @override
  String get addPrinterSubmit => 'Añadir impresora';

  @override
  String get addPrinterConnectionNote =>
      'El servidor verifica la conexión antes de guardar; si la IP o el código de acceso son incorrectos, se notificará y no se creará nada.';

  @override
  String get addPrinterRequiredField => 'Obligatorio';

  @override
  String get addPrinterSuccess => 'Impresora añadida';

  @override
  String get addPrinterErrConnection =>
      'No se pudo conectar con la impresora. Comprueba la dirección IP, el número de serie y el código de acceso, y asegúrate de que el modo solo LAN esté activado.';

  @override
  String get addPrinterErrDuplicate =>
      'Ya existe una impresora con este número de serie';

  @override
  String get addPrinterErrForbidden =>
      'No tienes permiso para añadir impresoras';

  @override
  String get addPrinterErrGeneric =>
      'No se pudo añadir la impresora. Inténtalo de nuevo.';

  @override
  String get addPrinterAutoArchive =>
      'Archivar automáticamente las impresiones completadas';

  @override
  String get addPrinterScanTitle => 'Buscar impresoras en la red';

  @override
  String get addPrinterSubnet => 'Subred a escanear';

  @override
  String get addPrinterScanButton => 'Escanear subred en busca de impresoras';

  @override
  String get addPrinterDiscoverNetwork => 'Detectar impresoras en la red';

  @override
  String addPrinterScanning(int scanned, int total) {
    return 'Escaneando… $scanned/$total';
  }

  @override
  String get addPrinterScanningPlain => 'Escaneando…';

  @override
  String get addPrinterScanNoResults => 'No se encontraron impresoras';

  @override
  String get addPrinterScanError => 'Error en el escaneo. Inténtalo de nuevo.';

  @override
  String get addPrinterSubnetCustomOption => 'Subred personalizada…';

  @override
  String get addPrinterSubnetCustomLabel => 'Subred personalizada (CIDR)';

  @override
  String get addPrinterSubnetDockerNote =>
      'Docker detectado. Introduce la subred de tu impresora en notación CIDR. Requiere network_mode: host en docker-compose.yml.';

  @override
  String get addPrinterSubnetCustomNote =>
      'Usa una subred personalizada si tu impresora está en una red diferente a la del servidor. Los puertos FTP (990) y MQTT (8883) deben ser accesibles a través de los límites de enrutamiento.';

  @override
  String get addPrinterDiagnostic => 'Ejecutar diagnóstico';

  @override
  String get addPrinterDiagnosticRunning => 'Ejecutando diagnóstico…';

  @override
  String get addPrinterDiagnosticError =>
      'Error en el diagnóstico. Inténtalo de nuevo.';

  @override
  String get diagOverallOk => 'Todas las comprobaciones superadas';

  @override
  String get diagOverallWarnings => 'Completado con advertencias';

  @override
  String get diagOverallProblems => 'Problemas detectados';

  @override
  String get diagCheckPortMqtt => 'Puerto MQTT (8883)';

  @override
  String get diagCheckPortFtps => 'Puerto FTPS (990)';

  @override
  String get diagCheckPortRtsps => 'Puerto de la cámara (322)';

  @override
  String get diagCheckNetworkMode => 'Modo de red';

  @override
  String get diagCheckSubnet => 'Accesibilidad de la subred';

  @override
  String get diagCheckMqttAuth => 'Credenciales MQTT';

  @override
  String get diagCheckDeveloperMode => 'Modo desarrollador / LAN';

  @override
  String get changeServerQuestion => '¿Cambiar de servidor?';

  @override
  String get changeServerWarning =>
      'Se eliminarán el perfil y las credenciales guardadas.';

  @override
  String get cancel => 'Cancelar';

  @override
  String get clear => 'Borrar';

  @override
  String get change => 'Cambiar';

  @override
  String get noActivePrints => 'No hay impresiones activas';

  @override
  String printingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imprimiendo',
      one: '$count imprimiendo',
    );
    return '$_temp0';
  }

  @override
  String get nextAvailableLabel => 'Siguiente disponible: ';

  @override
  String get tempNozzle => 'Boquilla';

  @override
  String get tempBed => 'Cama';

  @override
  String get tempChamber => 'Cámara';

  @override
  String tempNozzleNumbered(String n) {
    return 'Boquilla $n';
  }

  @override
  String get ctrlFanPart => 'Ventilador de capa';

  @override
  String get ctrlFanAux => 'Ventilador auxiliar';

  @override
  String get ctrlFanAux2 => 'Ventilador auxiliar izquierdo';

  @override
  String get ctrlFanChamber => 'Ventilador de la cámara';

  @override
  String get ctrlFanExhaust => 'Ventilador de escape';

  @override
  String get ctrlFanPartShort => 'Capa';

  @override
  String get ctrlFanAuxShort => 'Aux';

  @override
  String get ctrlFanAux2Short => 'Aux izq.';

  @override
  String get ctrlFanChamberShort => 'Cámara';

  @override
  String get ctrlFanExhaustShort => 'Escape';

  @override
  String get ctrlSpeed => 'Velocidad';

  @override
  String get ctrlLight => 'Luz de la cámara';

  @override
  String get ctrlLightOn => 'Encendida';

  @override
  String get ctrlLightOff => 'Apagada';

  @override
  String get ctrlAirduct => 'Conducto de aire';

  @override
  String get ctrlAirductCooling => 'Enfriamiento';

  @override
  String get ctrlAirductHeating => 'Calentamiento';

  @override
  String get ctrlOff => 'Apagado';

  @override
  String get ctrlSet => 'Ajustar';

  @override
  String get ctrlActivate => 'Activar';

  @override
  String get ctrlNozzleActive => 'Activa';

  @override
  String get ctrlDry => 'Secar';

  @override
  String get ctrlDrying => 'Secando';

  @override
  String get ctrlDryStart => 'Iniciar';

  @override
  String get ctrlDryFilament => 'Filamento';

  @override
  String get ctrlDryTemp => 'Temperatura';

  @override
  String get ctrlDryDuration => 'Duración';

  @override
  String ctrlDryHours(int h) {
    return '$h h';
  }

  @override
  String get ctrlDryAutoIdle => 'Secado automático cuando la humedad es alta.';

  @override
  String get ctrlDryAutoQueue => 'Secado automático entre impresiones en cola.';

  @override
  String get ctrlDryAutoWhilePrinting => 'También durante las impresiones.';

  @override
  String get ctrlDryStartWhen => 'Hora de inicio';

  @override
  String get ctrlDryStartNow => 'Ahora';

  @override
  String get ctrlDryStartAfter => 'Más tarde';

  @override
  String get ctrlDryStartAt => 'A una hora';

  @override
  String get ctrlDryPickTime => 'Elegir una hora';

  @override
  String get ctrlDrySchedule => 'Programar';

  @override
  String get ctrlDryScheduled => 'Secado programado';

  @override
  String get ctrlDryScheduleTimePast => 'Elige una hora en el futuro';

  @override
  String ctrlDryScheduledFor(String time) {
    return 'Secado a las $time';
  }

  @override
  String get ctrlDryScheduledAsap =>
      'Secado programado, esperando a la impresora';

  @override
  String get ctrlDryScheduleCancel => 'Cancelar secado programado';

  @override
  String get ctrlDryScheduleDismiss => 'Descartar';

  @override
  String ctrlDryScheduleFailed(String reason) {
    return 'El secado programado falló: $reason';
  }

  @override
  String get ctrlDryScheduleFailedUnknown => 'error desconocido';

  @override
  String get ctrlDryWaitPower => 'Conecta el adaptador de corriente del AMS';

  @override
  String get ctrlDryWaitRetract => 'Retrae el filamento en la salida del AMS';

  @override
  String get ctrlDryWaitBlocked =>
      'El AMS no puede empezar a secar en este momento';

  @override
  String get ctrlDryWaitAmsNotFound => 'Esperando a que se detecte el AMS';

  @override
  String get ctrlDryWaitOffline => 'Esperando a que la impresora se conecte';

  @override
  String get ctrlDryWaitBusy => 'Esperando a que la impresora esté libre';

  @override
  String get ctrlDryWaitAlreadyDrying =>
      'Esperando a que termine el ciclo actual';

  @override
  String get ctrlDryWaitInterrupted =>
      'Interrumpido; se reiniciará cuando la impresora esté libre';

  @override
  String get ctrlMove => 'Mover';

  @override
  String get ctrlMoveHome => 'Ir al origen';

  @override
  String get ctrlMoveHomeStarted => 'Regreso al origen iniciado';

  @override
  String get ctrlMoveStep => 'Paso';

  @override
  String get ctrlMoveZ => 'Z (distancia a la cama)';

  @override
  String get ctrlMoveZUp => 'Subir';

  @override
  String get ctrlMoveZDown => 'Bajar';

  @override
  String get ctrlMoveExtruder => 'Extrusor';

  @override
  String get ctrlMoveExtrude => 'Extruir';

  @override
  String get ctrlMoveRetract => 'Retraer';

  @override
  String get ctrlMoveLength => 'Longitud';

  @override
  String ctrlMoveMm(int d) {
    return '$d mm';
  }

  @override
  String get ctrlPause => 'Pausar';

  @override
  String get ctrlResume => 'Reanudar';

  @override
  String get ctrlStop => 'Detener';

  @override
  String get ctrlStopConfirmTitle => '¿Detener la impresión?';

  @override
  String get ctrlStopConfirmBody =>
      'Esto cancela la impresión actual. No se puede reanudar.';

  @override
  String get ctrlForbidden => 'No tienes permiso para controlar esta impresora';

  @override
  String get ctrlFailed => 'No se pudo enviar el comando';

  @override
  String get skipObjectsTitle => 'Omitir objetos';

  @override
  String get skipObjectsSkip => 'Omitir';

  @override
  String get skipObjectsSkippedTag => 'Omitido';

  @override
  String skipObjectsSkippedToast(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se omitieron $count objetos',
      one: 'Se omitió “$names”',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Omitir $count objetos?',
      one: '¿Omitir este objeto?',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '“$names” se omitirán durante el resto de esta impresión. Esto no se puede deshacer.',
      one:
          '“$names” se omitirá durante el resto de esta impresión. Esto no se puede deshacer.',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsSelectedCount(int count) {
    return '$count seleccionados';
  }

  @override
  String get skipObjectsSelectHint =>
      'Toca un objeto arriba o abajo para seleccionarlo y omitirlo';

  @override
  String get skipObjectsMatchInfo =>
      'Haz coincidir los ID con la pantalla de la impresora';

  @override
  String get skipObjectsMatchHint =>
      'La pantalla de la impresora muestra los ID de los objetos en la placa de impresión';

  @override
  String skipObjectsCounter(int skipped, int total) {
    return '$skipped/$total omitidos';
  }

  @override
  String skipObjectsActiveCount(int count) {
    return '$count activos';
  }

  @override
  String skipObjectsWaitForLayer(int layer) {
    return 'Se puede omitir a partir de la capa 2 (actualmente capa $layer)';
  }

  @override
  String get skipObjectsEmpty => 'No hay objetos imprimibles';

  @override
  String get skipObjectsEmptyHint =>
      'Los objetos se cargan cuando comienza una impresión. Recarga si hay una impresión en curso.';

  @override
  String get skipObjectsReload => 'Recargar';

  @override
  String get skipObjectsLoadFailed =>
      'No se pudieron cargar los objetos imprimibles.';

  @override
  String get speedSilent => 'Silencioso';

  @override
  String get speedStandard => 'Estándar';

  @override
  String get speedSport => 'Sport';

  @override
  String get speedLudicrous => 'Ludicrous';

  @override
  String get smartPlugOn => 'Encendido';

  @override
  String get smartPlugOff => 'Apagado';

  @override
  String get smartPlugUnreachable => 'Inaccesible';

  @override
  String get smartPlugMonitorOnly => 'Solo monitorización';

  @override
  String get smartPlugCantPowerOff =>
      'No se puede cortar la corriente mientras la impresora está imprimiendo';

  @override
  String get smartPlugOffConfirmTitle => '¿Cortar la corriente?';

  @override
  String get smartPlugOffConfirmBody =>
      'La impresora perderá la corriente inmediatamente.';

  @override
  String get smartPlugTurnOff => 'Apagar';

  @override
  String get smartPlugOnConfirmTitle => '¿Encender?';

  @override
  String get smartPlugOnConfirmBody => 'La impresora se encenderá.';

  @override
  String get smartPlugTurnOn => 'Encender';

  @override
  String powerWatts(int watts) {
    return '$watts W';
  }

  @override
  String get totalPowerTooltip => 'Consumo total de todos los enchufes';

  @override
  String get queueEmpty => 'La cola está vacía';

  @override
  String get queueAmsFromSlicer => 'AMS del slicer';

  @override
  String queueAnyOfModels(String models) {
    return 'Cualquiera de: $models';
  }

  @override
  String get queueDeleteTitle => '¿Eliminar de la cola?';

  @override
  String get queueDeleteBody =>
      'Esto eliminará el elemento de la cola de impresión.';

  @override
  String get queueDeleteConfirm => 'Eliminar';

  @override
  String get queueStart => 'Iniciar ahora';

  @override
  String get queueStartNext => 'Iniciar siguiente';

  @override
  String get queueCancel => 'Cancelar';

  @override
  String get queueStop => 'Detener impresión';

  @override
  String get queueStopTitle => '¿Detener esta impresión?';

  @override
  String get queueStopBody =>
      'La impresora dejará de imprimir y el elemento saldrá de la cola. Lo que se ha impreso hasta ahora no se puede reanudar.';

  @override
  String get queueStopConfirm => 'Detener impresión';

  @override
  String get queueRemove => 'Eliminar de la cola';

  @override
  String get queueRemoveStoppedTitle => '¿Eliminar de la cola?';

  @override
  String get queueRemoveStoppedBody =>
      'La impresora no muestra esta impresión en ejecución. Al eliminarla, se quitará el elemento de la cola.';

  @override
  String get queueStopped => 'Impresión detenida';

  @override
  String get queueRemoved => 'Eliminado de la cola';

  @override
  String get queueRemovalStatusChanged =>
      'Este elemento ya no se encuentra en el estado mostrado. Actualiza la cola e inténtalo de nuevo.';

  @override
  String get queueNoFreePrinters => 'No hay impresoras libres en este momento';

  @override
  String get queuePrintStarted => 'Impresión iniciada';

  @override
  String get queueStatusPending => 'En espera';

  @override
  String get queueStatusScheduled => 'Programada';

  @override
  String get queueStatusPrinting => 'Imprimiendo';

  @override
  String get queueStatusPaused => 'En pausa';

  @override
  String get archiveSearchHint => 'Buscar en el archivo';

  @override
  String get archiveEmpty => 'No hay impresiones archivadas';

  @override
  String archiveSearchFailed(String query) {
    return 'No se pudo buscar “$query”. Prueba con otro término.';
  }

  @override
  String get archiveNoMatches => 'Ninguna impresión coincide con los filtros';

  @override
  String get archiveFilters => 'Filtros';

  @override
  String get archiveFiltersClear => 'Borrar filtros';

  @override
  String get archiveSortLabel => 'Ordenar por';

  @override
  String get archiveSortDateDesc => 'Más recientes primero';

  @override
  String get archiveSortDateAsc => 'Más antiguos primero';

  @override
  String get archiveSortNameAsc => 'Nombre A–Z';

  @override
  String get archiveSortNameDesc => 'Nombre Z–A';

  @override
  String get archiveSortSizeDesc => 'Más grandes primero';

  @override
  String get archiveSortSizeAsc => 'Más pequeños primero';

  @override
  String get archiveFilterFileType => 'Archivos';

  @override
  String get archiveFileTypeAll => 'Todos los archivos';

  @override
  String get archiveFileTypeGcode => 'Laminados';

  @override
  String get archiveFileTypeSource => 'Fuente';

  @override
  String get archiveFilterFlags => 'Mostrar';

  @override
  String get archiveFilterFavorites => 'Favoritos';

  @override
  String get archiveFilterHideFailed => 'Ocultar fallidas';

  @override
  String get archiveFilterHideDuplicates => 'Ocultar duplicados';

  @override
  String get archiveFilterPrinter => 'Impresora';

  @override
  String get archiveFilterMaterial => 'Material';

  @override
  String get archiveFilterColors => 'Colores';

  @override
  String get archiveColorModeAny => 'Cualquiera';

  @override
  String get archiveColorModeAll => 'Todos';

  @override
  String get archiveFavorite => 'Añadir a favoritos';

  @override
  String get archiveUnfavorite => 'Eliminar de favoritos';

  @override
  String get archiveFavoriteFailed => 'No se pudo actualizar el favorito';

  @override
  String get archiveReprint => 'Reimprimir';

  @override
  String get archiveAddToQueue => 'Añadir a la cola';

  @override
  String get archiveTimelapse => 'Ver timelapse';

  @override
  String archivePhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ver fotos ($count)',
      one: 'Ver foto',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaAction => 'Grabaciones y fotos';

  @override
  String get archiveMediaOnServer => 'En el servidor';

  @override
  String archiveMediaOnPrinter(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'En la impresora ($count)',
      zero: 'En la impresora',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaSearching => 'Buscando en la impresora…';

  @override
  String get archiveMediaNothingOnPrinter => 'Nada en la impresora';

  @override
  String archiveMediaPhotoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fotos',
      one: 'una foto',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaKindTimelapse => 'Timelapse';

  @override
  String get archiveMediaKindIpcam => 'Cámara';

  @override
  String archiveMediaDownloadSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos',
      one: 'un archivo',
      zero: 'seleccionados',
    );
    return 'Descargar $_temp0';
  }

  @override
  String get archiveMediaSaved => 'Vídeo guardado';

  @override
  String get archiveMediaNoFilePermission =>
      'Sin permiso para los archivos de la impresora';

  @override
  String get archiveMediaPrinterMissing => 'La impresora ya no está disponible';

  @override
  String get archiveMediaTimelapseUnavailable =>
      'Timelapses: sin respuesta de la impresora';

  @override
  String get archiveMediaIpcamUnavailable =>
      'Cámara: sin respuesta de la impresora';

  @override
  String archivePlate(int plate) {
    return 'Placa $plate';
  }

  @override
  String archivePlateDetail(int plate) {
    return 'Placa $plate de un archivo multiplaca';
  }

  @override
  String get archivePhotosTitle => 'Fotos';

  @override
  String get archivePhotosEmpty => 'No hay fotos de esta impresión';

  @override
  String get archivePhotoFailed => 'No se pudo cargar esta foto.';

  @override
  String get archiveFilamentUsed => 'Filamento utilizado';

  @override
  String archiveFilamentGrams(String grams) {
    return '$grams g';
  }

  @override
  String archiveFilamentActual(String grams, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$grams consumidos en $count ejecuciones',
      one: '$grams consumidos',
    );
    return '$_temp0';
  }

  @override
  String get archiveFilamentNoActual => 'Sin consumo registrado';

  @override
  String get archiveFilamentSaving => 'Guardando';

  @override
  String get archiveFilamentNone => 'No registrado';

  @override
  String get archiveFilamentLabel => 'Peso (g)';

  @override
  String get archiveFilamentNotANumber =>
      'Introduce un número o déjalo vacío para borrar el peso.';

  @override
  String archiveFilamentOutOfRange(String max) {
    return 'Un peso entre 0 y $max g.';
  }

  @override
  String get archiveFilamentSaved => 'Peso del filamento guardado';

  @override
  String get archiveFilamentUnsupported =>
      'Este servidor aún no almacena el peso del filamento introducido manualmente. Actualiza bambuddy.';

  @override
  String get archiveHasTimelapse => 'Tiene un timelapse';

  @override
  String archiveHasPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tiene $count fotos',
      one: 'Tiene una foto',
    );
    return '$_temp0';
  }

  @override
  String get timelapseTitle => 'Timelapse';

  @override
  String get timelapseError => 'No se pudo reproducir este timelapse.';

  @override
  String timelapseHttpError(int status) {
    return 'El servidor no proporcionó este timelapse ($status).';
  }

  @override
  String get timelapseStalled =>
      'El servidor está enviando el vídeo, pero el reproductor nunca inició la reproducción.';

  @override
  String get timelapsePlay => 'Reproducir';

  @override
  String get timelapsePause => 'Pausar';

  @override
  String get timelapseSave => 'Guardar en la galería';

  @override
  String get timelapseShare => 'Compartir';

  @override
  String get timelapseSaved => 'Guardado en la galería';

  @override
  String get timelapseSaveFailed => 'No se pudo guardar el vídeo';

  @override
  String get timelapseSaveDenied =>
      'Bambuddy necesita permiso para escribir en la galería en esta versión de Android.';

  @override
  String get timelapseEdit => 'Editar';

  @override
  String get timelapseEditSave => 'Guardar';

  @override
  String get timelapseEditTitle => 'Editar timelapse';

  @override
  String get timelapseEditTrim => 'Recortar';

  @override
  String get timelapseEditSpeed => 'Velocidad';

  @override
  String timelapseEditOutput(String length) {
    return 'Resultado: $length';
  }

  @override
  String timelapseEditSource(String length, int width, int height) {
    return 'Original: $length a $width×$height';
  }

  @override
  String get timelapseEditSaveTitle => '¿Sobrescribir la grabación?';

  @override
  String get timelapseEditSaveMessage =>
      'El servidor recodifica el timelapse y reemplaza el original. No hay ninguna copia a la que volver.';

  @override
  String get timelapseEditProcessing =>
      'El servidor está recodificando el vídeo. En un servidor modesto esto tarda varios minutos — salir de esta pantalla no lo detiene.';

  @override
  String get timelapseEdited => 'Timelapse actualizado';

  @override
  String get gcodeViewerTitle => 'Vista previa de G-code';

  @override
  String get gcodeViewerOpen => 'Previsualizar G-code';

  @override
  String get gcodeViewerError => 'No se pudo cargar la vista previa de G-code.';

  @override
  String get gcodeViewerLoading => 'Descargando G-code…';

  @override
  String get gcodeViewerParsing => 'Leyendo la trayectoria de la herramienta…';

  @override
  String get gcodeViewerTravels => 'Movimientos de desplazamiento';

  @override
  String get gcodeViewerColorByFilament => 'Filamento';

  @override
  String get gcodeViewerColorByFeature => 'Tipo de línea';

  @override
  String get gcodeViewerColorByHeight => 'Altura';

  @override
  String get gcodeViewerColorByWidth => 'Anchura';

  @override
  String get gcodeSingleLayer => 'capa única';

  @override
  String gcodeViewerFilamentSlot(int n) {
    return 'Filamento $n';
  }

  @override
  String get gcodeViewerEmpty =>
      'No hay trayectoria de herramienta en este archivo — todavía no ha sido laminado.';

  @override
  String gcodeViewerHttpError(int status) {
    return 'El servidor no proporcionó el G-code de este archivo ($status).';
  }

  @override
  String get gcodeFeatureWall => 'Paredes';

  @override
  String get gcodeFeatureSparseInfill => 'Relleno disperso';

  @override
  String get gcodeFeatureSolidInfill => 'Relleno sólido';

  @override
  String get gcodeFeatureSkirt => 'Falda / borde';

  @override
  String get gcodeFeatureSupport => 'Soporte';

  @override
  String get gcodeFeatureGapFill => 'Relleno de huecos';

  @override
  String get gcodeFeatureBridge => 'Puente / voladizo';

  @override
  String get gcodeFeatureIroning => 'Alisado';

  @override
  String get gcodeFeaturePrimeTower => 'Torre de purga';

  @override
  String get archiveNo3mfTitle =>
      'Algunas impresiones recientes se archivaron sin sus miniaturas';

  @override
  String get archiveNo3mfBody =>
      'El laminador no dejó el archivo .gcode.3mf en la tarjeta de la impresora, por lo que Bambuddy no pudo obtener la miniatura ni los metadatos del laminador. Por lo general, “Store sent files on external storage” está desactivado en la pestaña Device del laminador.';

  @override
  String get archiveNo3mfTitleInternal =>
      'Algunas impresiones recientes se quedaron en el almacenamiento interno de la impresora';

  @override
  String get archiveNo3mfBodyInternal =>
      'Bambu Studio guardó el archivo laminado en el almacenamiento interno de la impresora en lugar de en la tarjeta, por lo que no había nada que leer por FTP. En las series H2 y en la P2S, el botón Imprimir siempre hace esto — activar el ajuste del laminador no cambia nada. Esas impresiones se siguen archivando con su nombre y duración, pero sin miniatura ni metadatos del laminador. Para tener archivos completos, inicia la impresión desde Bambuddy o usa OrcaSlicer para laminar — en ambos casos con una tarjeta o memoria USB en la impresora.';

  @override
  String get archiveNo3mfTitleNoStorage =>
      'Algunas impresiones recientes no se pudieron archivar: no hay almacenamiento en la impresora';

  @override
  String get archiveNo3mfBodyNoStorage =>
      'La impresora indica que no hay ninguna tarjeta o memoria USB en su ranura, por lo que el archivo laminado no tenía dónde guardarse y Bambuddy no pudo leer nada. Inserta una y la próxima impresión se archivará completa.';

  @override
  String get archiveNo3mfDocs => 'Ver el paso 4 de instalación';

  @override
  String get archiveNo3mfDocsWhy => 'Por qué sucede esto';

  @override
  String get archiveNo3mfDismiss => 'Descartar este aviso';

  @override
  String get archiveNotSliceable =>
      'Esta impresión no tiene archivo de origen ni modelo, por lo que no se puede volver a laminar.';

  @override
  String get archiveDelete => 'Eliminar';

  @override
  String get archiveDeleteTitle => '¿Eliminar impresión?';

  @override
  String archiveDeleteBody(String name) {
    return 'Eliminar “$name” del archivo.';
  }

  @override
  String get archiveDeletePurgeStats => 'Eliminar también de las estadísticas';

  @override
  String get archiveDeletePurgeStatsHint =>
      'De lo contrario, la impresión se mantendrá en los totales de tus estadísticas.';

  @override
  String get archiveDeleted => 'Impresión eliminada';

  @override
  String get archiveDeleteFailed => 'No se pudo eliminar la impresión';

  @override
  String get archiveSelectAll => 'Seleccionar todo';

  @override
  String archiveSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionados',
      one: '1 seleccionado',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Eliminar $count impresiones?',
      one: '¿Eliminar 1 impresión?',
    );
    return '$_temp0';
  }

  @override
  String get archiveDeleteSelectedBody =>
      'Eliminar las impresiones seleccionadas del archivo.';

  @override
  String archiveDeletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impresiones eliminadas',
      one: '1 impresión eliminada',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSomeFailed(int ok, int failed) {
    return '$ok eliminadas, $failed fallidas';
  }

  @override
  String get archivePurgeOlder => 'Purgar impresiones antiguas…';

  @override
  String get archivePurgeTitle => 'Purgar impresiones antiguas';

  @override
  String get archivePurgeOlderThan => 'Más antiguas que';

  @override
  String archivePurgeDaysOption(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days días',
      one: '1 día',
    );
    return '$_temp0';
  }

  @override
  String archivePurgePreview(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impresiones · $size',
      one: '1 impresión · $size',
    );
    return '$_temp0';
  }

  @override
  String get archivePurgeNothing => 'No hay impresiones más antiguas que esto.';

  @override
  String get archivePurgePreviewError => 'No se pudo cargar la vista previa.';

  @override
  String archivePurgeResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impresiones purgadas',
      one: '1 impresión purgada',
      zero: 'No se purgó ninguna impresión',
    );
    return '$_temp0';
  }

  @override
  String get pickPrinterTitle => 'Seleccionar una impresora';

  @override
  String get noPrintersAvailable => 'No hay impresoras disponibles';

  @override
  String get detailsShow => 'Detalles';

  @override
  String get detailsHide => 'Ocultar detalles';

  @override
  String get cameraTooltip => 'Cámara';

  @override
  String get cameraConnecting => 'Conectando con la cámara…';

  @override
  String get cameraError => 'No se pudo cargar la transmisión de la cámara';

  @override
  String get cameraDemoUnavailable =>
      'La vista previa de la cámara no está disponible en modo demo';

  @override
  String amsUnit(int number) {
    return 'AMS $number';
  }

  @override
  String get externalSpool => 'Bobina externa';

  @override
  String get traySlotEmpty => 'Vacío';

  @override
  String get amsSlotFilament => 'Filamento';

  @override
  String get amsLoad => 'Cargar';

  @override
  String get amsUnload => 'Descargar';

  @override
  String get amsRfidReread => 'Releer etiqueta';

  @override
  String get amsLoadStarted => 'Cargando filamento…';

  @override
  String get amsUnloadStarted => 'Descargando filamento…';

  @override
  String get amsRfidRereadStarted => 'Releyendo la etiqueta…';

  @override
  String amsFeedTitle(String slot) {
    return '¿En qué boquilla introducir $slot?';
  }

  @override
  String get amsFeedPrompt =>
      'El Filament Track Switch puede dirigir esta ranura a cualquiera de las dos boquillas, por lo que la impresora no puede determinar adónde debe ir el filamento.';

  @override
  String get amsFeedAlreadyLoaded => 'ya cargado';

  @override
  String get amsSwitchNotReady =>
      'El Filament Track Switch aún no está configurado. Asigna cada AMS a una entrada de la impresora e inténtalo de nuevo.';

  @override
  String get amsUnloadSlotNotLoaded =>
      'Ninguna boquilla se alimenta desde esta ranura';

  @override
  String get amsActionsWhilePrinting =>
      'No disponible mientras la impresora está imprimiendo';

  @override
  String get amsSlotConfigure => 'Configurar ranura';

  @override
  String get amsSlotConfigTitle => 'Configuración de ranura';

  @override
  String get amsSlotConfigSearch => 'Buscar ajustes predefinidos';

  @override
  String get amsSlotConfigColour => 'Color';

  @override
  String get amsSlotConfigApply => 'Escribir en la impresora';

  @override
  String get amsSlotConfigStarted => 'Configurando la ranura…';

  @override
  String get amsSlotConfigNameNotSaved =>
      'Ranura configurada, pero no se pudo guardar el nombre del ajuste predefinido';

  @override
  String get amsSlotConfigEmpty =>
      'No hay ajustes predefinidos de filamento disponibles';

  @override
  String get amsSlotConfigNoMatch =>
      'Ningún ajuste predefinido coincide con la búsqueda';

  @override
  String get amsSlotConfigCloudHint =>
      'Inicia sesión en Bambu Cloud para elegir entre tus propios ajustes predefinidos.';

  @override
  String get amsSlotConfigCloudAction => 'Iniciar sesión';

  @override
  String get amsSlotConfigTierLocal => 'Importados';

  @override
  String get amsSlotConfigTierCloud => 'Bambu Cloud';

  @override
  String get amsSlotConfigTierBuiltin => 'Integrados';

  @override
  String amsSlotConfigOnlyPrinter(String model) {
    return 'Solo para $model';
  }

  @override
  String amsSlotConfigOnlyPrinterHiding(String model, int hidden) {
    return 'Solo para $model ($hidden ocultos)';
  }

  @override
  String get amsSlotConfigModelUnknown =>
      'Modelo de impresora desconocido — mostrando todos los ajustes predefinidos';

  @override
  String get amsSlotConfigCurrent => 'Configurado actualmente';

  @override
  String get amsSlotConfigKProfile => 'Perfil K';

  @override
  String amsSlotConfigKProfileDefault(String value) {
    return 'Predeterminado (K $value)';
  }

  @override
  String get amsSlotConfigKProfileOther => 'Otros perfiles';

  @override
  String get amsSlotConfigKProfileNone =>
      'Esta impresora no tiene perfiles K guardados para esta boquilla';

  @override
  String get amsSlotConfigKProfileUnavailable =>
      'No se pudieron leer los perfiles K de la impresora';

  @override
  String amsSlotConfigNozzleGuess(String diameter) {
    return 'La impresora no indicó el tamaño de su boquilla — se asume $diameter mm';
  }

  @override
  String amsSlotConfigKProfileValue(String value) {
    return 'K $value';
  }

  @override
  String get amsSlotConfigColourCatalogue => 'Colores del catálogo';

  @override
  String get amsSlotConfigColourCustom => 'Color personalizado';

  @override
  String get amsSlotReset => 'Restablecer ranura';

  @override
  String get amsSlotResetConfirmTitle => '¿Restablecer esta ranura?';

  @override
  String get amsSlotResetConfirmMessage =>
      'La impresora olvidará el filamento configurado aquí y bambuddy olvidará qué ajuste predefinido era.';

  @override
  String get amsSlotResetStarted => 'Restableciendo la ranura…';

  @override
  String get extruderLeft => 'Extrusor izquierdo';

  @override
  String get extruderRight => 'Extrusor derecho';

  @override
  String get extruderLeftShort => 'I';

  @override
  String get extruderRightShort => 'D';

  @override
  String get amsHumidityTooltip => 'Humedad del AMS';

  @override
  String get amsTempTooltip => 'Temperatura del AMS';

  @override
  String amsHistoryTitle(String ams) {
    return 'Historial de $ams';
  }

  @override
  String get amsHistoryHumidity => 'Humedad';

  @override
  String get amsHistoryTemperature => 'Temperatura';

  @override
  String get sensorHistoryCurrent => 'Actual';

  @override
  String get sensorHistoryAverage => 'Promedio';

  @override
  String get sensorHistoryMin => 'Mín.';

  @override
  String get sensorHistoryMax => 'Máx.';

  @override
  String get sensorHistoryRange6h => '6 h';

  @override
  String get sensorHistoryRange24h => '24 h';

  @override
  String get sensorHistoryRange48h => '48 h';

  @override
  String get sensorHistoryRange7d => '7 d';

  @override
  String get amsHistoryGood => 'Buena';

  @override
  String get amsHistoryFair => 'Aceptable';

  @override
  String get sensorHistoryEmpty => 'No hay datos para este intervalo';

  @override
  String get sensorHistoryError => 'No se pudo cargar el historial';

  @override
  String get amsHistoryRecordingInfo =>
      'Se registra cada 5 minutos mientras la impresora está conectada';

  @override
  String get heaterHistoryTitle => 'Historial de temperatura';

  @override
  String get heaterHistoryOpen => 'Historial de temperatura';

  @override
  String get heaterHistoryReading => 'Lectura';

  @override
  String get heaterHistoryTarget => 'Objetivo';

  @override
  String get heaterHistoryRecordingInfo =>
      'Se registra cada minuto mientras la impresora está conectada';

  @override
  String get wifiTooltip => 'Señal Wi-Fi';

  @override
  String get doorOpen => 'Puerta abierta';

  @override
  String get doorClosed => 'Puerta cerrada';

  @override
  String get firmwareUpToDate => 'Firmware actualizado';

  @override
  String firmwareUpdateAvailable(String version) {
    return 'Actualización de firmware disponible: $version';
  }

  @override
  String get statusUnavailable => 'estado no disponible';

  @override
  String get statusOffline => 'OFFLINE';

  @override
  String get online => 'en línea';

  @override
  String get offline => 'desconectada';

  @override
  String get widgetNoPrinter => 'Sin impresora';

  @override
  String get widgetStatusPrinting => 'Imprimiendo';

  @override
  String get widgetStatusPaused => 'En pausa';

  @override
  String get widgetStatusFinished => 'Finalizada';

  @override
  String get widgetStatusFailed => 'Fallida';

  @override
  String get widgetStatusIdle => 'Inactiva';

  @override
  String get widgetStatusOffline => 'Desconectada';

  @override
  String get widgetStatusError => 'Error';

  @override
  String get widgetMultiTitle => 'Impresoras';

  @override
  String widgetMultiActive(int active, int total) {
    return '$active/$total activas';
  }

  @override
  String widgetMultiMore(int count) {
    return '+$count más';
  }

  @override
  String get widgetMultiGaugeLabel => 'imprimiendo';

  @override
  String widgetMultiIdleCount(int count) {
    return '$count inactivas';
  }

  @override
  String widgetMultiOfflineCount(int count) {
    return '$count desconectadas';
  }

  @override
  String get widgetMultiName => 'Bambuddy · Impresoras';

  @override
  String get widgetMultiDescription => 'Todas las impresoras de un vistazo';

  @override
  String remaining(String time) {
    return '$time restante';
  }

  @override
  String eta(String time) {
    return 'ETA $time';
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
  String get connectToServer => 'Conectar al servidor';

  @override
  String get serverAddressLabel => 'Dirección del servidor bambuddy';

  @override
  String get serverAddressHint => 'p. ej. 192.168.1.10:8000';

  @override
  String get serverAddressHelper =>
      'Acceso remoto: usa HTTPS a través de un proxy inverso';

  @override
  String get testConnection => 'Probar conexión';

  @override
  String get serverRequiresAuth => 'El servidor requiere autenticación';

  @override
  String get authModeApiKey => 'Clave API (recomendado)';

  @override
  String get authModeLogin => 'Usuario y contraseña';

  @override
  String get apiKeyExplain =>
      'Una clave API no caduca y tiene permisos limitados — crea una en el servidor: Settings → API Keys.';

  @override
  String get apiKeyLabel => 'Clave API';

  @override
  String get saveAndConnect => 'Guardar y conectar';

  @override
  String get loginExplain =>
      'Una sesión de inicio de sesión caduca tras 24 h. Marca “Recordarme” para que la aplicación vuelva a iniciar sesión automáticamente.';

  @override
  String get usernameLabel => 'Usuario o correo electrónico';

  @override
  String get passwordLabel => 'Contraseña';

  @override
  String get rememberMe => 'Recordarme';

  @override
  String get rememberMeSubtitle =>
      'La contraseña se guarda en un almacenamiento cifrado (Android Keystore)';

  @override
  String get signInAndConnect => 'Iniciar sesión y conectar';

  @override
  String get twoFactorTitle => 'Autenticación de dos factores';

  @override
  String get twoFactorMethodTotp => 'Authenticator';

  @override
  String get twoFactorMethodEmail => 'Correo electrónico';

  @override
  String get twoFactorMethodBackup => 'Código de respaldo';

  @override
  String get twoFactorExplainTotp =>
      'Introduce el código de 6 dígitos de tu aplicación de autenticación.';

  @override
  String get twoFactorExplainEmail =>
      'Solicita al servidor que te envíe un código de 6 dígitos por correo electrónico y luego introdúcelo aquí.';

  @override
  String get twoFactorExplainEmailSent =>
      'Se ha enviado un código de 6 dígitos a la dirección de tu cuenta. Caduca en 10 minutos.';

  @override
  String get twoFactorExplainBackup =>
      'Introduce uno de los códigos de respaldo de 8 caracteres que guardaste al configurar la 2FA. Cada uno funciona una sola vez.';

  @override
  String get twoFactorCodeLabel => 'Código';

  @override
  String get twoFactorSendEmail => 'Enviarme un código por correo';

  @override
  String get twoFactorResendEmail => 'Enviar otro código';

  @override
  String get twoFactorVerify => 'Confirmar y conectar';

  @override
  String get twoFactorBack => 'Usar otra cuenta';

  @override
  String get twoFactorSessionNote =>
      'La aplicación no puede renovar una sesión con 2FA por sí misma, por lo que volverá a solicitarlo cuando esta expire. Una clave de API no caduca y omite este paso.';

  @override
  String get tryDemo => 'Probar la demo';

  @override
  String get scanApiKeyTitle => 'Escanear clave de API';

  @override
  String get scanApiKeyHint =>
      'Apunta la cámara al código QR de la clave de API';

  @override
  String get cameraPermissionTitle => 'Se necesita acceso a la cámara';

  @override
  String get cameraPermissionBody =>
      'Permite el acceso a la cámara para escanear códigos QR.';

  @override
  String get errMissingUrl => 'Introduce la dirección del servidor';

  @override
  String get errMissingApiKey => 'Introduce la clave de API';

  @override
  String get errMissingCredentials => 'Introduce el usuario y la contraseña';

  @override
  String get errRequiresServerSetup =>
      'El servidor requiere una configuración inicial — complétala en un navegador y vuelve aquí.';

  @override
  String get errServerUnreachable => 'Servidor inaccesible';

  @override
  String get errUnauthorized => 'No autorizado';

  @override
  String get errForbidden => 'No permitido — el servidor rechazó esta acción';

  @override
  String errForbiddenDetail(String reason) {
    return 'No permitido: $reason';
  }

  @override
  String get errApiKeyOwnerDisabled =>
      'La cuenta propietaria de esta clave de API ha sido desactivada o eliminada — la clave seguirá siendo rechazada hasta que se restaure la cuenta.';

  @override
  String errBadResponse(int code) {
    return 'El servidor devolvió el error $code';
  }

  @override
  String get errBadCertificate =>
      'Certificado TLS no válido (los autofirmados no son compatibles en la v1)';

  @override
  String get errConnection => 'Error de conexión';

  @override
  String get errMalformedResponse => 'Respuesta del servidor mal formada';

  @override
  String get errInvalidCredentials => 'Usuario o contraseña no válidos';

  @override
  String get errTwoFactorUnsupported =>
      'La cuenta requiere 2FA — no es compatible en esta versión. Usa una clave de API (Ajustes → Claves de API en el servidor).';

  @override
  String get errTwoFactorCodeRejected =>
      'Código incorrecto — compruébalo e inténtalo de nuevo.';

  @override
  String get errTwoFactorChallengeExpired =>
      'El intento de inicio de sesión ha caducado — introduce tu contraseña de nuevo para obtener un código nuevo.';

  @override
  String get errTwoFactorMethodUnavailable =>
      'Ese método no está disponible en esta cuenta — elige otro.';

  @override
  String get errTwoFactorEmailUnavailable =>
      'El servidor no pudo enviar el código — no tiene el correo electrónico configurado o tu cuenta no tiene ninguna dirección. Usa otro método.';

  @override
  String get errMissingTwoFactorCode => 'Introduce el código';

  @override
  String get errApiKeyRejected =>
      'Clave de API rechazada — comprueba la clave y su alcance (se requiere can_read_status)';

  @override
  String get errTooManyAttempts =>
      'Demasiados intentos — el servidor está bloqueando el inicio de sesión durante unos minutos. Espera e inténtalo de nuevo, o usa una clave de API.';

  @override
  String get errSlotTagUnreadable =>
      'Esta ranura no tiene una etiqueta RFID legible — Spoolman vincula las bobinas por etiqueta, por lo que no puede admitir esta. El inventario integrado las asigna por ranura.';

  @override
  String get errPrinterOffline =>
      'La impresora está desconectada, por lo que la aplicación no puede leer lo que contiene la ranura. Vuelve a conectarla e inténtalo de nuevo.';

  @override
  String notifOngoingBody(int percent, String eta) {
    return '$percent% · ETA $eta';
  }

  @override
  String notifMorePrints(int count) {
    return '+$count';
  }

  @override
  String get printFinishedTitle => 'Impresión finalizada';

  @override
  String printFinishedBody(String name) {
    return '$name ha terminado';
  }

  @override
  String get printFailedTitle => 'Impresión fallida';

  @override
  String printFailedBody(String name) {
    return '$name ha fallado';
  }

  @override
  String get notifStartedTitle => 'Impresión iniciada';

  @override
  String notifStartedBody(String name) {
    return '$name ha comenzado a imprimirse';
  }

  @override
  String get notifFirstLayerTitle => 'Primera capa lista';

  @override
  String notifFirstLayerBody(String name) {
    return '$name ha terminado su primera capa';
  }

  @override
  String notifMilestoneTitle(int percent) {
    return '$percent% impreso';
  }

  @override
  String notifMilestoneBody(String name, int percent) {
    return '$name está al $percent%';
  }

  @override
  String get notifPlateTitle => 'Placa no vacía';

  @override
  String notifPlateBody(String printer) {
    return '$printer necesita que se despeje la placa antes del siguiente trabajo';
  }

  @override
  String get notifOfflineTitle => 'Impresora desconectada';

  @override
  String notifOfflineBody(String printer) {
    return '$printer ha perdido la conexión';
  }

  @override
  String get notifErrorTitle => 'Error de la impresora';

  @override
  String notifErrorBody(String printer, String detail) {
    return '$printer: $detail';
  }

  @override
  String get notifLowFilamentTitle => 'Poco filamento';

  @override
  String notifLowFilamentBody(String printer, int percent) {
    return 'A $printer le queda un $percent% de filamento';
  }

  @override
  String get notifHumidityTitle => 'Humedad alta en el AMS';

  @override
  String get notifHumidityHtTitle => 'Humedad alta en el AMS-HT';

  @override
  String notifHumidityBody(String printer, int value) {
    return 'La humedad del AMS de $printer es del $value%';
  }

  @override
  String get notifBedCooledTitle => 'Cama enfriada';

  @override
  String notifBedCooledBody(String printer, int temp) {
    return 'La cama de $printer se ha enfriado a $temp°C';
  }

  @override
  String get notifSettingsTitle => 'Notificaciones';

  @override
  String get notifSettingsHint =>
      'Elige qué eventos activan una notificación. Los cambios se aplicarán la próxima vez que se inicie la supervisión en segundo plano.';

  @override
  String get notifMasterTitle => 'Notificaciones de eventos';

  @override
  String get notifMasterDesc =>
      'Desactívalo para silenciar todas las alertas. La notificación continua del progreso de impresión se mantiene.';

  @override
  String get notifEventsHeader => 'Eventos';

  @override
  String get notifExtrasHeader => 'Detalles';

  @override
  String get notifFinishPhotoTitle => 'Foto de la impresión finalizada';

  @override
  String get notifFinishPhotoDesc =>
      'Añade la foto que toma el servidor al terminar la impresión a la notificación de finalización o fallo, en cuanto esté disponible';

  @override
  String get notifThresholdsHeader => 'Umbrales';

  @override
  String get notifEvtStarted => 'Impresión iniciada';

  @override
  String get notifEvtStartedDesc => 'Cuando comienza una impresión';

  @override
  String get notifEvtFinished => 'Impresión finalizada';

  @override
  String get notifEvtFinishedDesc =>
      'Cuando una impresión se completa con éxito';

  @override
  String get notifEvtFailed => 'Impresión fallida';

  @override
  String get notifEvtFailedDesc => 'Cuando falla una impresión';

  @override
  String get notifEvtFirstLayer => 'Primera capa lista';

  @override
  String get notifEvtFirstLayerDesc => 'Cuando finaliza la primera capa';

  @override
  String get notifEvtMilestones => 'Hitos de progreso';

  @override
  String get notifEvtMilestonesDesc => 'Al 25%, 50% y 75%';

  @override
  String get notifEvtPlate => 'Placa no vacía';

  @override
  String get notifEvtPlateDesc =>
      'Cuando se debe despejar la placa antes del siguiente trabajo';

  @override
  String get notifEvtOffline => 'Impresora desconectada';

  @override
  String get notifEvtOfflineDesc => 'Cuando una impresora pierde la conexión';

  @override
  String get notifEvtError => 'Error de la impresora (HMS)';

  @override
  String get notifEvtErrorDesc => 'Cuando la impresora notifica un error HMS';

  @override
  String get notifEvtLowFilament => 'Poco filamento';

  @override
  String get notifEvtLowFilamentDesc =>
      'Cuando el filamento restante cae por debajo del umbral';

  @override
  String get notifEvtHumidity => 'Humedad alta en el AMS';

  @override
  String get notifEvtHumidityDesc =>
      'Cuando la humedad del AMS supera el umbral';

  @override
  String get notifEvtBedCooled => 'Cama enfriada';

  @override
  String get notifEvtBedCooledDesc =>
      'Cuando la cama se enfría tras una impresión';

  @override
  String notifBedCooledThreshold(int temp) {
    return 'Cama enfriada por debajo de $temp°C';
  }

  @override
  String notifHumidityThreshold(int value) {
    return 'Humedad del AMS por encima del $value%';
  }

  @override
  String notifLowFilamentThreshold(int percent) {
    return 'Poco filamento por debajo del $percent%';
  }

  @override
  String get notifEventsMenu => 'Eventos de notificación';

  @override
  String get hmsErrorsHeader => 'Errores activos';

  @override
  String get hmsViewInWiki => 'Abrir en la wiki de Bambu';

  @override
  String hmsErrorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errores',
      one: '1 error',
    );
    return '$_temp0';
  }

  @override
  String get hmsDismissAll => 'Descartar todo';

  @override
  String get hmsDismissed => 'Errores borrados en la impresora';

  @override
  String get hmsDismissFailed => 'No se pudieron borrar los errores';

  @override
  String get hmsActionSent => 'Enviado a la impresora';

  @override
  String get hmsActionFailed => 'La impresora rechazó la acción';

  @override
  String get hmsActionNotAcknowledged =>
      'La impresora no confirmó la acción — comprueba su pantalla';

  @override
  String get hmsStopConfirmTitle => '¿Detener la impresión?';

  @override
  String hmsStopConfirmBody(String printer) {
    return '$printer cancelará el trabajo de impresión. Esto no se puede deshacer.';
  }

  @override
  String get hmsStopConfirmAction => 'Detener impresión';

  @override
  String get hmsActionResume => 'Reanudar';

  @override
  String get hmsActionResumeDefects => 'Reanudar de todos modos';

  @override
  String get hmsActionResumeSolved => 'Solucionado, reanudar';

  @override
  String get hmsActionProblemSolvedResume => 'Solucionado, reanudar';

  @override
  String get hmsActionFilamentLoadedResume => 'Cargado, reanudar';

  @override
  String get hmsActionProceed => 'Continuar';

  @override
  String get hmsActionStopPrinting => 'Detener';

  @override
  String get hmsActionIgnoreResume => 'Ignorar y reanudar';

  @override
  String get hmsActionIgnoreNoReminder => 'Ignorar siempre';

  @override
  String get hmsActionDontRemind => 'No recordar';

  @override
  String get hmsActionNoReminder => 'Descartar';

  @override
  String get hmsActionFilamentExtruded => 'Extruido';

  @override
  String get hmsActionRetryFilamentExtruded => 'Aún no, reintentar';

  @override
  String get hmsActionContinue => 'Listo, continuar';

  @override
  String get hmsActionRetrySolved => 'Solucionado, reintentar';

  @override
  String get hmsActionDone => 'Listo';

  @override
  String get hmsActionRetry => 'Reintentar';

  @override
  String get hmsActionResumePlain => 'Reanudar';

  @override
  String get hmsActionConfirm => 'Confirmar';

  @override
  String get hmsActionAbort => 'Abortar';

  @override
  String get hmsActionOk => 'Aceptar';

  @override
  String get hmsActionRecheck => 'Volver a comprobar';

  @override
  String get hmsActionTurnOffFireAlarm => 'Apagar alarma';

  @override
  String get hmsActionStopDrying => 'Detener secado';

  @override
  String get hmsActionDisablePurification => 'Desactivar purificación';

  @override
  String get batteryOptTitle => 'Notificaciones fiables en segundo plano';

  @override
  String get batteryOptBody =>
      'Para que las notificaciones de impresión sigan funcionando cuando la aplicación esté en segundo plano, permite que Bambuddy se ejecute sin restricciones de batería. En teléfonos Samsung esto es imprescindible.';

  @override
  String get batteryOptAllow => 'Abrir ajustes';

  @override
  String get batteryOptLater => 'Más tarde';

  @override
  String get batteryOptMenu => 'Notificaciones en segundo plano';

  @override
  String get notificationsReady => 'Las notificaciones están configuradas';

  @override
  String get notificationsBlocked =>
      'Las notificaciones están desactivadas — actívalas en los ajustes del sistema';

  @override
  String get bgServiceTitle => 'Bambuddy';

  @override
  String get bgServiceText => 'Supervisando impresoras';

  @override
  String get bgMonitoringToggle => 'Supervisión en segundo plano';

  @override
  String get bgMonitoringSubtitle =>
      'Sigue supervisando las impresiones mientras la aplicación está cerrada. Muestra una notificación persistente.';

  @override
  String get bgMonitoringOn => 'Supervisión en segundo plano activada';

  @override
  String get bgMonitoringOff => 'Supervisión en segundo plano desactivada';

  @override
  String get navDashboard => 'Impresoras';

  @override
  String get navQueue => 'Cola';

  @override
  String get navArchive => 'Archivo';

  @override
  String get navMaintenance => 'Mantenimiento';

  @override
  String get navFilaments => 'Filamentos';

  @override
  String get inventoryEmpty => 'No hay bobinas en el inventario';

  @override
  String get inventoryNoMatches => 'Ningún filamento coincide con tu búsqueda';

  @override
  String get inventorySearchHint => 'Buscar material, marca, color…';

  @override
  String get inventoryShowArchived => 'Mostrar archivados';

  @override
  String get inventoryArchived => 'Archivado';

  @override
  String get inventoryLowStock => 'Bajo';

  @override
  String get inventoryFilters => 'Filtros';

  @override
  String get inventoryFilterStatus => 'Estado';

  @override
  String get inventoryStatusActive => 'Activo';

  @override
  String get inventoryStatusArchived => 'Archivado';

  @override
  String get inventoryFilterStock => 'Stock';

  @override
  String get inventoryStockAll => 'Todos';

  @override
  String get inventoryStockLow => 'Stock bajo';

  @override
  String get inventoryFilterMaterial => 'Material';

  @override
  String get inventoryFilterBrand => 'Marca';

  @override
  String get inventoryFiltersClear => 'Borrar todo';

  @override
  String inventorySpoolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas',
      one: 'bobina',
    );
    return '$count $_temp0';
  }

  @override
  String inventoryRemaining(String grams) {
    return '$grams g restantes';
  }

  @override
  String inventoryTotalConsumed(String weight) {
    return '$weight consumidos';
  }

  @override
  String inventoryConsumedSinceReset(String weight) {
    return 'Consumido desde el reinicio: $weight';
  }

  @override
  String inventoryOfTotal(int total) {
    return 'de $total g';
  }

  @override
  String inventoryLoadedIn(String slot) {
    return 'Cargada en $slot';
  }

  @override
  String get inventoryNotLoaded => 'No cargada en ninguna ranura del AMS';

  @override
  String get inventoryLocation => 'Ubicación';

  @override
  String get inventoryNozzleTemp => 'Temp. de boquilla';

  @override
  String inventoryCostPerKg(String cost) {
    return '$cost/kg';
  }

  @override
  String get inventoryNote => 'Nota';

  @override
  String get inventoryTag => 'Etiqueta';

  @override
  String get inventoryId => 'ID de filamento';

  @override
  String get inventoryUsageHistory => 'Historial de uso';

  @override
  String get inventoryUsageEmpty => 'Aún no hay uso registrado';

  @override
  String inventoryUsageWeight(String grams) {
    return '$grams g';
  }

  @override
  String get inventoryKProfiles => 'Calibración (K)';

  @override
  String inventoryKProfileLine(String nozzle, String k) {
    return '$nozzle mm · K $k';
  }

  @override
  String get inventoryAddSpool => 'Añadir bobina';

  @override
  String inventoryAddSpools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas',
      one: 'bobina',
    );
    return 'Añadir $count $_temp0';
  }

  @override
  String get inventoryNewSpool => 'Nueva bobina';

  @override
  String get inventoryEditSpool => 'Editar bobina';

  @override
  String get inventorySave => 'Guardar';

  @override
  String get inventoryFieldQuantity => 'Cantidad';

  @override
  String get inventoryQuantityHint => 'Crear varias bobinas idénticas a la vez';

  @override
  String get inventoryEdit => 'Editar';

  @override
  String get inventoryDelete => 'Eliminar';

  @override
  String get inventoryArchive => 'Archivar';

  @override
  String get inventoryRestore => 'Restaurar';

  @override
  String get inventoryResetUsage => 'Restablecer uso';

  @override
  String get inventoryFieldSlicerPreset => 'Perfil de laminador';

  @override
  String get inventorySlicerPresetHint =>
      'Perfil de impresión con el que se añade esta bobina';

  @override
  String get inventorySlicerPresetNone => 'Sin perfil';

  @override
  String get inventorySlicerPresetSearch => 'Buscar perfiles…';

  @override
  String get inventorySlicerPresetUnavailable =>
      'No hay perfiles de laminador disponibles. Habilita el laminado en el servidor (y conecta Bambu Cloud para obtener perfiles de la nube).';

  @override
  String get inventorySectionPrinterPresets =>
      'Perfiles por modelo de impresora';

  @override
  String get inventoryPrinterPresetsHint =>
      'La opción elegida aquí tiene prioridad sobre el perfil de la bobina.';

  @override
  String get inventoryPrinterPresetDefault => 'Igual que en la bobina';

  @override
  String inventoryPrinterPresetNozzle(String model, String diameter) {
    return '$model · boquilla de $diameter';
  }

  @override
  String get inventoryPrinterPresetsLoadFailed =>
      'No se pudieron leer — al guardar no se modificarán.';

  @override
  String get inventoryPrinterPresetsSaveFailed =>
      'Bobina guardada, pero sus perfiles por modelo no.';

  @override
  String get inventoryFieldMaterial => 'Material';

  @override
  String get inventoryFieldBrand => 'Marca';

  @override
  String get inventoryFieldSubtype => 'Variante';

  @override
  String get inventoryFieldColorName => 'Nombre del color';

  @override
  String get inventoryFieldColorHex => 'Color (hex)';

  @override
  String get inventoryFieldLabelWeight => 'Peso de la bobina (g)';

  @override
  String get inventoryFieldWeightUsed => 'Usado (g)';

  @override
  String get inventoryFieldCostPerKg => 'Coste por kg';

  @override
  String get inventoryFieldLowStock => 'Umbral de stock bajo (%)';

  @override
  String get inventoryFieldLocation => 'Ubicación de almacenamiento';

  @override
  String get inventoryFieldNozzleMin => 'Boquilla mín. (°C)';

  @override
  String get inventoryFieldNozzleMax => 'Boquilla máx. (°C)';

  @override
  String get inventoryFieldNote => 'Nota';

  @override
  String get inventoryFieldRequired => 'Obligatorio';

  @override
  String get inventoryFieldInvalidNumber => 'Introduce un número';

  @override
  String inventoryFieldRange(int min, int max) {
    return 'Introduce un valor de $min a $max';
  }

  @override
  String get inventoryFieldNegative => 'Introduce un valor de 0 o más';

  @override
  String get inventorySectionBasics => 'Datos básicos';

  @override
  String get inventorySectionWeight => 'Peso y coste';

  @override
  String get inventorySectionDetails => 'Detalles';

  @override
  String get inventorySectionFilament => 'Filamento';

  @override
  String get inventorySectionColor => 'Color';

  @override
  String get inventorySectionAdditional => 'Adicional';

  @override
  String get inventoryFieldEmptySpoolWeight => 'Peso de la bobina vacía (g)';

  @override
  String get inventoryCoreWeightSelect => 'Seleccionar…';

  @override
  String get inventoryCoreWeightSearch => 'Buscar bobinas…';

  @override
  String get inventoryFieldRemainingWeight => 'Peso restante (g)';

  @override
  String get inventoryFieldMeasuredWeight => 'Peso medido (g)';

  @override
  String get inventoryFieldCategory => 'Categoría';

  @override
  String get inventoryFieldExtraColors => 'Colores adicionales';

  @override
  String get inventoryExtraColorsHint => '2–8 valores hex, separados por comas';

  @override
  String get inventoryFieldEffect => 'Efecto';

  @override
  String get inventoryEffectNone => 'Ninguno';

  @override
  String get inventoryColorCommon => 'Colores habituales';

  @override
  String get inventoryColorSearchHint => 'Buscar colores…';

  @override
  String get inventoryColorPickTitle => 'Elegir un color';

  @override
  String get inventoryColorSelect => 'Seleccionar';

  @override
  String get inventoryColorNone => 'Sin color';

  @override
  String get inventoryLowStockHint =>
      'Dejar en blanco para usar el umbral global';

  @override
  String inventoryRemainingOfLabel(int total) {
    return 'de $total g';
  }

  @override
  String get inventoryDeleteTitle => '¿Eliminar bobina?';

  @override
  String inventoryDeleteConfirm(String name) {
    return '¿Eliminar $name permanentemente? Esto no se puede deshacer.';
  }

  @override
  String get inventoryResetUsageConfirm =>
      '¿Restablecer el contador de filamento consumido a cero? Las futuras impresiones contarán de nuevo desde cero — el peso restante no se modificará.';

  @override
  String get inventorySpoolCreated => 'Bobina añadida';

  @override
  String inventorySpoolsCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas añadidas',
      one: 'bobina añadida',
    );
    return '$count $_temp0';
  }

  @override
  String get inventorySpoolUpdated => 'Bobina actualizada';

  @override
  String get inventorySpoolDeleted => 'Bobina eliminada';

  @override
  String get inventorySpoolArchived => 'Bobina archivada';

  @override
  String get inventorySpoolRestored => 'Bobina restaurada';

  @override
  String get inventoryUsageReset => 'Contador restablecido';

  @override
  String get inventorySaveFailed => 'No se pudo guardar la bobina';

  @override
  String get inventoryActionFailed => 'Acción fallida';

  @override
  String get inventoryUnassign => 'Desasignar';

  @override
  String get inventoryAssign => 'Asignar a ranura';

  @override
  String get inventoryAssignPrinter => 'Impresora';

  @override
  String get inventoryAssignNoPrinters => 'No hay impresoras disponibles';

  @override
  String get inventorySlotAms => 'Ranura AMS';

  @override
  String get inventoryAssignUnit => 'Unidad AMS';

  @override
  String get inventoryAssignSlot => 'Ranura';

  @override
  String get inventoryAssignExtruder => 'Extrusor';

  @override
  String get inventoryAssignExternalHint =>
      'Asigna al soporte de bobina externo';

  @override
  String get inventoryAssignConfirm => 'Asignar';

  @override
  String get inventoryAssignTitle => 'Asignar bobina';

  @override
  String get inventoryAssignCurrent => 'Actualmente en esta ranura';

  @override
  String get inventoryAssignPick => 'Selecciona una bobina';

  @override
  String get inventoryReassignTitle => '¿Mover bobina?';

  @override
  String inventoryReassignMessage(String slot) {
    return 'Esta bobina está actualmente en $slot. Se retirará de allí y se asignará a esta ranura.';
  }

  @override
  String get inventoryReassignAction => 'Mover';

  @override
  String get inventorySpoolAssigned => 'Bobina asignada';

  @override
  String get inventorySpoolUnassigned => 'Bobina desasignada';

  @override
  String get inventoryFromSlot => 'Añadir al inventario';

  @override
  String get inventoryFromSlotHint =>
      'Registra la bobina etiquetada que la impresora notifica en esta ranura';

  @override
  String get inventoryFromSlotDone => 'Bobina añadida y asignada a la ranura';

  @override
  String get inventoryFromSlotNoTag =>
      'La impresora ya no notifica una bobina etiquetada en esta ranura';

  @override
  String get inventoryFromSlotOffline =>
      'La impresora no está conectada, por lo que no puede indicar qué hay en la ranura';

  @override
  String get inventoryFromSlotUnsupported =>
      'Esta versión del servidor no puede añadir una bobina directamente desde una ranura';

  @override
  String get inventoryScanSpool => 'Escanear QR';

  @override
  String get inventoryScanTitle => 'Escanear QR de bobina';

  @override
  String get inventoryScanHint =>
      'Apunta con la cámara al código QR de la bobina';

  @override
  String get inventoryScanPermissionTitle => 'Acceso a la cámara necesario';

  @override
  String get inventoryScanPermissionBody =>
      'Permite el acceso a la cámara para escanear códigos QR de bobinas.';

  @override
  String get inventoryScanOpenSettings => 'Abrir ajustes';

  @override
  String get inventoryScanInvalid => 'Código QR no reconocido';

  @override
  String inventoryScanNotFound(int id) {
    return 'Bobina #$id no encontrada';
  }

  @override
  String inventorySelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionadas',
      one: '$count seleccionada',
    );
    return '$_temp0';
  }

  @override
  String get inventorySelectAll => 'Seleccionar todo';

  @override
  String inventoryBulkArchiveTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas',
      one: 'bobina',
    );
    return '¿Archivar $count $_temp0?';
  }

  @override
  String get inventoryBulkArchiveBody =>
      'Se ocultarán de la lista activa. Podrás restaurarlas más tarde.';

  @override
  String inventoryBulkRestoreTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas',
      one: 'bobina',
    );
    return '¿Restaurar $count $_temp0?';
  }

  @override
  String get inventoryBulkRestoreBody => 'Volverán a la lista activa.';

  @override
  String inventoryBulkDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas',
      one: 'bobina',
    );
    return '¿Eliminar $count $_temp0?';
  }

  @override
  String get inventoryBulkDeleteBody =>
      'Esto las eliminará permanentemente y no se puede deshacer.';

  @override
  String inventoryBulkResetTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas',
      one: 'bobina',
    );
    return '¿Restablecer el uso de $count $_temp0?';
  }

  @override
  String get inventoryBulkResetBody =>
      'Sus contadores de filamento consumido volverán a cero. Los pesos restantes no cambiarán.';

  @override
  String inventoryBulkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas actualizadas',
      one: 'bobina actualizada',
    );
    return '$count $_temp0';
  }

  @override
  String inventoryBulkPartial(int ok, int failed) {
    return '$ok completadas, $failed fallidas';
  }

  @override
  String inventoryBulkSkipped(int ok, int skipped) {
    return '$ok completadas, $skipped ya estaban ahí';
  }

  @override
  String inventoryBulkPartialSkipped(int ok, int skipped, int failed) {
    return '$ok completadas, $skipped ya estaban ahí, $failed fallidas';
  }

  @override
  String get inventoryBulkEdit => 'Editar campos';

  @override
  String inventoryBulkEditTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas',
      one: 'bobina',
    );
    return 'Editar $count $_temp0';
  }

  @override
  String get inventoryBulkEditHint =>
      'Solo cambiarán los campos que rellenes. Deja el resto en blanco.';

  @override
  String get inventoryBulkEditUnchanged => 'Sin cambios';

  @override
  String inventoryBulkEditApply(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas',
      one: 'bobina',
    );
    return 'Aplicar a $count $_temp0';
  }

  @override
  String inventoryBulkEditConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'bobinas',
      one: 'bobina',
    );
    return '¿Modificar $count $_temp0?';
  }

  @override
  String inventoryBulkEditConfirmBody(int fields) {
    String _temp0 = intl.Intl.pluralLogic(
      fields,
      locale: localeName,
      other: 'Se sobrescribirán $fields campos',
      one: 'Se sobrescribirá $fields campo',
    );
    return '$_temp0 en cada bobina seleccionada.';
  }

  @override
  String get inventoryBulkEditUnsupported =>
      'Este servidor es demasiado antiguo para la edición masiva. Actualiza Bambuddy o edita las bobinas una a una.';

  @override
  String get inventoryApply => 'Aplicar';

  @override
  String get inventoryLabelsTitle => 'Imprimir etiquetas de bobina';

  @override
  String get inventoryLabelsPrint => 'Imprimir etiquetas';

  @override
  String get inventoryLabelsPrintAll => 'Imprimir etiquetas para todas';

  @override
  String get inventoryClimateTitle => 'Condiciones de almacenamiento';

  @override
  String get inventoryClimateTitleAlerting =>
      'Condiciones de almacenamiento: fuera del rango de alerta';

  @override
  String get inventoryClimateSource =>
      'El servidor lee estos datos de Home Assistant. Los sensores se vinculan a una ubicación en la interfaz web de Bambuddy.';

  @override
  String get inventoryClimateNoReading => 'sin lectura';

  @override
  String inventoryClimateReading(String name, String value) {
    return '$name: $value';
  }

  @override
  String inventoryClimateReadingAlerting(String name, String value) {
    return '$name: $value, fuera del rango de alerta';
  }

  @override
  String inventoryClimateReadingStale(String name, String value) {
    return '$name: $value, sensor inaccesible';
  }

  @override
  String get inventoryLabelsSearchHint => 'Buscar por nombre, marca o #ID';

  @override
  String get inventoryLabelsPickSpools =>
      'Elige para qué bobinas imprimir etiquetas:';

  @override
  String get inventoryLabelsMaterial => 'Material:';

  @override
  String get inventoryLabelsAllMaterials => 'Todos';

  @override
  String get inventoryLabelsSort => 'Ordenar:';

  @override
  String get inventoryLabelsSortById => 'Por ID';

  @override
  String get inventoryLabelsSortByColor => 'Por color';

  @override
  String get inventoryLabelsSelectVisible => 'Seleccionar visibles';

  @override
  String get inventoryLabelsDeselectVisible => 'Deseleccionar visibles';

  @override
  String get inventoryLabelsClearAll => 'Deseleccionar todo';

  @override
  String get inventoryLabelsNoMatches =>
      'Ninguna bobina coincide con la búsqueda o el filtro actual.';

  @override
  String get inventoryLabelsMonochrome =>
      'Monocromo (impresora en blanco y negro)';

  @override
  String get inventoryLabelsMonochromeHint =>
      'Omite la muestra de color y ensancha el texto';

  @override
  String get inventoryLabelsShare => 'Compartir PDF en lugar de imprimir';

  @override
  String get inventoryLabelsPickTemplate =>
      'Elige un tamaño de etiqueta para imprimir:';

  @override
  String inventoryLabelsTooMany(int max) {
    return 'Elige como máximo $max bobinas por impresión';
  }

  @override
  String get inventoryLabelsFailed => 'No se pudieron generar las etiquetas';

  @override
  String get inventoryLabelsAmsSmall => 'Soporte AMS — pequeño (74 × 33 mm)';

  @override
  String get inventoryLabelsAmsSmallHint =>
      'Una por página; coincide con la etiqueta imprimible del modelo 752566 de MakerWorld.';

  @override
  String get inventoryLabelsAmsLarge => 'Soporte AMS — grande (75 × 55 mm)';

  @override
  String get inventoryLabelsAmsLargeHint =>
      'Una por página; se adapta a la variante con inserto de cartulina del mismo soporte.';

  @override
  String get inventoryLabelsBox40 => 'Etiqueta para caja (40 × 30 mm)';

  @override
  String get inventoryLabelsBox40Hint =>
      'Una por página; tamaño común de rollo DK/Brother, apto para bolsas y cajas.';

  @override
  String get inventoryLabelsBox62 => 'Etiqueta para caja (62 × 29 mm)';

  @override
  String get inventoryLabelsBox62Hint =>
      'Una por página; adaptada a etiquetas pequeñas Brother PT/QL y Dymo.';

  @override
  String get inventoryLabelsAveryL7160 =>
      'Avery L7160 — hoja A4 (38,1 × 63,5 mm × 21)';

  @override
  String get inventoryLabelsAveryL7160Hint =>
      'Formato de hoja de la UE; 21 etiquetas por página A4.';

  @override
  String get inventoryLabelsAvery5160 =>
      'Avery 5160 — hoja US Letter (25,4 × 66,7 mm × 30)';

  @override
  String get inventoryLabelsAvery5160Hint =>
      'Formato de hoja de EE. UU.; 30 etiquetas por página Letter.';

  @override
  String get inventoryLabelsStartTitle => 'Primera etiqueta libre';

  @override
  String get inventoryLabelsStartHint =>
      'Toca la posición donde debe imprimirse la primera etiqueta: las anteriores quedarán en blanco para poder aprovechar una hoja ya empezada en lugar de comenzar otra.';

  @override
  String inventoryLabelsStartSlot(int position) {
    return 'Posición $position';
  }

  @override
  String get maintenanceEmpty => 'Sin datos de mantenimiento';

  @override
  String maintenanceTotalHours(int hours) {
    return '$hours h en total';
  }

  @override
  String maintenanceDueBadge(int count) {
    return '$count pendientes';
  }

  @override
  String maintenanceWarningBadge(int count) {
    return '$count pronto';
  }

  @override
  String maintenanceDueIn(int hours) {
    return 'Vence en $hours h';
  }

  @override
  String maintenanceOverdueBy(int hours) {
    return 'Vencida hace $hours h';
  }

  @override
  String get maintenancePerform => 'Marcar como completada';

  @override
  String get maintenancePerformConfirm =>
      '¿Restablecer el contador de esta tarea de mantenimiento?';

  @override
  String get maintenanceNotesHint => 'Notas (opcional)';

  @override
  String get maintenanceHistory => 'Historial';

  @override
  String get maintenanceHistoryEmpty => 'Aún no hay historial';

  @override
  String get maintenanceDone => 'Mantenimiento marcado como completado';

  @override
  String get maintenanceFailed => 'No se pudo actualizar el mantenimiento';

  @override
  String get maintenanceSaved => 'Guardado';

  @override
  String get maintenanceSettingsTitle => 'Ajustes de mantenimiento';

  @override
  String get maintenanceOverridesTitle => 'Intervalos personalizados';

  @override
  String get maintenanceOverridesSubtitle =>
      'Silencia tareas o personaliza intervalos por impresora';

  @override
  String get maintenanceTabStatus => 'Estado';

  @override
  String get maintenanceTabSettings => 'Ajustes';

  @override
  String get maintenanceMute => 'Silenciar';

  @override
  String get maintenanceUnmute => 'Reactivar';

  @override
  String get maintenanceMuted => 'Tarea silenciada';

  @override
  String get maintenanceUnmuted => 'Tarea reactivada';

  @override
  String get maintenanceEditInterval => 'Editar intervalo';

  @override
  String get maintenanceResetInterval => 'Restablecer valor predeterminado';

  @override
  String get maintenanceTypesTitle => 'Tipos de mantenimiento';

  @override
  String get maintenanceTypesSubtitle =>
      'Tipos del sistema y tus tareas personalizadas';

  @override
  String get maintenanceRestoreDefaults => 'Restaurar valores predeterminados';

  @override
  String get maintenanceRestoreConfirm =>
      '¿Restaurar todos los tipos de mantenimiento predeterminados ocultos?';

  @override
  String get maintenanceAddType => 'Añadir tipo personalizado';

  @override
  String get maintenanceEditType => 'Editar tipo';

  @override
  String get maintenanceSystemType => 'Sistema';

  @override
  String maintenanceEveryHours(int count) {
    return 'Cada $count h';
  }

  @override
  String maintenanceEveryDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cada $count días',
      one: 'Cada día',
    );
    return '$_temp0';
  }

  @override
  String get maintenanceDeleteTypeTitle => '¿Eliminar tipo de mantenimiento?';

  @override
  String maintenanceDeleteTypeConfirm(String name) {
    return '¿Eliminar “$name”? Esta acción no se puede deshacer.';
  }

  @override
  String maintenanceHideTypeConfirm(String name) {
    return '¿Ocultar el tipo predeterminado “$name”? Podrás restaurarlo más tarde.';
  }

  @override
  String get maintenanceFieldName => 'Nombre';

  @override
  String get maintenanceFieldNameHint => 'p. ej., Cambiar filtro HEPA';

  @override
  String get maintenanceFieldIntervalType => 'Tipo de intervalo';

  @override
  String get maintenanceFieldInterval => 'Intervalo';

  @override
  String get maintenanceIntervalHours => 'Horas de impresión';

  @override
  String get maintenanceIntervalDays => 'Días';

  @override
  String get maintenanceIntervalInvalid => 'Introduce un valor ≥ 1';

  @override
  String get maintenanceFieldIcon => 'Icono';

  @override
  String get maintenanceFieldDocLink => 'Enlace a la documentación (opcional)';

  @override
  String get maintenanceAssignPrinters => 'Asignar a impresoras';

  @override
  String get maintenanceSelectPrinter => 'Selecciona al menos una impresora';

  @override
  String get notifEvtMaintenance => 'Mantenimiento pendiente';

  @override
  String get notifEvtMaintenanceDesc =>
      'Cuando vence una tarea de mantenimiento';

  @override
  String get maintenanceNotifTitle => 'Mantenimiento pendiente';

  @override
  String maintenanceNotifBody(String printer, String task) {
    return '$printer: $task';
  }

  @override
  String get maintenanceReminderTitle => 'Recordatorio de mantenimiento';

  @override
  String maintenanceReminderBody(String printer, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'tareas de mantenimiento vencidas',
      one: 'tarea de mantenimiento vencida',
    );
    return '$printer tiene $count $_temp0';
  }

  @override
  String get maintenanceNotifAction => 'Marcar como completada';

  @override
  String get navMenu => 'Menú';

  @override
  String get menuStatistics => 'Estadísticas';

  @override
  String get statsTitle => 'Estadísticas';

  @override
  String get statsRangeAllTime => 'Histórico';

  @override
  String get statsRangeLast7Days => 'Últimos 7 días';

  @override
  String get statsRangeLast30Days => 'Últimos 30 días';

  @override
  String get statsRangeLast90Days => 'Últimos 90 días';

  @override
  String get statsRangeThisYear => 'Este año';

  @override
  String get statsRangeCustom => 'Intervalo personalizado';

  @override
  String get statsEmpty => 'No hay impresiones en este periodo';

  @override
  String get statsLoadFailed => 'No se pudieron cargar las estadísticas';

  @override
  String get statsOverview => 'Resumen';

  @override
  String get statsTotalPrints => 'Impresiones totales';

  @override
  String get statsPrintTime => 'Tiempo de impresión';

  @override
  String get statsFilamentUsed => 'Filamento usado';

  @override
  String get statsFilamentCost => 'Coste de filamento';

  @override
  String get statsEnergyUsed => 'Energía consumida';

  @override
  String get statsEnergyCost => 'Coste energético';

  @override
  String get statsTotalCost => 'Coste total';

  @override
  String get statsEnergyWarmingUp =>
      'Los datos de energía aún se están recopilando';

  @override
  String get statsSuccessRate => 'Tasa de éxito';

  @override
  String statsSuccessful(int count) {
    return 'Exitosas: $count';
  }

  @override
  String statsFailed(int count) {
    return 'Fallidas: $count';
  }

  @override
  String statsCancelled(int count) {
    return 'Canceladas: $count';
  }

  @override
  String get statsAllUsers => 'Todos los usuarios';

  @override
  String get statsNoUser => 'Sin usuario (Sistema)';

  @override
  String get statsTimeAccuracy => 'Precisión del tiempo';

  @override
  String get statsTimeAccuracyHint => '100 % = estimación perfecta';

  @override
  String get statsByMaterial => 'Impresiones por material';

  @override
  String get statsByPrinter => 'Impresiones por impresora';

  @override
  String get statsTimeAccuracyByPrinter => 'Precisión del tiempo por impresora';

  @override
  String statsPrintsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impresiones',
      one: '$count impresión',
    );
    return '$_temp0';
  }

  @override
  String statsHours(String hours) {
    return '$hours h';
  }

  @override
  String statsPrinterFallback(String id) {
    return 'Impresora #$id';
  }

  @override
  String get statsMetricWeight => 'Peso';

  @override
  String get statsMetricPrints => 'Impresiones';

  @override
  String get statsMetricTime => 'Tiempo';

  @override
  String get statsFailureAnalysis => 'Análisis de fallos';

  @override
  String get statsFailureRate => 'Tasa de fallos';

  @override
  String statsFailurePeriod(int days) {
    return 'Últimos $days días';
  }

  @override
  String statsFailedOfTotal(int failed, int total) {
    return '$failed / $total impresiones fallidas';
  }

  @override
  String get statsTopFailureReasons => 'Principales causas de fallo';

  @override
  String get statsNoFailures => 'Sin fallos en este periodo';

  @override
  String get statsPrintActivity => 'Actividad de impresión';

  @override
  String get statsHeatmapLess => 'Menos';

  @override
  String get statsHeatmapMore => 'Más';

  @override
  String get statsRecords => 'Récords';

  @override
  String get statsLongestPrint => 'Impresión más larga';

  @override
  String get statsHeaviestPrint => 'Impresión más pesada';

  @override
  String get statsMostExpensive => 'Impresión más costosa';

  @override
  String get statsBusiestDay => 'Día con más actividad';

  @override
  String get statsSuccessStreak => 'Racha de éxitos';

  @override
  String statsConsecutive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count consecutivas',
      one: '$count consecutiva',
    );
    return '$_temp0';
  }

  @override
  String get statsFilamentTrends => 'Tendencias de filamento';

  @override
  String get statsPeriodFilament => 'Filamento del periodo';

  @override
  String get statsPeriodCost => 'Coste del periodo';

  @override
  String get statsAvgPerPrint => 'Media por impresión';

  @override
  String get statsUsageOverTime => 'Uso a lo largo del tiempo';

  @override
  String get statsEnergyOverTime => 'Energía a lo largo del tiempo';

  @override
  String get statsMostEnergy => 'Mayor consumo de energía';

  @override
  String statsKwh(String value) {
    return '$value kWh';
  }

  @override
  String get statsByMaterialTitle => 'Por material';

  @override
  String get statsSuccessByMaterial => 'Éxito por material';

  @override
  String get statsColorDistribution => 'Distribución de colores';

  @override
  String get statsColorShareHint =>
      'Proporción de filamento utilizado, por peso';

  @override
  String statsColorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'colores',
      one: 'color',
    );
    return '$count $_temp0';
  }

  @override
  String statsMoreCount(int count) {
    return '+$count más';
  }

  @override
  String get statsPrintDuration => 'Duración de impresión';

  @override
  String get statsPrintHabits => 'Hábitos de impresión';

  @override
  String get statsPrintTimeOfDay => 'Hora del día de impresión';

  @override
  String get aboutMenu => 'Acerca de';

  @override
  String get aboutTitle => 'Acerca de';

  @override
  String get aboutTagline =>
      'Cliente nativo de Android para Bambuddy: un gestor de impresoras Bambu Lab autoalojado.';

  @override
  String appVersionLabel(String version) {
    return 'App $version';
  }

  @override
  String serverVersionLabel(String version) {
    return 'Servidor $version';
  }

  @override
  String get serverVersionUnknown => 'Versión del servidor desconocida';

  @override
  String get aboutLicenseHeader => 'Licencia';

  @override
  String get aboutLicenseBody =>
      'Bambuddy es software libre publicado bajo la GNU Affero General Public License v3.0 (AGPL-3.0). Puedes usarlo, estudiarlo, compartirlo y modificarlo; si ejecutas una versión modificada como servicio de red, debes ofrecer su código fuente a sus usuarios.';

  @override
  String get aboutViewLicense => 'Leer la licencia AGPL-3.0';

  @override
  String get aboutSourceHeader => 'Código fuente';

  @override
  String get aboutSourceBody =>
      'El código fuente completo está disponible en GitHub.';

  @override
  String get aboutSourceLink => 'Repositorio de código abierto';

  @override
  String get aboutThirdParty => 'Licencias de código abierto';

  @override
  String get aboutThirdPartySubtitle =>
      'Licencias de las bibliotecas incluidas';

  @override
  String get aboutOpenLinkError => 'No se pudo abrir el enlace';

  @override
  String get fileManagerMenu => 'Gestor de archivos';

  @override
  String get fileManagerTitle => 'Gestor de archivos';

  @override
  String get fmRoot => 'Todos los archivos';

  @override
  String get fmSearchHint => 'Buscar archivos…';

  @override
  String get fmEmpty => 'Esta carpeta está vacía';

  @override
  String get fmNoMatches => 'Ningún archivo coincide con los filtros';

  @override
  String get fmSortBy => 'Ordenar por';

  @override
  String get fmSortDateNewest => 'Más recientes primero';

  @override
  String get fmSortDateOldest => 'Más antiguos primero';

  @override
  String get fmSortNameAZ => 'Nombre A–Z';

  @override
  String get fmSortNameZA => 'Nombre Z–A';

  @override
  String get fmSortSizeLargest => 'Más grandes primero';

  @override
  String get fmSortSizeSmallest => 'Más pequeños primero';

  @override
  String get fmFilterType => 'Tipo de archivo';

  @override
  String get fmAllTypes => 'Todos los tipos';

  @override
  String get fmNewFolder => 'Nueva carpeta';

  @override
  String get fmFolderName => 'Nombre de la carpeta';

  @override
  String get fmFileName => 'Nombre del archivo';

  @override
  String get fmSave => 'Guardar';

  @override
  String get fmRename => 'Renombrar';

  @override
  String get fmRenameFolder => 'Renombrar carpeta';

  @override
  String get fmRenameFile => 'Renombrar archivo';

  @override
  String get fmRenamed => 'Renombrado';

  @override
  String get fmFolderCreated => 'Carpeta creada';

  @override
  String get fmDelete => 'Eliminar';

  @override
  String get fmDeleted => 'Movido a la papelera';

  @override
  String get fmDeleteFile => 'Eliminar archivo';

  @override
  String fmDeleteFileConfirm(String name) {
    return '¿Mover “$name” a la papelera?';
  }

  @override
  String get fmDeleteFolder => 'Eliminar carpeta';

  @override
  String fmDeleteFolderConfirm(String name) {
    return '¿Eliminar la carpeta “$name” y todo su contenido?';
  }

  @override
  String fmDeleteSelectedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'archivos',
      one: 'archivo',
    );
    return '¿Mover $count $_temp0 a la papelera?';
  }

  @override
  String get fmMoveTo => 'Mover a…';

  @override
  String get fmMoved => 'Movido';

  @override
  String fmFolderItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'elementos',
      one: 'elemento',
    );
    return '$count $_temp0';
  }

  @override
  String get fmPrint => 'Imprimir';

  @override
  String get fmAddToQueue => 'Añadir a la cola';

  @override
  String get fmAddedToQueue => 'Añadido a la cola';

  @override
  String get fmGroupAsVariants => 'Agrupar como alternativas';

  @override
  String get fmQueueAsVariants => 'Añadir a la cola como un solo trabajo';

  @override
  String get fmUngroupVariants => 'Desagrupar alternativas';

  @override
  String fmVariantsGrouped(int count) {
    return '$count archivos agrupados como alternativas';
  }

  @override
  String get fmVariantsUngrouped => 'Alternativas desagrupadas';

  @override
  String fmVariantsMemberCount(int count) {
    return '$count alternativas';
  }

  @override
  String get fmVariantsGone => 'Este grupo ya no existe';

  @override
  String get fmUpload => 'Subir archivo';

  @override
  String get fmUploading => 'Subiendo…';

  @override
  String fmUploaded(String name) {
    return 'Subido $name';
  }

  @override
  String get fmUploadFailed => 'Error al subir';

  @override
  String fmSelectedCount(int count) {
    return '$count seleccionados';
  }

  @override
  String fmStatsFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'archivos',
      one: 'archivo',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'carpetas',
      one: 'carpeta',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFree(String size) {
    return '$size libre';
  }

  @override
  String get fmTrash => 'Papelera';

  @override
  String get fmTrashTitle => 'Papelera';

  @override
  String get fmTrashEmpty => 'La papelera está vacía';

  @override
  String get fmRestore => 'Restaurar';

  @override
  String get fmRestored => 'Restaurado';

  @override
  String get fmEmptyTrash => 'Vaciar papelera';

  @override
  String get fmEmptyTrashConfirm =>
      '¿Eliminar permanentemente todos los archivos de la papelera? Esta acción no se puede deshacer.';

  @override
  String get fmHardDelete => 'Eliminar permanentemente';

  @override
  String fmHardDeleteConfirm(String name) {
    return '¿Eliminar permanentemente “$name”? Esta acción no se puede deshacer.';
  }

  @override
  String get fmDeletedForever => 'Eliminado permanentemente';

  @override
  String get fmTags => 'Etiquetas';

  @override
  String get fmTagsFilterTitle => 'Filtrar por etiquetas';

  @override
  String get fmTagsFilterHint =>
      'Las etiquetas buscan en toda la biblioteca — se ignora la carpeta actual.';

  @override
  String get fmTagsManage => 'Gestionar etiquetas';

  @override
  String get fmTagsEmpty => 'Aún no hay etiquetas';

  @override
  String get fmTagsNone => 'Sin etiquetas';

  @override
  String get fmTagsApply => 'Aplicar';

  @override
  String get fmTagNew => 'Nueva etiqueta';

  @override
  String get fmTagName => 'Nombre de la etiqueta';

  @override
  String get fmTagRename => 'Renombrar etiqueta';

  @override
  String get fmTagDelete => 'Eliminar etiqueta';

  @override
  String fmTagDeleteConfirm(String name) {
    return '¿Eliminar la etiqueta “$name”? Los archivos conservarán todo lo demás — solo perderán esta etiqueta.';
  }

  @override
  String get fmTagCreated => 'Etiqueta creada';

  @override
  String get fmTagDeleted => 'Etiqueta eliminada';

  @override
  String get fmTagExists => 'Ya existe una etiqueta con este nombre';

  @override
  String get fmTagsSaved => 'Etiquetas actualizadas';

  @override
  String fmTagsPartial(int count, int total) {
    return 'Se actualizaron $count de $total archivos — no puedes editar el resto';
  }

  @override
  String fmTagsBulkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'archivos',
      one: 'archivo',
    );
    return 'Etiquetar $count $_temp0';
  }

  @override
  String get fmTagsAdd => 'Añadir';

  @override
  String get fmTagsRemove => 'Quitar';

  @override
  String get fmTagsReplace => 'Reemplazar';

  @override
  String fmTagsReplaceConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'archivos',
      one: 'archivo',
    );
    return '¿Reemplazar todas las etiquetas de $count $_temp0 por las seleccionadas?';
  }

  @override
  String get fmTagsPickSome => 'Elige al menos una etiqueta';

  @override
  String get makerworldMenu => 'MakerWorld';

  @override
  String get makerworldTitle => 'MakerWorld';

  @override
  String get mwIntro =>
      'Pega la URL de un modelo de MakerWorld para importarlo e imprimirlo directamente desde Bambuddy.';

  @override
  String get mwUrlHint =>
      'https://makerworld.com/en/models/… o cualquier enlace de MakerWorld';

  @override
  String get mwResolve => 'Resolver';

  @override
  String get mwEnterUrl => 'Introduce una URL de MakerWorld';

  @override
  String get mwUntitledModel => 'Modelo sin título';

  @override
  String mwPlatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count placas',
      one: '1 placa',
      zero: 'Sin placas',
    );
    return '$_temp0';
  }

  @override
  String get mwNoPlates => 'No se encontraron placas para este modelo.';

  @override
  String get mwImport => 'Importar';

  @override
  String mwShowAllPlates(int count) {
    return 'Mostrar las $count placas';
  }

  @override
  String get mwShowLess => 'Mostrar menos';

  @override
  String get mwInLibrary => 'En la biblioteca';

  @override
  String get mwImported => 'Importado a tu biblioteca';

  @override
  String get mwAlreadyInLibrary => 'Ya está en tu biblioteca';

  @override
  String get mwViewInFiles => 'Ver en el administrador de archivos';

  @override
  String get mwRecentImports => 'Importaciones recientes';

  @override
  String get mwNoRecent => 'Aún no hay importaciones recientes';

  @override
  String get mwOpenOnMakerworld => 'Abrir en MakerWorld';

  @override
  String get mwLoginRequired =>
      'Inicia sesión en tu cuenta de Bambu Cloud para descargar modelos de MakerWorld.';

  @override
  String get cloudAccountMenu => 'Cuenta de Bambu Cloud';

  @override
  String get cloudAccountTitle => 'Bambu Cloud';

  @override
  String get cloudCredsNote =>
      'Inicia sesión con tu cuenta de Bambu Lab. Estas credenciales se utilizan únicamente para descargar modelos de MakerWorld.';

  @override
  String get cloudEmail => 'Correo electrónico';

  @override
  String get cloudPassword => 'Contraseña';

  @override
  String get cloudRegionGlobal => 'Global';

  @override
  String get cloudRegionChina => 'China';

  @override
  String get cloudSignIn => 'Iniciar sesión';

  @override
  String get cloudSignOut => 'Cerrar sesión';

  @override
  String get cloudSignedIn => 'Sesión iniciada';

  @override
  String get cloudSignedInOk => 'Sesión iniciada en Bambu Cloud';

  @override
  String get cloudSignInFailed => 'Error al iniciar sesión';

  @override
  String get cloudFillCredentials =>
      'Introduce tu correo electrónico y contraseña';

  @override
  String get cloudVerify => 'Verificar';

  @override
  String get cloudVerificationCode => 'Código de verificación';

  @override
  String get cloudVerificationPrompt =>
      'Introduce el código de verificación para completar el inicio de sesión.';

  @override
  String get cloudEnterCode => 'Introduce el código de verificación';

  @override
  String get swatchCodesMenu => 'Códigos de muestras';

  @override
  String get swatchCodesTitle => 'Códigos de muestras';

  @override
  String get swatchSearchHint => 'Buscar por código o nombre';

  @override
  String get swatchSectionCodes => 'Códigos';

  @override
  String get swatchSectionUncoded => 'Filamentos del inventario sin código';

  @override
  String get swatchNoCodes => 'Aún no hay códigos de muestras';

  @override
  String get swatchNoCodesHint =>
      'Crea un código para etiquetar una muestra de filamento.';

  @override
  String swatchNoMatch(String query) {
    return 'Ningún código coincide con “$query”';
  }

  @override
  String get swatchAllCoded =>
      'Todos los filamentos del inventario tienen código';

  @override
  String get swatchNewCode => 'Nuevo código';

  @override
  String get swatchGenerate => 'Generar';

  @override
  String get swatchGenerateCode => 'Generar código';

  @override
  String get swatchExists => 'Ese filamento ya tiene un código';

  @override
  String swatchCreatedSnack(String code) {
    return 'Código $code creado';
  }

  @override
  String swatchUpdatedSnack(String code) {
    return 'Código $code actualizado';
  }

  @override
  String swatchCopied(String code) {
    return '$code copiado';
  }

  @override
  String get swatchDelete => 'Eliminar';

  @override
  String get swatchDeleteTitle => '¿Eliminar código?';

  @override
  String swatchDeleteBody(String code, String name) {
    return 'Se eliminará el código $code para $name.';
  }

  @override
  String get swatchExport => 'Exportar';

  @override
  String get swatchImport => 'Importar';

  @override
  String get swatchExportEmpty => 'No hay códigos para exportar';

  @override
  String swatchExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count códigos exportados',
      one: '1 código exportado',
    );
    return '$_temp0';
  }

  @override
  String get swatchExportFailed => 'Error al exportar';

  @override
  String get swatchImportTitle => '¿Importar códigos?';

  @override
  String swatchImportWarning(int existing, int incoming) {
    return 'Esto reemplazará los $existing códigos existentes por los $incoming códigos del archivo. Esta acción no se puede deshacer.';
  }

  @override
  String get swatchImportConfirm => 'Reemplazar todo';

  @override
  String swatchImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count códigos importados',
      one: '1 código importado',
    );
    return '$_temp0';
  }

  @override
  String get swatchImportFailed => 'No se pudo leer el archivo';

  @override
  String get swatchImportEmpty => 'No se encontraron códigos en el archivo';

  @override
  String get swatchFormTitle => 'Nuevo código de muestra';

  @override
  String get swatchEditTitle => 'Editar código';

  @override
  String get swatchSave => 'Guardar';

  @override
  String get swatchRegenerate => 'Regenerar';

  @override
  String get swatchFieldCode => 'Código';

  @override
  String get swatchCodeInvalid =>
      'Usa 6 caracteres: dígitos y letras, sin 0, 1, I, L ni O';

  @override
  String get swatchCodeTaken => 'Ese código ya está en uso';

  @override
  String get swatchFieldBrand => 'Fabricante';

  @override
  String get swatchFieldMaterial => 'Material';

  @override
  String get swatchFieldVariant => 'Variante';

  @override
  String get swatchFieldColor => 'Color';

  @override
  String get swatchFieldHex => 'Color hexadecimal';

  @override
  String get swatchMaterialRequired => 'El material es obligatorio';

  @override
  String get swatchNoCatalogColors =>
      'No hay colores de catálogo disponibles. Introduce el nombre del color y el código hexadecimal manualmente.';

  @override
  String get projectsMenu => 'Proyectos';

  @override
  String get projectsTitle => 'Proyectos';

  @override
  String get projectsEmpty => 'Aún no hay proyectos';

  @override
  String get projectsFilterAll => 'Todos';

  @override
  String get projectCreate => 'Nuevo proyecto';

  @override
  String get projectEdit => 'Editar proyecto';

  @override
  String get projectDelete => 'Eliminar';

  @override
  String get projectDeleteTitle => '¿Eliminar proyecto?';

  @override
  String projectDeleteBody(String name) {
    return '“$name” se eliminará. Las impresiones vinculadas permanecerán en el archivo.';
  }

  @override
  String get projectDeleted => 'Proyecto eliminado';

  @override
  String get projectDeleteFailed => 'No se pudo eliminar el proyecto';

  @override
  String get projectSaved => 'Proyecto guardado';

  @override
  String get projectName => 'Nombre';

  @override
  String get projectNameRequired => 'El nombre es obligatorio';

  @override
  String get projectDescription => 'Descripción';

  @override
  String get projectNotes => 'Notas';

  @override
  String get projectStatus => 'Estado';

  @override
  String get projectPriority => 'Prioridad';

  @override
  String get projectColor => 'Color';

  @override
  String get projectDueDate => 'Fecha límite';

  @override
  String get projectDueDateClear => 'Borrar';

  @override
  String get projectBudget => 'Presupuesto';

  @override
  String get projectTargetCount => 'Objetivo de placas';

  @override
  String get projectTargetPartsCount => 'Objetivo de piezas';

  @override
  String get projectTargetSets => 'Objetivo de juegos';

  @override
  String get projectTargetSetsHint =>
      'Cuántas veces se debe imprimir cada archivo del proyecto';

  @override
  String get projectTags => 'Etiquetas (separadas por comas)';

  @override
  String get projectUrl => 'Enlace';

  @override
  String get projectParent => 'Proyecto principal';

  @override
  String get projectParentNone => 'Ninguno';

  @override
  String get projectSave => 'Guardar';

  @override
  String get projectStatusPlanning => 'Planificación';

  @override
  String get projectStatusActive => 'Activo';

  @override
  String get projectStatusOnHold => 'En espera';

  @override
  String get projectStatusCompleted => 'Completado';

  @override
  String get projectStatusArchived => 'Archivado';

  @override
  String get projectPriorityLow => 'Baja';

  @override
  String get projectPriorityNormal => 'Normal';

  @override
  String get projectPriorityHigh => 'Alta';

  @override
  String get projectPriorityUrgent => 'Urgente';

  @override
  String get projectTabOverview => 'Resumen';

  @override
  String get projectTabArchives => 'Archivos';

  @override
  String get projectTabBom => 'BOM';

  @override
  String get projectTabQueue => 'Cola';

  @override
  String get projectTabTimeline => 'Cronología';

  @override
  String get projectTabFiles => 'Archivos';

  @override
  String get projectTabAttachments => 'Adjuntos';

  @override
  String get projectStatsTitle => 'Estadísticas';

  @override
  String get projectStatProgress => 'Progreso';

  @override
  String get projectStatPartsProgress => 'Piezas';

  @override
  String get projectStatSets => 'Juegos completos';

  @override
  String projectSetsOfTarget(int done, int target) {
    return '$done de $target';
  }

  @override
  String get projectStatPrints => 'Placas';

  @override
  String get projectStatCompleted => 'Completados';

  @override
  String get projectStatFailed => 'Fallidos';

  @override
  String get projectStatQueued => 'En cola';

  @override
  String get projectStatInProgress => 'En curso';

  @override
  String get projectStatPrintTime => 'Tiempo de impresión';

  @override
  String get projectStatFilament => 'Filamento';

  @override
  String get projectStatCost => 'Coste est.';

  @override
  String get projectStatEnergy => 'Energía';

  @override
  String get projectStatEnergyCost => 'Coste de energía';

  @override
  String get projectStatRemaining => 'Restante';

  @override
  String get projectStatBom => 'BOM';

  @override
  String get projectChildren => 'Subproyectos';

  @override
  String get projectNoDescription => 'Sin descripción';

  @override
  String projectDueOn(String date) {
    return 'Fecha límite: $date';
  }

  @override
  String get projectAddArchives => 'Añadir archivos';

  @override
  String get projectRemoveArchive => 'Quitar del proyecto';

  @override
  String get projectArchivesEmpty => 'No hay archivos vinculados';

  @override
  String get projectArchiveRemoved => 'Eliminado del proyecto';

  @override
  String get archiveAddToProject => 'Añadir al proyecto';

  @override
  String get projectArchivesAdded => 'Añadido al proyecto';

  @override
  String get projectPickTitle => 'Elige un proyecto';

  @override
  String get projectBomEmpty => 'No hay elementos en el BOM';

  @override
  String get bomAdd => 'Añadir elemento';

  @override
  String get bomEditTitle => 'Editar elemento';

  @override
  String get bomAddTitle => 'Nuevo elemento';

  @override
  String get bomName => 'Nombre';

  @override
  String get bomQtyNeeded => 'Cantidad';

  @override
  String get bomQtyAcquired => 'Adquirido';

  @override
  String get bomUnitPrice => 'Precio unitario';

  @override
  String get bomSourcingUrl => 'URL de origen';

  @override
  String get bomRemarks => 'Observaciones';

  @override
  String get bomComplete => 'Completado';

  @override
  String get bomDelete => 'Eliminar elemento';

  @override
  String get bomDeleted => 'Elemento eliminado';

  @override
  String get projectQueueEmpty => 'No hay elementos en la cola';

  @override
  String get projectTimelineEmpty => 'Aún no hay eventos';

  @override
  String get projectAttachmentsEmpty => 'Sin adjuntos';

  @override
  String get projectFilesEmpty => 'Sin archivos imprimibles';

  @override
  String get projectAttachmentUpload => 'Subir archivo';

  @override
  String get projectAttachmentDownload => 'Descargar';

  @override
  String get projectAttachmentDelete => 'Eliminar';

  @override
  String get projectAttachmentDeleted => 'Adjunto eliminado';

  @override
  String get projectAttachmentUploaded => 'Adjunto subido';

  @override
  String projectFileSaved(String path) {
    return 'Guardado en $path';
  }

  @override
  String get projectDownloadFailed => 'Error al descargar';

  @override
  String get projectCoverUpload => 'Establecer imagen de portada';

  @override
  String get projectCoverDelete => 'Eliminar imagen de portada';

  @override
  String get projectCoverUpdated => 'Portada actualizada';

  @override
  String get projectCoverRemoved => 'Portada eliminada';

  @override
  String get projectMenuExport => 'Exportar';

  @override
  String get projectMenuCreateTemplate => 'Guardar como plantilla';

  @override
  String get projectMenuImport => 'Importar proyecto';

  @override
  String get projectFromTemplate => 'Crear desde plantilla';

  @override
  String get projectTemplateNone => 'Sin plantillas';

  @override
  String get projectTemplatePickTitle => 'Elegir una plantilla';

  @override
  String get projectTemplateNamePrompt => 'Nombre del nuevo proyecto';

  @override
  String projectExported(String path) {
    return 'Exportado a $path';
  }

  @override
  String get projectExportFailed => 'Error al exportar';

  @override
  String get projectTemplateCreated => 'Plantilla creada';

  @override
  String get projectImported => 'Proyecto importado';

  @override
  String get projectImportFailed => 'Error al importar';

  @override
  String get projectUploading => 'Subiendo…';

  @override
  String get projectLinkFolder => 'Vincular carpeta';

  @override
  String get projectNoFoldersToLink =>
      'No hay carpetas disponibles para vincular';

  @override
  String get projectUnlinkFolder => 'Desvincular carpeta';

  @override
  String get projectFolderLinked => 'Carpeta vinculada';

  @override
  String get projectFolderUnlinked => 'Carpeta desvinculada';

  @override
  String get projectNotesEmpty => 'Aún no hay notas';

  @override
  String projectFolderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos',
      one: '$count archivo',
    );
    return '$_temp0';
  }

  @override
  String projectRemainingShort(int count) {
    return 'Quedan $count';
  }

  @override
  String get sliceAction => 'Laminar';

  @override
  String get sliceTitle => 'Laminar archivo';

  @override
  String get slicePrinter => 'Impresora';

  @override
  String get sliceProcess => 'Proceso / Calidad';

  @override
  String get sliceBedType => 'Placa de impresión';

  @override
  String get sliceBedDefault => 'Predeterminada (del preajuste)';

  @override
  String get sliceFilament => 'Filamento';

  @override
  String sliceFilamentNumbered(String n) {
    return 'Filamento $n';
  }

  @override
  String get sliceAutoOrient => 'Orientación automática';

  @override
  String get sliceAutoOrientHint =>
      'Gira cada objeto hacia su mejor cara de impresión.';

  @override
  String get sliceAutoArrange => 'Distribución automática';

  @override
  String get sliceAutoArrangeHint =>
      'Vuelve a distribuir los objetos sobre la placa.';

  @override
  String sliceDesignedFor(String printer) {
    return 'Este archivo es para $printer';
  }

  @override
  String get sliceUseDesignedPrinter => 'Cambiar';

  @override
  String get sliceAsDesigned => 'Usar los ajustes propios del archivo';

  @override
  String get sliceAsDesignedHint =>
      'Los ajustes del diseñador en lugar de los perfiles anteriores.';

  @override
  String get sliceAsDesignedInactive => 'No se usa — el archivo decide';

  @override
  String get sliceFilamentUnused => 'No se usa en esta placa';

  @override
  String get processSettingsTitle => 'Ajustes de proceso';

  @override
  String get sliceProcessSettingsNeedsProcess =>
      'Elige primero un preajuste de proceso';

  @override
  String get sliceProcessSettingsUnchanged => 'Usando el preajuste tal cual';

  @override
  String sliceProcessSettingsChanged(int count) {
    return '$count modificados';
  }

  @override
  String get processSettingsModeSimple => 'Simple';

  @override
  String get processSettingsModeAdvanced => 'Avanzado';

  @override
  String get processSettingsModeExpert => 'Experto';

  @override
  String get processSettingsSearchHint => 'Buscar ajustes';

  @override
  String get processSettingsNoMatches =>
      'Ningún ajuste coincide con esta búsqueda.';

  @override
  String get processSettingsRevert => 'Restablecer al valor del preajuste';

  @override
  String processSettingsRevertAll(int count) {
    return 'Restablecer $count';
  }

  @override
  String processSettingsOutOfRange(String range) {
    return 'El laminador acepta $range';
  }

  @override
  String get processSettingsDisabledHint =>
      'El laminador ignora esto con tus ajustes actuales.';

  @override
  String get processSettingsUnavailable =>
      'Este servidor no puede informar los ajustes de proceso para el preajuste seleccionado.';

  @override
  String get processSettingsDefaultsOutdatedSidecar =>
      'Mostrando valores predeterminados del laminador: el sidecar del laminador es anterior a esta función y no puede consultar los valores del preajuste. Actualiza la imagen del sidecar para verlos. Todo lo que no modifiques seguirá usando el preajuste.';

  @override
  String get processSettingsDefaultsNotConfigured =>
      'Mostrando valores predeterminados del laminador: no hay ningún sidecar del laminador configurado, por lo que no se pueden leer los valores del preajuste. Todo lo que no modifiques seguirá usando el preajuste.';

  @override
  String get processSettingsDefaultsSidecarUnavailable =>
      'Mostrando valores predeterminados del laminador: el sidecar del laminador no respondió, por lo que no se pueden leer los valores del preajuste. Todo lo que no modifiques seguirá usando el preajuste.';

  @override
  String get processSettingsDefaultsUnavailable =>
      'Mostrando valores predeterminados del laminador: no se pudieron leer los valores propios del preajuste seleccionado. Todo lo que no modifiques seguirá usando el preajuste.';

  @override
  String get processSettingsFilamentDefault =>
      'Predeterminado (el filamento propio de la región)';

  @override
  String processSettingsFilamentSlot(String slot, String name) {
    return '$slot: $name';
  }

  @override
  String processSettingsFilamentSlotMissing(String slot) {
    return 'Ranura $slot — este archivo no tiene esa ranura';
  }

  @override
  String get sliceSelect => 'Toca para seleccionar';

  @override
  String get sliceStart => 'Laminar';

  @override
  String get sliceShowAll => 'Todos';

  @override
  String get sliceSearchHint => 'Buscar preajustes';

  @override
  String get sliceOwnedEmpty =>
      'No hay preajustes coincidentes para tu impresora y filamentos. Activa “Todos” para explorar el catálogo completo.';

  @override
  String get sliceNoPresets => 'No hay preajustes disponibles';

  @override
  String get sliceInProgress => 'Laminando…';

  @override
  String get sliceDone => 'Laminación completada';

  @override
  String get sliceFailed => 'Error al laminar';

  @override
  String get sliceExternalFallback =>
      'Guardado en la biblioteca del servidor — la carpeta propia del archivo no pudo alojarlo.';

  @override
  String get sliceExternalReadonly =>
      'Esa carpeta está configurada como de solo lectura.';

  @override
  String get sliceExternalNoPath =>
      'Esa carpeta no tiene ninguna ruta configurada.';

  @override
  String get sliceExternalUnreachable =>
      'La ruta de esa carpeta no es accesible ahora mismo.';

  @override
  String get sliceExternalNotWritable =>
      'El servidor no puede escribir en esa carpeta.';

  @override
  String get sliceExternalInvalidName =>
      'Esa carpeta no aceptó el nombre del archivo.';

  @override
  String get sliceClose => 'Cerrar';

  @override
  String sliceResultTime(String time) {
    return 'Tiempo estimado: $time';
  }

  @override
  String get sliceRefusedStep =>
      'Los archivos STEP no se pueden laminar. Exporta primero el modelo como STL o 3MF desde tu CAD.';

  @override
  String get sliceRefusedFormat => 'El archivo de origen debe ser STL o 3MF.';

  @override
  String get sliceRefusedNoSource =>
      'Este archivo solo conservó el G-code que imprimió, no el modelo — no hay nada que volver a laminar.';

  @override
  String sliceResultFilament(String grams) {
    return 'Filamento: $grams g';
  }

  @override
  String get sliceTierLocal => 'Preajuste local';

  @override
  String get sliceTierCloud => 'Bambu Cloud';

  @override
  String get sliceTierOrcaCloud => 'Orca Cloud';

  @override
  String get sliceTierStandard => 'Integrado';

  @override
  String get pipelineSection => 'Pipeline';

  @override
  String get pipelineApply => 'Aplicar pipeline…';

  @override
  String get pipelineApplyEmpty => 'Sin pipelines guardados';

  @override
  String pipelineApplied(String name) {
    return 'Se aplicó “$name”';
  }

  @override
  String get pipelineSaveAs => 'Guardar como pipeline';

  @override
  String get pipelineNameHint => 'Nombre del pipeline';

  @override
  String get pipelineSaveConfirm => 'Guardar';

  @override
  String get pipelineSaved => 'Pipeline guardado';

  @override
  String get pipelineSaveHint =>
      'La impresora, el proceso, los filamentos y la placa anteriores, bajo un nombre que puedes reutilizar en el siguiente archivo.';

  @override
  String get pipelinesMenu => 'Pipelines';

  @override
  String get pipelinesTitle => 'Pipelines';

  @override
  String get pipelinesEmpty => 'Aún no hay pipelines';

  @override
  String get pipelinesEmptyHint =>
      'Guarda uno desde el formulario de laminado: impresora, proceso, filamentos y placa en un paquete que puedes aplicar con un solo toque.';

  @override
  String get pipelineProfiles => 'Perfiles';

  @override
  String pipelineFilamentsCount(int count) {
    return 'Filamentos ($count)';
  }

  @override
  String get pipelineHistory => 'Historial de ejecuciones';

  @override
  String get pipelineCardActions => 'Acciones del pipeline';

  @override
  String pipelineSlotNumbered(int n) {
    return 'Filamento $n';
  }

  @override
  String get pipelineBed => 'Placa';

  @override
  String get pipelinePresetGone => 'Ya no está en el catálogo';

  @override
  String get pipelineNeedsTarget =>
      'Define un destino antes de ejecutar este pipeline.';

  @override
  String get pipelineNoTargetChip => 'Sin destino';

  @override
  String get pipelineEditTitle => 'Editar pipeline';

  @override
  String get pipelineDescriptionHint => 'Descripción (opcional)';

  @override
  String get pipelineTargetType => 'Destino';

  @override
  String get pipelineTargetSpecific => 'Una impresora';

  @override
  String get pipelineTargetClass => 'Modelo de impresora';

  @override
  String get pipelineTargetPickPrinter => 'Elegir una impresora';

  @override
  String get pipelineTargetPickClass => 'Elegir un modelo';

  @override
  String get pipelineTargetNone => '— sin destino —';

  @override
  String pipelineTargetPrinterGone(int id) {
    return 'Impresora #$id (ya no existe)';
  }

  @override
  String get pipelineFanout => 'Distribución de copias';

  @override
  String get pipelineFanoutMaxParallel =>
      'Máximo en paralelo — en cualquier impresora compatible inactiva';

  @override
  String get pipelineFanoutRoundRobin =>
      'Round robin — rotar entre impresoras compatibles';

  @override
  String get pipelineFanoutFillOneFirst =>
      'Llenar primero una — todas las copias en una sola impresora';

  @override
  String get pipelineDelete => 'Eliminar pipeline';

  @override
  String pipelineDeleteConfirm(String name) {
    return '¿Eliminar “$name”? Las ejecuciones ya realizadas conservarán su nombre.';
  }

  @override
  String get pipelineDeleted => 'Pipeline eliminado';

  @override
  String get pipelineDescriptionNoClear =>
      'Una descripción no se puede vaciar una vez guardada — este servidor solo puede escribir una nueva.';

  @override
  String get pipelineRun => 'Ejecutar';

  @override
  String pipelineRunTitle(String name) {
    return 'Ejecutar “$name”';
  }

  @override
  String get pipelineRunCopies => 'Copias';

  @override
  String get pipelineRunStart => 'Iniciar';

  @override
  String get pipelineRunStarted => 'Ejecución iniciada';

  @override
  String get pipelineRunAnyway => 'Ejecutar de todos modos';

  @override
  String pipelineRunMaxCopies(int max) {
    return 'Este servidor permite un máximo de $max.';
  }

  @override
  String get pipelineCheckingEligibility => 'Comprobando impresoras…';

  @override
  String get pipelineEligibilityOk => 'Listo para ejecutar.';

  @override
  String pipelineEligibilityClassCount(int ok, int total) {
    return '$ok de $total impresoras listas';
  }

  @override
  String get pipelineEligibilityBlocked =>
      'Ninguna impresora puede aceptar esta ejecución ahora mismo.';

  @override
  String get pipelineEligibilityAdvisory =>
      'Conviene revisar antes de empezar.';

  @override
  String get pipelineIssuePrinterNotSet =>
      'Este pipeline no tiene impresora de destino.';

  @override
  String get pipelineIssuePrinterNotFound =>
      'La impresora de destino ya no existe.';

  @override
  String get pipelineIssuePrinterDisabled =>
      'La impresora de destino está desactivada en bambuddy.';

  @override
  String get pipelineIssuePrinterOffline =>
      'La impresora de destino está desconectada.';

  @override
  String get pipelineIssueFilamentType =>
      'Tipo de filamento cargado incorrecto.';

  @override
  String get pipelineIssueFilamentColor =>
      'El filamento cargado es de un color diferente.';

  @override
  String get pipelineIssueAmsSlotMissing =>
      'El AMS tiene menos ranuras de las que necesita este pipeline.';

  @override
  String get pipelineIssueFilamentUnverified =>
      'Este preajuste de filamento no se puede comprobar desde aquí — conviene confirmarlo tú mismo.';

  @override
  String get pipelineIssueNoClassMatches =>
      'No hay instalada ninguna impresora de este modelo.';

  @override
  String get pipelineIssueClassNotSet =>
      'Este pipeline no tiene establecido un modelo de impresora.';

  @override
  String pipelineIssueSlot(int n) {
    return 'Ranura $n';
  }

  @override
  String pipelineIssueWantedGot(String expected, String actual) {
    return 'esperado: $expected, cargado: $actual';
  }

  @override
  String pipelineIssueWanted(String expected) {
    return 'esperado: $expected';
  }

  @override
  String get pipelineRunsTitle => 'Ejecuciones de pipelines';

  @override
  String get pipelineRunsEmpty => 'Aún no hay ejecuciones';

  @override
  String get pipelineRunsNoneMatch =>
      'Ninguna ejecución coincide con estos filtros';

  @override
  String get pipelineRunsFilter => 'Filtrar ejecuciones';

  @override
  String get pipelineCopiesLess => 'Una copia menos';

  @override
  String get pipelineCopiesMore => 'Una copia más';

  @override
  String get pipelineEligible => 'Lista';

  @override
  String get pipelineIneligible => 'No lista';

  @override
  String pipelineRunsFilterActive(int count) {
    return 'Filtrar ejecuciones ($count activas)';
  }

  @override
  String get pipelineRunsFilterAny => 'Cualquiera';

  @override
  String get pipelineRunsFilterStatus => 'Estado';

  @override
  String get pipelineRunsFilterStatusHint =>
      'Coincide con el último estado registrado, de modo que una ejecución aún puede corresponder al paso anterior al actual.';

  @override
  String get pipelineRunsFilterTarget => 'Destino';

  @override
  String get pipelineRunsFilterTargetHint =>
      'Hacia dónde apunta el pipeline ahora — reasignar el destino traslada todo su historial.';

  @override
  String get pipelineRunsFilterPipelineHint =>
      'No se pueden filtrar las ejecuciones de un pipeline eliminado.';

  @override
  String get pipelineRunsFilterClear => 'Borrar filtros';

  @override
  String get pipelineRunsLoadMore => 'Cargar más';

  @override
  String pipelineRunsShowingAll(int count) {
    return 'Mostrando las $count';
  }

  @override
  String get pipelineRunsDone => 'Terminado';

  @override
  String get pipelineRunsClear => 'Borrar finalizadas';

  @override
  String pipelineRunsCleared(int count) {
    return '$count eliminadas';
  }

  @override
  String get pipelineRunsClearConfirm =>
      '¿Eliminar todas las ejecuciones finalizadas de esta lista?';

  @override
  String pipelineRunCopiesProgress(int done, int total) {
    return '$done de $total copias';
  }

  @override
  String get pipelineRunCancel => 'Cancelar ejecución';

  @override
  String get pipelineRunCancelConfirm =>
      '¿Cancelar esta ejecución? Las copias aún no enviadas se descartarán; lo que ya se esté imprimiendo debe detenerse en la propia impresora.';

  @override
  String get pipelineRunCancelled => 'Ejecución cancelada';

  @override
  String get pipelineRunRetry => 'Reintentar fallidas';

  @override
  String pipelineRunRetryStarted(int count) {
    return 'Reintentando $count copias';
  }

  @override
  String get pipelineRunOverridden =>
      'Iniciado a pesar de una comprobación fallida';

  @override
  String get pipelineRunDeletedPipeline => 'Pipeline eliminado';

  @override
  String pipelineRunSource(String name) {
    return 'Desde $name';
  }

  @override
  String pipelineRunRetryOf(int id) {
    return 'Reintento de la ejecución #$id';
  }

  @override
  String pipelineRunOnPrinter(String printer) {
    return 'En $printer';
  }

  @override
  String pipelineRunOnClass(String model) {
    return 'En cualquier $model';
  }

  @override
  String get pipelineStatusQueued => 'En cola';

  @override
  String get pipelineStatusSlicing => 'Laminando';

  @override
  String get pipelineStatusDispatching => 'Enviando';

  @override
  String get pipelineStatusInProgress => 'Imprimiendo';

  @override
  String get pipelineStatusCompleted => 'Completado';

  @override
  String get pipelineStatusFailed => 'Fallido';

  @override
  String get pipelineStatusPartial => 'Parcialmente fallido';

  @override
  String get pipelineStatusCancelled => 'Cancelado';

  @override
  String get pipelineStatusUnknown => 'Desconocido';

  @override
  String pipelineJobCopy(int n) {
    return 'Copia $n';
  }

  @override
  String get pipelineJobPending => 'Pendiente';

  @override
  String get pipelineJobAwaitingPrinter => 'Esperando una impresora';

  @override
  String get pipelineJobQueued => 'En cola';

  @override
  String get pipelineJobPrinting => 'Imprimiendo';

  @override
  String get pipelineJobCompleted => 'Completado';

  @override
  String get pipelineJobFailed => 'Fallido';

  @override
  String get pipelineJobCancelled => 'Cancelado';

  @override
  String get pipelineJobUnknown => 'Desconocido';

  @override
  String get queueFilamentMapping => 'Mapeo de filamentos';

  @override
  String get mappingNoPrinter =>
      'Asigna primero una impresora a este elemento para mapear sus ranuras de AMS.';

  @override
  String get mappingNoSlots =>
      'Sin información de filamento para este archivo.';

  @override
  String mappingNoAms(String printer) {
    return 'No hay filamentos de AMS cargados en $printer.';
  }

  @override
  String get mappingPickTray => 'Seleccionar ranura de AMS';

  @override
  String get mappingExternalSpool => 'Bobina externa';

  @override
  String mappingAmsSlot(String unit, String slot) {
    return 'AMS $unit · ranura $slot';
  }

  @override
  String get mappingSaved => 'Mapeo de filamentos guardado';

  @override
  String get plateClearTitle => '¿Está despejada la placa?';

  @override
  String get plateClearBody =>
      'Asegúrate de que la placa de impresión esté vacía antes de iniciar esta impresión.';

  @override
  String get plateClearConfirm => 'La placa está despejada';

  @override
  String get plateClearAction => 'Marcar la placa como despejada';

  @override
  String get plateClearBadge => 'Placa no despejada';

  @override
  String get plateClearedSnack => 'Placa marcada como despejada';

  @override
  String get plateClearNeedsOnline =>
      'Este servidor solo libera la placa mientras la impresora está conectada. Actualiza bambuddy para hacerlo con una impresora apagada.';

  @override
  String get pfmTitle => 'Administrador de archivos';

  @override
  String get pfmTooltip => 'Archivos en la impresora';

  @override
  String pfmStorageUsed(String size) {
    return 'Usado: $size';
  }

  @override
  String get pfmTabRoot => 'Raíz';

  @override
  String get pfmTabCache => 'Caché';

  @override
  String get pfmTabModels => 'Modelos';

  @override
  String get pfmTabTimelapse => 'Timelapse';

  @override
  String get pfmSearchHint => 'Filtrar archivos…';

  @override
  String get pfmSortTooltip => 'Ordenar';

  @override
  String get pfmRefreshTooltip => 'Actualizar';

  @override
  String get pfmSortNameAsc => 'Nombre (A–Z)';

  @override
  String get pfmSortNameDesc => 'Nombre (Z–A)';

  @override
  String get pfmSortSizeLargest => 'Tamaño (más grande)';

  @override
  String get pfmSortSizeSmallest => 'Tamaño (más pequeño)';

  @override
  String get pfmSortDateNewest => 'Fecha (más reciente)';

  @override
  String get pfmSortDateOldest => 'Fecha (más antigua)';

  @override
  String get pfmUp => 'Subir una carpeta';

  @override
  String get pfmSelectAll => 'Seleccionar todo';

  @override
  String get pfmDeselectAll => 'Deseleccionar todo';

  @override
  String pfmSelected(int count) {
    return '$count seleccionados';
  }

  @override
  String get pfmEmpty => 'Esta carpeta está vacía';

  @override
  String get pfmNoMatches => 'Ningún archivo coincide con tu filtro';

  @override
  String get pfmPrinterUnavailable =>
      'La impresora no respondió, por lo que no se pudieron listar sus archivos';

  @override
  String get pfmDownloadTooLarge =>
      'La selección es demasiado grande para que el servidor la empaquete';

  @override
  String get pfmDownloadNoServerSpace =>
      'El servidor no tiene espacio para preparar esta descarga';

  @override
  String get pfmDownloadTookTooLong =>
      'Preparar la descarga tardó demasiado y el servidor la canceló';

  @override
  String get pfmPreparingOnServer => 'Preparando en el servidor…';

  @override
  String get pfmDownloading => 'Descargando…';

  @override
  String get pfmDownloadCancelled => 'Descarga cancelada';

  @override
  String get pfmDownloadPrepareFailed =>
      'El servidor no pudo preparar esta descarga';

  @override
  String pfmDownloadPartial(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se omitieron $count archivos que no se pudieron leer de la impresora',
      one: 'Se omitió un archivo que no se pudo leer de la impresora',
    );
    return '$_temp0';
  }

  @override
  String get pfmDownloadSaved => 'Archivo guardado';

  @override
  String get pfmDownloadNotSaved =>
      'No se pudo guardar el archivo en la ubicación seleccionada';

  @override
  String get pfmDownload => 'Descargar';

  @override
  String get pfmDelete => 'Eliminar';

  @override
  String get pfmDeleteConfirmTitle => '¿Eliminar archivos?';

  @override
  String pfmDeleteConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'archivos',
      one: 'archivo',
    );
    return '¿Eliminar permanentemente $count $_temp0 de la impresora? Esta acción no se puede deshacer.';
  }

  @override
  String pfmDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se eliminaron $count archivos',
      one: 'Se eliminó $count archivo',
    );
    return '$_temp0';
  }

  @override
  String get wearConnectionFailed => 'Error de conexión';

  @override
  String get wearNoPrinters => 'Sin impresoras';

  @override
  String get wearPrinterUnavailable => 'Impresora no disponible';

  @override
  String get wearNoActions => 'Sin acciones disponibles';

  @override
  String get wearClearPlate => 'Despejar placa';

  @override
  String get wearPlateCleared => 'Placa despejada';

  @override
  String get wearPlateNeedsOnline =>
      'El servidor requiere la impresora en línea';

  @override
  String get wearStarted => 'Iniciado';

  @override
  String get wearPhoneUnreachable => 'Teléfono no disponible';

  @override
  String get wearPhoneNoResponse => 'El teléfono no respondió';

  @override
  String get wearConfirm => 'Confirmar';

  @override
  String get wearServerUrl => 'URL del servidor';

  @override
  String get wearConnect => 'Conectar';

  @override
  String get wearAuthKey => 'Clave';

  @override
  String get wearAuthLogin => 'Iniciar sesión';

  @override
  String get wearUsername => 'Usuario';

  @override
  String get wearSetupPhoneTitle => 'Configurar desde el teléfono';

  @override
  String get wearSetupPhoneBody =>
      'Abre Bambuddy en tu teléfono emparejado — el reloj obtendrá el servidor y la sesión desde él.';

  @override
  String get wearSetupPhoneCheck => 'Comprobar de nuevo';

  @override
  String get wearSetupPhoneEmpty => 'Aún no se ha recibido nada del teléfono.';

  @override
  String get wearSetupManual => 'Introducir manualmente';

  @override
  String get wearSetupDemo => 'Demo';

  @override
  String get wearSetupTapToType => 'Toca para escribir';

  @override
  String get wearSettingsTitle => 'Ajustes';

  @override
  String get wearFromPhone => 'Desde tu teléfono';

  @override
  String get wearFromPhoneUse => 'Usar este servidor';

  @override
  String get wearFromPhoneLater => 'Ahora no';

  @override
  String get wearAuthNone => 'Sin inicio de sesión';

  @override
  String get wearFromPhoneWaiting =>
      'El teléfono ofrece un servidor diferente.';

  @override
  String get wearCurrentServer => 'Servidor actual';

  @override
  String get wearOk => 'OK';

  @override
  String get commonOn => 'Activado';

  @override
  String get commonOff => 'Desactivado';

  @override
  String get commonAuto => 'Auto';

  @override
  String get queueEdit => 'Editar';

  @override
  String get queueEditTitle => 'Editar elemento de la cola';

  @override
  String get queueEditSave => 'Guardar';

  @override
  String get queueEditSaved => 'Elemento de la cola actualizado';

  @override
  String get queueCreateTitle => 'Imprimir';

  @override
  String get queueCreateSubmit => 'Imprimir';

  @override
  String get queueCreateAdded => 'Añadido a la cola';

  @override
  String get queueEditPrintJob => 'Trabajo de impresión';

  @override
  String get queueEditTarget => 'Destino';

  @override
  String get queueEditSpecificPrinter => 'Impresora específica';

  @override
  String queueEditAnyModel(String model) {
    return 'Cualquier $model';
  }

  @override
  String get queueEditAnyModelGeneric => 'Cualquier modelo';

  @override
  String get queueEditTargetModel => 'Modelo';

  @override
  String get queueEditTargetLocation => 'Ubicación';

  @override
  String get queueEditAnyLocation => 'Cualquier ubicación';

  @override
  String get queueEditMappingNeedsPrinter =>
      'Selecciona una impresora para asignar filamentos';

  @override
  String queueEditMappingSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ranuras asignadas',
      one: 'ranura asignada',
    );
    return '$count $_temp0';
  }

  @override
  String get queueEditMappingAuto => 'Automático (sin asignación manual)';

  @override
  String get queueEditPlate => 'Placa';

  @override
  String queueEditPlateSelected(int plate) {
    return 'Placa $plate';
  }

  @override
  String queueEditPlateNamed(int plate, String name) {
    return 'Placa $plate · $name';
  }

  @override
  String queueEditPlateFixed(int plate) {
    return 'Este trabajo imprime la placa $plate';
  }

  @override
  String get queuePlatePickTitle => '¿Qué placa?';

  @override
  String queuePlateObjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count objetos',
      one: '1 objeto',
      zero: 'Sin objetos',
    );
    return '$_temp0';
  }

  @override
  String get queueEditPrintOptions => 'Opciones de impresión';

  @override
  String get queueOptBedLevelling => 'Nivelación de la cama';

  @override
  String get queueOptBedLevellingDesc =>
      'Nivelar la cama automáticamente antes de imprimir';

  @override
  String get queueOptFlowCali => 'Calibración de flujo';

  @override
  String get queueOptFlowCaliDesc => 'Calibrar el flujo de extrusión';

  @override
  String get queueOptVibrationCali => 'Calibración de vibraciones';

  @override
  String get queueOptVibrationCaliDesc =>
      'Reducir los artefactos de resonancia';

  @override
  String get queueOptLayerInspect => 'Inspección de la primera capa';

  @override
  String get queueOptLayerInspectDesc => 'Inspección por IA de la primera capa';

  @override
  String get queueOptTimelapse => 'Timelapse';

  @override
  String get queueOptTimelapseDesc => 'Grabar vídeo timelapse';

  @override
  String get queueOptNozzleOffset => 'Calibración del desfase de boquillas';

  @override
  String get queueOptNozzleOffsetDesc =>
      'Calibrar los desfases de boquilla entre extrusores';

  @override
  String get queueEditPreheat => 'Precalentamiento y estabilización térmica';

  @override
  String get queueEditPreheatDesc =>
      'Calienta la cama y la cámara antes de iniciar esta impresión. Por defecto usa el interruptor global Ajustes → Workflow.';

  @override
  String get queuePreheatInherit => 'Heredar';

  @override
  String get queueEditChamberTarget =>
      'Sobrescribir temperatura de cámara (°C, vacío = por defecto del filamento)';

  @override
  String queueEditChamberTargetRange(int max) {
    return '0–$max °C';
  }

  @override
  String get queueEditWhenToPrint => 'Cuándo imprimir';

  @override
  String get queueScheduleAsap => 'Inmediato';

  @override
  String get queueScheduleQueue => 'Cola';

  @override
  String get queueScheduleSchedule => 'Programar';

  @override
  String get queueEditPickTime => 'Elegir fecha y hora';

  @override
  String get queueEditRequireManualStart => 'Requerir inicio manual';

  @override
  String get queueEditRequirePrevious =>
      'Iniciar solo si la impresión anterior tuvo éxito';

  @override
  String get queueEditPowerOff => 'Apagar la impresora al terminar';

  @override
  String get queueEditGcodeInjection =>
      'Inyectar G-code de impresión automática';

  @override
  String queueEditGcodeInjectionNoSnippet(String model) {
    return 'No hay ningún fragmento de G-code para $model — no se inyectará nada.';
  }

  @override
  String get queueEditNoModel => 'Selecciona un modelo de destino';

  @override
  String get queueEditNoPrinter => 'Selecciona una impresora';

  @override
  String get queueEditFilamentOverride => 'Sustitución de filamento';

  @override
  String get queueEditFilamentOverrideDesc =>
      'Sustituye opcionalmente filamentos para la asignación basada en modelo. El programador buscará coincidencias con los filamentos seleccionados en lugar de los valores originales del 3MF.';

  @override
  String get queueEditNoFilamentReqs =>
      'Este trabajo no tiene requisitos de filamento.';

  @override
  String get queueEditOriginal => 'Original';

  @override
  String queueEditSlotLabel(String slot, String type) {
    return 'Ranura $slot · $type';
  }

  @override
  String get queueEditForceColorMatch => 'Forzar coincidencia de color';

  @override
  String get queueEditNozzleRack => 'Soporte de boquillas';

  @override
  String get queueEditNozzleRackDesc =>
      'Elige desde qué boquilla del soporte imprime cada filamento. Si se deja en automático, se elegirá una posición adecuada al iniciar la impresión.';

  @override
  String queueEditRackGroupLabel(String slots, String nozzle) {
    return 'Filamento $slots · $nozzle';
  }

  @override
  String get queueEditRackAuto => 'Automático';

  @override
  String queueEditRackPosition(int position, String nozzle) {
    return 'Posición $position · $nozzle';
  }

  @override
  String queueEditRackPositionTaken(int position, String nozzle) {
    return 'Posición $position · $nozzle — ya seleccionada';
  }

  @override
  String queueEditRackPositionUnfit(int position, String nozzle) {
    return 'Posición $position · $nozzle — no compatible';
  }

  @override
  String get queueEditRackEmpty => 'vacía';

  @override
  String get queueEditRackPickStale =>
      'La posición elegida ya no es compatible con este filamento — selecciona otra o la impresión se rechazará al iniciar.';

  @override
  String queueEditRackNoFit(String nozzle) {
    return 'Ninguna posición del soporte tiene una boquilla $nozzle — instala una o la impresora decidirá por sí misma.';
  }

  @override
  String get nozzleFlowStandard => 'Estándar';

  @override
  String get nozzleFlowHigh => 'Alto flujo';

  @override
  String get bugReportMenu => 'Informar de un error o una idea';

  @override
  String get bugReportTitle => 'Informar de un error o una idea';

  @override
  String get bugReportIntroHeader => 'Cómo funciona';

  @override
  String get bugReportStepRecord => 'Iniciar grabación';

  @override
  String get bugReportStepReproduce => 'Reproduce el problema';

  @override
  String get bugReportStepFinish => 'Vuelve y finaliza';

  @override
  String get bugReportLogScreens => 'Pantallas que abres y botones que pulsas';

  @override
  String get bugReportLogRequests => 'Peticiones al servidor y sus respuestas';

  @override
  String get bugReportLogService =>
      'La vista en directo y qué notificaciones envió u omitió el servicio en segundo plano';

  @override
  String get bugReportLogErrors =>
      'Errores y fallos inesperados, incluidos los que nunca ves';

  @override
  String get bugReportLogSetup =>
      'Versión de la app y del servidor, tu teléfono, tu idioma';

  @override
  String get bugReportLogNoKey => 'Tu clave de API o contraseña';

  @override
  String get bugReportLogNoTyping => 'El texto que escribes';

  @override
  String get bugReportLogNoAddress =>
      'La dirección de tu servidor — solo http o https, nombre o IP, y el puerto';

  @override
  String get bugReportLogNoData =>
      'Números de serie de las impresoras o nombres de tus archivos, modelos y bobinas';

  @override
  String get bugReportReviewFirst =>
      'Puedes revisarlo todo antes de que salga del teléfono.';

  @override
  String get bugReportPrivacyHeader => 'Qué se incluye en el registro';

  @override
  String get bugReportStart => 'Iniciar grabación';

  @override
  String get bugReportRecordingHeader => 'Grabando';

  @override
  String get bugReportRecordingBody =>
      'Vuelve a la app y reproduce el problema. La barra de grabación permanecerá en pantalla — muévela a un lado o pliégala si te estorba, y úsala para marcar el momento del fallo y finalizar.';

  @override
  String get bugReportMark => 'Marcar el momento';

  @override
  String get bugReportMarked => 'Momento marcado';

  @override
  String get bugReportStop => 'Finalizar grabación';

  @override
  String get bugReportStopShort => 'Finalizar';

  @override
  String get bugReportBannerLabel => 'Grabando';

  @override
  String get bugReportBarMove => 'Mover la barra de grabación';

  @override
  String get bugReportBarCollapse => 'Plegar la barra de grabación';

  @override
  String get bugReportBarExpand => 'Desplegar la barra de grabación';

  @override
  String get bugReportReviewHeader => 'Revisar antes de enviar';

  @override
  String get bugReportReviewBody =>
      'Esto es todo lo que se ha grabado. Léelo detenidamente — más abajo puedes elegir si permanece en el teléfono o se envía como una incidencia pública.';

  @override
  String bugReportSummary(int records, int errors, int warnings) {
    return '$records registros · $errors errores · $warnings advertencias';
  }

  @override
  String bugReportMarkers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count momentos marcados',
      one: '1 momento marcado',
    );
    return '$_temp0';
  }

  @override
  String get bugReportTruncated =>
      'La sesión fue larga — se descartaron los registros más antiguos.';

  @override
  String get bugReportEmpty => 'No se grabó nada.';

  @override
  String get bugReportShowRaw => 'Mostrar registro sin procesar';

  @override
  String get bugReportHideRaw => 'Ocultar registro sin procesar';

  @override
  String bugReportRawClipped(int kb) {
    return 'Los primeros $kb kB no se muestran aquí. El archivo que guardes contiene la sesión completa.';
  }

  @override
  String get bugReportSave => 'Guardar en un archivo';

  @override
  String get bugReportSaveShort => 'Guardar';

  @override
  String get bugReportSaved => 'Registro guardado en el archivo';

  @override
  String get bugReportSaveFailed => 'No se pudo guardar el registro.';

  @override
  String get bugReportDiscard => 'Descartar';

  @override
  String get bugReportDiscardQuestion => '¿Descartar esta grabación?';

  @override
  String get bugReportDiscardBody => 'El registro se eliminará del teléfono.';

  @override
  String get bugReportDiscardBodyQueued =>
      'El registro se eliminará del teléfono y se cancelará el reporte en cola.';

  @override
  String bugReportLimit(int minutes) {
    return 'La grabación se detiene automáticamente tras $minutes minutos.';
  }

  @override
  String bugReportLimitReached(int minutes) {
    return 'Grabación finalizada — se alcanzó el límite de $minutes minutos.';
  }

  @override
  String bugReportSizeLimitReached(int megabytes) {
    return 'Grabación finalizada — el registro alcanzó su límite de $megabytes MB.';
  }

  @override
  String get bugReportShow => 'Mostrar';

  @override
  String get bugReportRecoveredHeader =>
      'Una grabación sobrevivió a un cierre inesperado';

  @override
  String get bugReportRecoveredBody =>
      'La app se cerró mientras estaba grabando. Lo que se llegó a registrar aún está en el teléfono — puedes revisarlo o descartarlo.';

  @override
  String get bugReportDestinationHeader => 'Qué ocurre con este registro';

  @override
  String get bugReportDestinationFile => 'Guardar en un archivo';

  @override
  String get bugReportDestinationIssue => 'Reportar en GitHub';

  @override
  String get bugReportDestinationFileBody =>
      'El registro se guarda donde elijas y permanece en tu teléfono. Tú decides si quieres enviarlo a algún sitio.';

  @override
  String get bugReportDestinationIssueBody =>
      'El registro y tu descripción se publicarán como una incidencia pública en GitHub, donde cualquiera podrá verlos y quedarán guardados permanentemente. Revisa primero el registro a continuación.';

  @override
  String get bugReportDescriptionLabel => '¿Qué salió mal?';

  @override
  String get bugReportDescriptionHint =>
      'Qué estabas haciendo, qué esperabas y qué ocurrió en su lugar.';

  @override
  String get bugReportDescriptionRequired =>
      'Explica qué salió mal — un registro sin descripción es prácticamente inservible.';

  @override
  String get bugReportSend => 'Reportar';

  @override
  String get bugReportSending => 'Enviando…';

  @override
  String bugReportSendWaiting(String clock) {
    return 'Enviando en $clock';
  }

  @override
  String get bugReportSendWaitingBody =>
      'El relay espacia los reportes. Puedes salir de esta pantalla — se enviará por sí solo.';

  @override
  String get bugReportSent => 'Reporte enviado';

  @override
  String get bugReportSentBody =>
      'Gracias. La incidencia está abierta y el registro se ha adjuntado a ella.';

  @override
  String get bugReportOpenIssue => 'Abrir la incidencia';

  @override
  String get bugReportDone => 'Listo';

  @override
  String get bugReportSendFailedNotYet =>
      'El relay no acepta reportes en este momento. Inténtalo de nuevo más tarde o guarda el registro en un archivo.';

  @override
  String get bugReportSendFailedRefused =>
      'El relay denegó este reporte. Guarda el registro en un archivo y adjúntalo tú mismo.';

  @override
  String get bugReportSendFailedDuplicate => 'Esto ya ha sido reportado.';

  @override
  String get bugReportSendFailedUnreachable =>
      'No se pudo conectar con el relay. Comprueba la conexión o guarda el registro en un archivo.';

  @override
  String get bugReportSendFailedRejected =>
      'El relay rechazó este reporte. Guarda el registro en un archivo y adjúntalo tú mismo.';

  @override
  String get bugReportSendFailedDemo =>
      'El modo demo no publica reportes. Guarda el registro en un archivo en su lugar.';

  @override
  String get bugReportKindQuestion => '¿Qué deseas reportar?';

  @override
  String get bugReportKindBug => 'Error';

  @override
  String get bugReportKindChange => 'Cambio';

  @override
  String get bugReportKindFeature => 'Nueva función';

  @override
  String get bugReportChangeHeader => 'Solicitar un cambio';

  @override
  String get bugReportChangeBody => 'Algo funciona, pero no como debería.';

  @override
  String get bugReportChangeLabel => '¿Qué debería cambiar?';

  @override
  String get bugReportChangeHint =>
      'Qué hace ahora y qué debería hacer en su lugar.';

  @override
  String get bugReportFeatureHeader => 'Sugerir una función';

  @override
  String get bugReportFeatureBody => 'Algo que la app todavía no puede hacer.';

  @override
  String get bugReportFeatureLabel => '¿Qué falta?';

  @override
  String get bugReportFeatureHint =>
      'Qué quieres hacer y por qué la app no te lo permite.';

  @override
  String get bugReportRequestPrivacyHeader => 'Qué se envía';

  @override
  String get bugReportRequestWhatYouWrite => 'Lo que escribes';

  @override
  String get bugReportRequestVersions => 'Versión de la app y del servidor';

  @override
  String get bugReportRequestNoLog => 'Sin registro ni grabación';

  @override
  String get bugReportRequestNoData =>
      'Nada sobre tus impresoras ni tu teléfono';

  @override
  String get bugReportRequestPublic =>
      'Se convertirá en una incidencia pública en GitHub — cualquiera podrá leerla y quedará guardada permanentemente.';

  @override
  String get bugReportRequestRequired =>
      'Escribe lo que solicitas — una petición vacía no se puede tramitar.';

  @override
  String get bugReportRequestSentBody => 'Gracias. La incidencia está abierta.';

  @override
  String get bugReportCancelSend => 'Cancelar envío';

  @override
  String get bugReportRequestFailedNotYet =>
      'El relay no acepta solicitudes en este momento. Inténtalo de nuevo más tarde.';

  @override
  String get bugReportRequestFailedRefused =>
      'El relay denegó esta solicitud. Puedes abrir la incidencia tú mismo en GitHub.';

  @override
  String get bugReportRequestFailedUnreachable =>
      'No se pudo conectar con el relay. Comprueba la conexión e inténtalo de nuevo.';

  @override
  String get bugReportRequestFailedDemo =>
      'El modo demo no publica solicitudes.';

  @override
  String get bugReportRequestNotPrepared =>
      'La app no pudo preparar la solicitud. No se envió nada — inténtalo de nuevo.';

  @override
  String get usersTitle => 'Usuarios';

  @override
  String get usersMenu => 'Usuarios';

  @override
  String get usersEmpty => 'No hay cuentas en este servidor.';

  @override
  String get usersYou => 'tú';

  @override
  String get usersRoleAdmin => 'Administrador';

  @override
  String get usersRoleUser => 'Usuario';

  @override
  String get usersInactive => 'Inactivo';

  @override
  String get usersEmailLabel => 'Correo electrónico';

  @override
  String get usersEmailNone => 'ninguno';

  @override
  String get usersGroupsLabel => 'Grupos';

  @override
  String get usersNoGroups => 'ninguno';

  @override
  String get usersPermissionsLabel => 'Permisos';

  @override
  String usersPermissionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count permisos',
      one: '1 permiso',
      zero: 'ninguno',
    );
    return '$_temp0';
  }

  @override
  String get usersPermissionsUnknown => 'no informado por el servidor';

  @override
  String get usersAuthSourceLabel => 'Inicio de sesión';

  @override
  String get usersAuthSourceLocal => 'Cuenta local';

  @override
  String get usersCreatedLabel => 'Creado';

  @override
  String get usersOwnedTitle => 'CREADO POR ESTA CUENTA';

  @override
  String get usersOwnedArchives => 'Impresiones';

  @override
  String get usersOwnedQueue => 'Cola';

  @override
  String get usersOwnedLibrary => 'Archivos';

  @override
  String get usersOwnedFailed => 'No se pudo leer el contenido de esta cuenta.';

  @override
  String get usersCreate => 'Añadir cuenta';

  @override
  String get usersCreateTitle => 'Nueva cuenta';

  @override
  String get usersEdit => 'Editar';

  @override
  String get usersEditTitle => 'Editar cuenta';

  @override
  String get usersDelete => 'Eliminar';

  @override
  String get usersSave => 'Guardar';

  @override
  String get usersSaved => 'Cuenta guardada';

  @override
  String get usersSaveFailed => 'No se ha podido guardar la cuenta.';

  @override
  String get usersDeleted => 'Cuenta eliminada';

  @override
  String get usersFieldUsername => 'Nombre de usuario';

  @override
  String get usersFieldEmail => 'Correo electrónico (opcional)';

  @override
  String get usersFieldEmailRequired => 'Correo electrónico';

  @override
  String get usersFieldPassword => 'Contraseña';

  @override
  String get usersFieldNewPassword => 'Nueva contraseña';

  @override
  String get usersFieldConfirmPassword => 'Repite la contraseña';

  @override
  String get usersFieldActive => 'Activo';

  @override
  String get usersFieldGroups => 'Grupos';

  @override
  String get usersGroupSystem => '(integrado)';

  @override
  String get usersFieldRequired => 'Completa este campo';

  @override
  String get usersPasswordsDoNotMatch => 'Las dos contraseñas son diferentes.';

  @override
  String get usersGroupsAdminHint =>
      'Pertenecer a Administrators es lo que convierte a una cuenta en administradora.';

  @override
  String get usersActiveHint => 'Una cuenta inactiva no puede iniciar sesión.';

  @override
  String get usersEmailAdvancedHint =>
      'Este servidor envía la contraseña por correo, por lo que necesita una dirección.';

  @override
  String get usersPasswordMailed =>
      'El servidor genera la contraseña automáticamente y la envía a esta dirección. Nadie, incluyéndote a ti, podrá verla.';

  @override
  String get usersNoSmtpWarning =>
      'No hay ningún servidor de correo configurado, por lo que el mensaje no llegará — la cuenta se crearía con una contraseña que nadie conoce.';

  @override
  String get usersLdapPasswordNote =>
      'Esta cuenta inicia sesión mediante el directorio (LDAP). Su contraseña reside allí y no se puede configurar desde aquí.';

  @override
  String get usersPasswordKeepHint =>
      'Deja este campo vacío para mantener la contraseña actual.';

  @override
  String get usersPasswordRulesHint =>
      'Al menos 8 caracteres, con mayúscula, minúscula, un dígito y un símbolo.';

  @override
  String get usersPasswordTooShort => 'Al menos 8 caracteres.';

  @override
  String get usersPasswordNoUppercase => 'Añade una letra mayúscula.';

  @override
  String get usersPasswordNoLowercase => 'Añade una letra minúscula.';

  @override
  String get usersPasswordNoDigit => 'Añade un dígito.';

  @override
  String get usersPasswordNoSpecial => 'Añade un símbolo.';

  @override
  String usersDeleteTitle(String username) {
    return '¿Eliminar $username?';
  }

  @override
  String get usersDeleteBody =>
      'Se eliminarán la cuenta, sus claves de API y su estado de inicio de sesión. Esta acción no se puede deshacer.';

  @override
  String usersDeleteOwnsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Esta cuenta creó $count elementos',
      one: 'Esta cuenta creó 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get usersDeleteItemsToo => 'Eliminarlos también';

  @override
  String get usersDeleteItemsTooHint =>
      'Sus impresiones, elementos en cola y archivos se eliminarán con la cuenta.';

  @override
  String get usersDeleteItemsKeepHint =>
      'Sus impresiones, elementos en cola y archivos se conservarán sin propietario.';

  @override
  String get usersDeleteConfirm => 'Eliminar';

  @override
  String get usersErrLastAdmin =>
      'Este es el último administrador — el servidor debe conservar uno.';

  @override
  String get usersErrLastAdminDelete =>
      'No se puede eliminar al último administrador — el servidor se quedaría sin nadie que pueda gestionarlo.';

  @override
  String get usersErrLastAdminDeactivate =>
      'No se puede desactivar al último administrador — el servidor se quedaría sin nadie que pueda gestionarlo.';

  @override
  String get usersErrLastAdminRole =>
      'No se puede degradar al último administrador — el servidor se quedaría sin nadie que pueda gestionarlo.';

  @override
  String get usersErrSelfDelete =>
      'No puedes eliminar la cuenta con la que has iniciado sesión.';

  @override
  String get usersErrUsernameTaken => 'Ese nombre de usuario ya está en uso.';

  @override
  String get usersErrEmailTaken =>
      'Ese correo electrónico ya pertenece a otra cuenta.';

  @override
  String get usersErrLdapPassword =>
      'La contraseña de una cuenta de directorio (LDAP) no se puede configurar aquí.';

  @override
  String get usersErrEmailRequired =>
      'Este servidor requiere una dirección de correo electrónico para las cuentas nuevas.';

  @override
  String get usersErrPasswordRequired =>
      'Este servidor requiere una contraseña para las cuentas nuevas.';

  @override
  String get usersErrGroupsInvalid =>
      'Uno de los grupos ya no existe — vuelve a abrir el formulario.';

  @override
  String get groupsTitle => 'Grupos';

  @override
  String get groupsMenu => 'Grupos';

  @override
  String get groupsEmpty => 'No hay grupos en este servidor.';

  @override
  String get groupsNoDescription => 'Sin descripción';

  @override
  String get groupsSystemPill => 'Integrado';

  @override
  String get groupsSystemNote =>
      'Un grupo integrado no se puede renombrar y sus permisos son fijos — solo pueden cambiar sus miembros.';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuentas',
      one: '1 cuenta',
      zero: 'ninguna cuenta',
    );
    return '$_temp0';
  }

  @override
  String groupsPermissionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count permisos',
      one: '1 permiso',
      zero: 'ningún permiso',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembersHeader => 'MIEMBROS';

  @override
  String get groupsNoMembers => 'No hay nadie en este grupo.';

  @override
  String get groupsAddMember => 'Añadir miembro';

  @override
  String groupsAddMemberTitle(String group) {
    return 'Añadir a $group';
  }

  @override
  String get groupsEveryoneIsIn =>
      'Todas las cuentas ya pertenecen a este grupo.';

  @override
  String get groupsRemoveMember => 'Quitar';

  @override
  String groupsRemoveMemberQuestion(String username, String group) {
    return '¿Quitar a $username de $group?';
  }

  @override
  String get groupsRemoveMemberBody =>
      'La cuenta se conserva y pierde lo que este grupo le otorgaba.';

  @override
  String get groupsCreate => 'Nuevo grupo';

  @override
  String get groupsCreateTitle => 'Nuevo grupo';

  @override
  String get groupsEditTitle => 'Editar grupo';

  @override
  String get groupsDelete => 'Eliminar grupo';

  @override
  String get groupsSaved => 'Grupo guardado';

  @override
  String get groupsDeleted => 'Grupo eliminado';

  @override
  String groupsDeleteQuestion(String group) {
    return '¿Eliminar $group?';
  }

  @override
  String get groupsDeleteBody =>
      'Los permisos que otorga desaparecerán con él.';

  @override
  String groupsDeleteBodyWithMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count cuentas pertenecen a él y se conservarán — solo perderán lo que este grupo les otorgaba.',
      one:
          '1 cuenta pertenece a él y se conservará — solo perderá lo que este grupo le otorgaba.',
    );
    return '$_temp0';
  }

  @override
  String get groupsFieldName => 'Nombre';

  @override
  String get groupsFieldDescription => 'Para qué sirve';

  @override
  String get groupsSystemFormNote =>
      'Grupo integrado: su nombre y permisos están fijados por el servidor. Aquí solo se puede modificar la descripción.';

  @override
  String get groupsPermissionsHeader => 'PERMISOS';

  @override
  String groupsPermissionsSelected(int count) {
    return '$count seleccionados';
  }

  @override
  String get groupsAdvancedPermissions => 'Administración del servidor';

  @override
  String get groupsAdvancedHint =>
      'Usuarios, claves de API, ajustes, copias de seguridad — todo para lo que la propia aplicación no tiene pantalla.';

  @override
  String get serverSettingsMenu => 'Ajustes del servidor';

  @override
  String get serverSettingsTitle => 'Ajustes del servidor';

  @override
  String get serverSettingsQueueSubtitle =>
      'Programación, precalentamiento y mantenimiento de la cama caliente entre impresiones';

  @override
  String get serverSettingsMaintenanceSubtitle =>
      'Tipos de tareas e intervalos por impresora';

  @override
  String get serverSettingsAdminSubtitle => 'Cuentas, grupos y claves de API';

  @override
  String get serverSettingsCloudSubtitle =>
      'La cuenta de Bambu que utiliza el servidor para descargar';

  @override
  String get queueSettingsTitle => 'Cola y precalentamiento';

  @override
  String get queueSettingsReadOnlyApiKey =>
      'Una clave de API nunca puede modificar los ajustes del servidor. Inicia sesión con una cuenta para cambiarlos.';

  @override
  String get queueSettingsReadOnlyPermission =>
      'Tu cuenta puede leer estos ajustes, pero no modificarlos.';

  @override
  String get queueSettingsUnavailable =>
      'Este servidor no proporciona ninguno de estos ajustes. O bien es más antiguo que ellos, o no se pudieron leer — desliza hacia abajo para reintentarlo.';

  @override
  String get queueSettingsQueueHeader => 'Cola';

  @override
  String get queueSettingsPlateClearTitle =>
      'Confirmar que la placa está vacía';

  @override
  String get queueSettingsPlateClearDesc =>
      'Tras una impresión, la impresora espera a que alguien confirme que la placa está vacía.';

  @override
  String get queueSettingsShortestFirstTitle => 'Trabajo más corto primero';

  @override
  String get queueSettingsShortestFirstDesc =>
      'Tomar el trabajo en espera más corto en lugar del que lleva más tiempo esperando.';

  @override
  String queueSettingsMaxUploads(int count) {
    return 'Archivos subidos al mismo tiempo: $count';
  }

  @override
  String get queueSettingsPreheatHeader => 'Precalentamiento';

  @override
  String get queueSettingsPreheatTitle => 'Precalentar antes de un trabajo';

  @override
  String get queueSettingsPreheatDesc =>
      'Calienta la cámara antes de enviar el archivo. Un trabajo en cola individual puede anularlo.';

  @override
  String queueSettingsPreheatMaxWait(String duration) {
    return 'Límite de espera de la cámara: $duration';
  }

  @override
  String queueSettingsPreheatSoak(String duration) {
    return 'Estabilización tras alcanzar la temperatura: $duration';
  }

  @override
  String get queueSettingsNoSoak => 'sin estabilización';

  @override
  String get queueSettingsPreheatOffNote =>
      'El precalentamiento está desactivado, por lo que los ajustes siguientes no tendrán efecto.';

  @override
  String get queueSettingsKeepWarmHeader => 'Mantenimiento del calor';

  @override
  String get queueSettingsKeepWarmTitle =>
      'Mantener la cama caliente entre impresiones';

  @override
  String get queueSettingsKeepWarmDesc =>
      'Hasta que alguien retire la impresión terminada, la cama permanece caliente para que el siguiente trabajo con cámara calefactada no empiece en frío. Se omite para PLA y PETG.';

  @override
  String queueSettingsKeepWarmTemp(int temp) {
    return 'Temperatura de la cama para calentar la cámara: $temp °C';
  }

  @override
  String queueSettingsKeepWarmMax(String duration) {
    return 'Tiempo máximo de mantenimiento de la cama: $duration';
  }

  @override
  String get queueSettingsMaxUploadsDesc =>
      'Antes de que comience un trabajo en cola, su archivo se envía a la impresora por FTP, lo que puede tardar minutos. Esto indica cuántas transferencias de este tipo se realizan a la vez; solo tiene efecto con varias impresoras.';

  @override
  String get queueSettingsPreheatMaxWaitDesc =>
      'Una X1C o P2S no tiene calentador de cámara — la cámara se calienta con la cama, lo que puede tardar 15–30 minutos. Tras este tiempo, la cola deja de esperar y pasa a la estabilización.';

  @override
  String get queueSettingsPreheatSoakDesc =>
      'Tiempo adicional a temperatura después de que la cámara la alcance, o tras agotarse la espera anterior. Cero lo omite.';

  @override
  String get queueSettingsKeepWarmTempDesc =>
      '90 mantiene el calor de la cámara en una impresora cerrada y activa los calentadores de cámara adicionales, que suelen encenderse con la cama a 80. Una temperatura de cama más alta definida en el archivo siempre tiene prioridad.';

  @override
  String get queueSettingsKeepWarmMaxDesc =>
      'Establécelo según el tiempo que tardas de forma realista en llegar a la impresora. Un tiempo demasiado corto solo provocará que la siguiente impresión deba estabilizarse desde frío; sin un límite, una placa sin retirar mantendría la cama caliente indefinidamente.';

  @override
  String get queueSettingsKeepWarmOffNote =>
      'El mantenimiento del calor está desactivado. La temperatura de la cama indicada arriba se sigue aplicando al precalentamiento.';

  @override
  String get adminMenu => 'Administración';

  @override
  String get adminTitle => 'Administración';

  @override
  String adminSignedInAs(String username) {
    return 'Sesión iniciada como $username';
  }

  @override
  String get adminUsersSubtitle =>
      'Quién tiene una cuenta y qué puede hacer cada uno';

  @override
  String get adminGroupsSubtitle =>
      'Conjuntos de permisos y quiénes los tienen';

  @override
  String get adminApiKeysSubtitle =>
      'Credenciales para todo lo que no sea esta aplicación';

  @override
  String get apiKeysTitle => 'Claves de API';

  @override
  String get apiKeysEmpty => 'No se han emitido claves.';

  @override
  String get apiKeysCreate => 'Nueva clave';

  @override
  String get apiKeysCreateTitle => 'Nueva clave de API';

  @override
  String get apiKeysEditTitle => 'Editar clave';

  @override
  String get apiKeysSaved => 'Clave guardada';

  @override
  String get apiKeysRevoke => 'Revocar';

  @override
  String get apiKeysRevoked => 'Clave revocada';

  @override
  String apiKeysRevokeQuestion(String name) {
    return '¿Revocar $name?';
  }

  @override
  String get apiKeysRevokeBody =>
      'Cualquier cosa que use esta clave dejará de funcionar de inmediato. Esta acción no se puede deshacer — habría que emitir una nueva clave.';

  @override
  String apiKeysLastUsed(String date) {
    return 'último uso el $date';
  }

  @override
  String get apiKeysNeverUsed => 'nunca usada';

  @override
  String get apiKeysDisabled => 'Desactivada';

  @override
  String get apiKeysExpired => 'Caducada';

  @override
  String apiKeysExpiresOn(String date) {
    return 'hasta el $date';
  }

  @override
  String apiKeysPrinterLimited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impresoras',
      one: '1 impresora',
    );
    return '$_temp0';
  }

  @override
  String get apiKeysLegacy => 'Sin propietario';

  @override
  String get apiKeysFieldName => 'Nombre';

  @override
  String get apiKeysFieldNameHint =>
      'Qué servicio utiliza esta clave — “Home Assistant”, “SpoolBuddy”.';

  @override
  String get apiKeysFieldEnabled => 'Activa';

  @override
  String get apiKeysFieldEnabledHint =>
      'Desactivarla impide que la clave funcione sin eliminarla.';

  @override
  String get apiKeysScopesHeader => 'QUÉ PUEDE HACER';

  @override
  String get apiKeysScopesHint =>
      'Una clave nunca puede administrar cuentas, grupos, claves ni ajustes — el servidor deniega esto a todas las claves.';

  @override
  String get apiKeysPrintersHeader => 'IMPRESORAS';

  @override
  String get apiKeysAllPrinters => 'Todas las impresoras';

  @override
  String get apiKeysAllPrintersHint =>
      'Desactivado: elige con qué impresoras puede interactuar esta clave.';

  @override
  String get apiKeysExpiryHeader => 'CADUCIDAD';

  @override
  String get apiKeysNoExpiry => 'No caduca';

  @override
  String get apiKeysExpiryHint =>
      'Toca para elegir una fecha a partir de la cual la clave dejará de funcionar.';

  @override
  String get apiKeysExpiryClear => 'Sin caducidad';

  @override
  String get apiKeysCreatedTitle => 'Clave creada';

  @override
  String get apiKeysCreatedWarning =>
      'Cópiala ahora. El servidor solo guarda un hash — esta es la última vez que podrá mostrarse.';

  @override
  String get apiKeysCopy => 'Copiar';

  @override
  String get apiKeysCopied => 'Clave copiada';

  @override
  String get apiKeysCreatedDone => 'Listo';

  @override
  String get apiKeyScopeRead => 'Lectura de estado';

  @override
  String get apiKeyScopeReadHint =>
      'Impresoras, cola, archivo, biblioteca, estadísticas — solo lectura.';

  @override
  String get apiKeyScopeQueue => 'Cola';

  @override
  String get apiKeyScopeControl => 'Controlar impresoras';

  @override
  String get apiKeyScopeControlHint =>
      'Pausa, detención, temperaturas, AMS, enchufes inteligentes.';

  @override
  String get apiKeyScopeLibrary => 'Archivos';

  @override
  String get apiKeyScopeInventory => 'Filamentos';

  @override
  String get apiKeyScopeMaintenance => 'Mantenimiento';

  @override
  String get apiKeyScopeArchives => 'Archivo';

  @override
  String get apiKeyScopeProjects => 'Proyectos';

  @override
  String get apiKeyScopeCloud => 'Bambu Cloud';

  @override
  String get apiKeyScopeCloudHint =>
      'Consulta la nube en nombre de la cuenta que crea la clave. Requiere autenticación activada en el servidor.';

  @override
  String get apiKeyScopeEnergy => 'Precio de la energía';

  @override
  String get apiKeyScopeEnergyHint =>
      'El único valor de configuración que puede escribir una clave — para tarifas dinámicas.';

  @override
  String get printLogTitle => 'Registro de impresiones';

  @override
  String get printLogSearchHint => 'Buscar impresiones';

  @override
  String get printLogEmpty => 'Aún no hay impresiones registradas';

  @override
  String get printLogNoMatches => 'Ninguna impresión coincide con tus filtros';

  @override
  String get printLogLoadFailed =>
      'No se ha podido cargar el registro de impresiones';

  @override
  String get printLogFilters => 'Filtros';

  @override
  String get printLogFilterPrinter => 'Impresora';

  @override
  String get printLogFilterUser => 'Usuario';

  @override
  String get printLogFilterStatus => 'Estado';

  @override
  String get printLogFilterDates => 'Rango de fechas';

  @override
  String get printLogAnyPrinter => 'Cualquier impresora';

  @override
  String get printLogAnyUser => 'Cualquier usuario';

  @override
  String get printLogAnyStatus => 'Cualquier estado';

  @override
  String get printLogNoUser => 'Sin usuario';

  @override
  String get printLogOrphan => 'Archivo eliminado';

  @override
  String printLogShowing(int loaded, int total) {
    return '$loaded de $total';
  }

  @override
  String get printLogLoadMore => 'Cargar más';

  @override
  String get printLogSort => 'Ordenar por';

  @override
  String get printLogSortDate => 'Fecha';

  @override
  String get printLogSortName => 'Nombre';

  @override
  String get printLogSortPrinter => 'Impresora';

  @override
  String get printLogSortUser => 'Usuario';

  @override
  String get printLogSortStatus => 'Estado';

  @override
  String get printLogSortDuration => 'Duración';

  @override
  String get printLogSortFilament => 'Filamento usado';

  @override
  String get printLogSortCost => 'Coste';

  @override
  String get printLogSortEnergy => 'Energía';

  @override
  String get printLogSortDirection => 'Dirección';

  @override
  String get printLogSortDescending => 'Descendente';

  @override
  String get printLogSortAscending => 'Ascendente';

  @override
  String get printLogStatusCompleted => 'Completado';

  @override
  String get printLogStatusFailed => 'Fallido';

  @override
  String get printLogStatusStopped => 'Detenido';

  @override
  String get printLogStatusCancelled => 'Cancelado';

  @override
  String get printLogStatusSkipped => 'Omitido';

  @override
  String get printLogStatusAborted => 'Abortado';

  @override
  String printLogEnergy(String value) {
    return '$value kWh';
  }

  @override
  String get printLogClassifyTitle => 'Clasificar esta impresión';

  @override
  String get printLogDetailStarted => 'Iniciado';

  @override
  String get printLogDetailFinished => 'Finalizado';

  @override
  String get printLogDetailDuration => 'Duración';

  @override
  String get printLogDetailFilament => 'Filamento';

  @override
  String get printLogDetailCost => 'Coste';

  @override
  String get printLogDetailEnergy => 'Energía';

  @override
  String get printLogFailureCause => 'Causa del fallo';

  @override
  String get printLogNoClassification => 'Sin clasificar';

  @override
  String get printLogStatusLabel => 'Estado';

  @override
  String get printLogCountsAsFailure =>
      'Contabilizado como fallo — esta impresión y su causa aparecerán en el análisis de fallos.';

  @override
  String get printLogNotCountedAsFailure =>
      'No contabilizado como fallo, por lo que la causa queda fuera del análisis de fallos.';

  @override
  String printLogStatusOneWay(String status) {
    return 'Este servidor no puede restablecer el estado “$status”. Si lo cambias, se perderá definitivamente.';
  }

  @override
  String get printLogSave => 'Guardar';

  @override
  String get printLogSaveFailed => 'No se ha podido guardar la clasificación';

  @override
  String get printLogDelete => 'Eliminar impresión';

  @override
  String get printLogDeleteTitle => '¿Eliminar esta impresión?';

  @override
  String get printLogDeleteBody =>
      'Se eliminará del registro, y su filamento, coste y tiempo desaparecerán de las estadísticas. El archivo al que apunta se conservará.';

  @override
  String get printLogDeleteFailed => 'No se ha podido eliminar la impresión';

  @override
  String get printLogClear => 'Vaciar registro de impresiones';

  @override
  String get printLogClearTitle => '¿Vaciar todo el registro de impresiones?';

  @override
  String printLogClearBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se eliminarán las $count impresiones',
      one: 'Se eliminará la única impresión del registro',
    );
    return '$_temp0 — las de todos, no solo las tuyas — y su filamento, coste y tiempo desaparecerán de las estadísticas. Los archivos y la cola quedarán intactos. Esta acción no se puede deshacer.';
  }

  @override
  String get printLogClearBodyFiltered =>
      'Se eliminarán todas las impresiones del registro — las de todos, no solo las tuyas, y el filtro aplicado no las limita — y su filamento, coste y tiempo desaparecerán de las estadísticas. Los archivos y la cola quedarán intactos. Esta acción no se puede deshacer.';

  @override
  String printLogCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count impresiones eliminadas',
      one: '$count impresión eliminada',
    );
    return '$_temp0';
  }

  @override
  String get printLogClearFailed =>
      'No se ha podido vaciar el registro de impresiones';

  @override
  String get failureReasonAdhesion => 'Fallo de adherencia';

  @override
  String get failureReasonSpaghetti => 'Espagueti / impresión desprendida';

  @override
  String get failureReasonLayerShift => 'Desplazamiento de capas';

  @override
  String get failureReasonCloggedNozzle => 'Boquilla atascada';

  @override
  String get failureReasonFilamentRunout => 'Fin de filamento';

  @override
  String get failureReasonWarping => 'Deformación (warping)';

  @override
  String get failureReasonStringing => 'Hilos (stringing)';

  @override
  String get failureReasonUnderExtrusion => 'Subextrusión';

  @override
  String get failureReasonPowerFailure => 'Corte de corriente';

  @override
  String get failureReasonUserCancelled => 'Cancelado por el usuario';

  @override
  String get failureReasonOther => 'Otro';

  @override
  String get failureReasonUnknown => 'Desconocido';
}
