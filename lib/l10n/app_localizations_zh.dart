// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get printersTitle => '打印机';

  @override
  String get changeServer => '更换服务器';

  @override
  String get sessionExpired => '登录已过期，请重新登录';

  @override
  String get signInRequiredTitle => '请重新登录';

  @override
  String get signInRequiredBody =>
      '服务器拒绝了已保存的密码，应用已停止自动重试（反复尝试会导致账号被锁定）。请重新登录；若密码已修改，请使用新密码。';

  @override
  String get signInRequiredAction => '登录';

  @override
  String get signInRequiredTwoFactorBody =>
      '你的账号现在要求二次验证，应用无法在后台完成，因此已停止自动登录。请重新登录并输入验证码。';

  @override
  String get signInRequiredMissingBody =>
      '一次安全更新或备份恢复使加密登录信息的密钥失效了，除此之外没有其他数据丢失。';

  @override
  String get serverUnreachableStale => '无法连接服务器，数据可能已过期';

  @override
  String get wsReconnecting => '实时连接已断开，每 5 秒刷新一次';

  @override
  String get connLive => '实时';

  @override
  String get connLiveTooltip => '通过 WebSocket 实时更新';

  @override
  String get connPolling => '轮询';

  @override
  String get connPollingTooltip => '无实时连接，每 5 秒刷新一次（REST）';

  @override
  String get connectFailed => '无法连接服务器';

  @override
  String get filePickerFailed => '无法打开文件选择器';

  @override
  String get retry => '重试';

  @override
  String get back => '返回';

  @override
  String get searchPrinters => '搜索打印机…';

  @override
  String get noPrinters => '暂无打印机，请先在服务器上添加';

  @override
  String noSearchResults(String query) {
    return '没有与“$query”匹配的结果';
  }

  @override
  String get noPrintersMatchFilters => '没有符合当前筛选条件的打印机';

  @override
  String get dashboardFilters => '筛选与排序';

  @override
  String get filterStatus => '状态';

  @override
  String get filtersClear => '清除';

  @override
  String get hideOffline => '隐藏离线';

  @override
  String get statusAll => '全部';

  @override
  String get statusPrinting => '打印中';

  @override
  String get statusIdle => '空闲';

  @override
  String get statusPaused => '已暂停';

  @override
  String get statusFinished => '已完成';

  @override
  String get statusErrorFilter => '出错';

  @override
  String get statusOfflineFilter => '离线';

  @override
  String get addPrinterTitle => '添加打印机';

  @override
  String get addPrinterName => '名称';

  @override
  String get addPrinterIp => 'IP 地址';

  @override
  String get addPrinterSerial => '序列号';

  @override
  String get addPrinterAccessCode => '访问码';

  @override
  String get addPrinterRevealAccessCode => '显示访问码';

  @override
  String get addPrinterHideAccessCode => '隐藏访问码';

  @override
  String get addPrinterModel => '型号';

  @override
  String get addPrinterModelOptional => '可选';

  @override
  String get addPrinterModelNone => '未设置';

  @override
  String get addPrinterLocation => '位置';

  @override
  String get addPrinterLocationOptional => '可选';

  @override
  String get printerLocationsManage => '管理位置';

  @override
  String get addPrinterSubmit => '添加打印机';

  @override
  String get addPrinterConnectionNote =>
      '服务器会先验证连接再保存，所以 IP 或访问码有误会直接提示，不会创建任何内容。';

  @override
  String get addPrinterRequiredField => '必填';

  @override
  String get addPrinterSuccess => '打印机已添加';

  @override
  String get addPrinterErrConnection =>
      '无法连接打印机。请检查 IP 地址、序列号和访问码，并确认已开启仅局域网模式。';

  @override
  String get addPrinterErrDuplicate => '该序列号的打印机已存在';

  @override
  String get addPrinterErrForbidden => '你没有添加打印机的权限';

  @override
  String get addPrinterErrGeneric => '无法添加打印机，请重试。';

  @override
  String get addPrinterAutoArchive => '自动归档已完成的打印';

  @override
  String get editPrinterTitle => '编辑打印机';

  @override
  String get editPrinterSubmit => '保存更改';

  @override
  String get editPrinterSaved => '打印机已保存';

  @override
  String get editPrinterSerialLocked => '序列号不可修改';

  @override
  String get editPrinterAccessCodeKeep => '留空则保持当前访问码';

  @override
  String get editPrinterMaintenance => '维护模式';

  @override
  String get editPrinterMaintenanceHelp => '暂停该打印机的连接、排队任务和通知。';

  @override
  String editPrinterWearCost(String currency) {
    return '每打印小时磨损成本（$currency）';
  }

  @override
  String get editPrinterWearCostHelp => '仅对新的打印生效。留空则关闭该功能。';

  @override
  String get editPrinterWearCostInvalid => '请输入 0 到 100000 之间的数字';

  @override
  String get editPrinterPreflightWarning =>
      '部分连接检查未通过，该打印机可能显示为离线。请查看下方检查项，尽量修复，或仍然保存。';

  @override
  String get editPrinterSaveAnyway => '仍然保存';

  @override
  String get addPrinterScanTitle => '在网络中查找打印机';

  @override
  String get addPrinterSubnet => '要扫描的子网';

  @override
  String get addPrinterScanButton => '扫描子网中的打印机';

  @override
  String get addPrinterDiscoverNetwork => '发现网络中的打印机';

  @override
  String addPrinterScanning(int scanned, int total) {
    return '扫描中… $scanned/$total';
  }

  @override
  String get addPrinterScanningPlain => '扫描中…';

  @override
  String get addPrinterScanNoResults => '未找到打印机';

  @override
  String get addPrinterScanError => '扫描失败，请重试。';

  @override
  String get addPrinterSubnetCustomOption => '自定义子网…';

  @override
  String get addPrinterSubnetCustomLabel => '自定义子网（CIDR）';

  @override
  String get addPrinterSubnetDockerNote =>
      '检测到 Docker。请用 CIDR 格式填写打印机所在子网。需要在 docker-compose.yml 中设置 network_mode: host。';

  @override
  String get addPrinterSubnetCustomNote =>
      '如果打印机与服务器不在同一网络，请使用自定义子网。FTP（990）和 MQTT（8883）端口必须能跨路由访问。';

  @override
  String get addPrinterDiagnostic => '运行诊断';

  @override
  String get addPrinterDiagnosticRunning => '正在诊断…';

  @override
  String get addPrinterDiagnosticError => '诊断失败，请重试。';

  @override
  String get diagOverallOk => '所有检查均已通过';

  @override
  String get diagOverallWarnings => '已完成，但有警告';

  @override
  String get diagOverallProblems => '发现问题';

  @override
  String get diagCheckPortMqtt => 'MQTT 端口（8883）';

  @override
  String get diagCheckPortFtps => 'FTPS 端口（990）';

  @override
  String get diagCheckPortRtsps => '摄像头端口（322）';

  @override
  String get diagCheckNetworkMode => '网络模式';

  @override
  String get diagCheckSubnet => '子网可达性';

  @override
  String get diagCheckMqttAuth => 'MQTT 凭据';

  @override
  String get diagCheckDeveloperMode => '开发者 / 局域网模式';

  @override
  String get changeServerQuestion => '更换服务器？';

  @override
  String get changeServerWarning => '已保存的配置和凭据将被删除。';

  @override
  String get cancel => '取消';

  @override
  String get clear => '清除';

  @override
  String get change => '更改';

  @override
  String get noActivePrints => '没有正在打印的任务';

  @override
  String printingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个正在打印',
    );
    return '$_temp0';
  }

  @override
  String get nextAvailableLabel => '下一个可用： ';

  @override
  String get tempNozzle => '喷嘴';

  @override
  String get tempBed => '热床';

  @override
  String get tempChamber => '腔体';

  @override
  String tempNozzleNumbered(String n) {
    return '喷嘴 $n';
  }

  @override
  String get ctrlFanPart => '模型散热风扇';

  @override
  String get ctrlFanAux => '辅助风扇';

  @override
  String get ctrlFanAux2 => '左侧辅助风扇';

  @override
  String get ctrlFanChamber => '腔体风扇';

  @override
  String get ctrlFanExhaust => '排风扇';

  @override
  String get ctrlFanPartShort => '模型';

  @override
  String get ctrlFanAuxShort => '辅助';

  @override
  String get ctrlFanAux2Short => '左辅';

  @override
  String get ctrlFanChamberShort => '腔体';

  @override
  String get ctrlFanExhaustShort => '排风';

  @override
  String get ctrlFanPartLabel => '模型散热';

  @override
  String get ctrlFanAuxLabel => '辅助';

  @override
  String get ctrlFanAux2Label => '左侧辅助';

  @override
  String get ctrlFanChamberLabel => '腔体';

  @override
  String get ctrlFanExhaustLabel => '排风';

  @override
  String get ctrlSpeed => '速度';

  @override
  String get ctrlLight => '腔体照明';

  @override
  String get ctrlAirduct => '风道';

  @override
  String get ctrlAirductCooling => '制冷';

  @override
  String get ctrlAirductHeating => '制热';

  @override
  String get ctrlAirductPrintTitle => '打印中切换腔体模式？';

  @override
  String get ctrlAirductPrintBody => '打印中在制热和制冷之间切换会改变打印环境温度，可能导致打印失败。';

  @override
  String get ctrlOff => '关闭';

  @override
  String get ctrlSet => '设置';

  @override
  String get ctrlActivate => '启用';

  @override
  String get ctrlNozzleActive => '已启用';

  @override
  String get amsDryer => '干燥箱';

  @override
  String get ctrlDry => '烘干';

  @override
  String get ctrlDrying => '烘干中';

  @override
  String get ctrlDryNotRunning => '未运行';

  @override
  String get ctrlDryNotRunningHint =>
      '打印机保留了烘干计时器，但并未倒计时，AMS 也未报告在烘干。烘干循环从未开始或被暂停，例如被功率限制或当前打印任务中断。';

  @override
  String get ctrlDryStart => '开始';

  @override
  String get ctrlDryFilament => '耗材';

  @override
  String get ctrlDryTemp => '温度';

  @override
  String get ctrlDryDuration => '时长';

  @override
  String ctrlDryHours(int h) {
    return '$h 小时';
  }

  @override
  String get ctrlDryAutoIdle => '湿度高时自动烘干。';

  @override
  String get ctrlDryAutoQueue => '队列打印任务之间自动烘干。';

  @override
  String get ctrlDryAutoWhilePrinting => '打印过程中也进行。';

  @override
  String get ctrlDryStartWhen => '开始时间';

  @override
  String get ctrlDryStartNow => '立即';

  @override
  String get ctrlDryStartAfter => '稍后';

  @override
  String get ctrlDryStartAt => '指定时间';

  @override
  String get ctrlDryPickTime => '选择时间';

  @override
  String get ctrlDrySchedule => '定时';

  @override
  String get ctrlDryScheduled => '已安排烘干';

  @override
  String get ctrlDryScheduleTimePast => '请选择将来的时间';

  @override
  String ctrlDryScheduledFor(String time) {
    return '$time 烘干';
  }

  @override
  String get ctrlDryScheduledAsap => '已安排烘干，等待打印机空闲';

  @override
  String get ctrlDryScheduleCancel => '取消定时烘干';

  @override
  String get ctrlDryScheduleDismiss => '忽略';

  @override
  String ctrlDryScheduleFailed(String reason) {
    return '定时烘干失败：$reason';
  }

  @override
  String get ctrlDryScheduleFailedUnknown => '未知错误';

  @override
  String get ctrlDryWaitPower => '请连接 AMS 电源适配器';

  @override
  String get ctrlDryWaitRetract => '请在 AMS 出料口回抽耗材';

  @override
  String get ctrlDryWaitBlocked => 'AMS 当前无法开始烘干';

  @override
  String get ctrlDryWaitAmsNotFound => '等待检测到 AMS';

  @override
  String get ctrlDryWaitOffline => '等待打印机上线';

  @override
  String get ctrlDryWaitBusy => '等待打印机空闲';

  @override
  String get ctrlDryWaitAlreadyDrying => '等待当前烘干循环结束';

  @override
  String get ctrlDryWaitInterrupted => '已中断，打印机空闲后会自动重新开始';

  @override
  String get ctrlMove => '移动';

  @override
  String get ctrlMoveHome => '全轴归位';

  @override
  String get ctrlMoveHomeStarted => '已开始归位';

  @override
  String get ctrlMoveStep => '步进';

  @override
  String get ctrlMoveZ => 'Z 轴';

  @override
  String get ctrlMoveZUp => '向上';

  @override
  String get ctrlMoveZDown => '向下';

  @override
  String get ctrlMoveZUnknownDirection =>
      '该打印机的 Z 轴方向取决于服务器版本，目前无法确认，因此已停用这里的 Z 轴移动。请更新服务器，或在服务器可访问后重新打开此面板。';

  @override
  String get ctrlMoveZNoModel =>
      '该打印机在 Bambuddy 中未设置型号，应用无法判断 Z 轴移动的是热床还是工具头，因此已停用这里的 Z 轴移动。请在 Bambuddy 中设置型号后再使用。';

  @override
  String get ctrlMoveExtrude => '挤出';

  @override
  String get ctrlMoveRetract => '回抽';

  @override
  String get ctrlMoveLength => '长度';

  @override
  String ctrlMoveMm(int d) {
    return '$d 毫米';
  }

  @override
  String ctrlMoveAxisPlus(String axis) {
    return '正向移动 $axis 轴';
  }

  @override
  String ctrlMoveAxisMinus(String axis) {
    return '负向移动 $axis 轴';
  }

  @override
  String get ctrlPause => '暂停';

  @override
  String get ctrlResume => '继续';

  @override
  String get ctrlStop => '停止';

  @override
  String get ctrlStopConfirmTitle => '停止打印？';

  @override
  String get ctrlStopConfirmBody => '这将取消当前打印，且无法恢复。';

  @override
  String get ctrlForbidden => '没有控制该打印机的权限';

  @override
  String get ctrlFailed => '命令发送失败';

  @override
  String get skipObjectsTitle => '跳过对象';

  @override
  String get skipObjectsSkip => '跳过';

  @override
  String get skipObjectsSkippedTag => '已跳过';

  @override
  String skipObjectsSkippedToast(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已跳过 $count 个对象',
      one: '已跳过“$names”',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '跳过 $count 个对象？',
      one: '跳过此对象？',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsConfirmBody(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '“$names”将在本次打印剩余时间内被跳过，且无法撤销。',
      one: '“$names”将在本次打印剩余时间内被跳过，且无法撤销。',
    );
    return '$_temp0';
  }

  @override
  String skipObjectsSelectedCount(int count) {
    return '已选中 $count 个';
  }

  @override
  String get skipObjectsSelectHint => '点击上方或下方的对象，将其选中以跳过';

  @override
  String get skipObjectsMatchInfo => '与打印机屏幕上的编号对照';

  @override
  String get skipObjectsMatchHint => '打印机屏幕会显示打印板上的对象编号';

  @override
  String skipObjectsCounter(int skipped, int total) {
    return '已跳过 $skipped/$total';
  }

  @override
  String skipObjectsActiveCount(int count) {
    return '$count 个进行中';
  }

  @override
  String skipObjectsWaitForLayer(int layer) {
    return '从第 2 层起可跳过（当前第 $layer 层）';
  }

  @override
  String get skipObjectsEmpty => '没有可打印的对象';

  @override
  String get skipObjectsEmptyHint => '对象会在开始打印时加载。若正在打印，请重新加载。';

  @override
  String get skipObjectsReload => '重新加载';

  @override
  String get skipObjectsLoadFailed => '无法加载可打印对象。';

  @override
  String get speedSilent => '静音';

  @override
  String get speedStandard => '标准';

  @override
  String get speedSport => '运动';

  @override
  String get speedLudicrous => '狂暴';

  @override
  String get smartPlugOn => '已开启';

  @override
  String get smartPlugOff => '已关闭';

  @override
  String get smartPlugUnreachable => '无法连接';

  @override
  String get smartPlugMonitorOnly => '仅监测';

  @override
  String get smartPlugCantPowerOff => '打印机正在打印，无法断电';

  @override
  String get smartPlugOffConfirmTitle => '切断电源？';

  @override
  String get smartPlugOffConfirmBody => '打印机会立即断电。';

  @override
  String get smartPlugTurnOff => '关闭电源';

  @override
  String get smartPlugOnConfirmTitle => '接通电源？';

  @override
  String get smartPlugOnConfirmBody => '打印机将通电开机。';

  @override
  String get smartPlugTurnOn => '接通电源';

  @override
  String powerWatts(int watts) {
    return '$watts W';
  }

  @override
  String get totalPowerTooltip => '所有插座的合计功耗';

  @override
  String get powerBreakdownTitle => '功耗';

  @override
  String get powerUnassignedPlugs => '未分配给打印机';

  @override
  String get plugStateOn => '已开启';

  @override
  String get plugStateOff => '已关闭';

  @override
  String get queueEmpty => '队列为空';

  @override
  String get queueAmsFromSlicer => '切片器指定的 AMS';

  @override
  String queueColorSubstitution(int slot, String got, String wanted) {
    return '槽位 $slot 使用 $got 打印，文件要求 $wanted';
  }

  @override
  String queueColorSubstitutionSlots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个槽位',
    );
    return '$_temp0';
  }

  @override
  String get queueColorSubstitutionTitle => '使用了其他颜色';

  @override
  String get queueColorSubstitutionWhy => '没有装载文件所需颜色的料盘，或该槽位是手动选择的。';

  @override
  String queueColorSubstitutionSlot(int slot) {
    return '槽位 $slot';
  }

  @override
  String get queueColorSubstitutionPrinted => '实际使用';

  @override
  String get queueColorSubstitutionWanted => '文件要求';

  @override
  String queueAnyOfModels(String models) {
    return '以下任一：$models';
  }

  @override
  String get queueDeleteTitle => '从队列中移除？';

  @override
  String get queueDeleteBody => '该项将从打印队列中移除。';

  @override
  String get queueDeleteConfirm => '移除';

  @override
  String get queueStart => '立即开始';

  @override
  String get queueStartNext => '开始下一个';

  @override
  String get queueCancel => '取消';

  @override
  String get queueStop => '停止打印';

  @override
  String get queueStopTitle => '停止此打印任务？';

  @override
  String get queueStopBody => '打印机会停止打印，该项将移出队列。已打印的部分无法继续。';

  @override
  String get queueStopConfirm => '停止打印';

  @override
  String get queueRemove => '从队列移除';

  @override
  String get queueRemoveStoppedTitle => '从队列中移除？';

  @override
  String get queueRemoveStoppedBody => '打印机未显示该任务正在运行。移除后会将该项从队列中清除。';

  @override
  String get queueStopped => '打印已停止';

  @override
  String get queueRemoved => '已从队列移除';

  @override
  String get queueRemovalStatusChanged => '该项的状态已改变，请刷新队列后重试。';

  @override
  String queueResumeBanner(String printer, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个任务被跳过',
    );
    return '$printer：打印失败后有 $_temp0';
  }

  @override
  String queueResumeModelBanner(String model, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个任务在等待',
    );
    return '任一 $model：打印失败后有 $_temp0';
  }

  @override
  String queueResumeModelConfirmBody(String model) {
    return '等待中的任务将在下一台空闲的 $model 上开始。打印机都准备好了吗？';
  }

  @override
  String get queueResumeButton => '恢复';

  @override
  String get queueResumeConfirmTitle => '失败后恢复队列？';

  @override
  String queueResumeConfirmBody(int count, String printer) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个被跳过的任务',
    );
    return '$_temp0将回到 $printer 的队列。打印机准备好了吗？';
  }

  @override
  String queueResumed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个任务已回到队列',
      zero: '队列已恢复',
    );
    return '$_temp0';
  }

  @override
  String queueSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选中 $count 项',
    );
    return '$_temp0';
  }

  @override
  String get queueSelectAll => '全选等待项';

  @override
  String get queueBulkEdit => '编辑所选';

  @override
  String queueBulkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '编辑 $count 项',
    );
    return '$_temp0';
  }

  @override
  String get queueBulkIntro => '只有你选择的内容会改变。再次点击可撤销该选择。';

  @override
  String get queueBulkNoChange => '不更改';

  @override
  String get queueBulkUnassigned => '无打印机（未分配）';

  @override
  String get queueBulkQueueOptions => '队列选项';

  @override
  String get queueBulkApply => '应用更改';

  @override
  String get queueOptUseAms => '使用 AMS';

  @override
  String queueBulkUpdated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已更新 $count 项',
    );
    return '$_temp0';
  }

  @override
  String get queueBulkNothingUpdated => '没有更改';

  @override
  String queueBulkSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已跳过 $count 项',
    );
    return '$_temp0';
  }

  @override
  String get queueNoFreePrinters => '当前没有空闲的打印机';

  @override
  String get queuePrintStarted => '已开始打印';

  @override
  String get queueStatusPending => '等待中';

  @override
  String get queueStatusScheduled => '已排期';

  @override
  String get queueStatusPrinting => '打印中';

  @override
  String get queueStatusPaused => '已暂停';

  @override
  String get archiveSearchHint => '搜索归档';

  @override
  String get archiveEmpty => '暂无归档记录';

  @override
  String get archiveNoMatches => '没有符合筛选条件的打印';

  @override
  String get archiveFilters => '筛选';

  @override
  String get archiveFiltersClear => '清除筛选';

  @override
  String get archiveSortLabel => '排序方式';

  @override
  String get archiveSortDateDesc => '最新在前';

  @override
  String get archiveSortDateAsc => '最早在前';

  @override
  String get archiveSortNameAsc => '名称 A–Z';

  @override
  String get archiveSortNameDesc => '名称 Z–A';

  @override
  String get archiveSortSizeDesc => '最大在前';

  @override
  String get archiveSortSizeAsc => '最小在前';

  @override
  String get archiveFilterFileType => '文件';

  @override
  String get archiveFileTypeAll => '全部文件';

  @override
  String get archiveFileTypeGcode => '已切片';

  @override
  String get archiveFileTypeSource => '源文件';

  @override
  String get archiveFilterFlags => '显示';

  @override
  String get archiveFilterFavorites => '收藏';

  @override
  String get archiveFilterHideFailed => '隐藏失败';

  @override
  String get archiveFilterHideDuplicates => '隐藏重复';

  @override
  String get archiveFilterPrinter => '打印机';

  @override
  String get archiveFilterMaterial => '材料';

  @override
  String get archiveFilterColors => '颜色';

  @override
  String get archiveColorModeAny => '任一';

  @override
  String get archiveColorModeAll => '全部';

  @override
  String get archiveFavorite => '加入收藏';

  @override
  String get archiveUnfavorite => '取消收藏';

  @override
  String get archiveFavoriteFailed => '无法更新收藏';

  @override
  String get archiveReprint => '重新打印';

  @override
  String get archiveAddToQueue => '加入队列';

  @override
  String get archiveReprintNoQueue => '你没有加入队列的权限';

  @override
  String get archiveReprintNotAllowed => '你没有重新打印该任务的权限';

  @override
  String get archiveTimelapse => '观看延时摄影';

  @override
  String archivePhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '查看照片（$count）',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaAction => '录像与照片';

  @override
  String get archiveMediaOnServer => '在服务器上';

  @override
  String archiveMediaOnPrinter(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '在打印机上（$count）',
      zero: '在打印机上',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaSearching => '正在打印机上查找…';

  @override
  String get archiveMediaNothingOnPrinter => '打印机上没有文件';

  @override
  String archiveMediaPhotoCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 张照片',
    );
    return '$_temp0';
  }

  @override
  String get archiveMediaKindTimelapse => '延时摄影';

  @override
  String get archiveMediaKindIpcam => '摄像头';

  @override
  String archiveMediaDownloadSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件',
      zero: '所选项',
    );
    return '下载$_temp0';
  }

  @override
  String get archiveMediaSaved => '视频已保存';

  @override
  String get archiveMediaNoFilePermission => '没有访问打印机文件的权限';

  @override
  String get archiveMediaPrinterMissing => '打印机已不存在';

  @override
  String get archiveMediaTimelapseUnavailable => '延时摄影：打印机无响应';

  @override
  String get archiveMediaIpcamUnavailable => '摄像头：打印机无响应';

  @override
  String archivePlate(int plate) {
    return '打印板 $plate';
  }

  @override
  String archivePlateDetail(int plate) {
    return '多板文件中的第 $plate 板';
  }

  @override
  String get archivePhotosTitle => '照片';

  @override
  String get archivePhotosEmpty => '该打印没有照片';

  @override
  String get archivePhotoFailed => '无法加载该照片。';

  @override
  String get archiveFilamentUsed => '耗材用量';

  @override
  String archiveFilamentGrams(String grams) {
    return '$grams g';
  }

  @override
  String archiveFilamentActual(String grams, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '共 $count 次打印，用量 $grams',
    );
    return '$_temp0';
  }

  @override
  String get archiveFilamentNoActual => '未记录用量';

  @override
  String get archiveFilamentSaving => '保存中';

  @override
  String get archiveFilamentNone => '未记录';

  @override
  String get archiveFilamentLabel => '重量（g）';

  @override
  String get archiveFilamentNotANumber => '请输入数字，留空可清除重量。';

  @override
  String archiveFilamentOutOfRange(String max) {
    return '请输入 0 到 $max g 之间的重量。';
  }

  @override
  String get archiveFilamentSaved => '耗材重量已保存';

  @override
  String get archiveFilamentUnsupported => '该服务器尚不支持手动填写耗材重量，请更新 bambuddy。';

  @override
  String get archiveHasTimelapse => '有延时摄影';

  @override
  String archiveHasPhotos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有 $count 张照片',
    );
    return '$_temp0';
  }

  @override
  String get timelapseTitle => '延时摄影';

  @override
  String get timelapseError => '无法播放该延时摄影。';

  @override
  String timelapseHttpError(int status) {
    return '服务器未提供该延时摄影（$status）。';
  }

  @override
  String get timelapseStalled => '服务器正在传输视频，但播放器未能启动。';

  @override
  String get timelapsePlay => '播放';

  @override
  String get timelapsePause => '暂停';

  @override
  String get timelapseSave => '保存到相册';

  @override
  String get timelapseShare => '分享';

  @override
  String get timelapseSaved => '已保存到相册';

  @override
  String get timelapseSaveFailed => '无法保存视频';

  @override
  String get timelapseSaveDenied => '当前 Android 版本需要授予 Bambuddy 写入相册的权限。';

  @override
  String get timelapseEdit => '编辑';

  @override
  String get timelapseEditSave => '保存';

  @override
  String get timelapseEditTitle => '编辑延时摄影';

  @override
  String get timelapseEditTrim => '裁剪';

  @override
  String get timelapseEditSpeed => '速度';

  @override
  String timelapseEditOutput(String length) {
    return '结果：$length';
  }

  @override
  String timelapseEditSource(String length, int width, int height) {
    return '原始：$length，$width×$height';
  }

  @override
  String get timelapseEditSaveTitle => '覆盖原录像？';

  @override
  String get timelapseEditSaveMessage => '服务器会重新编码延时摄影并替换原文件，且没有备份可还原。';

  @override
  String get timelapseEditProcessing =>
      '服务器正在重新编码视频。配置较低的服务器需要数分钟，离开此页面不会中断处理。';

  @override
  String get timelapseEdited => '延时摄影已更新';

  @override
  String get gcodeViewerTitle => 'G-code 预览';

  @override
  String get gcodeViewerOpen => '预览 G-code';

  @override
  String get gcodeViewerError => '无法加载 G-code 预览。';

  @override
  String get gcodeViewerLoading => '正在下载 G-code…';

  @override
  String get gcodeViewerParsing => '正在读取路径…';

  @override
  String get gcodeViewerTravels => '空移路径';

  @override
  String get gcodeViewerColorByFilament => '按耗材';

  @override
  String get gcodeViewerColorByFeature => '按特征';

  @override
  String get gcodeViewerColorByHeight => '按高度';

  @override
  String get gcodeViewerColorByWidth => '按线宽';

  @override
  String get gcodeSingleLayer => '单层';

  @override
  String gcodeViewerFilamentSlot(int n) {
    return '耗材 $n';
  }

  @override
  String get gcodeViewerEmpty => '该文件没有路径数据，尚未切片。';

  @override
  String gcodeViewerHttpError(int status) {
    return '服务器未提供该文件的 G-code（$status）。';
  }

  @override
  String get gcodeFeatureWall => '外墙';

  @override
  String get gcodeFeatureSparseInfill => '稀疏填充';

  @override
  String get gcodeFeatureSolidInfill => '实心填充';

  @override
  String get gcodeFeatureSkirt => '裙边';

  @override
  String get gcodeFeatureSupport => '支撑';

  @override
  String get gcodeFeatureGapFill => '缝隙填充';

  @override
  String get gcodeFeatureBridge => '桥接 / 悬垂';

  @override
  String get gcodeFeatureIroning => '熨烫';

  @override
  String get gcodeFeaturePrimeTower => '擦料塔';

  @override
  String get archiveNo3mfTitle => '部分近期打印的归档缺少缩略图';

  @override
  String get archiveNo3mfBody =>
      '切片器没有把 .gcode.3mf 留在打印机存储卡上，因此 Bambuddy 无法获取缩略图和切片信息。通常是切片器“设备”页中的“将发送的文件存储到外部存储”已关闭。';

  @override
  String get archiveNo3mfTitleInternal => '部分近期打印留在了打印机内置存储中';

  @override
  String get archiveNo3mfBodyInternal =>
      'Bambu Studio 把切片文件保存到了打印机内置存储而不是存储卡，因此无法通过 FTP 读取。H2 系列和 P2S 的“打印”按钮总是如此，修改切片器设置也没有用。这些打印仍会以名称和时间归档，只是缺少缩略图和切片信息。如需完整归档，请从 Bambuddy 发起打印，或用 OrcaSlicer 切片，并确保打印机中插有存储卡或 U 盘。';

  @override
  String get archiveNo3mfTitleNoStorage => '部分近期打印未能归档：打印机没有存储设备';

  @override
  String get archiveNo3mfBodyNoStorage =>
      '打印机报告卡槽中没有存储卡或 U 盘，切片文件无处存放，Bambuddy 也没有内容可读。插入存储设备后，下一次打印即可完整归档。';

  @override
  String get archiveNo3mfDocs => '参见安装第 4 步';

  @override
  String get archiveNo3mfDocsWhy => '为什么会这样';

  @override
  String get archiveNo3mfDismiss => '关闭此提示';

  @override
  String get archiveNotSliceable => '该打印没有源文件或模型，无法重新切片。';

  @override
  String get archiveDelete => '删除';

  @override
  String get archiveDeleteTitle => '删除打印记录？';

  @override
  String archiveDeleteBody(String name) {
    return '从归档中移除“$name”。';
  }

  @override
  String get archiveDeletePurgeStats => '同时从统计中移除';

  @override
  String get archiveDeletePurgeStatsHint => '否则该打印仍会保留在统计总数中。';

  @override
  String get archiveDeleted => '打印记录已删除';

  @override
  String get archiveDeleteFailed => '无法删除该打印记录';

  @override
  String get archiveSelectAll => '全选';

  @override
  String archiveSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选中 $count 项',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSelectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '删除 $count 条打印记录？',
    );
    return '$_temp0';
  }

  @override
  String get archiveDeleteSelectedBody => '从归档中移除所选的打印记录。';

  @override
  String archiveDeletedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已删除 $count 条打印记录',
    );
    return '$_temp0';
  }

  @override
  String archiveDeleteSomeFailed(int ok, int failed) {
    return '成功 $ok 条，失败 $failed 条';
  }

  @override
  String get archivePurgeOlder => '清理旧打印记录…';

  @override
  String get archivePurgeTitle => '清理旧打印记录';

  @override
  String get archivePurgeOlderThan => '早于';

  @override
  String archivePurgeDaysOption(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days 天',
    );
    return '$_temp0';
  }

  @override
  String archivePurgePreview(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 条打印记录 · $size',
    );
    return '$_temp0';
  }

  @override
  String get archivePurgeNothing => '没有早于该时间的打印记录。';

  @override
  String get archivePurgePreviewError => '无法加载预览。';

  @override
  String archivePurgeResult(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已清理 $count 条打印记录',
      zero: '未清理任何打印记录',
    );
    return '$_temp0';
  }

  @override
  String get pickPrinterTitle => '选择打印机';

  @override
  String get detailsShow => '详情';

  @override
  String get detailsHide => '隐藏详情';

  @override
  String get cameraTooltip => '摄像头';

  @override
  String get cameraConnecting => '正在连接摄像头…';

  @override
  String get cameraError => '无法加载摄像头画面';

  @override
  String get cameraDemoUnavailable => '该演示打印机处于离线状态，没有摄像头画面。';

  @override
  String get nozzleRack => '喷嘴架';

  @override
  String get nozzleRackMounted => '安装在喷头';

  @override
  String nozzleRackPosition(int position, String diameter) {
    return '位置 $position：$diameter mm';
  }

  @override
  String nozzleRackPositionEmpty(int position) {
    return '位置 $position：空';
  }

  @override
  String get externalInputs => '外部输入';

  @override
  String externalInputsEmpty(int count) {
    return '全部 $count 个外部输入均为空';
  }

  @override
  String get externalSpool => '外置料盘';

  @override
  String get traySlotEmpty => '空';

  @override
  String get traySlotUnconfigured => '未设置';

  @override
  String get amsSlotFilament => '耗材';

  @override
  String get amsLoad => '装载';

  @override
  String get amsUnload => '卸载';

  @override
  String get amsRfidReread => '重新读取标签';

  @override
  String get amsLoadStarted => '正在装载耗材…';

  @override
  String get amsUnloadStarted => '正在卸载耗材…';

  @override
  String get amsRfidRereadStarted => '正在重新读取标签…';

  @override
  String amsFeedTitle(String slot) {
    return '将 $slot 送入哪个喷嘴？';
  }

  @override
  String get amsFeedPrompt => '耗材通道切换器可将该槽位导向任一喷嘴，因此打印机无法判断耗材应去往何处。';

  @override
  String get amsFeedAlreadyLoaded => '已装载';

  @override
  String get amsSwitchNotReady => '耗材通道切换器尚未配置。请先将每个 AMS 分配到打印机的进料口，然后重试。';

  @override
  String get amsUnloadSlotNotLoaded => '该槽位没有为任何喷嘴供料';

  @override
  String amsUnloadAms3h(int slot) {
    return '正在退出料槽 $slot。打印机提示时，请手动将耗材从 AMS 3H 中拉出。';
  }

  @override
  String amsLoadAms3hEmpty(int slot) {
    return '料槽 $slot 中没有耗材。将耗材推入进料口，待 AMS 3H 吸入后重新装料。';
  }

  @override
  String dryAms3hSlots(int a, int b) {
    return 'AMS 3H 仅干燥料槽 $a 和 $b';
  }

  @override
  String get amsActionsWhilePrinting => '打印机打印中，无法使用';

  @override
  String get amsSlotConfigure => '配置槽位';

  @override
  String get amsSlotConfigTitle => '槽位配置';

  @override
  String get amsSlotConfigSearch => '搜索预设';

  @override
  String get amsSlotConfigColour => '颜色';

  @override
  String get amsSlotConfigApply => '写入打印机';

  @override
  String get amsSlotConfigStarted => '正在配置槽位…';

  @override
  String get amsSlotConfigNameNotSaved => '槽位已配置，但预设名称未能保存';

  @override
  String get amsSlotConfigEmpty => '没有可用的耗材预设';

  @override
  String get amsSlotConfigNoMatch => '没有与搜索匹配的预设';

  @override
  String get amsSlotConfigCloudHint => '登录 Bambu Cloud 以从你自己的预设中选择。';

  @override
  String get amsSlotConfigCloudAction => '登录';

  @override
  String get amsSlotConfigTierLocal => '已导入';

  @override
  String get amsSlotConfigTierCloud => 'Bambu Cloud';

  @override
  String get amsSlotConfigTierBuiltin => '内置';

  @override
  String amsSlotConfigOnlyPrinter(String model) {
    return '仅适用于 $model';
  }

  @override
  String amsSlotConfigOnlyPrinterHiding(String model, int hidden) {
    return '仅适用于 $model（隐藏 $hidden 个）';
  }

  @override
  String get amsSlotConfigModelUnknown => '打印机型号未知，显示全部预设';

  @override
  String get amsSlotConfigCurrent => '当前设置';

  @override
  String get amsSlotConfigKProfile => 'K 值配置';

  @override
  String amsSlotConfigKProfileDefault(String value) {
    return '默认（K $value）';
  }

  @override
  String get amsSlotConfigKProfileOther => '其他配置';

  @override
  String get amsSlotConfigKProfileNone => '该打印机没有此喷嘴的 K 值记录';

  @override
  String get amsSlotConfigKProfileUnavailable => '无法读取打印机的 K 值配置';

  @override
  String amsSlotConfigNozzleGuess(String diameter) {
    return '打印机未报告喷嘴口径，暂按 $diameter 毫米处理';
  }

  @override
  String amsSlotConfigKProfileValue(String value) {
    return 'K $value';
  }

  @override
  String get amsSlotConfigColourCatalogue => '标准色卡';

  @override
  String get amsSlotReset => '清空槽位';

  @override
  String get amsSlotResetConfirmTitle => '清空该槽位？';

  @override
  String get amsSlotResetConfirmMessage => '打印机会忘记此处配置的耗材，bambuddy 也会忘记对应的预设。';

  @override
  String get amsSlotResetStarted => '正在清空槽位…';

  @override
  String get extruderLeft => '左挤出机';

  @override
  String get extruderRight => '右挤出机';

  @override
  String get extruderLeftShort => '左';

  @override
  String get extruderRightShort => '右';

  @override
  String amsHistoryTitle(String ams) {
    return '$ams 历史';
  }

  @override
  String get amsHistoryHumidity => '湿度';

  @override
  String get amsHistoryTemperature => '温度';

  @override
  String get sensorHistoryCurrent => '当前';

  @override
  String get sensorHistoryAverage => '平均';

  @override
  String get sensorHistoryMin => '最低';

  @override
  String get sensorHistoryMax => '最高';

  @override
  String get sensorHistoryRange6h => '6 小时';

  @override
  String get sensorHistoryRange24h => '24 小时';

  @override
  String get sensorHistoryRange48h => '48 小时';

  @override
  String get sensorHistoryRange7d => '7 天';

  @override
  String get amsHistoryGood => '良好';

  @override
  String get amsHistoryFair => '一般';

  @override
  String get sensorHistoryEmpty => '该时间范围内没有数据';

  @override
  String get sensorHistoryError => '无法加载历史数据';

  @override
  String get amsHistoryRecordingInfo => '打印机连接期间每 5 分钟记录一次';

  @override
  String get heaterHistoryTitle => '温度历史';

  @override
  String get heaterHistoryReading => '实测';

  @override
  String get heaterHistoryTarget => '目标';

  @override
  String get heaterHistoryRecordingInfo => '打印机连接期间每分钟记录一次';

  @override
  String get doorOpen => '舱门已打开';

  @override
  String get doorClosed => '舱门已关闭';

  @override
  String get firmwareUpToDate => '固件已是最新';

  @override
  String firmwareUpdateAvailable(String version) {
    return '有可用固件更新：$version';
  }

  @override
  String get statusUnavailable => '状态不可用';

  @override
  String get statusOffline => '离线';

  @override
  String get online => '在线';

  @override
  String get offline => '离线';

  @override
  String get widgetNoPrinter => '无打印机';

  @override
  String get widgetStatusPrinting => '打印中';

  @override
  String get widgetStatusPaused => '已暂停';

  @override
  String get widgetStatusFinished => '已完成';

  @override
  String get widgetStatusIdle => '空闲';

  @override
  String get widgetStatusOffline => '离线';

  @override
  String get widgetStatusError => '出错';

  @override
  String get widgetMultiTitle => '打印机';

  @override
  String widgetMultiActive(int active, int total) {
    return '$active/$total 台运行中';
  }

  @override
  String widgetMultiMore(int count) {
    return '还有 $count 台';
  }

  @override
  String get widgetMultiGaugeLabel => '打印中';

  @override
  String widgetMultiIdleCount(int count) {
    return '$count 台空闲';
  }

  @override
  String widgetMultiOfflineCount(int count) {
    return '$count 台离线';
  }

  @override
  String remaining(String time) {
    return '剩余 $time';
  }

  @override
  String eta(String time) {
    return '预计 $time 完成';
  }

  @override
  String durationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String durationHoursMinutes(int hours, int minutes) {
    return '$hours小时$minutes分钟';
  }

  @override
  String durationHours(int hours) {
    return '$hours 小时';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String get connectToServer => '连接服务器';

  @override
  String get serverAddressLabel => 'bambuddy 服务器地址';

  @override
  String get serverAddressHint => '例如 192.168.1.10:8000';

  @override
  String get serverAddressHelper => '远程访问：通过反向代理使用 HTTPS';

  @override
  String get testConnection => '测试连接';

  @override
  String get serverRequiresAuth => '该服务器需要身份验证';

  @override
  String get authModeApiKey => 'API 密钥（推荐）';

  @override
  String get authModeLogin => '用户名与密码';

  @override
  String get apiKeyExplain => 'API 密钥不会过期且权限受限。请在服务器上创建：设置 → API 密钥。';

  @override
  String get apiKeyLabel => 'API 密钥';

  @override
  String get saveAndConnect => '保存并连接';

  @override
  String get loginExplain => '登录会话 24 小时后过期。勾选“记住我”可让应用自动重新登录。';

  @override
  String get usernameLabel => '用户名或邮箱';

  @override
  String get passwordLabel => '密码';

  @override
  String get rememberMe => '记住我';

  @override
  String get rememberMeSubtitle => '密码保存在加密存储中（Android Keystore）';

  @override
  String get signInAndConnect => '登录并连接';

  @override
  String get twoFactorTitle => '二次验证';

  @override
  String get twoFactorMethodTotp => '验证器应用';

  @override
  String get twoFactorMethodEmail => '电子邮件';

  @override
  String get twoFactorMethodBackup => '备用码';

  @override
  String get twoFactorExplainTotp => '请输入验证器应用中的 6 位验证码。';

  @override
  String get twoFactorExplainEmail => '让服务器向你的邮箱发送 6 位验证码，然后在此输入。';

  @override
  String get twoFactorExplainEmailSent => '6 位验证码已发送至你账号绑定的邮箱，10 分钟内有效。';

  @override
  String get twoFactorExplainBackup => '请输入设置二次验证时保存的 8 位备用码之一，每个只能用一次。';

  @override
  String get twoFactorCodeLabel => '验证码';

  @override
  String get twoFactorSendEmail => '发送验证码到邮箱';

  @override
  String get twoFactorResendEmail => '重新发送验证码';

  @override
  String get twoFactorVerify => '确认并连接';

  @override
  String get twoFactorBack => '使用其他账号';

  @override
  String get twoFactorSessionNote =>
      '应用无法自行续期二次验证会话，本次会话过期后会再次要求验证。API 密钥不会过期，可跳过此步骤。';

  @override
  String get tryDemo => '试用演示';

  @override
  String customCaTrusted(String name) {
    return '已信任的 CA：$name';
  }

  @override
  String get customCaRemove => '移除 CA 证书';

  @override
  String get certificateImport => '导入证书';

  @override
  String get certificateInvalid => '该文件不包含证书';

  @override
  String get clientCertInvalid => '该文件不包含带私钥的客户端证书';

  @override
  String get customCaPickFailed => '无法打开文件';

  @override
  String clientCertInUse(String name) {
    return '客户端证书：$name';
  }

  @override
  String get clientCertRemove => '移除客户端证书';

  @override
  String get clientCertWrongPassword => '证书密码错误';

  @override
  String get clientCertPasswordTitle => '证书密码';

  @override
  String get certificatesTitle => '证书';

  @override
  String get customCaRemoveTitle => '确定移除 CA 证书？';

  @override
  String get customCaRemoveMessage => '应用将不再信任由其签发的服务器。';

  @override
  String get clientCertRemoveTitle => '确定移除客户端证书？';

  @override
  String get clientCertRemoveMessage => '要求提供该证书的服务器将拒绝应用连接。';

  @override
  String get certificatesRemoveAll => '移除全部证书';

  @override
  String get certificatesRemoveAllTitle => '确定移除全部证书？';

  @override
  String get certificatesRemoveAllMessage => '应用将无法再连接需要这些证书的服务器。';

  @override
  String get certificateRemoveConfirm => '移除';

  @override
  String get scanApiKeyTitle => '扫描 API 密钥';

  @override
  String get scanApiKeyHint => '将摄像头对准 API 密钥二维码';

  @override
  String get cameraPermissionTitle => '需要摄像头权限';

  @override
  String get cameraPermissionBody => '请允许使用摄像头以扫描二维码。';

  @override
  String get scannerTorch => '手电筒';

  @override
  String get errMissingUrl => '请输入服务器地址';

  @override
  String get errMissingApiKey => '请输入 API 密钥';

  @override
  String get errMissingCredentials => '请输入用户名和密码';

  @override
  String get errRequiresServerSetup => '服务器需要完成初始设置，请在浏览器中完成后再回到这里。';

  @override
  String get errServerUnreachable => '无法连接服务器';

  @override
  String get errUnauthorized => '未通过身份验证';

  @override
  String get errForbidden => '无权限，服务器拒绝了该操作';

  @override
  String errForbiddenDetail(String reason) {
    return '无权限：$reason';
  }

  @override
  String get errApiKeyOwnerDisabled => '该 API 密钥所属账号已被停用或删除，账号恢复前该密钥将一直被拒绝。';

  @override
  String errBadResponse(int code) {
    return '服务器返回错误 $code';
  }

  @override
  String get errBadCertificate => '服务器证书不受信任';

  @override
  String get errClientCertRefused => '服务器要求提供有效的客户端证书';

  @override
  String get errConnection => '连接出错';

  @override
  String get errMalformedResponse => '服务器返回内容格式错误';

  @override
  String get errNotBambuddy => '该地址不是 Bambuddy 服务器——请检查端口，并去掉地址后面的路径。';

  @override
  String get errInvalidCredentials => '用户名或密码错误';

  @override
  String get errTwoFactorUnsupported =>
      '该账号需要二次验证，此版本尚不支持。请改用 API 密钥（服务器：设置 → API 密钥）。';

  @override
  String get errTwoFactorCodeRejected => '验证码错误，请检查后重试。';

  @override
  String get errTwoFactorChallengeExpired => '登录尝试已超时，请重新输入密码以获取新的验证码。';

  @override
  String get errTwoFactorMethodUnavailable => '该账号不支持此方式，请选择其他方式。';

  @override
  String get errTwoFactorEmailUnavailable =>
      '服务器无法发送验证码：未配置邮件服务，或账号未绑定邮箱。请换用其他方式。';

  @override
  String get errMissingTwoFactorCode => '请输入验证码';

  @override
  String get errApiKeyRejected => 'API 密钥被拒绝，请检查密钥及其权限范围（需要 can_read_status）';

  @override
  String get errTooManyAttempts => '尝试次数过多，服务器已暂时禁止登录数分钟。请稍后重试，或改用 API 密钥。';

  @override
  String notifOngoingBody(int percent, String eta) {
    return '$percent% · 预计 $eta 完成';
  }

  @override
  String get notifEtaSoon => '即将完成';

  @override
  String get demoSettingsSection => '演示';

  @override
  String get demoPrintingCountTitle => '正在打印的打印机';

  @override
  String get demoPrintingCountDesc => '演示中有多少台打印机同时打印，用于查看多台打印机对仪表盘和常驻通知的影响。';

  @override
  String notifOngoingMultiBody(String printer, int percent, String eta) {
    return '$printer（$percent% · 预计 $eta 完成）';
  }

  @override
  String notifOngoingMultiBodyNoEta(String printer, int percent) {
    return '$printer（$percent%）';
  }

  @override
  String get printFinishedTitle => '打印完成';

  @override
  String printFinishedBody(String name) {
    return '$name 已完成';
  }

  @override
  String get printFailedTitle => '打印失败';

  @override
  String printFailedBody(String name) {
    return '$name 失败';
  }

  @override
  String get notifStartedTitle => '已开始打印';

  @override
  String notifStartedBody(String name) {
    return '$name 已开始打印';
  }

  @override
  String get notifFirstLayerTitle => '首层完成';

  @override
  String notifFirstLayerBody(String name) {
    return '$name 已完成首层';
  }

  @override
  String notifMilestoneTitle(int percent) {
    return '已打印 $percent%';
  }

  @override
  String notifMilestoneBody(String name, int percent) {
    return '$name 已完成 $percent%';
  }

  @override
  String get notifPlateTitle => '打印板未清空';

  @override
  String notifPlateBody(String printer) {
    return '$printer 需要在下一个任务前清空打印板';
  }

  @override
  String get notifOfflineTitle => '打印机离线';

  @override
  String notifOfflineBody(String printer) {
    return '$printer 已断开连接';
  }

  @override
  String get notifErrorTitle => '打印机出错';

  @override
  String notifErrorBody(String printer, String detail) {
    return '$printer：$detail';
  }

  @override
  String get notifLowFilamentTitle => '耗材不足';

  @override
  String notifLowFilamentBody(String printer, int percent) {
    return '$printer 剩余耗材 $percent%';
  }

  @override
  String get notifHumidityTitle => 'AMS 湿度偏高';

  @override
  String get notifHumidityHtTitle => 'AMS-HT 湿度偏高';

  @override
  String notifHumidityBody(String printer, int value) {
    return '$printer 的 AMS 湿度为 $value%';
  }

  @override
  String get notifBedCooledTitle => '热床已降温';

  @override
  String notifBedCooledBody(String printer, int temp) {
    return '$printer 热床已降至 $temp°C';
  }

  @override
  String get notifSettingsTitle => '通知';

  @override
  String get notifSettingsHint => '选择哪些事件会触发通知。更改将在下次启动后台监控时生效。';

  @override
  String get notifMasterTitle => '事件通知';

  @override
  String get notifMasterDesc => '关闭后所有提醒静音，常驻的打印进度通知仍会保留。';

  @override
  String get notifEventsHeader => '事件';

  @override
  String get notifExtrasHeader => '详情';

  @override
  String get notifFinishPhotoTitle => '完成打印的照片';

  @override
  String get notifFinishPhotoDesc => '打印结束时服务器拍下的照片到达后，会附加到完成/失败通知中';

  @override
  String get alarmHeader => '闹钟';

  @override
  String get alarmTitle => '闹钟提醒';

  @override
  String get alarmDesc => '在锁屏上方响铃，直到你手动停止';

  @override
  String get alarmEvtFinished => '打印完成';

  @override
  String get alarmEvtFinishedDesc => '打印成功结束';

  @override
  String get alarmEvtBlocked => '打印因故障停止';

  @override
  String get alarmEvtBlockedDesc => '故障导致打印暂停、停止或失败';

  @override
  String get alarmEvtDrying => '干燥完成';

  @override
  String get alarmEvtDryingDesc => 'AMS 干燥周期结束';

  @override
  String get alarmWindowTitle => '仅限设定时段';

  @override
  String get alarmWindowDesc => '时段之外闹钟保持静音';

  @override
  String get alarmWindowFrom => '开始';

  @override
  String get alarmWindowTo => '结束';

  @override
  String alarmRingFor(int minutes) {
    return '响铃 $minutes 分钟';
  }

  @override
  String get alarmRingForDesc => '之后自动停止';

  @override
  String alarmMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get alarmStop => '停止';

  @override
  String get alarmTest => '测试闹钟';

  @override
  String get alarmTestBody => '闹钟将以这样的声音响起';

  @override
  String get alarmTestFailed => '闹钟无法响铃，请检查通知权限是否已开启。';

  @override
  String get alarmFullScreenNeeded => '未获权限时，闹钟无法覆盖锁屏界面';

  @override
  String get alarmFullScreenAllow => '允许';

  @override
  String get alarmHoursHeader => '时段';

  @override
  String get alarmLengthHeader => '响铃时长';

  @override
  String get alarmSettingsSubtitle => '触发条件、时段与响铃时长';

  @override
  String get alarmExcludedLocationsHeader => '排除的位置';

  @override
  String get alarmExcludedPrintersHeader => '排除的打印机';

  @override
  String get alarmExcludeLocationDesc => '此位置的打印机不会触发闹钟';

  @override
  String get alarmExcludePrinterDesc => '这台打印机不会触发闹钟';

  @override
  String alarmExcludedWithLocation(String location) {
    return '随 $location 一并排除';
  }

  @override
  String get notifThresholdsHeader => '阈值';

  @override
  String get notifEvtStarted => '开始打印';

  @override
  String get notifEvtStartedDesc => '打印开始时';

  @override
  String get notifEvtFinished => '打印完成';

  @override
  String get notifEvtFinishedDesc => '打印成功完成时';

  @override
  String get notifEvtFailed => '打印失败';

  @override
  String get notifEvtFailedDesc => '打印失败时';

  @override
  String get notifEvtFirstLayer => '首层完成';

  @override
  String get notifEvtFirstLayerDesc => '首层打印完成时';

  @override
  String get notifEvtMilestones => '进度节点';

  @override
  String get notifEvtMilestonesDesc => '在 25%、50% 和 75% 时';

  @override
  String get notifEvtPlate => '打印板未清空';

  @override
  String get notifEvtPlateDesc => '下个任务前需要清空打印板时';

  @override
  String get notifEvtOffline => '打印机离线';

  @override
  String get notifEvtOfflineDesc => '打印机断开连接时';

  @override
  String get notifEvtError => '打印机错误（HMS）';

  @override
  String get notifEvtErrorDesc => '打印机报告 HMS 错误时';

  @override
  String get notifEvtLowFilament => '耗材不足';

  @override
  String get notifEvtLowFilamentDesc => '剩余耗材低于阈值时';

  @override
  String get notifEvtHumidity => 'AMS 湿度偏高';

  @override
  String get notifEvtHumidityDesc => 'AMS 湿度高于阈值时';

  @override
  String get notifEvtBedCooled => '热床已降温';

  @override
  String get notifEvtBedCooledDesc => '打印后热床降温时';

  @override
  String notifBedCooledThreshold(int temp) {
    return '热床降至 $temp°C 以下';
  }

  @override
  String printPauseAtLayer(int layer) {
    return '第 $layer 层';
  }

  @override
  String printPauseA11yIn(String duration, int layer) {
    return '下一次暂停在 $duration 后，第 $layer 层';
  }

  @override
  String printPauseA11yLayer(int layer) {
    return '下一次暂停在第 $layer 层';
  }

  @override
  String get serverSettingsPauseWarningSubtitle => '提前多久发出暂停提醒';

  @override
  String get pauseWarningTitle => '暂停提醒';

  @override
  String pauseWarningLabel(String duration) {
    return '暂停前 $duration 提醒';
  }

  @override
  String get pauseWarningDesc => '这是服务器设置：服务器自身的提醒时间也会随之改变，并对所有设备生效。';

  @override
  String get notifEvtPauseUpcoming => '即将暂停';

  @override
  String get notifEvtPauseUpcomingDesc => '在切片器设置的暂停之前提醒';

  @override
  String get notifPauseUpcomingTitle => '即将暂停';

  @override
  String notifPauseUpcomingBody(String name, int minutes, int layer) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes 分钟',
      zero: '不到 1 分钟',
    );
    return '$name：$_temp0后暂停，第 $layer 层';
  }

  @override
  String notifHumidityThreshold(int value) {
    return 'AMS 湿度高于 $value%';
  }

  @override
  String notifLowFilamentThreshold(int percent) {
    return '耗材低于 $percent%';
  }

  @override
  String get notifEventsMenu => '通知事件';

  @override
  String get hmsViewInWiki => '在 Bambu 百科中查看';

  @override
  String hmsErrorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个错误',
    );
    return '$_temp0';
  }

  @override
  String get hmsDismissAll => '全部忽略';

  @override
  String get hmsDismissed => '已在打印机上清除错误';

  @override
  String hmsStillReported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '打印机仍报告 $count 个错误',
    );
    return '$_temp0';
  }

  @override
  String get hmsActionSent => '已发送到打印机';

  @override
  String get hmsActionNotAcknowledged => '打印机未确认该操作，请查看其屏幕';

  @override
  String get hmsStopConfirmTitle => '停止打印？';

  @override
  String hmsStopConfirmBody(String printer) {
    return '$printer 将放弃该打印任务，此操作无法撤销。';
  }

  @override
  String get hmsStopConfirmAction => '停止打印';

  @override
  String get hmsActionResume => '继续';

  @override
  String get hmsActionResumeDefects => '仍然继续';

  @override
  String get hmsActionResumeSolved => '已解决，继续';

  @override
  String get hmsActionProblemSolvedResume => '已解决，继续';

  @override
  String get hmsActionFilamentLoadedResume => '已装载，继续';

  @override
  String get hmsActionProceed => '继续';

  @override
  String get hmsActionStopPrinting => '停止';

  @override
  String get hmsActionIgnoreResume => '忽略并继续';

  @override
  String get hmsActionIgnoreNoReminder => '始终忽略';

  @override
  String get hmsActionDontRemind => '不再提醒';

  @override
  String get hmsActionNoReminder => '忽略';

  @override
  String get hmsActionFilamentExtruded => '已挤出';

  @override
  String get hmsActionRetryFilamentExtruded => '还没，重试';

  @override
  String get hmsActionContinue => '完成，继续';

  @override
  String get hmsActionRetrySolved => '已解决，重试';

  @override
  String get hmsActionDone => '完成';

  @override
  String get hmsActionRetry => '重试';

  @override
  String get hmsActionResumePlain => '继续';

  @override
  String get hmsActionConfirm => '确认';

  @override
  String get hmsActionAbort => '中止';

  @override
  String get hmsActionOk => '确定';

  @override
  String get hmsActionRecheck => '重新检查';

  @override
  String get hmsActionTurnOffFireAlarm => '关闭警报';

  @override
  String get hmsActionStopDrying => '停止烘干';

  @override
  String get hmsActionDisablePurification => '关闭净化';

  @override
  String get batteryOptTitle => '可靠的后台通知';

  @override
  String get batteryOptBody =>
      '为保证应用在后台时仍能收到打印通知，请允许 Bambuddy 不受电池限制运行。在三星手机上这一点尤为重要。';

  @override
  String get batteryOptAllow => '打开设置';

  @override
  String get batteryOptLater => '以后再说';

  @override
  String get batteryOptMenu => '后台通知';

  @override
  String get notificationsReady => '通知已全部就绪';

  @override
  String get notificationsBlocked => '通知已关闭，请在系统设置中开启';

  @override
  String get bgServiceTitle => 'Bambuddy';

  @override
  String get bgServiceText => '正在监控打印机';

  @override
  String get wearOngoingChannel => '打印进度';

  @override
  String get bgMonitoringToggle => '后台监控';

  @override
  String get bgMonitoringSubtitle => '应用关闭后仍持续监控打印，并显示常驻通知。';

  @override
  String get bgMonitoringOn => '后台监控已开启';

  @override
  String get bgMonitoringOff => '后台监控已关闭';

  @override
  String get navDashboard => '打印机';

  @override
  String get navQueue => '队列';

  @override
  String get navArchive => '归档';

  @override
  String get navMaintenance => '维护';

  @override
  String get navFilaments => '耗材';

  @override
  String get inventoryEmpty => '库存中没有料盘';

  @override
  String get inventoryNoMatches => '没有符合搜索的耗材';

  @override
  String get inventorySearchHint => '搜索编号、材料、品牌、颜色…';

  @override
  String get inventoryLowStock => '库存不足';

  @override
  String get inventoryFilters => '筛选';

  @override
  String get inventoryFilterStatus => '状态';

  @override
  String get inventoryStatusActive => '在用';

  @override
  String get inventoryStatusArchived => '已归档';

  @override
  String get inventoryFilterStock => '库存';

  @override
  String get inventoryStockAll => '全部';

  @override
  String get inventoryStockLow => '库存不足';

  @override
  String get inventoryFilterMaterial => '材料';

  @override
  String get inventoryFilterBrand => '品牌';

  @override
  String get inventoryFiltersClear => '清除全部';

  @override
  String get inventorySortLabel => '排序方式';

  @override
  String get inventorySortStandard => '默认';

  @override
  String get inventorySortUsage => '用量';

  @override
  String get inventorySortAdded => '添加时间';

  @override
  String get inventorySortPrice => '单价/kg';

  @override
  String get inventorySortId => 'ID';

  @override
  String inventorySpoolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '$count $_temp0';
  }

  @override
  String inventoryRemaining(String grams) {
    return '剩余 $grams g';
  }

  @override
  String inventoryTotalConsumed(String weight) {
    return '已消耗 $weight';
  }

  @override
  String inventoryOfTotal(int total) {
    return '共 $total g';
  }

  @override
  String get inventoryLocation => '位置';

  @override
  String get inventoryNozzleTemp => '喷嘴温度';

  @override
  String get inventoryNote => '备注';

  @override
  String get inventoryTag => '标签';

  @override
  String get inventoryUsageHistory => '用量记录';

  @override
  String get inventoryUsageEmpty => '暂无用量记录';

  @override
  String inventoryUsageWeight(String grams) {
    return '$grams g';
  }

  @override
  String get inventoryKProfiles => '校准（K）';

  @override
  String inventoryKProfileLine(String nozzle, String k) {
    return '$nozzle 毫米 · K $k';
  }

  @override
  String get inventoryAddSpool => '添加料盘';

  @override
  String inventoryAddSpools(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '添加 $count $_temp0';
  }

  @override
  String get inventoryNewSpool => '新料盘';

  @override
  String get inventoryEditSpool => '编辑料盘';

  @override
  String get inventorySave => '保存';

  @override
  String get inventoryQuantityHint => '一次创建多个相同料盘';

  @override
  String get inventoryEdit => '编辑';

  @override
  String get inventoryDuplicate => '复制';

  @override
  String get inventoryDelete => '删除';

  @override
  String get inventoryArchive => '归档';

  @override
  String get inventoryRestore => '恢复';

  @override
  String get inventoryResetUsage => '重置用量';

  @override
  String get inventoryFieldSlicerPreset => '切片预设';

  @override
  String get inventorySlicerPresetHint => '添加该料盘时使用的打印配置';

  @override
  String get inventorySlicerPresetNone => '无预设';

  @override
  String get inventorySlicerPresetSearch => '搜索预设…';

  @override
  String get inventorySlicerPresetUnavailable =>
      '没有可用的切片预设。请在服务器上启用切片（并连接 Bambu Cloud 以获取云端预设）。';

  @override
  String get inventorySectionPrinterPresets => '各机型预设';

  @override
  String get inventoryPrinterPresetsHint => '此处选择将覆盖料盘自身的预设。';

  @override
  String get inventoryPrinterPresetDefault => '与料盘一致';

  @override
  String inventoryPrinterPresetNozzle(String model, String diameter) {
    return '$model · $diameter 喷嘴';
  }

  @override
  String get inventoryPrinterPresetsLoadFailed => '未读取，保存时不会改动这些设置。';

  @override
  String inventoryProfileDefaultPrefilled(String product) {
    return '已按 $product 的默认值填充';
  }

  @override
  String get inventoryProfileDefaultUse => '设为默认';

  @override
  String inventoryProfileDefaultFor(String product) {
    return '用于 $product';
  }

  @override
  String get inventoryProfileDefaultNeedsMaterial => '请先填写材料';

  @override
  String get inventoryProfileDefaultScope => '适用范围';

  @override
  String get inventoryProfileDefaultAllColors => '所有颜色';

  @override
  String inventoryProfileDefaultColorOnly(String color) {
    return '仅 $color';
  }

  @override
  String get inventoryProfileDefaultSaveFailed => '料盘已保存，但默认配置未保存。';

  @override
  String get serverSettingsProfileDefaultsSubtitle => '新料盘的初始配置';

  @override
  String get profileDefaultsTitle => '配置默认值';

  @override
  String get profileDefaultsDescription =>
      '在料盘表单中点击“设为默认”即可保存一份默认配置。应用时只填充料盘缺少的内容。';

  @override
  String get profileDefaultsEmpty => '暂无已保存的默认值';

  @override
  String get profileDefaultsApply => '应用到料盘';

  @override
  String profileDefaultsApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已填充 $count 个料盘',
      zero: '没有料盘需要它',
    );
    return '$_temp0';
  }

  @override
  String get profileDefaultsDeleteTitle => '删除该默认值？';

  @override
  String profileDefaultsDeleteBody(String product) {
    return '$product：新料盘将不再以它为初始配置；已应用的料盘保持原样。';
  }

  @override
  String profileDefaultsModelPresets(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个机型预设',
    );
    return '$_temp0';
  }

  @override
  String profileDefaultsKProfiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个 K 值配置',
    );
    return '$_temp0';
  }

  @override
  String get inventoryFieldMaterial => '材料';

  @override
  String get inventoryFieldBrand => '品牌';

  @override
  String get inventoryFieldSubtype => '子类型';

  @override
  String get inventoryFieldColorName => '颜色名称';

  @override
  String get inventoryFieldColorHex => '颜色（十六进制）';

  @override
  String get inventoryFieldLabelWeight => '料盘重量（g）';

  @override
  String get inventoryFieldCostPerKg => '每公斤价格';

  @override
  String get inventoryFieldLowStock => '低库存阈值（%）';

  @override
  String get inventoryFieldLocation => '存放位置';

  @override
  String get inventoryFieldNote => '备注';

  @override
  String get inventoryFieldRequired => '必填';

  @override
  String get inventoryFieldInvalidNumber => '请输入数字';

  @override
  String inventoryFieldRange(int min, int max) {
    return '请输入 $min 到 $max 之间的值';
  }

  @override
  String get inventoryFieldNegative => '请输入 0 或更大的值';

  @override
  String get inventorySectionFilament => '耗材';

  @override
  String get inventorySectionColor => '颜色';

  @override
  String get inventorySectionAdditional => '附加信息';

  @override
  String get inventoryFieldEmptySpoolWeight => '空料盘重量（g）';

  @override
  String get inventoryCoreWeightSelect => '选择…';

  @override
  String get inventoryCoreWeightSearch => '搜索料盘…';

  @override
  String get inventoryFieldRemainingWeight => '剩余重量（g）';

  @override
  String get inventoryFieldMeasuredWeight => '实测重量（g）';

  @override
  String get inventoryFieldCategory => '类别';

  @override
  String get inventoryFieldMaterialNumber => '材料编号';

  @override
  String get inventoryMaterialNumberHint => '同一产品的所有料盘共用。';

  @override
  String get inventorySpoolmanCannotClear => 'Spoolman 无法移除此值，请改为其他值。';

  @override
  String get inventoryFieldExtraColors => '附加颜色';

  @override
  String get inventoryExtraColorsHint => '2–8 个十六进制色标，用逗号分隔';

  @override
  String get inventoryFieldEffect => '效果';

  @override
  String get inventoryEffectNone => '无';

  @override
  String get inventoryColorCatalog => '颜色目录';

  @override
  String get inventoryColorSearchHint => '搜索颜色…';

  @override
  String get inventoryColorPickTitle => '选择颜色';

  @override
  String get inventoryColorSelect => '选择';

  @override
  String get inventoryColorNone => '无颜色';

  @override
  String get inventoryLowStockHint => '留空则使用全局阈值';

  @override
  String inventoryRemainingOfLabel(int total) {
    return '共 $total g';
  }

  @override
  String get inventoryDeleteTitle => '删除料盘？';

  @override
  String inventoryDeleteConfirm(String name) {
    return '永久删除 $name？此操作无法撤销。';
  }

  @override
  String get inventoryResetUsageConfirm => '将已消耗耗材计数归零？之后的打印从零开始累计，剩余重量不会改变。';

  @override
  String get inventorySpoolCreated => '料盘已添加';

  @override
  String inventorySpoolsCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '已添加 $count $_temp0';
  }

  @override
  String get inventorySpoolUpdated => '料盘已更新';

  @override
  String get inventorySpoolDeleted => '料盘已删除';

  @override
  String get inventorySpoolArchived => '料盘已归档';

  @override
  String get inventorySpoolRestored => '料盘已恢复';

  @override
  String get inventoryUsageReset => '计数已重置';

  @override
  String get inventoryUnassign => '取消分配';

  @override
  String get inventoryAssign => '分配到槽位';

  @override
  String get inventoryAssignPrinter => '打印机';

  @override
  String get inventoryAssignNoPrinters => '没有可用的打印机';

  @override
  String get inventorySlotAms => 'AMS 槽位';

  @override
  String get inventoryAssignUnit => 'AMS 单元';

  @override
  String get inventoryAssignSlot => '槽位';

  @override
  String get inventoryAssignInput => '输入口';

  @override
  String get inventoryAssignExtruder => '挤出机';

  @override
  String get inventoryAssignExternalHint => '分配到外置料盘架';

  @override
  String get inventoryAssignConfirm => '分配';

  @override
  String get inventoryAssignTitle => '分配料盘';

  @override
  String get inventoryAssignCurrent => '当前在该槽位';

  @override
  String get inventoryAssignPick => '选择料盘';

  @override
  String get inventoryTagBound => '该槽位中的料盘带有标签，因此通过标签关联，而不在此处分配。';

  @override
  String get inventoryReassignTitle => '移动料盘？';

  @override
  String inventoryReassignMessage(String slot) {
    return '该料盘当前在 $slot，将被移出并分配到该槽位。';
  }

  @override
  String get inventoryReassignAction => '移动';

  @override
  String get inventorySpoolAssigned => '料盘已分配';

  @override
  String get inventorySpoolUnassigned => '料盘已取消分配';

  @override
  String get inventoryFromSlot => '加入库存';

  @override
  String get inventoryFromSlotHint => '登记打印机在该槽位报告的带标签料盘';

  @override
  String get inventoryFromSlotDone => '料盘已添加并分配到该槽位';

  @override
  String get inventoryFromSlotNoTag => '打印机已不再报告该槽位中有带标签的料盘';

  @override
  String get inventoryFromSlotOffline => '打印机未连接，无法得知槽位中的料盘';

  @override
  String get inventoryFromSlotUnsupported => '该服务器版本不支持直接从槽位添加料盘';

  @override
  String get inventoryScanSpool => '扫描二维码';

  @override
  String get inventoryScanTitle => '扫描料盘二维码';

  @override
  String get inventoryScanHint => '将摄像头对准料盘二维码';

  @override
  String inventoryScanNotFound(int id) {
    return '未找到 #$id 号料盘';
  }

  @override
  String inventorySelectedCount(int count) {
    return '已选中 $count 项';
  }

  @override
  String get inventorySelectAll => '全选';

  @override
  String inventoryBulkArchiveTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '归档 $count $_temp0？';
  }

  @override
  String get inventoryBulkArchiveBody => '它们将从在用列表中隐藏，之后可以恢复。';

  @override
  String inventoryBulkRestoreTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '恢复 $count $_temp0？';
  }

  @override
  String get inventoryBulkRestoreBody => '它们将回到在用列表。';

  @override
  String inventoryBulkDeleteTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '删除 $count $_temp0？';
  }

  @override
  String get inventoryBulkDeleteBody => '这将永久删除，且无法撤销。';

  @override
  String inventoryBulkResetTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '重置 $count $_temp0的用量？';
  }

  @override
  String get inventoryBulkResetBody => '它们的已消耗耗材计数将归零，剩余重量不会改变。';

  @override
  String inventoryBulkDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '已更新 $count $_temp0';
  }

  @override
  String inventoryBulkPartial(int ok, int failed) {
    return '成功 $ok 个，失败 $failed 个';
  }

  @override
  String inventoryBulkSkipped(int ok, int skipped) {
    return '成功 $ok 个，$skipped 个已存在';
  }

  @override
  String inventoryBulkPartialSkipped(int ok, int skipped, int failed) {
    return '成功 $ok 个，$skipped 个已存在，失败 $failed 个';
  }

  @override
  String get inventoryBulkEdit => '编辑字段';

  @override
  String inventoryBulkEditTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '编辑 $count $_temp0';
  }

  @override
  String get inventoryBulkEditHint => '只修改你填写的字段，其余留空即可。';

  @override
  String get inventoryBulkEditUnchanged => '不修改';

  @override
  String inventoryBulkEditApply(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '应用到 $count $_temp0';
  }

  @override
  String inventoryBulkEditConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个料盘',
    );
    return '修改 $count $_temp0？';
  }

  @override
  String inventoryBulkEditConfirmBody(int fields) {
    String _temp0 = intl.Intl.pluralLogic(
      fields,
      locale: localeName,
      other: '个字段',
    );
    return '$fields $_temp0将在每个所选料盘上被覆盖。';
  }

  @override
  String get inventoryBulkEditUnsupported =>
      '该服务器版本过旧，不支持批量编辑。请更新 bambuddy，或逐个编辑料盘。';

  @override
  String get inventoryBulkEditConfirmSuppliers => '供应商会添加到每个所选料盘。';

  @override
  String get inventoryApply => '应用';

  @override
  String get inventoryLabelsTitle => '打印料盘标签';

  @override
  String get inventoryLabelsPrint => '打印标签';

  @override
  String get inventoryLabelsPrintAll => '为全部打印标签';

  @override
  String get inventoryClimateTitle => '存放环境';

  @override
  String get inventoryClimateTitleAlerting => '存放环境：超出提醒范围';

  @override
  String get inventoryClimateSource =>
      '这些数据由服务器从 Home Assistant 读取。传感器需在 Bambuddy 网页界面中绑定到位置。';

  @override
  String get inventoryClimateNoReading => '无读数';

  @override
  String inventoryClimateReading(String name, String value) {
    return '$name：$value';
  }

  @override
  String inventoryClimateReadingAlerting(String name, String value) {
    return '$name：$value，超出提醒范围';
  }

  @override
  String inventoryClimateReadingStale(String name, String value) {
    return '$name：$value，传感器无法连接';
  }

  @override
  String get inventoryLabelsSearchHint => '搜索名称、品牌或 #ID';

  @override
  String get inventoryLabelsPickSpools => '选择要打印标签的料盘：';

  @override
  String get inventoryLabelsMaterial => '材料：';

  @override
  String get inventoryLabelsAllMaterials => '全部';

  @override
  String get inventoryLabelsSort => '排序：';

  @override
  String get inventoryLabelsSortById => '按 ID';

  @override
  String get inventoryLabelsSortByColor => '按颜色';

  @override
  String get inventoryLabelsSelectVisible => '选择可见项';

  @override
  String get inventoryLabelsDeselectVisible => '取消选择可见项';

  @override
  String get inventoryLabelsClearAll => '清除全部';

  @override
  String get inventoryLabelsNoMatches => '没有符合当前搜索或筛选的料盘。';

  @override
  String get inventoryLabelsMonochrome => '单色（黑白打印机）';

  @override
  String get inventoryLabelsMonochromeHint => '去掉色块并加宽文字';

  @override
  String get inventoryLabelsShare => '分享 PDF 而不打印';

  @override
  String get inventoryLabelsPickTemplate => '选择要打印的标签尺寸：';

  @override
  String inventoryLabelsTooMany(int max) {
    return '每次最多选择 $max 个料盘';
  }

  @override
  String get inventoryLabelsFailed => '无法生成标签';

  @override
  String get inventoryLabelsAmsSmall => 'AMS 支架 — 小号（74 × 33 毫米）';

  @override
  String get inventoryLabelsAmsSmallHint =>
      '每页一张；与 MakerWorld 模型 752566 的可打印标签一致。';

  @override
  String get inventoryLabelsAmsLarge => 'AMS 支架 — 大号（75 × 55 毫米）';

  @override
  String get inventoryLabelsAmsLargeHint => '每页一张；适合同款支架的卡纸插入版。';

  @override
  String get inventoryLabelsBox40 => '包装盒标签（40 × 30 毫米）';

  @override
  String get inventoryLabelsBox40Hint => '每页一张；常见的 DK/Brother 卷纸尺寸，适合收纳袋和收纳盒。';

  @override
  String get inventoryLabelsBox62 => '包装盒标签（62 × 29 毫米）';

  @override
  String get inventoryLabelsBox62Hint => '每页一张；适用于 Brother PT/QL 和 Dymo 小标签。';

  @override
  String get inventoryLabelsAveryL7160 =>
      'Avery L7160 — A4 整张（38.1 × 63.5 毫米 × 21）';

  @override
  String get inventoryLabelsAveryL7160Hint => '欧标纸张；每张 A4 排 21 枚标签。';

  @override
  String get inventoryLabelsAvery5160 =>
      'Avery 5160 — US Letter 整张（25.4 × 66.7 毫米 × 30）';

  @override
  String get inventoryLabelsAvery5160Hint => '美标纸张；每张 Letter 排 30 枚标签。';

  @override
  String get inventoryLabelsStartTitle => '第一枚空标签';

  @override
  String get inventoryLabelsStartHint =>
      '点选第一枚标签要打印的位置，之前的位置会留空，这样用剩的半张纸能接着用完，而不必重新开始。';

  @override
  String inventoryLabelsStartSlot(int position) {
    return '第 $position 位';
  }

  @override
  String get labelSheetCustom => '自定义标签纸';

  @override
  String get labelSheetCustomHint => '自定义纸张、标签尺寸与排版网格';

  @override
  String get labelSheetSavedTitle => '已存模板';

  @override
  String labelSheetSummary(
    String page,
    String width,
    String height,
    int count,
    int columns,
    int rows,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个标签',
      one: '$count 个标签',
    );
    return '$page · $width × $height mm · $_temp0（$columns × $rows）';
  }

  @override
  String get labelSheetPageA4 => 'A4';

  @override
  String get labelSheetPageLetter => 'Letter';

  @override
  String get labelSheetPage => '纸张';

  @override
  String get labelSheetLabelWidth => '标签宽度（mm）';

  @override
  String get labelSheetLabelHeight => '标签高度（mm）';

  @override
  String get labelSheetColumns => '列数';

  @override
  String get labelSheetRows => '行数';

  @override
  String get labelSheetTopMargin => '上边距（mm）';

  @override
  String get labelSheetLeftMargin => '左边距（mm）';

  @override
  String get labelSheetColumnGap => '列间距（mm）';

  @override
  String get labelSheetRowGap => '行间距（mm）';

  @override
  String get labelSheetIncomplete => '请在每个字段中填入数字。';

  @override
  String labelSheetTooSmall(int minWidth, int minHeight) {
    return '标签宽度至少 $minWidth mm，高度至少 $minHeight mm。';
  }

  @override
  String labelSheetTooLong(int max) {
    return '尺寸、边距与间距最大为 $max mm。';
  }

  @override
  String labelSheetColumnsRange(int max) {
    return '列数必须为 1 到 $max 之间的整数。';
  }

  @override
  String labelSheetRowsRange(int max) {
    return '行数必须为 1 到 $max 之间的整数。';
  }

  @override
  String get labelSheetNegative => '边距与间距不能为负数。';

  @override
  String labelSheetTooWide(String size, String page) {
    return '含左边距后标签宽度为 $size mm，但纸张宽度仅 $page mm。';
  }

  @override
  String labelSheetTooTall(String size, String page) {
    return '含上边距后标签高度为 $size mm，但纸张高度仅 $page mm。';
  }

  @override
  String get labelSheetUse => '使用此标签纸';

  @override
  String get labelSheetName => '模板名称';

  @override
  String get labelSheetNameTaken => '已存在同名模板。';

  @override
  String get labelSheetSaveAs => '存为模板';

  @override
  String get labelSheetSaveChanges => '保存修改';

  @override
  String get labelSheetDelete => '删除模板';

  @override
  String labelSheetSaved(String name) {
    return '模板“$name”已保存';
  }

  @override
  String labelSheetDeleted(String name) {
    return '模板“$name”已删除';
  }

  @override
  String labelSheetDeleteTitle(String name) {
    return '删除模板“$name”？';
  }

  @override
  String get labelSheetDeleteBody => '已用该模板打印的标签不受影响。';

  @override
  String get labelSheetEdit => '编辑模板';

  @override
  String get labelSheetSaveAsNew => '另存为新模板';

  @override
  String labelPngTooLarge(int maxPages, int dpi, int pages) {
    return 'PNG 在 $dpi dpi 下最多 $maxPages 页，而本次需要 $pages 页。请改用 PDF、降低分辨率或减少料盘数量。';
  }

  @override
  String get maintenanceEmpty => '暂无维护数据';

  @override
  String maintenanceTotalHours(int hours) {
    return '累计 $hours 小时';
  }

  @override
  String maintenanceDueBadge(int count) {
    return '$count 项到期';
  }

  @override
  String maintenanceDueIn(int hours) {
    return '$hours 小时后到期';
  }

  @override
  String maintenanceOverdueBy(int hours) {
    return '已逾期 $hours 小时';
  }

  @override
  String get maintenancePerform => '标记完成';

  @override
  String get maintenancePerformConfirm => '重置该维护任务的计数？';

  @override
  String get maintenanceNotesHint => '备注（可选）';

  @override
  String get maintenanceHistory => '历史记录';

  @override
  String get maintenanceHistoryEmpty => '暂无历史记录';

  @override
  String get maintenanceDone => '维护已标记为完成';

  @override
  String get maintenanceSaved => '已保存';

  @override
  String get maintenanceSettingsTitle => '维护设置';

  @override
  String get maintenanceOverridesTitle => '周期覆盖';

  @override
  String get maintenanceOverridesSubtitle => '按打印机静音任务或自定义周期';

  @override
  String get maintenanceMute => '静音';

  @override
  String get maintenanceUnmute => '取消静音';

  @override
  String get maintenanceMuted => '任务已静音';

  @override
  String get maintenanceUnmuted => '任务已取消静音';

  @override
  String get maintenanceEditInterval => '编辑周期';

  @override
  String get maintenanceResetInterval => '恢复默认';

  @override
  String get maintenanceTypesTitle => '维护类型';

  @override
  String get maintenanceTypesSubtitle => '系统类型与你的自定义任务';

  @override
  String get maintenanceRestoreDefaults => '恢复默认';

  @override
  String get maintenanceRestoreConfirm => '恢复所有已隐藏的默认维护类型？';

  @override
  String get maintenanceAddType => '添加自定义类型';

  @override
  String get maintenanceEditType => '编辑类型';

  @override
  String get maintenanceSystemType => '系统';

  @override
  String maintenanceEveryHours(int count) {
    return '每 $count 小时';
  }

  @override
  String maintenanceEveryDays(int count) {
    return '每 $count 天';
  }

  @override
  String get maintenanceDeleteTypeTitle => '删除维护类型？';

  @override
  String maintenanceDeleteTypeConfirm(String name) {
    return '删除“$name”？此操作无法撤销。';
  }

  @override
  String maintenanceHideTypeConfirm(String name) {
    return '隐藏默认类型“$name”？之后可以恢复。';
  }

  @override
  String get maintenanceFieldName => '名称';

  @override
  String get maintenanceFieldNameHint => '例如 更换 HEPA 滤芯';

  @override
  String get maintenanceFieldIntervalType => '周期类型';

  @override
  String get maintenanceFieldInterval => '周期';

  @override
  String get maintenanceIntervalHours => '打印小时';

  @override
  String get maintenanceIntervalDays => '天';

  @override
  String get maintenanceIntervalInvalid => '请输入 ≥ 1 的值';

  @override
  String get maintenanceFieldIcon => '图标';

  @override
  String get maintenanceFieldDocLink => '文档链接（可选）';

  @override
  String get maintenanceAssignPrinters => '分配到打印机';

  @override
  String get maintenanceSelectPrinter => '请至少选择一台打印机';

  @override
  String get notifEvtMaintenance => '维护到期';

  @override
  String get notifEvtMaintenanceDesc => '维护任务逾期时';

  @override
  String get maintenanceNotifTitle => '维护到期';

  @override
  String maintenanceNotifBody(String printer, String task) {
    return '$printer：$task';
  }

  @override
  String get maintenanceReminderTitle => '维护提醒';

  @override
  String maintenanceReminderBody(String printer, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '任务',
    );
    return '$printer 有 $count 项逾期维护$_temp0';
  }

  @override
  String get maintenanceNotifAction => '标记完成';

  @override
  String get menuStatistics => '统计';

  @override
  String get statsTitle => '统计';

  @override
  String get statsRangeAllTime => '全部时间';

  @override
  String get statsRangeLast7Days => '最近 7 天';

  @override
  String get statsRangeLast30Days => '最近 30 天';

  @override
  String get statsRangeLast90Days => '最近 90 天';

  @override
  String get statsRangeThisYear => '今年';

  @override
  String get statsRangeCustom => '自定义范围';

  @override
  String get statsEmpty => '该时段没有打印记录';

  @override
  String get statsLoadFailed => '无法加载统计数据';

  @override
  String get statsOverview => '概览';

  @override
  String get statsTotalPrints => '打印总数';

  @override
  String get statsPrintTime => '打印时长';

  @override
  String get statsFilamentUsed => '耗材用量';

  @override
  String get statsFilamentCost => '耗材成本';

  @override
  String get statsEnergyUsed => '用电量';

  @override
  String get statsEnergyCost => '电费';

  @override
  String get statsWearCost => '磨损成本';

  @override
  String get statsTotalCost => '总成本';

  @override
  String get statsEnergyWarmingUp => '用电数据仍在累积中';

  @override
  String get statsSuccessRate => '成功率';

  @override
  String statsSuccessful(int count) {
    return '成功：$count';
  }

  @override
  String statsFailed(int count) {
    return '失败：$count';
  }

  @override
  String statsCancelled(int count) {
    return '已取消：$count';
  }

  @override
  String get statsAllUsers => '所有用户';

  @override
  String get statsNoUser => '无用户（系统）';

  @override
  String get statsTimeAccuracy => '时间准确度';

  @override
  String get statsTimeAccuracyHint => '100% = 预估完全准确';

  @override
  String get statsByPrinter => '各打印机打印量';

  @override
  String statsPrintsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 次打印',
    );
    return '$_temp0';
  }

  @override
  String statsHours(String hours) {
    return '$hours 小时';
  }

  @override
  String statsPrinterFallback(String id) {
    return '打印机 #$id';
  }

  @override
  String get statsMetricWeight => '重量';

  @override
  String get statsMetricPrints => '次数';

  @override
  String get statsMetricTime => '时间';

  @override
  String get statsFailureAnalysis => '失败分析';

  @override
  String statsFailedOfTotal(int failed, int total) {
    return '$failed / $total 次打印失败';
  }

  @override
  String get statsTopFailureReasons => '主要失败原因';

  @override
  String get statsNoFailures => '该时段没有失败';

  @override
  String get statsPrintActivity => '打印活跃度';

  @override
  String get statsHeatmapLess => '少';

  @override
  String get statsHeatmapMore => '多';

  @override
  String get statsRecords => '记录';

  @override
  String get statsLongestPrint => '最长打印';

  @override
  String get statsHeaviestPrint => '最重打印';

  @override
  String get statsMostExpensive => '最贵打印';

  @override
  String get statsBusiestDay => '最忙的一天';

  @override
  String get statsSuccessStreak => '连续成功';

  @override
  String statsConsecutive(int count) {
    return '连续 $count 次';
  }

  @override
  String get statsFilamentTrends => '耗材趋势';

  @override
  String get statsPeriodFilament => '本期耗材';

  @override
  String get statsPeriodCost => '本期成本';

  @override
  String get statsAvgPerPrint => '平均每次';

  @override
  String get statsUsageOverTime => '用量趋势';

  @override
  String get statsEnergyOverTime => '用电趋势';

  @override
  String get statsMostEnergy => '耗电最多';

  @override
  String statsKwh(String value) {
    return '$value 千瓦时';
  }

  @override
  String get statsByMaterialTitle => '按材料';

  @override
  String get statsSuccessByMaterial => '各材料成功率';

  @override
  String get statsColorDistribution => '颜色分布';

  @override
  String get statsColorShareHint => '按重量统计耗材占比';

  @override
  String statsColorsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '种颜色',
    );
    return '$count $_temp0';
  }

  @override
  String statsMoreCount(int count) {
    return '还有 $count 项';
  }

  @override
  String get statsPrintDuration => '打印时长';

  @override
  String get statsPrintHabits => '打印习惯';

  @override
  String get statsPrintTimeOfDay => '各时段打印量';

  @override
  String get aboutMenu => '关于';

  @override
  String get aboutTitle => '关于';

  @override
  String get aboutTagline =>
      'bambuddy 的原生 Android 客户端。bambuddy 是自托管的 Bambu Lab 打印机管理器。';

  @override
  String appVersionLabel(String version) {
    return '应用 $version';
  }

  @override
  String serverVersionLabel(String version) {
    return '服务器 $version';
  }

  @override
  String get serverVersionUnknown => '服务器版本未知';

  @override
  String get aboutLicenseHeader => '许可协议';

  @override
  String get aboutLicenseBody =>
      'Bambuddy 是基于 GNU Affero 通用公共许可证 v3.0（AGPL-3.0）发布的开源软件。你可以使用、研究、分享和修改它；如果你将修改后的版本作为网络服务运行，必须向用户提供其源代码。';

  @override
  String get aboutViewLicense => '查看 AGPL-3.0 许可证';

  @override
  String get aboutSourceHeader => '源代码';

  @override
  String get aboutSourceBody => '完整源代码可在 GitHub 上获取。';

  @override
  String get aboutSourceLink => '打开代码仓库';

  @override
  String get aboutThirdParty => '开源许可';

  @override
  String get aboutThirdPartySubtitle => '所捆绑第三方库的许可证';

  @override
  String get fileManagerMenu => '文件管理';

  @override
  String get fileManagerTitle => '文件管理';

  @override
  String get fmRoot => '全部文件';

  @override
  String get fmSearchHint => '搜索文件…';

  @override
  String get fmEmpty => '此文件夹为空';

  @override
  String get fmNoMatches => '没有符合筛选条件的文件';

  @override
  String get fmSortBy => '排序方式';

  @override
  String get fmSortDateNewest => '最新在前';

  @override
  String get fmSortDateOldest => '最早在前';

  @override
  String get fmSortNameAZ => '名称 A–Z';

  @override
  String get fmSortNameZA => '名称 Z–A';

  @override
  String get fmSortSizeLargest => '最大在前';

  @override
  String get fmSortSizeSmallest => '最小在前';

  @override
  String get fmFilterType => '文件类型';

  @override
  String get fmAllTypes => '全部类型';

  @override
  String get fmNewFolder => '新建文件夹';

  @override
  String get fmFolderName => '文件夹名称';

  @override
  String get fmFileName => '文件名称';

  @override
  String get fmSave => '保存';

  @override
  String get fmRename => '重命名';

  @override
  String get fmRenameFolder => '重命名文件夹';

  @override
  String get fmRenameFile => '重命名文件';

  @override
  String get fmRenamed => '已重命名';

  @override
  String get fmFolderCreated => '文件夹已创建';

  @override
  String get fmDelete => '删除';

  @override
  String get fmDeleted => '已移入回收站';

  @override
  String get fmDeleteFile => '删除文件';

  @override
  String fmDeleteFileConfirm(String name) {
    return '将“$name”移入回收站？';
  }

  @override
  String get fmDeleteFolder => '删除文件夹';

  @override
  String fmDeleteFolderConfirm(String name) {
    return '删除文件夹“$name”及其全部内容？';
  }

  @override
  String fmDeleteSelectedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个文件',
    );
    return '将 $count $_temp0移入回收站？';
  }

  @override
  String get fmMoveTo => '移动到…';

  @override
  String get fmMoved => '已移动';

  @override
  String fmFolderItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个项目',
    );
    return '$count $_temp0';
  }

  @override
  String get fmPrint => '打印';

  @override
  String get fmAddToQueue => '加入队列';

  @override
  String get fmAddedToQueue => '已加入队列';

  @override
  String fmQueueTargetTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件应在哪里打印？',
    );
    return '$_temp0';
  }

  @override
  String fmQueueCostCenterTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '这些 $count 个任务应记入哪个成本中心？',
    );
    return '$_temp0';
  }

  @override
  String get fmQueueTargetAuto => '文件中指定的机型';

  @override
  String get fmQueueTargetAutoHint => '每个文件等待与其切片机型一致的打印机';

  @override
  String fmAddedToQueuePartial(int added, int total, String reason) {
    return '已将 $added/$total 个文件加入队列。$reason';
  }

  @override
  String get fmQueueErrWrongModel => '切片机型与打印机不一致。';

  @override
  String get fmQueueErrNotSliced => '未切片，只有 G-code 文件可以加入队列。';

  @override
  String get fmFileDetails => '照片、链接和备注';

  @override
  String get fmPhotosEmpty => '暂无该打印的照片';

  @override
  String get fmPhotoAdd => '添加照片';

  @override
  String get fmPhotoFromCamera => '拍照';

  @override
  String get fmPhotoFromGallery => '从相册选择';

  @override
  String get fmPhotoFromFiles => '从文件选择';

  @override
  String get fmPhotoAdded => '照片已添加';

  @override
  String get fmPhotoDelete => '删除照片';

  @override
  String get fmPhotoDeleteConfirm => '从该文件中删除此照片？';

  @override
  String get fmPhotoDeleted => '照片已删除';

  @override
  String get fmPhotoErrType => '只能添加 JPG、PNG 或 WebP 格式的照片。';

  @override
  String get fmPhotoErrTooLarge => '照片超过 10 MB。';

  @override
  String get fmPhotoPickFailed => '无法打开相机或选择器。';

  @override
  String get fmLink => '链接';

  @override
  String get fmLinkNone => '无链接';

  @override
  String get fmLinkEdit => '编辑链接';

  @override
  String get fmLinkField => '地址';

  @override
  String get fmLinkSaved => '链接已保存';

  @override
  String get fmLinkErrScheme => '链接必须以 http:// 或 https:// 开头。';

  @override
  String get linkOpenFailed => '无法打开该链接。';

  @override
  String get fmSource => '导入来源';

  @override
  String get fmNotes => '备注';

  @override
  String get fmNotesNone => '无备注';

  @override
  String get fmNotesEdit => '编辑备注';

  @override
  String get fmNotesSaved => '备注已保存';

  @override
  String get fmGroupAsVariants => '按备选方案分组';

  @override
  String get fmQueueAsVariants => '作为一个任务加入队列';

  @override
  String get fmUngroupVariants => '取消备选分组';

  @override
  String fmVariantsGrouped(int count) {
    return '$count 个文件已作为备选方案分组';
  }

  @override
  String get fmVariantsUngrouped => '已取消备选分组';

  @override
  String fmVariantsMemberCount(int count) {
    return '$count 个备选';
  }

  @override
  String get fmVariantsGone => '该分组已不存在';

  @override
  String get fmUpload => '上传文件';

  @override
  String get fmAddFiles => '添加文件';

  @override
  String get fmUploading => '上传中…';

  @override
  String fmUploaded(String name) {
    return '已上传 $name';
  }

  @override
  String get fmUploadFailed => '上传失败';

  @override
  String fmSelectedCount(int count) {
    return '已选中 $count 项';
  }

  @override
  String fmStatsFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个文件',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个文件夹',
    );
    return '$count $_temp0';
  }

  @override
  String fmStatsFree(String size) {
    return '可用 $size';
  }

  @override
  String get fmTrash => '回收站';

  @override
  String get fmTrashTitle => '回收站';

  @override
  String get fmTrashEmpty => '回收站为空';

  @override
  String get fmRestore => '恢复';

  @override
  String get fmRestored => '已恢复';

  @override
  String get fmEmptyTrash => '清空回收站';

  @override
  String get fmEmptyTrashConfirm => '永久删除回收站中的全部文件？此操作无法撤销。';

  @override
  String get fmHardDelete => '永久删除';

  @override
  String fmHardDeleteConfirm(String name) {
    return '永久删除“$name”？此操作无法撤销。';
  }

  @override
  String get fmDeletedForever => '已永久删除';

  @override
  String get fmTags => '标签';

  @override
  String get fmTagsFilterTitle => '按标签筛选';

  @override
  String get fmTagsFilterHint => '标签会搜索整个文件库，忽略当前文件夹。';

  @override
  String get fmTagsManage => '管理标签';

  @override
  String get fmTagsEmpty => '暂无标签';

  @override
  String get fmTagsNone => '无标签';

  @override
  String get fmTagsApply => '应用';

  @override
  String get fmTagNew => '新建标签';

  @override
  String get fmTagName => '标签名称';

  @override
  String get fmTagRename => '重命名标签';

  @override
  String get fmTagDelete => '删除标签';

  @override
  String fmTagDeleteConfirm(String name) {
    return '删除标签“$name”？文件的其他信息不受影响，只会去掉这个标签。';
  }

  @override
  String get fmTagCreated => '标签已创建';

  @override
  String get fmTagDeleted => '标签已删除';

  @override
  String get fmTagExists => '已存在同名标签';

  @override
  String get fmTagsSaved => '标签已更新';

  @override
  String fmTagsPartial(int count, int total) {
    return '已更新 $count/$total 个文件，其余文件你无权限编辑';
  }

  @override
  String fmTagsBulkTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个文件',
    );
    return '为 $count $_temp0打标签';
  }

  @override
  String get fmTagsAdd => '添加';

  @override
  String get fmTagsRemove => '移除';

  @override
  String get fmTagsReplace => '替换';

  @override
  String fmTagsReplaceConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个文件',
    );
    return '将 $count $_temp0的所有标签替换为所选项？';
  }

  @override
  String get fmTagsPickSome => '请至少选择一个标签';

  @override
  String get makerworldTitle => 'MakerWorld';

  @override
  String get modelSourcesTitle => '模型来源';

  @override
  String get manyfoldTitle => 'Manyfold';

  @override
  String get mfDescription => '浏览和搜索你的 Manyfold 模型库，导入其中的文件进行切片和打印。';

  @override
  String get mfNotConnectedTitle => 'Manyfold 未连接';

  @override
  String get mfNotConnectedBody => '请联系管理员连接你的 Manyfold 模型库。';

  @override
  String get mfConnectionTitle => 'Manyfold 连接';

  @override
  String get mfConnectionHelp =>
      '在 Manyfold 中打开“设置 → API”，创建一个具备“public”和“read”权限范围的应用，然后在此填写其客户端 ID 和密钥。Bambuddy 能看到该应用所有者可见的模型。';

  @override
  String get mfUrl => 'Manyfold 地址';

  @override
  String get mfUrlPlaceholder => 'http://192.168.1.10:3214';

  @override
  String get mfClientId => '客户端 ID';

  @override
  String get mfClientSecret => '客户端密钥';

  @override
  String get mfClientSecretStored => '已保存，留空则保持不变。';

  @override
  String get mfTest => '测试连接';

  @override
  String get mfSave => '保存';

  @override
  String get mfSaved => '设置已保存';

  @override
  String mfTestOk(int count) {
    return '连接成功。Bambuddy 可见的模型数：$count';
  }

  @override
  String get mfDisconnect => '断开连接';

  @override
  String get mfDisconnectTitle => '断开 Manyfold？';

  @override
  String get mfDisconnectBody =>
      'Bambuddy 将忘记 Manyfold 地址、客户端 ID 和密钥。已导入的文件仍保留在文件库中。';

  @override
  String get mfDisconnected => '已断开 Manyfold';

  @override
  String get mfEditConnection => '连接';

  @override
  String get mfSearchPlaceholder => '搜索模型';

  @override
  String mfModelCount(int count) {
    return '模型数：$count';
  }

  @override
  String get mfNoModels => '未找到模型。';

  @override
  String get mfPrevious => '上一页';

  @override
  String get mfNext => '下一页';

  @override
  String mfPage(int page) {
    return '第 $page 页';
  }

  @override
  String get mfOpenInManyfold => '在 Manyfold 中打开';

  @override
  String get mfLicense => '许可';

  @override
  String get mfFiles => '文件';

  @override
  String get mfNoFiles => '该模型没有文件。';

  @override
  String get mfImportTo => '导入到';

  @override
  String get mfFolderAuto => 'Manyfold 文件夹';

  @override
  String get mfImport => '导入';

  @override
  String get mfImporting => '导入中…';

  @override
  String mfImported(String filename) {
    return '已导入 $filename';
  }

  @override
  String get mfAlreadyInLibrary => '已在文件库中';

  @override
  String get mfInLibrary => '在文件库中';

  @override
  String get mfShowInLibrary => '在文件库中查看';

  @override
  String get mfNotImportable => 'Bambuddy 无法切片或打印该类型';

  @override
  String get mfSelectAll => '全选';

  @override
  String mfSelectFile(String name) {
    return '选择 $name';
  }

  @override
  String mfImportSelected(int count) {
    return '导入所选（$count）';
  }

  @override
  String get mfImportAll => '全部导入';

  @override
  String mfImportProgress(int current, int total) {
    return '正在导入 $current/$total';
  }

  @override
  String mfBulkDone(int imported, int existing, int failed) {
    return '已导入：$imported · 已在库中：$existing · 失败：$failed';
  }

  @override
  String mfBulkFailed(String names, String reason) {
    return '未导入：$names。$reason';
  }

  @override
  String get mfBulkNothing => '没有可导入的内容，所有可打印文件都已在你的文件库中。';

  @override
  String mfSelectModel(String name) {
    return '选择 $name';
  }

  @override
  String get mfSelectPage => '选择本页';

  @override
  String mfModelsSelected(int count) {
    return '已选模型：$count';
  }

  @override
  String get mfImportModels => '导入它们的文件';

  @override
  String get mfClearSelection => '清除选择';

  @override
  String mfCollectProgress(int current, int total) {
    return '正在读取模型 $current/$total';
  }

  @override
  String mfModelsUnreadable(String names) {
    return '无法读取：$names';
  }

  @override
  String get mfErrNotConfigured => 'Manyfold 未连接。';

  @override
  String get mfErrCredentials => 'Manyfold 不接受该客户端 ID 或密钥。';

  @override
  String get mfErrScope =>
      'Manyfold 应用需要“read”权限范围，请在 Manyfold 的“设置 → API”中修改。';

  @override
  String get mfErrRateLimited => 'Manyfold 正在限制登录频率，请过几分钟再试。';

  @override
  String get mfErrUnreachable =>
      'Bambuddy 无法连接 Manyfold，请检查地址并确认 Manyfold 正在运行。';

  @override
  String get mfErrForbidden => 'Manyfold 拒绝访问，请确认该应用的所有者可以看到此模型。';

  @override
  String get mfErrNotFound => 'Manyfold 找不到该模型或文件。';

  @override
  String get mfErrTooLarge => '文件超过 200 MB。';

  @override
  String get mfErrNotImportable => '只能导入 3MF、STL 和 STEP 文件。';

  @override
  String get mfErrBadUrl => '请填写以 http:// 或 https:// 开头的 Manyfold 地址。';

  @override
  String get mfErrSecretRequired => '请输入客户端密钥。';

  @override
  String get mfErrFailed => 'Manyfold 返回了错误。';

  @override
  String get mwIntro => '粘贴 MakerWorld 模型链接，即可直接从 Bambuddy 导入并打印。';

  @override
  String get mwUrlHint =>
      'https://makerworld.com/en/models/… 或任意 MakerWorld 链接';

  @override
  String get mwResolve => '解析';

  @override
  String get mwEnterUrl => '请输入 MakerWorld 链接';

  @override
  String get mwUntitledModel => '未命名模型';

  @override
  String mwPlatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 块打印板',
      zero: '无打印板',
    );
    return '$_temp0';
  }

  @override
  String get mwNoPlates => '该模型没有找到打印板。';

  @override
  String get mwImport => '导入';

  @override
  String mwShowAllPlates(int count) {
    return '显示全部 $count 块打印板';
  }

  @override
  String get mwShowLess => '收起';

  @override
  String get mwInLibrary => '在文件库中';

  @override
  String get mwImported => '已导入到你的文件库';

  @override
  String get mwAlreadyInLibrary => '已在你的文件库中';

  @override
  String get mwViewInFiles => '打开文件管理';

  @override
  String get mwRecentImports => '最近导入';

  @override
  String get mwNoRecent => '暂无最近导入';

  @override
  String get mwOpenOnMakerworld => '在 MakerWorld 中打开';

  @override
  String get mwLoginRequired => '请登录 Bambu Cloud 账号以下载 MakerWorld 模型。';

  @override
  String get cloudAccountMenu => 'Bambu Cloud 账号';

  @override
  String get cloudAccountTitle => 'Bambu Cloud';

  @override
  String get cloudCredsNote => '使用你的 Bambu Lab 账号登录。这些凭据仅用于从 MakerWorld 下载模型。';

  @override
  String get cloudEmail => '邮箱';

  @override
  String get cloudPassword => '密码';

  @override
  String get cloudShowPassword => '显示密码';

  @override
  String get cloudHidePassword => '隐藏密码';

  @override
  String get cloudRegionGlobal => '国际';

  @override
  String get cloudRegionChina => '中国';

  @override
  String get cloudSignIn => '登录';

  @override
  String get cloudSignOut => '退出登录';

  @override
  String get cloudSignedIn => '已登录';

  @override
  String get cloudSignedInOk => '已登录 Bambu Cloud';

  @override
  String get cloudSignInFailed => '登录失败';

  @override
  String get cloudFillCredentials => '请输入邮箱和密码';

  @override
  String get cloudVerify => '验证';

  @override
  String get cloudVerificationCode => '验证码';

  @override
  String get cloudVerificationPrompt => '请输入验证码以完成登录。';

  @override
  String get cloudEnterCode => '请输入验证码';

  @override
  String get swatchCodesMenu => '色卡编码';

  @override
  String get swatchCodesTitle => '色卡编码';

  @override
  String get swatchSearchHint => '按编码或名称搜索';

  @override
  String get swatchSectionCodes => '编码';

  @override
  String get swatchSectionUncoded => '未编码的库存耗材';

  @override
  String get swatchNoCodes => '暂无色卡编码';

  @override
  String get swatchNoCodesHint => '创建编码以标记耗材样品。';

  @override
  String swatchNoMatch(String query) {
    return '没有与“$query”匹配的编码';
  }

  @override
  String get swatchAllCoded => '所有库存耗材都已编码';

  @override
  String get swatchNewCode => '新建编码';

  @override
  String get swatchGenerate => '生成';

  @override
  String get swatchGenerateCode => '生成编码';

  @override
  String get swatchExists => '该耗材已有编码';

  @override
  String swatchCreatedSnack(String code) {
    return '已创建编码 $code';
  }

  @override
  String swatchUpdatedSnack(String code) {
    return '已更新编码 $code';
  }

  @override
  String swatchCopied(String code) {
    return '已复制 $code';
  }

  @override
  String get swatchDelete => '删除';

  @override
  String get swatchDeleteTitle => '删除编码？';

  @override
  String swatchDeleteBody(String code, String name) {
    return '$name 的编码 $code 将被删除。';
  }

  @override
  String get swatchExport => '导出';

  @override
  String get swatchImport => '导入';

  @override
  String get swatchExportEmpty => '没有可导出的编码';

  @override
  String swatchExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个编码',
    );
    return '已导出 $_temp0';
  }

  @override
  String get swatchExportFailed => '导出失败';

  @override
  String get swatchImportTitle => '导入编码？';

  @override
  String swatchImportWarning(int existing, int incoming) {
    return '这将用文件中的 $incoming 个编码替换现有的全部 $existing 个编码，且无法撤销。';
  }

  @override
  String get swatchImportConfirm => '全部替换';

  @override
  String swatchImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个编码',
    );
    return '已导入 $_temp0';
  }

  @override
  String get swatchImportFailed => '无法读取该文件';

  @override
  String get swatchImportEmpty => '文件中没有编码';

  @override
  String get swatchFormTitle => '新建色卡编码';

  @override
  String get swatchEditTitle => '编辑编码';

  @override
  String get swatchSave => '保存';

  @override
  String get swatchRegenerate => '重新生成';

  @override
  String get swatchFieldCode => '编码';

  @override
  String get swatchCodeInvalid => '请使用 6 位字符：数字和字母，不含 0、1、I、L 和 O';

  @override
  String get swatchCodeTaken => '该编码已被使用';

  @override
  String get swatchFieldBrand => '厂商';

  @override
  String get swatchFieldMaterial => '材料';

  @override
  String get swatchFieldVariant => '子类型';

  @override
  String get swatchFieldColor => '颜色';

  @override
  String get swatchFieldHex => '颜色十六进制值';

  @override
  String get swatchMaterialRequired => '材料为必填项';

  @override
  String get swatchNoCatalogColors => '没有可用的色卡颜色，请手动填写颜色名称和十六进制值。';

  @override
  String get projectsMenu => '项目';

  @override
  String get projectsTitle => '项目';

  @override
  String get projectsEmpty => '暂无项目';

  @override
  String get projectsFilterAll => '全部';

  @override
  String get projectCreate => '新建项目';

  @override
  String get projectEdit => '编辑项目';

  @override
  String get projectDelete => '删除';

  @override
  String get projectDeleteTitle => '删除项目？';

  @override
  String projectDeleteBody(String name) {
    return '“$name”将被移除，关联的打印记录仍保留在归档中。';
  }

  @override
  String get projectDeleted => '项目已删除';

  @override
  String get projectSaved => '项目已保存';

  @override
  String get projectName => '名称';

  @override
  String get projectNameRequired => '名称为必填项';

  @override
  String get projectDescription => '描述';

  @override
  String get projectNotes => '备注';

  @override
  String get projectStatus => '状态';

  @override
  String get projectPriority => '优先级';

  @override
  String get projectColor => '颜色';

  @override
  String get projectDueDate => '截止日期';

  @override
  String get projectDueDateClear => '清除';

  @override
  String get projectBudget => '预算';

  @override
  String get projectTargetCount => '目标打印板数';

  @override
  String get projectTargetPartsCount => '目标零件数';

  @override
  String get projectTargetSets => '目标套数';

  @override
  String get projectTargetSetsHint => '项目中每个文件需要打印的次数';

  @override
  String get projectTags => '标签（逗号分隔）';

  @override
  String get projectUrl => '链接';

  @override
  String get projectParent => '上级项目';

  @override
  String get projectParentNone => '无';

  @override
  String get projectSave => '保存';

  @override
  String get projectStatusPlanning => '规划中';

  @override
  String get projectStatusActive => '进行中';

  @override
  String get projectStatusOnHold => '已搁置';

  @override
  String get projectStatusCompleted => '已完成';

  @override
  String get projectStatusArchived => '已归档';

  @override
  String get projectPriorityLow => '低';

  @override
  String get projectPriorityNormal => '普通';

  @override
  String get projectPriorityHigh => '高';

  @override
  String get projectPriorityUrgent => '紧急';

  @override
  String get projectTabBom => '物料清单';

  @override
  String get projectTabTimeline => '时间线';

  @override
  String get projectTabFiles => '文件';

  @override
  String get projectTabAttachments => '附件';

  @override
  String get projectStatProgress => '进度';

  @override
  String get projectStatPartsProgress => '零件';

  @override
  String get projectStatSets => '完整套数';

  @override
  String projectSetsOfTarget(int done, int target) {
    return '$done/$target';
  }

  @override
  String get projectStatPrints => '打印板';

  @override
  String get projectStatCompleted => '已完成';

  @override
  String get projectStatFailed => '失败';

  @override
  String get projectStatQueued => '排队中';

  @override
  String get projectStatPrintTime => '打印时长';

  @override
  String get projectStatFilament => '耗材';

  @override
  String get projectStatCost => '预估成本';

  @override
  String get projectStatEnergy => '能耗';

  @override
  String get projectStatBom => '物料';

  @override
  String get projectChildren => '子项目';

  @override
  String projectDueOn(String date) {
    return '$date 截止';
  }

  @override
  String get projectAddArchives => '添加归档记录';

  @override
  String get archiveAddToProject => '加入项目';

  @override
  String get projectArchivesAdded => '已加入项目';

  @override
  String get projectPickTitle => '选择项目';

  @override
  String get projectBomEmpty => '没有物料条目';

  @override
  String get bomAdd => '添加条目';

  @override
  String get bomEditTitle => '编辑条目';

  @override
  String get bomAddTitle => '新建条目';

  @override
  String get bomName => '名称';

  @override
  String get bomQtyNeeded => '数量';

  @override
  String get bomUnitPrice => '单价';

  @override
  String get bomSourcingUrl => '采购链接';

  @override
  String get bomRemarks => '备注';

  @override
  String get bomDelete => '删除条目';

  @override
  String get projectTimelineEmpty => '暂无事件';

  @override
  String get projectAttachmentsEmpty => '暂无附件';

  @override
  String get projectFilesEmpty => '没有可打印文件';

  @override
  String get projectAttachmentUpload => '上传文件';

  @override
  String get projectAttachmentDownload => '下载';

  @override
  String get projectAttachmentDelete => '删除';

  @override
  String get projectAttachmentDeleted => '附件已删除';

  @override
  String get projectAttachmentUploaded => '附件已上传';

  @override
  String projectFileSaved(String path) {
    return '已保存到 $path';
  }

  @override
  String get projectDownloadFailed => '下载失败';

  @override
  String get projectCoverUpload => '设置封面图';

  @override
  String get projectCoverDelete => '移除封面图';

  @override
  String get projectCoverUpdated => '封面已更新';

  @override
  String get projectCoverRemoved => '封面已移除';

  @override
  String get projectMenuExport => '导出';

  @override
  String get projectMenuCreateTemplate => '保存为模板';

  @override
  String get projectMenuImport => '导入项目';

  @override
  String get projectFromTemplate => '从模板创建';

  @override
  String projectExported(String path) {
    return '已导出到 $path';
  }

  @override
  String get projectTemplateCreated => '模板已创建';

  @override
  String get projectImported => '项目已导入';

  @override
  String get projectImportFailed => '导入失败';

  @override
  String get projectUploading => '上传中…';

  @override
  String get projectLinkFolder => '关联文件夹';

  @override
  String get projectNoFoldersToLink => '没有可关联的文件夹';

  @override
  String get projectUnlinkFolder => '取消关联文件夹';

  @override
  String get projectFolderLinked => '已关联文件夹';

  @override
  String get projectFolderUnlinked => '已取消关联文件夹';

  @override
  String get projectNotesEmpty => '暂无备注';

  @override
  String projectFolderFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个文件',
    );
    return '$_temp0';
  }

  @override
  String projectRemainingShort(int count) {
    return '剩余 $count';
  }

  @override
  String get sliceAction => '切片';

  @override
  String get sliceTitle => '切片文件';

  @override
  String get slicePrinter => '打印机';

  @override
  String get sliceProcess => '工艺 / 质量';

  @override
  String get sliceBedType => '打印板类型';

  @override
  String get sliceBedDefault => '默认（来自预设）';

  @override
  String get sliceFilament => '耗材';

  @override
  String sliceFilamentNumbered(String n) {
    return '耗材 $n';
  }

  @override
  String get sliceAutoOrient => '自动摆放朝向';

  @override
  String get sliceAutoOrientHint => '将每个对象翻转到最适合打印的一面。';

  @override
  String get sliceAutoArrange => '自动排列';

  @override
  String get sliceAutoArrangeHint => '重新在打印板上排布对象。';

  @override
  String sliceDesignedFor(String printer) {
    return '该文件适用于 $printer';
  }

  @override
  String get sliceUseDesignedPrinter => '切换';

  @override
  String get sliceAsDesigned => '使用文件自带设置';

  @override
  String get sliceAsDesignedHint => '使用设计者的设置，而不是上面的配置。';

  @override
  String get sliceAsDesignedInactive => '未使用，由文件决定';

  @override
  String get sliceFilamentUnused => '该打印板不使用';

  @override
  String get processSettingsTitle => '工艺设置';

  @override
  String get sliceProcessSettingsNeedsProcess => '请先选择工艺预设';

  @override
  String get sliceProcessSettingsUnchanged => '按预设原样使用';

  @override
  String sliceProcessSettingsChanged(int count) {
    return '已修改 $count 项';
  }

  @override
  String get processSettingsModeSimple => '简单';

  @override
  String get processSettingsModeAdvanced => '高级';

  @override
  String get processSettingsModeExpert => '专家';

  @override
  String get processSettingsSearchHint => '搜索设置项';

  @override
  String get processSettingsNoMatches => '没有符合该搜索的设置项。';

  @override
  String get processSettingsRevert => '恢复为预设值';

  @override
  String processSettingsRevertAll(int count) {
    return '重置 $count 项';
  }

  @override
  String processSettingsOutOfRange(String range) {
    return '切片器可接受 $range';
  }

  @override
  String get processSettingsDisabledHint => '按当前设置，切片器会忽略该项。';

  @override
  String get processSettingsUnavailable => '该服务器无法提供所选预设的工艺设置。';

  @override
  String get processSettingsDefaultsOutdatedSidecar =>
      '当前显示的是切片器默认值：你的切片器 sidecar 版本较旧，不支持读取预设值。请更新 sidecar 镜像以查看实际值。未修改的项仍按预设执行。';

  @override
  String get processSettingsDefaultsNotConfigured =>
      '当前显示的是切片器默认值：未配置切片器 sidecar，无法读取预设值。未修改的项仍按预设执行。';

  @override
  String get processSettingsDefaultsSidecarUnavailable =>
      '当前显示的是切片器默认值：切片器 sidecar 无响应，无法读取预设值。未修改的项仍按预设执行。';

  @override
  String get processSettingsDefaultsUnavailable =>
      '当前显示的是切片器默认值：无法读取所选预设的值。未修改的项仍按预设执行。';

  @override
  String get processSettingsFilamentDefault => '默认（该区域自带的耗材配置）';

  @override
  String processSettingsFilamentSlot(String slot, String name) {
    return '$slot：$name';
  }

  @override
  String processSettingsFilamentSlotMissing(String slot) {
    return '槽位 $slot，该文件没有此槽位';
  }

  @override
  String get sliceSelect => '点击选择';

  @override
  String get sliceStart => '切片';

  @override
  String get sliceShowAll => '全部';

  @override
  String get sliceSearchHint => '搜索预设';

  @override
  String get sliceOnlyOnline => '仅在线打印机';

  @override
  String get sliceOnlyOnlineHint => '仅显示当前在线机型的打印机配置，涵盖所有喷嘴口径。';

  @override
  String get sliceOnlyLoaded => '仅已装载料盘';

  @override
  String get sliceOnlyLoadedHint => '仅显示所选机型在线打印机中已装载料盘的耗材配置。你自行选择的配置会保留。';

  @override
  String get sliceNoneOnline => '没有在线打印机，因此显示全部配置。';

  @override
  String get sliceNoneLoaded => '没有已装载的料盘具备该打印机的配置，因此显示全部耗材配置。';

  @override
  String get sliceLoadedNoneOfModel => '该机型没有在线打印机。';

  @override
  String get sliceLoadedNothing => '既无 AMS，也无外置料盘。';

  @override
  String get sliceSpoolUnidentified => '未识别料盘';

  @override
  String get sliceSpoolEmpty => '空';

  @override
  String sliceAllPlates(int count) {
    return '切分全部 $count 块打印板';
  }

  @override
  String get sliceAllPlatesHint => '所有打印板合成一个文件，耗材覆盖项目的全部槽位。';

  @override
  String get sliceTabSpools => '料盘';

  @override
  String get sliceTabProfiles => '配置';

  @override
  String sliceNeedsMaterial(String material) {
    return '该打印板需要：$material';
  }

  @override
  String get sliceFilterPrinter => '打印机';

  @override
  String get sliceFilterMaterial => '材料';

  @override
  String get sliceFilterBrand => '品牌';

  @override
  String sliceProfilesShown(int shown, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total 个配置',
    );
    return '显示 $shown/$_temp0';
  }

  @override
  String get sliceSpoolsUnavailable => '不可用：';

  @override
  String sliceSpoolFrom(String source) {
    return '来自料盘 · $source';
  }

  @override
  String get sliceSpoolNoProfileShort => '无配置';

  @override
  String get sliceOwnedEmpty => '没有与你的打印机和耗材匹配的预设。开启“全部”可浏览完整目录。';

  @override
  String get sliceNoPresets => '没有可用的预设';

  @override
  String get sliceInProgress => '切片中…';

  @override
  String get sliceDone => '切片完成';

  @override
  String get sliceFailed => '切片失败';

  @override
  String get sliceExternalFallback => '已保存到服务器文件库，原因：文件原所在文件夹无法接收。';

  @override
  String get sliceExternalReadonly => '该文件夹为只读。';

  @override
  String get sliceExternalNoPath => '该文件夹未配置路径。';

  @override
  String get sliceExternalUnreachable => '该文件夹路径当前无法访问。';

  @override
  String get sliceExternalNotWritable => '服务器无法写入该文件夹。';

  @override
  String get sliceExternalInvalidName => '该文件夹不接受该文件名。';

  @override
  String get sliceClose => '关闭';

  @override
  String sliceResultTime(String time) {
    return '预计用时：$time';
  }

  @override
  String get sliceRefusedStep => 'STEP 文件无法切片，请先从 CAD 导出为 STL 或 3MF。';

  @override
  String get sliceRefusedFormat => '源文件必须是 STL 或 3MF。';

  @override
  String get sliceRefusedNoSource => '该归档只保留了打印用的 G-code，没有模型，无法再次切片。';

  @override
  String sliceResultFilament(String grams) {
    return '耗材：$grams g';
  }

  @override
  String get sliceTierLocal => '本地预设';

  @override
  String get sliceTierCloud => 'Bambu Cloud';

  @override
  String get sliceTierOrcaCloud => 'Orca Cloud';

  @override
  String get sliceTierStandard => '内置';

  @override
  String get pipelineSection => '流水线';

  @override
  String get pipelineApply => '应用流水线…';

  @override
  String get pipelineApplyEmpty => '暂无已保存的流水线';

  @override
  String pipelineApplied(String name) {
    return '已应用“$name”';
  }

  @override
  String get pipelineSaveAs => '保存为流水线';

  @override
  String get pipelineNameHint => '流水线名称';

  @override
  String get pipelineSaveConfirm => '保存';

  @override
  String get pipelineSaved => '流水线已保存';

  @override
  String get pipelineSaveHint => '将上面的打印机、工艺、耗材和打印板打包命名保存，之后可一键应用到下一个文件。';

  @override
  String get pipelinesMenu => '流水线';

  @override
  String get pipelinesTitle => '流水线';

  @override
  String get pipelinesEmpty => '暂无流水线';

  @override
  String get pipelinesEmptyHint => '在切片表单中保存一份：把打印机、工艺、耗材和打印板打包，一键复用。';

  @override
  String pipelineFilamentsCount(int count) {
    return '耗材（$count）';
  }

  @override
  String get pipelineHistory => '运行历史';

  @override
  String get pipelineCardActions => '流水线操作';

  @override
  String pipelineSlotNumbered(int n) {
    return '耗材 $n';
  }

  @override
  String get pipelineBed => '打印板';

  @override
  String get pipelinePresetGone => '已不在目录中';

  @override
  String get pipelineNeedsTarget => '运行该流水线前请先设置目标。';

  @override
  String get pipelineNoTargetChip => '无目标';

  @override
  String get pipelineEditTitle => '编辑流水线';

  @override
  String get pipelineDescriptionHint => '描述（可选）';

  @override
  String get pipelineTargetType => '目标';

  @override
  String get pipelineTargetSpecific => '指定一台打印机';

  @override
  String get pipelineTargetClass => '打印机机型';

  @override
  String get pipelineTargetPickPrinter => '选择打印机';

  @override
  String get pipelineTargetPickClass => '选择机型';

  @override
  String get pipelineTargetNone => '— 未设置目标 —';

  @override
  String pipelineTargetPrinterGone(int id) {
    return '打印机 #$id（已不存在）';
  }

  @override
  String get pipelineFanout => '副本分发方式';

  @override
  String get pipelineFanoutMaxParallel => '最大并行：在所有空闲的匹配打印机上同时进行';

  @override
  String get pipelineFanoutRoundRobin => '轮询：在多台可用打印机间轮流';

  @override
  String get pipelineFanoutFillOneFirst => '先满一台：所有副本在同一台打印机上完成';

  @override
  String get pipelineDelete => '删除流水线';

  @override
  String pipelineDeleteConfirm(String name) {
    return '删除“$name”？已产生的运行记录会保留名称。';
  }

  @override
  String get pipelineDeleted => '流水线已删除';

  @override
  String get pipelineRun => '运行';

  @override
  String get pipelineRunCopies => '份数';

  @override
  String get pipelineRunStart => '开始';

  @override
  String get pipelineRunStarted => '已开始运行';

  @override
  String get pipelineRunAnyway => '仍然运行';

  @override
  String pipelineRunMaxCopies(int max) {
    return '该服务器最多允许 $max 份。';
  }

  @override
  String get pipelineEligibilityOk => '可以运行。';

  @override
  String pipelineEligibilityClassCount(int ok, int total) {
    return '$total 台打印机中有 $ok 台就绪';
  }

  @override
  String get pipelineEligibilityBlocked => '当前没有任何打印机可以承接本次运行。';

  @override
  String get pipelineEligibilityAdvisory => '开始前建议先查看。';

  @override
  String get pipelineIssuePrinterNotSet => '该流水线没有设置目标打印机。';

  @override
  String get pipelineIssuePrinterNotFound => '目标打印机已不存在。';

  @override
  String get pipelineIssuePrinterDisabled => '目标打印机已在 bambuddy 中停用。';

  @override
  String get pipelineIssuePrinterOffline => '目标打印机离线。';

  @override
  String get pipelineIssueFilamentType => '装载的耗材类型不正确。';

  @override
  String get pipelineIssueFilamentColor => '装载的耗材颜色不一致。';

  @override
  String get pipelineIssueAmsSlotMissing => 'AMS 槽位数量少于该流水线的需要。';

  @override
  String get pipelineIssueFilamentUnverified => '此处无法校验该耗材预设，建议自行确认。';

  @override
  String get pipelineIssueNoClassMatches => '该机型没有已安装的打印机。';

  @override
  String get pipelineIssueClassNotSet => '该流水线没有设置打印机机型。';

  @override
  String pipelineIssueSlot(int n) {
    return '槽位 $n';
  }

  @override
  String pipelineIssueWantedGot(String expected, String actual) {
    return '需要 $expected，实际装载 $actual';
  }

  @override
  String pipelineIssueWanted(String expected) {
    return '需要 $expected';
  }

  @override
  String get pipelineRunsTitle => '流水线运行记录';

  @override
  String get pipelineRunsEmpty => '暂无运行记录';

  @override
  String get pipelineRunsNoneMatch => '没有符合筛选的运行记录';

  @override
  String get pipelineRunsFilter => '筛选运行记录';

  @override
  String get copiesLess => '减少一份';

  @override
  String get copiesMore => '增加一份';

  @override
  String get pipelineEligible => '就绪';

  @override
  String get pipelineIneligible => '未就绪';

  @override
  String pipelineRunsFilterActive(int count) {
    return '筛选运行记录（$count 个进行中）';
  }

  @override
  String get pipelineRunsFilterAny => '任意';

  @override
  String get pipelineRunsFilterStatus => '状态';

  @override
  String get pipelineRunsFilterStatusHint => '按最后记录的状态匹配，因此一次运行也可能对应它前一步的状态。';

  @override
  String get pipelineRunsFilterTarget => '目标';

  @override
  String get pipelineRunsFilterTargetHint => '按流水线当前指向的目标筛选，更改目标会同时改变其全部历史记录。';

  @override
  String get pipelineRunsFilterPipelineHint => '已删除流水线的运行记录无法按流水线筛选。';

  @override
  String get pipelineRunsFilterClear => '清除筛选';

  @override
  String get pipelineRunsLoadMore => '加载更多';

  @override
  String pipelineRunsShowingAll(int count) {
    return '已显示全部 $count 条';
  }

  @override
  String get pipelineRunsDone => '已完成';

  @override
  String get pipelineRunsClear => '清除已结束';

  @override
  String pipelineRunsCleared(int count) {
    return '已移除 $count 条';
  }

  @override
  String get pipelineRunsClearConfirm => '从列表中移除所有已结束的运行？';

  @override
  String pipelineRunCopiesProgress(int done, int total) {
    return '已完成 $done/$total 份';
  }

  @override
  String get pipelineRunCancel => '取消运行';

  @override
  String get pipelineRunCancelConfirm => '取消本次运行？尚未发送的副本将被丢弃；已在打印的需在打印机上手动停止。';

  @override
  String get pipelineRunCancelled => '运行已取消';

  @override
  String get pipelineRunRetry => '重试失败项';

  @override
  String pipelineRunRetryStarted(int count) {
    return '正在重试 $count 份副本';
  }

  @override
  String get pipelineRunOverridden => '已跳过未通过的检查开始';

  @override
  String get pipelineRunDeletedPipeline => '已删除的流水线';

  @override
  String pipelineRunSource(String name) {
    return '来自 $name';
  }

  @override
  String pipelineRunRetryOf(int id) {
    return '重试 #$id 次运行';
  }

  @override
  String pipelineRunOnPrinter(String printer) {
    return '在 $printer 上';
  }

  @override
  String pipelineRunOnClass(String model) {
    return '在任一 $model 上';
  }

  @override
  String get pipelineStatusQueued => '排队中';

  @override
  String get pipelineStatusSlicing => '切片中';

  @override
  String get pipelineStatusDispatching => '分发中';

  @override
  String get pipelineStatusInProgress => '打印中';

  @override
  String get pipelineStatusCompleted => '已完成';

  @override
  String get pipelineStatusFailed => '失败';

  @override
  String get pipelineStatusPartial => '部分失败';

  @override
  String get pipelineStatusCancelled => '已取消';

  @override
  String get pipelineStatusUnknown => '未知';

  @override
  String pipelineJobCopy(int n) {
    return '第 $n 份';
  }

  @override
  String get pipelineJobPending => '待处理';

  @override
  String get pipelineJobAwaitingPrinter => '等待打印机';

  @override
  String get pipelineJobQueued => '排队中';

  @override
  String get pipelineJobPrinting => '打印中';

  @override
  String get pipelineJobCompleted => '完成';

  @override
  String get pipelineJobFailed => '失败';

  @override
  String get pipelineJobCancelled => '已取消';

  @override
  String get pipelineJobUnknown => '未知';

  @override
  String get queueFilamentMapping => '耗材映射';

  @override
  String get mappingNoSlots => '该文件没有耗材信息。';

  @override
  String mappingNoAms(String printer) {
    return '$printer 上没有装载 AMS 耗材。';
  }

  @override
  String get mappingPickTray => '选择 AMS 槽位';

  @override
  String get mappingExternalSpool => '外置料盘';

  @override
  String get mappingSaved => '耗材映射已保存';

  @override
  String get mappingStatusReady => '就绪';

  @override
  String get mappingStatusColorMismatch => '颜色不符';

  @override
  String get mappingStatusTypeNotFound => '未找到该材料';

  @override
  String get mappingTapToChange => '点击耗材可更改其槽位';

  @override
  String get mappingExactColor => '颜色完全匹配';

  @override
  String mappingSameTypeOtherColor(String required, String loaded) {
    return '同材料不同颜色：需要 $required，槽位为 $loaded';
  }

  @override
  String get mappingTypeNotLoaded => '未装载该耗材类型';

  @override
  String get mappingManual => '手动选择';

  @override
  String mappingRequired(String name, String color) {
    return '需要：$name，$color';
  }

  @override
  String get mappingUseSlicer => '使用切片器映射';

  @override
  String get mappingUseSlicerHint => '按切片器随该打印保存的 AMS 映射选择每个槽位，而不是按材料类型和颜色匹配。';

  @override
  String get mappingReRead => '重新读取';

  @override
  String mappingFtsSameInlet(String inlet) {
    return '本次打印的所有耗材都在耗材通道切换器的 IN-$inlet 上。同一进料口内切换耗材更慢，可将其中的一个移到另一进料口的 AMS 上以加快速度。';
  }

  @override
  String get mappingRackPosition => '料架位置';

  @override
  String get mappingRackPositionHint => '由料架上的哪个喷嘴打印该耗材。位置编号与打印机一致。';

  @override
  String mappingRackNeeds(String nozzle) {
    return '该耗材需要 $nozzle 喷嘴。';
  }

  @override
  String get mappingRackEmptyPosition => '该料架位置为空';

  @override
  String mappingRackWrongNozzle(String has, String needs) {
    return '当前为 $has 喷嘴，该耗材需要 $needs';
  }

  @override
  String mappingRackSlot(int position) {
    return 'R$position';
  }

  @override
  String get colorFamilyRed => '红色';

  @override
  String get colorFamilyOrange => '橙色';

  @override
  String get colorFamilyYellow => '黄色';

  @override
  String get colorFamilyGreen => '绿色';

  @override
  String get colorFamilyCyan => '青色';

  @override
  String get colorFamilyBlue => '蓝色';

  @override
  String get colorFamilyPurple => '紫色';

  @override
  String get colorFamilyPink => '粉色';

  @override
  String get colorFamilyBrown => '棕色';

  @override
  String get colorFamilyWhite => '白色';

  @override
  String get colorFamilyLightGray => '浅灰';

  @override
  String get colorFamilyGray => '灰色';

  @override
  String get colorFamilyDarkGray => '深灰';

  @override
  String get colorFamilyBlack => '黑色';

  @override
  String get colorFamilyClear => '透明';

  @override
  String get colorFamilyUnknown => '未知';

  @override
  String get plateClearTitle => '打印板已清空？';

  @override
  String get plateClearBody => '开始打印前请确认打印板上没有残留。';

  @override
  String get plateClearConfirm => '打印板已清空';

  @override
  String get plateClearAction => '标记打印板已清空';

  @override
  String get plateClearBadge => '打印板未清空';

  @override
  String get plateClearedSnack => '已标记打印板为清空';

  @override
  String get plateClearNeedsOnline =>
      '该服务器仅在打印机连接时才能释放打印板状态。请更新 bambuddy，以便在打印机断电时也能操作。';

  @override
  String get pfmTitle => '文件管理';

  @override
  String get pfmTooltip => '打印机上的文件';

  @override
  String pfmStorageUsed(String size) {
    return '已用：$size';
  }

  @override
  String get pfmTabRoot => '根目录';

  @override
  String get pfmTabCache => '缓存';

  @override
  String get pfmTabModels => '模型';

  @override
  String get pfmTabTimelapse => '延时摄影';

  @override
  String get pfmSearchHint => '筛选文件…';

  @override
  String get pfmSortTooltip => '排序';

  @override
  String get pfmRefreshTooltip => '刷新';

  @override
  String get pfmSortNameAsc => '名称（A–Z）';

  @override
  String get pfmSortNameDesc => '名称（Z–A）';

  @override
  String get pfmSortSizeLargest => '大小（从大到小）';

  @override
  String get pfmSortSizeSmallest => '大小（从小到大）';

  @override
  String get pfmSortDateNewest => '日期（最新）';

  @override
  String get pfmSortDateOldest => '日期（最早）';

  @override
  String get pfmUp => '上一级';

  @override
  String get pfmSelectAll => '全选';

  @override
  String get pfmDeselectAll => '取消全选';

  @override
  String pfmSelected(int count) {
    return '已选中 $count 项';
  }

  @override
  String get pfmEmpty => '此文件夹为空';

  @override
  String get pfmNoMatches => '没有符合筛选条件的文件';

  @override
  String get pfmPrinterUnavailable => '打印机无响应，无法列出其文件';

  @override
  String get pfmDownloadTooLarge => '所选内容过大，服务器无法打包';

  @override
  String get pfmDownloadNoServerSpace => '服务器空间不足，无法准备该下载';

  @override
  String get pfmDownloadTookTooLong => '准备下载耗时过长，服务器已放弃';

  @override
  String get pfmPreparingOnServer => '正在服务器上准备…';

  @override
  String get pfmDownloading => '下载中…';

  @override
  String get pfmDownloadCancelled => '下载已取消';

  @override
  String get pfmDownloadPrepareFailed => '服务器无法准备该下载';

  @override
  String pfmDownloadPartial(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个',
    );
    return '已排除 $_temp0无法从打印机读取的文件';
  }

  @override
  String get pfmDownloadSaved => '文件已保存';

  @override
  String get pfmDownloadNotSaved => '无法保存到你选择的位置';

  @override
  String get pfmDownload => '下载';

  @override
  String get pfmDelete => '删除';

  @override
  String get pfmDeleteConfirmTitle => '删除文件？';

  @override
  String pfmDeleteConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个文件',
    );
    return '从打印机上永久删除 $count $_temp0？此操作无法撤销。';
  }

  @override
  String pfmDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个文件',
    );
    return '已删除 $count $_temp0';
  }

  @override
  String get wearConnectionFailed => '连接失败';

  @override
  String get wearNoPrinters => '无打印机';

  @override
  String get wearPrinterUnavailable => '打印机不可用';

  @override
  String get wearWaitingForState => '正在获取当前状态';

  @override
  String get wearNoActions => '无可用操作';

  @override
  String get wearClearPlate => '清空打印板';

  @override
  String get wearPlateCleared => '打印板已清空';

  @override
  String get wearPlateNeedsOnline => '该服务器需要打印机在线';

  @override
  String get wearStarted => '已开始';

  @override
  String get wearNothingQueuedHere => '该打印机没有排队任务';

  @override
  String get wearPhoneUnreachable => '无法连接手机';

  @override
  String get wearPhoneNoResponse => '手机无响应';

  @override
  String get wearConfirm => '确认';

  @override
  String get wearAuthKey => '密钥';

  @override
  String get wearAuthLogin => '登录';

  @override
  String get wearSetupPhoneTitle => '在手机上完成设置';

  @override
  String get wearSetupPhoneBody => '在已配对的手机上打开 Bambuddy，手表会从中获取服务器和登录信息。';

  @override
  String get wearSetupPhoneCheck => '重新检查';

  @override
  String get wearSetupPhoneEmpty => '尚未从手机获取到信息。';

  @override
  String get wearPhoneAppMissing => '手机上还没有安装？';

  @override
  String get wearPhoneAppInstall => '在手机上安装';

  @override
  String get wearPhoneAppOpened => '请在手机上继续';

  @override
  String get wearPhoneAppOpenFailed => '无法连接到手机。';

  @override
  String get wearSetupDemo => '演示';

  @override
  String get wearSettingsTitle => '设置';

  @override
  String get wearFromPhone => '来自手机';

  @override
  String get wearFromPhoneUse => '使用该服务器';

  @override
  String get wearFromPhoneLater => '暂不';

  @override
  String get wearAuthNone => '无需登录';

  @override
  String get wearFromPhoneWaiting => '手机上提供了另一个服务器。';

  @override
  String get wearCurrentServer => '当前服务器';

  @override
  String get wearOk => '确定';

  @override
  String get commonOn => '开';

  @override
  String get commonOff => '关';

  @override
  String get commonAuto => '自动';

  @override
  String get queueEdit => '编辑';

  @override
  String get queueEditTitle => '编辑队列项';

  @override
  String get queueEditSave => '保存';

  @override
  String get queueEditSaved => '队列项已更新';

  @override
  String get queueCreateTitle => '打印';

  @override
  String get queueCreateSubmit => '打印';

  @override
  String get queueCreateAdded => '已加入队列';

  @override
  String get queueEditPrintJob => '打印任务';

  @override
  String get queueEditTarget => '目标';

  @override
  String get queueEditSpecificPrinter => '指定打印机';

  @override
  String get queueEditPrinter => '打印机';

  @override
  String queueEditAnyModel(String model) {
    return '任一 $model';
  }

  @override
  String get queueEditAnyModelGeneric => '任意机型';

  @override
  String get queueEditTargetModel => '机型';

  @override
  String get queueEditTargetLocation => '位置';

  @override
  String get queueEditAnyLocation => '任意位置';

  @override
  String get queueEditMappingNeedsPrinter => '请选择打印机以映射耗材';

  @override
  String queueEditMappingSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个槽位',
    );
    return '已映射 $count $_temp0';
  }

  @override
  String get queueEditMappingAuto => '自动（不手动映射）';

  @override
  String get queueEditPlate => '打印板';

  @override
  String queueEditPlateSelected(int plate) {
    return '第 $plate 板';
  }

  @override
  String queueEditPlateNamed(int plate, String name) {
    return '第 $plate 板 · $name';
  }

  @override
  String queueEditPlateFixed(int plate) {
    return '该任务打印第 $plate 板';
  }

  @override
  String get queuePlatePickTitle => '选择哪块打印板？';

  @override
  String queuePlateObjects(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个对象',
      zero: '无对象',
    );
    return '$_temp0';
  }

  @override
  String get queueEditPrintOptions => '打印选项';

  @override
  String get queueOptBedLevelling => '热床调平';

  @override
  String get queueOptBedLevellingDesc => '打印前自动调平热床';

  @override
  String get queueOptFlowCali => '流量校准';

  @override
  String get queueOptFlowCaliDesc => '校准挤出流量';

  @override
  String get queueOptVibrationCali => '振动校准';

  @override
  String get queueOptVibrationCaliDesc => '减少振纹';

  @override
  String get queueOptLayerInspect => '首层检测';

  @override
  String get queueOptLayerInspectDesc => 'AI 检测首层';

  @override
  String get queueOptTimelapse => '延时摄影';

  @override
  String get queueOptTimelapseDesc => '录制延时视频';

  @override
  String get queueOptNozzleOffset => '喷嘴偏移校准';

  @override
  String get queueOptNozzleOffsetDesc => '校准各挤出机之间的喷嘴偏移';

  @override
  String get queueEditPreheat => '预热与热平衡';

  @override
  String get queueEditPreheatDesc => '开始打印前预热热床和腔体。默认遵循“设置 → 工作流”中的全局开关。';

  @override
  String get queuePreheatInherit => '跟随全局';

  @override
  String get queueEditChamberTarget => '腔体目标温度覆盖（°C，留空则使用耗材默认值）';

  @override
  String queueEditChamberTargetRange(int max) {
    return '0–$max °C';
  }

  @override
  String get queueEditWhenToPrint => '何时打印';

  @override
  String get queueScheduleAsap => '尽快';

  @override
  String get queueScheduleQueue => '排队';

  @override
  String get queueScheduleSchedule => '定时';

  @override
  String get queueEditPickTime => '选择日期和时间';

  @override
  String get queueEditRequireManualStart => '需手动开始';

  @override
  String get queueBadgeStaged => '已暂存';

  @override
  String get queueBadgeAwaitingReview => '等待审核';

  @override
  String get queueAwaitingReviewRefused => '该任务等待审核：需由管理队列的人启动。';

  @override
  String get queueEditAwaitingReviewNote => '你的打印任务等待审核，将由管理队列的人启动。';

  @override
  String get queueEditRequirePrevious => '仅在上一次打印成功后才开始';

  @override
  String get queueEditPowerOff => '完成后关闭打印机';

  @override
  String get queueEditGcodeInjection => '注入自动打印 G-code';

  @override
  String queueEditGcodeInjectionNoSnippet(String model) {
    return '没有适用于 $model 的 G-code 片段，不会注入任何内容。';
  }

  @override
  String get queueEditNoModel => '请选择目标机型';

  @override
  String get queueEditNoPrinter => '请选择打印机';

  @override
  String get queueEditFilamentOverride => '覆盖耗材';

  @override
  String get queueEditFilamentOverrideDesc =>
      '可为基于机型的分配覆盖耗材。调度器将按你选择的耗材匹配，而不是使用原始 3MF 值。';

  @override
  String get queueEditNoFilamentReqs => '该任务没有耗材要求。';

  @override
  String get queueEditOriginal => '原始值';

  @override
  String queueEditSlotLabel(String slot, String type) {
    return '槽位 $slot · $type';
  }

  @override
  String get queueEditForceColorMatch => '强制颜色匹配';

  @override
  String get queueEditRackPickStale => '所选位置已不适配该耗材，请重新选择，否则开始时会拒绝打印。';

  @override
  String queueEditRackNoFit(String nozzle) {
    return '料架上没有 $nozzle 喷嘴，请安装一个，或交由打印机自行决定。';
  }

  @override
  String get nozzleFlowStandard => '标准流量';

  @override
  String get nozzleFlowHigh => '高流量';

  @override
  String get bugReportMenu => '反馈问题或建议';

  @override
  String get bugReportTitle => '反馈问题或建议';

  @override
  String get bugReportLogScreens => '你打开的页面和点击的按钮';

  @override
  String get bugReportLogRequests => '对服务器的请求及其响应';

  @override
  String get bugReportLogService => '实时视图，以及后台服务发送或跳过了哪些通知';

  @override
  String get bugReportLogErrors => '错误与崩溃，包括你从未看到的那些';

  @override
  String get bugReportLogSetup => '应用与服务器版本、你的手机和语言';

  @override
  String get bugReportLogNoKey => '你的 API 密钥或密码';

  @override
  String get bugReportLogNoTyping => '你输入的文本';

  @override
  String get bugReportLogNoAddress => '你的服务器地址，仅保留 http 或 https、域名或 IP 及端口';

  @override
  String get bugReportLogNoData => '打印机序列号，以及你的文件、模型和料盘名称';

  @override
  String get bugReportRequestNoData => '不包含任何打印机或手机信息';

  @override
  String get usersTitle => '用户';

  @override
  String get usersEmpty => '该服务器上没有账号。';

  @override
  String get usersYou => '你';

  @override
  String get usersRoleAdmin => '管理员';

  @override
  String get usersRoleUser => '用户';

  @override
  String get usersInactive => '已停用';

  @override
  String get usersEmailLabel => '邮箱';

  @override
  String get usersEmailNone => '无';

  @override
  String get usersGroupsLabel => '用户组';

  @override
  String get usersNoGroups => '无';

  @override
  String get usersPermissionsLabel => '权限';

  @override
  String usersPermissionsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项权限',
      zero: '无',
    );
    return '$_temp0';
  }

  @override
  String get usersPermissionsUnknown => '服务器未报告';

  @override
  String get usersAuthSourceLabel => '登录方式';

  @override
  String get usersAuthSourceLocal => '本地账号';

  @override
  String get usersCreatedLabel => '创建时间';

  @override
  String get usersOwnedTitle => '由该账号创建';

  @override
  String get usersOwnedArchives => '打印记录';

  @override
  String get usersOwnedQueue => '队列';

  @override
  String get usersOwnedLibrary => '文件';

  @override
  String get usersOwnedFailed => '无法读取该账号拥有的内容。';

  @override
  String get usersCreate => '添加账号';

  @override
  String get usersCreateTitle => '新建账号';

  @override
  String get usersEdit => '编辑';

  @override
  String get usersEditTitle => '编辑账号';

  @override
  String get usersDelete => '删除';

  @override
  String get usersSave => '保存';

  @override
  String get usersSaved => '账号已保存';

  @override
  String get usersSaveFailed => '无法保存该账号。';

  @override
  String get usersDeleted => '账号已删除';

  @override
  String get usersFieldUsername => '用户名';

  @override
  String get usersFieldEmail => '邮箱（可选）';

  @override
  String get usersFieldEmailRequired => '邮箱';

  @override
  String get usersFieldPassword => '密码';

  @override
  String get usersFieldNewPassword => '新密码';

  @override
  String get usersFieldConfirmPassword => '再次输入密码';

  @override
  String get usersFieldActive => '启用';

  @override
  String get usersFieldGroups => '用户组';

  @override
  String get usersGroupSystem => '（内置）';

  @override
  String get usersFieldRequired => '请填写此项';

  @override
  String get usersPasswordsDoNotMatch => '两次输入的密码不一致。';

  @override
  String get usersGroupsAdminHint => '账号是否为管理员取决于是否属于 Administrators 组。';

  @override
  String get usersActiveHint => '停用的账号无法登录。';

  @override
  String get usersEmailAdvancedHint => '该服务器通过邮件发送密码，因此需要邮箱地址。';

  @override
  String get usersPasswordMailed => '密码由服务器生成并发送到该邮箱，包括你在内任何人都看不到。';

  @override
  String get usersNoSmtpWarning => '未配置邮件服务器，该邮件不会送达，账号将使用无人知晓的密码创建。';

  @override
  String get usersLdapPasswordNote => '该账号通过目录服务（LDAP）登录，密码保存在目录中，无法在此设置。';

  @override
  String get usersPasswordKeepHint => '留空则保持当前密码。';

  @override
  String get usersPasswordRulesHint => '至少 8 个字符，需包含大小写字母、数字和符号。';

  @override
  String get usersPasswordTooShort => '至少 8 个字符。';

  @override
  String get usersPasswordNoUppercase => '请加入大写字母。';

  @override
  String get usersPasswordNoLowercase => '请加入小写字母。';

  @override
  String get usersPasswordNoDigit => '请加入数字。';

  @override
  String get usersPasswordNoSpecial => '请加入符号。';

  @override
  String usersDeleteTitle(String username) {
    return '删除 $username？';
  }

  @override
  String get usersDeleteBody => '该账号、其 API 密钥和登录状态将被移除，且无法撤销。';

  @override
  String usersDeleteOwnsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '该账号创建了 $count 项内容',
    );
    return '$_temp0';
  }

  @override
  String get usersDeleteItemsToo => '一并删除';

  @override
  String get usersDeleteItemsTooHint => '其打印记录、队列项和文件将随账号一起删除。';

  @override
  String get usersDeleteItemsKeepHint => '其打印记录、队列项和文件将保留，但不再有归属。';

  @override
  String get usersDeleteConfirm => '删除';

  @override
  String get usersErrLastAdmin => '这是最后一个管理员，服务器至少保留一个。';

  @override
  String get usersErrLastAdminDelete => '不能删除最后一个管理员，否则服务器将无人可管理。';

  @override
  String get usersErrLastAdminDeactivate => '不能停用最后一个管理员，否则服务器将无人可管理。';

  @override
  String get usersErrLastAdminRole => '不能降级最后一个管理员，否则服务器将无人可管理。';

  @override
  String get usersErrSelfDelete => '不能删除当前登录的账号。';

  @override
  String get usersErrUsernameTaken => '该用户名已被占用。';

  @override
  String get usersErrEmailTaken => '该邮箱已被其他账号使用。';

  @override
  String get usersErrLdapPassword => '目录（LDAP）账号的密码无法在此设置。';

  @override
  String get usersErrEmailRequired => '该服务器新建账号需要邮箱地址。';

  @override
  String get usersErrPasswordRequired => '该服务器新建账号需要密码。';

  @override
  String get usersErrGroupsInvalid => '其中一个用户组已不存在，请重新打开表单。';

  @override
  String get groupsTitle => '用户组';

  @override
  String get groupsEmpty => '该服务器上没有用户组。';

  @override
  String get groupsNoDescription => '无描述';

  @override
  String get groupsSystemPill => '内置';

  @override
  String get groupsSystemNote => '内置组无法改名，其授予的权限固定，只能更改成员。';

  @override
  String groupsMemberCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个账号',
      zero: '无账号',
    );
    return '$_temp0';
  }

  @override
  String groupsPermissionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项权限',
      zero: '无权限',
    );
    return '$_temp0';
  }

  @override
  String get groupsMembersHeader => '成员';

  @override
  String get groupsNoMembers => '该组没有成员。';

  @override
  String get groupsAddMember => '添加成员';

  @override
  String groupsAddMemberTitle(String group) {
    return '添加到 $group';
  }

  @override
  String get groupsEveryoneIsIn => '所有账号都已在该组中。';

  @override
  String get groupsRemoveMember => '移除';

  @override
  String groupsRemoveMemberQuestion(String username, String group) {
    return '将 $username 从 $group 移除？';
  }

  @override
  String get groupsRemoveMemberBody => '账号会保留，但会失去该组授予的权限。';

  @override
  String get groupsCreate => '新建用户组';

  @override
  String get groupsCreateTitle => '新建用户组';

  @override
  String get groupsEditTitle => '编辑用户组';

  @override
  String get groupsDelete => '删除用户组';

  @override
  String get groupsSaved => '用户组已保存';

  @override
  String get groupsDeleted => '用户组已删除';

  @override
  String groupsDeleteQuestion(String group) {
    return '删除 $group？';
  }

  @override
  String get groupsDeleteBody => '其授予的权限会一并消失。';

  @override
  String groupsDeleteBodyWithMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '组内有 $count 个账号，账号会保留，只是失去该组授予的权限。',
    );
    return '$_temp0';
  }

  @override
  String get groupsFieldName => '名称';

  @override
  String get groupsFieldDescription => '用途说明';

  @override
  String get groupsSystemFormNote => '内置组：名称和权限由服务器固定，此处只能修改描述。';

  @override
  String get groupsPermissionsHeader => '权限';

  @override
  String groupsPermissionsSelected(int count) {
    return '已选中 $count 项';
  }

  @override
  String get groupsAdvancedPermissions => '服务器管理';

  @override
  String get groupsAdvancedHint => '用户、API 密钥、设置、备份等应用本身没有界面的内容。';

  @override
  String get serverSettingsMenu => '服务器设置';

  @override
  String get serverSettingsTitle => '服务器设置';

  @override
  String get serverSettingsQueueSubtitle => '调度、预热、打印间隙保温，以及询问打印结果';

  @override
  String get serverSettingsMaintenanceSubtitle => '任务类型与各打印机周期';

  @override
  String get serverSettingsAdminSubtitle => '账号、用户组和 API 密钥';

  @override
  String get serverSettingsCloudSubtitle => '服务器下载时使用的 Bambu 账号';

  @override
  String get queueSettingsTitle => '队列与预热';

  @override
  String get queueSettingsReadOnlyApiKey => 'API 密钥无法写入服务器设置，请使用账号登录后再修改。';

  @override
  String get queueSettingsReadOnlyPermission => '你的账号可以查看这些设置，但无权修改。';

  @override
  String get queueSettingsUnavailable => '该服务器未提供这些设置：可能是版本较旧，或读取失败。下拉刷新可重试。';

  @override
  String get queueSettingsQueueHeader => '队列';

  @override
  String get queueSettingsPlateClearTitle => '确认打印板已清空';

  @override
  String get queueSettingsPlateClearDesc => '打印结束后，打印机会等待有人确认打印板已清空。';

  @override
  String get queueSettingsShortestFirstTitle => '最短任务优先';

  @override
  String get queueSettingsShortestFirstDesc => '优先执行耗时最短的等待任务，而不是等待最久的任务。';

  @override
  String queueSettingsMaxUploads(int count) {
    return '同时上传的文件数：$count';
  }

  @override
  String get queueSettingsPreheatHeader => '预热';

  @override
  String get queueSettingsPreheatTitle => '任务前预热';

  @override
  String get queueSettingsPreheatDesc => '发送文件前先加热腔体。单个排队任务可以覆盖此设置。';

  @override
  String queueSettingsPreheatMaxWait(String duration) {
    return '腔体等待上限：$duration';
  }

  @override
  String queueSettingsPreheatSoak(String duration) {
    return '达到温度后保温：$duration';
  }

  @override
  String get queueSettingsNoSoak => '不保温';

  @override
  String get queueSettingsPreheatOffNote => '预热已关闭，以下设置不会生效。';

  @override
  String get queueSettingsKeepWarmHeader => '保温';

  @override
  String get queueSettingsKeepWarmTitle => '打印间隙保持热床温度';

  @override
  String get queueSettingsKeepWarmDesc =>
      '在有人取下成品前保持热床温度，使下一个需要腔体加热的任务不必从冷态开始。PLA 和 PETG 会跳过此功能。';

  @override
  String queueSettingsKeepWarmTemp(int temp) {
    return '用于加热腔体的热床温度：$temp °C';
  }

  @override
  String queueSettingsKeepWarmMax(String duration) {
    return '热床保持温度的最长时间：$duration';
  }

  @override
  String get queueSettingsMaxUploadsDesc =>
      '排队任务开始前会先通过 FTP 把文件发送到打印机，可能耗时数分钟。此项决定同时进行多少个传输，仅在有多台打印机时才有实际作用。';

  @override
  String get queueSettingsPreheatMaxWaitDesc =>
      'X1C 和 P2S 没有腔体加热器，腔体靠热床升温，可能需要 15–30 分钟。超过该时间后队列不再等待，直接进入保温阶段。';

  @override
  String get queueSettingsPreheatSoakDesc =>
      '腔体达到温度后（或上述等待超时后）额外保持的时间，设为 0 则跳过。';

  @override
  String get queueSettingsKeepWarmTempDesc =>
      '封闭式打印机上 90°C 可维持腔体温度，并会触发外接腔体加热器（通常热床 80°C 时启动）。文件中更高的热床温度始终优先。';

  @override
  String get queueSettingsKeepWarmMaxDesc =>
      '按你实际到达打印机所需的时间设置。过短只会让下一次打印从冷态开始多花时间；不设上限则未清空的打印板会让热床一直保持高温。';

  @override
  String get queueSettingsKeepWarmOffNote => '保温已关闭，上面的热床温度仍用于预热。';

  @override
  String get adminTitle => '管理';

  @override
  String adminSignedInAs(String username) {
    return '已登录为 $username';
  }

  @override
  String get adminUsersSubtitle => '谁拥有账号，以及各自可以做什么';

  @override
  String get adminGroupsSubtitle => '权限集及其持有人';

  @override
  String get adminApiKeysSubtitle => '供本应用以外一切使用的凭据';

  @override
  String get apiKeysTitle => 'API 密钥';

  @override
  String get apiKeysEmpty => '尚未签发任何密钥。';

  @override
  String get apiKeysCreate => '新建密钥';

  @override
  String get apiKeysCreateTitle => '新建 API 密钥';

  @override
  String get apiKeysEditTitle => '编辑密钥';

  @override
  String get apiKeysSaved => '密钥已保存';

  @override
  String get apiKeysRevoke => '吊销';

  @override
  String get apiKeysRevoked => '密钥已吊销';

  @override
  String apiKeysRevokeQuestion(String name) {
    return '吊销 $name？';
  }

  @override
  String get apiKeysRevokeBody => '使用该密钥的程序会立即失效，且无法撤销，只能重新签发新密钥。';

  @override
  String apiKeysLastUsed(String date) {
    return '最后使用于 $date';
  }

  @override
  String get apiKeysNeverUsed => '从未使用';

  @override
  String get apiKeysDisabled => '已停用';

  @override
  String get apiKeysExpired => '已过期';

  @override
  String apiKeysExpiresOn(String date) {
    return '至 $date';
  }

  @override
  String apiKeysPrinterLimited(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台打印机',
    );
    return '$_temp0';
  }

  @override
  String get apiKeysLegacy => '无所有者';

  @override
  String get apiKeysFieldName => '名称';

  @override
  String get apiKeysFieldNameHint =>
      '哪个程序在使用该密钥，例如“Home Assistant”“SpoolBuddy”。';

  @override
  String get apiKeysFieldEnabled => '启用';

  @override
  String get apiKeysFieldEnabledHint => '关闭后密钥立即失效，但不会被删除。';

  @override
  String get apiKeysScopesHeader => '可用权限';

  @override
  String get apiKeysScopesHint => '密钥永远无法管理账号、用户组、密钥或设置，服务器会对所有密钥拒绝这些操作。';

  @override
  String get apiKeysPrintersHeader => '打印机';

  @override
  String get apiKeysAllPrinters => '全部打印机';

  @override
  String get apiKeysAllPrintersHint => '关闭后，可选择该密钥可以操作哪些打印机。';

  @override
  String get apiKeysExpiryHeader => '有效期';

  @override
  String get apiKeysNoExpiry => '不过期';

  @override
  String get apiKeysExpiryHint => '点击选择失效日期。';

  @override
  String get apiKeysExpiryClear => '无有效期';

  @override
  String get apiKeysCreatedTitle => '密钥已创建';

  @override
  String get apiKeysCreatedWarning => '请立即复制。服务器只保存哈希值，这是唯一一次可见。';

  @override
  String get apiKeysCopy => '复制';

  @override
  String get apiKeysCopied => '密钥已复制';

  @override
  String get apiKeysCreatedDone => '完成';

  @override
  String get apiKeyScopeRead => '读取状态';

  @override
  String get apiKeyScopeReadHint => '打印机、队列、归档、文件库、统计，仅限读取。';

  @override
  String get apiKeyScopeQueue => '队列';

  @override
  String get apiKeyScopeControl => '控制打印机';

  @override
  String get apiKeyScopeControlHint => '暂停、停止、温度、AMS、智能插座。';

  @override
  String get apiKeyScopeLibrary => '文件';

  @override
  String get apiKeyScopeInventory => '耗材';

  @override
  String get apiKeyScopeMaintenance => '维护';

  @override
  String get apiKeyScopeArchives => '归档';

  @override
  String get apiKeyScopeProjects => '项目';

  @override
  String get apiKeyScopeCloud => 'Bambu Cloud';

  @override
  String get apiKeyScopeCloudHint => '代表创建该密钥的账号读取云端数据，需服务器端开启身份验证。';

  @override
  String get apiKeyScopeEnergy => '电价';

  @override
  String get apiKeyScopeEnergyHint => '密钥唯一可写的设置项，用于分时电价。';

  @override
  String get apiKeyScopeNotifications => '发送通知';

  @override
  String get apiKeyScopeNotificationsHint =>
      '允许其他应用向接受互联应用消息的通知渠道发布消息。密钥所有者还需具备管理通知的权限。';

  @override
  String get printLogTitle => '打印日志';

  @override
  String get printLogSearchHint => '搜索运行记录';

  @override
  String get printLogEmpty => '暂无运行记录';

  @override
  String get printLogNoMatches => '没有符合筛选条件的运行记录';

  @override
  String get printLogLoadFailed => '无法加载打印日志';

  @override
  String get printLogFilters => '筛选';

  @override
  String get printLogFilterPrinter => '打印机';

  @override
  String get printLogFilterUser => '用户';

  @override
  String get printLogFilterStatus => '状态';

  @override
  String get printLogFilterDates => '日期范围';

  @override
  String get printLogAnyPrinter => '任意打印机';

  @override
  String get printLogAnyUser => '任何人';

  @override
  String get printLogAnyStatus => '任意状态';

  @override
  String get printLogNoUser => '无用户';

  @override
  String get printLogOrphan => '归档已删除';

  @override
  String printLogShowing(int loaded, int total) {
    return '$loaded/$total';
  }

  @override
  String get printLogLoadMore => '加载更多';

  @override
  String get printLogSort => '排序方式';

  @override
  String get printLogSortDate => '日期';

  @override
  String get printLogSortName => '名称';

  @override
  String get printLogSortPrinter => '打印机';

  @override
  String get printLogSortUser => '用户';

  @override
  String get printLogSortStatus => '状态';

  @override
  String get printLogSortDuration => '时长';

  @override
  String get printLogSortFilament => '耗材用量';

  @override
  String get printLogSortCost => '成本';

  @override
  String get printLogSortEnergy => '能耗';

  @override
  String get printLogSortDirection => '方向';

  @override
  String get printLogSortDescending => '降序';

  @override
  String get printLogSortAscending => '升序';

  @override
  String get printLogStatusCompleted => '已完成';

  @override
  String get printLogStatusFailed => '失败';

  @override
  String get printLogStatusStopped => '已停止';

  @override
  String get printLogStatusCancelled => '已取消';

  @override
  String get printLogStatusSkipped => '已跳过';

  @override
  String get printLogStatusAborted => '已中止';

  @override
  String printLogEnergy(String value) {
    return '$value 千瓦时';
  }

  @override
  String get printLogClassifyTitle => '标记该次运行';

  @override
  String get printLogDetailStarted => '开始';

  @override
  String get printLogDetailFinished => '结束';

  @override
  String get printLogDetailDuration => '时长';

  @override
  String get printLogDetailFilament => '耗材';

  @override
  String get printLogDetailCost => '成本';

  @override
  String get printLogDetailEnergy => '能耗';

  @override
  String get printLogFailureCause => '失败原因';

  @override
  String get printLogNoClassification => '未分类';

  @override
  String get printLogStatusLabel => '状态';

  @override
  String get printLogCountsAsFailure => '计入失败：该次运行及其原因会出现在失败分析中。';

  @override
  String get printLogNotCountedAsFailure => '不计入失败，因此其原因不会出现在失败分析中。';

  @override
  String printLogStatusOneWay(String status) {
    return '该服务器无法将状态改回“$status”，修改后不可恢复。';
  }

  @override
  String get printLogSave => '保存';

  @override
  String get printLogSaveFailed => '无法保存分类';

  @override
  String get printLogDelete => '删除运行记录';

  @override
  String get printLogDeleteTitle => '删除该运行记录？';

  @override
  String get printLogDeleteBody => '它将从日志中移除，其耗材、成本和时间也会从统计中扣除；对应的归档记录仍会保留。';

  @override
  String get printLogDeleteFailed => '无法删除该运行记录';

  @override
  String get printLogClear => '清空打印日志';

  @override
  String get printLogClearTitle => '清空全部打印日志？';

  @override
  String printLogClearBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '日志中的全部 $count 条运行记录',
    );
    return '$_temp0将被删除（所有人的，不只是你的），其耗材、成本和时间也会从统计中扣除。归档和队列不受影响，且此操作无法撤销。';
  }

  @override
  String get printLogClearBodyFiltered =>
      '日志中的全部运行记录都将删除（所有人的，不只是你的，当前筛选不会缩小范围），其耗材、成本和时间也会从统计中扣除。归档和队列不受影响，且此操作无法撤销。';

  @override
  String printLogCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已删除 $count 条运行记录',
    );
    return '$_temp0';
  }

  @override
  String get printLogClearFailed => '无法清空打印日志';

  @override
  String get failureReasonAdhesion => '附着失败';

  @override
  String get failureReasonSpaghetti => '炒面 / 打印件脱落';

  @override
  String get failureReasonLayerShift => '层错位';

  @override
  String get failureReasonCloggedNozzle => '喷嘴堵塞';

  @override
  String get failureReasonFilamentRunout => '耗材用尽';

  @override
  String get failureReasonWarping => '翘边';

  @override
  String get failureReasonStringing => '拉丝';

  @override
  String get failureReasonUnderExtrusion => '挤出不足';

  @override
  String get failureReasonPowerFailure => '断电';

  @override
  String get failureReasonUserCancelled => '用户取消';

  @override
  String get failureReasonOther => '其他';

  @override
  String get failureReasonUnknown => '未知';

  @override
  String get appSettingsMenu => '应用设置';

  @override
  String get appSettingsTitle => '应用设置';

  @override
  String get appearanceTitle => '外观';

  @override
  String get appearanceAccent => '强调色';

  @override
  String get appearanceAccentBambuddy => 'Bambuddy 绿';

  @override
  String get appearanceAccentSystem => '跟随系统（Material You）';

  @override
  String get appearanceAccentBlue => '蓝色';

  @override
  String get appearanceAccentPurple => '紫色';

  @override
  String get appearanceAccentOrange => '橙色';

  @override
  String get appearanceAccentPink => '粉色';

  @override
  String get appearanceAccentGraphite => '石墨灰';

  @override
  String get appearanceMode => '主题';

  @override
  String get appearanceModeSystem => '跟随系统';

  @override
  String get appearanceModeLight => '浅色';

  @override
  String get appearanceModeDark => '深色';

  @override
  String get appSettingsPhone => '手机';

  @override
  String get appSettingsLabelPrinter => '打印机';

  @override
  String get watchSettingsTitle => '手表';

  @override
  String get watchThemeFromFace => '主题取自表盘';

  @override
  String get watchThemeFromFaceDesc => '适用于 Wear OS 6 及以上。表盘未提供颜色时，手表使用手机的主题。';

  @override
  String get watchThemeFromPhone => '主题取自手机';

  @override
  String get watchThemeFromPhoneDesc => '与本应用相同的强调色。';

  @override
  String get appSettingsNotificationsSubtitle => '哪些事件会发送通知，以及阈值';

  @override
  String get collapsePrinterCardsTitle => '折叠打印机卡片';

  @override
  String get collapsePrinterCardsDesc => '卡片默认只显示名称、状态和打印进度，任意卡片仍可展开。';

  @override
  String get printerCardExpand => '展开卡片';

  @override
  String get printerCardCollapse => '收起卡片';

  @override
  String get ordersTitle => '批量订单';

  @override
  String get ordersEmpty => '没有该状态的批量订单。';

  @override
  String get ordersFilterActive => '进行中';

  @override
  String get ordersFilterCompleted => '已完成';

  @override
  String get ordersFilterCancelled => '已取消';

  @override
  String get ordersFilterAll => '全部';

  @override
  String get ordersStatusActive => '进行中';

  @override
  String get ordersStatusCompleted => '已完成';

  @override
  String get ordersStatusCancelled => '已取消';

  @override
  String get ordersStatusUnknown => '状态未知';

  @override
  String get ordersGroupingOnly => '仅分组';

  @override
  String ordersBy(String name) {
    return '由 $name 添加';
  }

  @override
  String ordersDue(String date) {
    return '$date 到期';
  }

  @override
  String ordersProgress(int completed, int total) {
    return '已完成 $completed/$total';
  }

  @override
  String ordersPrinting(int count) {
    return '$count 个打印中';
  }

  @override
  String ordersPending(int count) {
    return '$count 个等待中';
  }

  @override
  String ordersFailed(int count) {
    return '$count 个失败';
  }

  @override
  String ordersOwed(int count) {
    return '还差 $count 个';
  }

  @override
  String ordersCostSoFar(String amount) {
    return '目前 $amount';
  }

  @override
  String ordersStrandedNotice(int runs, int owed) {
    return '$owed 个待完成运行中有 $runs 个无法加入队列：请先从文件为其打印板排队一次。';
  }

  @override
  String get ordersStrandedPlate => '从文件为该打印板排队一次';

  @override
  String ordersPlateProgress(int completed, int target) {
    return '$completed/$target';
  }

  @override
  String get ordersWholeFile => '整个文件';

  @override
  String ordersDispatchRemaining(int count) {
    return '排队待完成项（$count）';
  }

  @override
  String get ordersDispatchPlate => '排队待完成项';

  @override
  String ordersDispatched(String name) {
    return '已排队 $name 剩余的运行';
  }

  @override
  String get ordersCancel => '取消订单';

  @override
  String get ordersCancelTitle => '取消该订单？';

  @override
  String get ordersCancelBody => '队列中仍在等待的运行将被取消，订单也不再索要尚未产出的内容。已在打印的任务会继续完成。';

  @override
  String get ordersCancelled => '订单已取消';

  @override
  String get ordersUngroup => '取消分组';

  @override
  String get ordersUngroupTitle => '取消该批量的分组？';

  @override
  String get ordersUngroupBody => '其中各项将作为独立任务保留在队列中。';

  @override
  String get ordersUngroupOrderBody =>
      '其中各项将作为独立任务保留在队列中。当队列中不再有任何一项时，订单会连同目标和进度一起删除；你无权修改的其他用户的项会让订单继续存在。';

  @override
  String ordersUngrouped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已取消 $count 项的分组',
      zero: '没有可取消分组的项',
    );
    return '$_temp0';
  }

  @override
  String ordersErrStranded(String plates) {
    return '$plates 没有可复制设置的排队或已完成的运行。请先从文件为该打印板排队一次，再从这里排队其余项。';
  }

  @override
  String get ordersErrCancelled => '该订单已取消。';

  @override
  String get ordersErrGone => '该订单已不存在。';

  @override
  String queueInBatch(String name) {
    return '批量：$name';
  }

  @override
  String get orderEditTitle => '编辑订单';

  @override
  String get orderEditSave => '保存';

  @override
  String get orderEditName => '名称';

  @override
  String get orderEditErrName => '订单需要一个名称。';

  @override
  String get orderEditDue => '截止日期';

  @override
  String get orderEditDueNone => '无截止日期';

  @override
  String get orderEditDueHint => '服务器可以修改截止日期，但不能移除。';

  @override
  String get orderEditProject => '项目';

  @override
  String get orderEditProjectNone => '无项目';

  @override
  String get orderEditProjectHint => '服务器可以将订单移到其他项目，但不能移出项目。';

  @override
  String get orderEditNotes => '备注';

  @override
  String get orderEditTargets => '各打印板的运行次数';

  @override
  String get orderEditTargetsHint => '调低目标不会取消已排队的运行；设为 0 表示该打印板不需要。';

  @override
  String orderEditPlateDone(int count) {
    return '已完成：$count';
  }

  @override
  String get orderEditSaved => '订单已保存';

  @override
  String get orderEditErrNothingAsked => '至少有一个打印板的目标需要大于 0。';

  @override
  String get orderEditErrProject => '该项目已不存在。';

  @override
  String get ordersEdit => '编辑';

  @override
  String get ordersReopen => '重新打开订单';

  @override
  String get ordersReopened => '订单已重新打开';

  @override
  String get ordersGroup => '合并队列项';

  @override
  String get ordersGroupName => '批量名称';

  @override
  String get ordersGroupHint => '请选择至少两个尚未归入批量的等待任务。';

  @override
  String get ordersGroupEmpty => '没有可分组的项：批量之外不足两个等待任务。';

  @override
  String get ordersGroupConfirm => '合并';

  @override
  String ordersGrouped(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个任务已合并为 $name',
    );
    return '$_temp0';
  }

  @override
  String ordersPlateDispatched(String plate, String name) {
    return '已排队 $plate 的待完成运行（$name）';
  }

  @override
  String get queueEditCopies => '份数';

  @override
  String get queueEditCopiesHint => '这些副本将作为一个批量排队。';

  @override
  String get queueEditCopiesOrder => '这将生成一个订单：失败的副本可在“批量订单”中重新排队。';

  @override
  String get ordersGroupedNone => '没有任务可以合并。';

  @override
  String get orderEditTargetLess => '减少一次运行';

  @override
  String get orderEditTargetMore => '增加一次运行';

  @override
  String get queueEditOrderRefused => '无法创建订单，副本已作为普通批量排队。';

  @override
  String get inventoryQuantityLess => '减少一个料盘';

  @override
  String get inventoryQuantityMore => '增加一个料盘';

  @override
  String get outcomeGoodPart => '合格件';

  @override
  String get outcomeRejected => '不合格件';

  @override
  String get outcomeAwaiting => '等待判定';

  @override
  String get outcomeNotRecorded => '未记录判定';

  @override
  String get outcomeSourceDialog => '在应用内记录';

  @override
  String get outcomeSourceLink => '通过一键链接记录';

  @override
  String get outcomeSourcePlateClear => '在确认清空打印板时记录';

  @override
  String get outcomeSourcePrinterCard => '从打印机卡片记录';

  @override
  String get outcomeSourceApi => '通过 API 记录';

  @override
  String get outcomeSourceReaction => '通过聊天中的表情回应记录';

  @override
  String get outcomeTitle => '这次的打印结果如何？';

  @override
  String get outcomeGood => '合格';

  @override
  String get outcomeReject => '不合格';

  @override
  String get outcomeLater => '稍后再问';

  @override
  String get outcomeClear => '清除判定';

  @override
  String get outcomeRejectReason => '不合格原因（可选）';

  @override
  String get outcomeNoReason => '无原因';

  @override
  String get outcomeSaveReject => '保存';

  @override
  String get outcomeRejectAndReprint => '再打印一次';

  @override
  String get outcomeSavedGood => '已标记为合格件';

  @override
  String get outcomeSavedReject => '已标记为不合格';

  @override
  String get outcomeCleared => '判定已移除';

  @override
  String get outcomeUnsupported => '服务器未保存该判定。请更新 bambuddy 以记录打印结果。';

  @override
  String get queueOptConfirmOutcome => '询问打印结果';

  @override
  String get queueOptConfirmOutcomeDesc => '打印完成后询问是否合格';

  @override
  String get queueSettingsOutcomeHeader => '打印结果';

  @override
  String get queueSettingsOutcomeDefaultTitle => '新打印默认询问结果';

  @override
  String get queueSettingsOutcomeDefaultDesc =>
      '新任务默认询问结果，在打印表单中可以逐项更改；没有表单的场景（如一次加入多个文件或运行流水线）也遵循此设置。';

  @override
  String get queueSettingsOutcomeExternalTitle => '外部发起的打印也询问';

  @override
  String get queueSettingsOutcomeExternalDesc =>
      '在打印机、Bambu Studio 或 Bambu Handy 上发起并被 Bambuddy 归档的打印，同样会询问结果。';

  @override
  String get queueSettingsOutcomePlateClearTitle => '确认清空打印板后，将未答复的打印视为合格';

  @override
  String get queueSettingsOutcomePlateClearDesc =>
      '当有人确认打印板已清空时（若关闭该确认，则当下一个排队任务发送到该打印机时），已完成但尚未判定结果的打印会被记为合格件。此后打开的通知链接只会显示已记录的内容。';

  @override
  String get notifEvtOutcome => '结果询问';

  @override
  String get notifEvtOutcomeDesc => '需要询问结果的打印完成时，可直接在通知中选择合格或不合格';

  @override
  String get notifEvtBilling => '计费问题';

  @override
  String get notifEvtBillingDesc => '服务器停止未授权打印或无法对已完成的打印计费时';

  @override
  String get notifBillingKillTitle => '未授权打印已停止';

  @override
  String notifBillingKillBody(String printer, String filename) {
    return '计费熔断机制在 $printer 上停止了未授权打印：$filename';
  }

  @override
  String get notifBillingChargeTitle => '计费失败';

  @override
  String notifBillingChargeBody(String printer, String filename) {
    return '$printer 上的 $filename 计费失败。预算预留已保留，请检查服务器日志。';
  }

  @override
  String get notifBillingUnknownFile => '未知文件';

  @override
  String outcomeNotifTitle(String name) {
    return '$name 的结果如何？';
  }

  @override
  String get outcomeNotifBody => '可在此直接答复，或点击先查看成品照片。';

  @override
  String get queueOptConfirmOutcomeSticky => '该打印已要求询问结果，其所有重新打印也会如此';

  @override
  String get wallModeTitle => '展示墙模式';

  @override
  String get wallModeExit => '退出展示墙模式';

  @override
  String get wallKeepAwakeTitle => '保持屏幕常亮';

  @override
  String get wallKeepAwakeDesc => '展示墙模式开启时屏幕保持常亮；关闭则使用设备自身的息屏规则。';

  @override
  String get wallPanelFarm => '打印农场';

  @override
  String get wallPanelSettings => '设置';

  @override
  String get wallPanelExpand => '展开面板';

  @override
  String get wallPanelCollapse => '收起面板';

  @override
  String get wallErrorsTitle => '错误';

  @override
  String get wallNoFaults => '无活动错误';

  @override
  String wallQueueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '队列中 $count 个',
    );
    return '$_temp0';
  }

  @override
  String get wallLivePaused => '实时画面已暂停';

  @override
  String get wallLiveCameraTitle => '实时摄像头';

  @override
  String get wallLiveCameraDesc => '关闭后仅显示各打印机状态，不打开摄像头流。';

  @override
  String get wallPrintersTitle => '展示墙上的打印机';

  @override
  String get wallAllHidden => '所有打印机都已从该展示墙隐藏，请在设置中显示。';

  @override
  String get controllerTitle => '控制台';

  @override
  String get controllerExit => '退出控制台';

  @override
  String get controllerSwitchPrinter => '切换打印机';

  @override
  String get controllerTabOverview => '概览';

  @override
  String get controllerPrinterGone => '该打印机已不在服务器上。';

  @override
  String get controllerLiveBadge => '实时';

  @override
  String get controllerPreviewBadge => '文件预览';

  @override
  String get controllerNoPreview => '无预览';

  @override
  String get controllerPower => '电源';

  @override
  String get controllerTabHeat => '加热';

  @override
  String get controllerNoChamberHeater => '无腔体加热';

  @override
  String get controllerMoveLocked => '打印进行中，轴已锁定';

  @override
  String get controllerTabFilament => '耗材';

  @override
  String get controllerTabFiles => '文件';

  @override
  String get controllerTabPrints => '打印记录';

  @override
  String controllerQueueCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个任务',
      zero: '无任务',
    );
    return '$_temp0';
  }

  @override
  String get controllerQueueEmpty => '该打印机没有等待的任务';

  @override
  String get controllerQueueCrossModel => '该任务有其他打印机备选，将在第一台空闲的打印机上开始。';

  @override
  String get controllerQueueNoStart => '你的账号无法启动该任务。';

  @override
  String get controllerArchiveEmpty => '该打印机还没有打印记录';

  @override
  String get controllerArchiveLoadingMore => '正在加载更早的打印记录…';

  @override
  String get controllerFileNotSliced => '未切片';

  @override
  String get controllerFileReasonNotSliced => '只有已切片的文件才能打印。';

  @override
  String controllerFileReasonModel(String model) {
    return '为 $model 切片，该打印机无法使用。';
  }

  @override
  String get controllerFilesReadOnly => '该文件夹为只读。';

  @override
  String get controllerPrintTitle => '打印设置';

  @override
  String get controllerPrintNow => '现在';

  @override
  String get controllerPrintNowAction => '立即打印';

  @override
  String controllerPrintAutoMatched(String printer) {
    return '已自动匹配到 $printer';
  }

  @override
  String get controllerPrintManualMapping => '手动映射';

  @override
  String get controllerPrintResetMapping => '恢复自动';

  @override
  String get controllerPrintNotLoaded => '未装载';

  @override
  String controllerPrintUnmapped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 种耗材没有匹配的槽位',
    );
    return '$_temp0';
  }

  @override
  String get controllerPrintBusy => '打印机正忙，空闲后该任务将开始。';

  @override
  String get controllerPrintOffline => '打印机离线，任务会等待其恢复。';

  @override
  String get controllerPrintJob => '任务';

  @override
  String get controllerPrintOptions => '选项';

  @override
  String get controllerPrintMore => '更多';

  @override
  String get controllerPrintMoreTitle => '更多选项';

  @override
  String controllerPrintCostCenter(String name) {
    return '成本中心：$name';
  }

  @override
  String get controllerPrintNoCostCenter => '没有可用的成本中心';

  @override
  String get controllerPrintCostCentersRefused => '当前登录方式无法读取成本中心';

  @override
  String get controllerPrintChamber => '腔体目标温度';

  @override
  String controllerPrintWrongModel(String model, String printer) {
    return '为 $model 切片，而该打印机是 $printer。';
  }

  @override
  String get controllerExtruder => '挤出机';

  @override
  String get controllerEditSlot => '编辑槽位';

  @override
  String get controllerTouchToWake => '点击唤醒';

  @override
  String get controllerPrintPaused => '打印已暂停';

  @override
  String get controllerTabSettings => '设置';

  @override
  String get controllerSaverTitle => '屏幕保护';

  @override
  String get controllerSaverAfter => '启动延时';

  @override
  String get controllerSaverNever => '从不';

  @override
  String get controllerSaverNeverTitle => '从不息屏？';

  @override
  String get controllerSaverNeverBody =>
      '静止不动的画面可能灼屏，OLED 屏幕尤为严重。仅在你接受该风险时才关闭屏保。';

  @override
  String get controllerSaverNeverConfirm => '关闭屏保';

  @override
  String get controllerSaverBrightness => '亮度';

  @override
  String get controllerSaverBrightnessHint => '屏保显示时的屏幕亮度';

  @override
  String get controllerWakeOnWarnings => '警告时唤醒';

  @override
  String get controllerWakeOnWarningsHint => '导致打印暂停的故障总会唤醒屏幕。';

  @override
  String get controllerSaverPreview => '预览';

  @override
  String get controllerDisplayTitle => '显示';

  @override
  String get controllerKeepAwakeHint => '手机不会自动息屏，屏保仍会生效。';

  @override
  String get controllerLiveCameraHint => '关闭后显示文件预览。';

  @override
  String get controllerKeepAwake => '屏幕常亮';

  @override
  String get controllerSaverNeedsAwake => '不开启此项时屏保不会生效。';

  @override
  String get inventorySuppliersTitle => '供应商';

  @override
  String get inventorySuppliersHint =>
      '供应商是你购买耗材的渠道，而非生产品牌。请在料盘表单中为其指定供应商；仍被料盘使用的供应商无法删除。';

  @override
  String get inventorySuppliersEmpty => '暂无供应商';

  @override
  String get inventorySuppliersLoadFailed => '无法加载供应商';

  @override
  String get inventorySupplierAdd => '添加';

  @override
  String get inventorySupplierNew => '新建供应商';

  @override
  String get inventorySupplierEdit => '编辑供应商';

  @override
  String get inventorySupplierFieldName => '名称';

  @override
  String get inventorySupplierFieldWebsite => '网站';

  @override
  String get inventorySupplierFieldCustomerNumber => '你的客户编号';

  @override
  String inventorySupplierCustomerNumberValue(String number) {
    return '客户号 $number';
  }

  @override
  String get inventorySupplierNameSeparator => '名称不能包含分号';

  @override
  String get inventorySupplierNameTaken => '已存在同名供应商';

  @override
  String get inventorySupplierSaved => '供应商已保存';

  @override
  String get inventorySupplierDeleted => '供应商已删除';

  @override
  String inventorySupplierDeleteTitle(String name) {
    return '删除 $name？';
  }

  @override
  String get inventorySupplierDeleteBody => '将从供应商列表中移除。';

  @override
  String inventorySupplierInUse(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已分配给 $count 个料盘，请先在这些料盘中移除',
    );
    return '$_temp0';
  }

  @override
  String get inventorySupplierInUseUnknown => '仍被料盘使用，请先在那里移除';

  @override
  String get inventorySupplierBoughtHere => '在此购买';

  @override
  String inventorySupplierArticleValue(String number) {
    return '货号 $number';
  }

  @override
  String inventorySupplierQuotedPrice(String price) {
    return '报价 $price/kg';
  }

  @override
  String get inventorySupplierLinksHint => '该产品可购买的地点。请标记该料盘的购买渠道。';

  @override
  String get inventoryBulkSupplierLinksHint =>
      '添加到每个所选料盘；料盘已有的供应商会保留。“在此购买”会替换其当前购买渠道。';

  @override
  String get inventorySupplierAssign => '添加供应商';

  @override
  String get inventorySupplierUnassign => '从该料盘移除';

  @override
  String get inventorySupplierFieldArticle => '货号';

  @override
  String get inventorySupplierFieldQuotedPrice => '报价/kg';

  @override
  String get inventorySupplierNoneLeft => '所有供应商都已在该料盘上';

  @override
  String get statsBySupplier => '按供应商';

  @override
  String get statsBySupplierHint => '按各供应商购买的料盘统计耗材用量及成本。库存仅统计在用料盘，不受时间范围影响。';

  @override
  String get statsBySupplierFailed => '无法加载供应商数据';

  @override
  String get statsByMaterialNumber => '按材料编号';

  @override
  String get statsByMaterialNumberHint =>
      '按材料编号相同的料盘统计耗材用量及成本。库存仅统计在用料盘，不受时间范围影响。';

  @override
  String get statsByMaterialNumberFailed => '无法加载材料编号数据';

  @override
  String statsSupplierDetail(String spools, String remaining, String cost) {
    return '$spools · 库存 $remaining · 成本 $cost';
  }

  @override
  String get inventoryDetailSlot => '槽位';

  @override
  String get inventoryDetailNotLoaded => '未装载';

  @override
  String get inventoryDetailConsumedSinceReset => '重置后已消耗';

  @override
  String get inventoryLastDried => '上次烘干';

  @override
  String get inventoryLastDriedNow => '现在';

  @override
  String get inventoryLastDriedHelp => '在 AMS 烘干后自动填写。若在别处烘干，请手动设置。';

  @override
  String inventorySupplierArchivedCount(int count) {
    return '$count 个已归档';
  }

  @override
  String get timeJustNow => '刚刚';

  @override
  String get timeNow => '现在';

  @override
  String timeMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String timeInMinutes(int count) {
    return '$count 分钟后';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String timeInHours(int count) {
    return '$count 小时后';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 天前',
    );
    return '$_temp0';
  }

  @override
  String timeInDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 天后',
    );
    return '$_temp0';
  }

  @override
  String get queueHistory => '历史';

  @override
  String queueItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
    );
    return '$_temp0';
  }

  @override
  String get queueHistoryEmpty => '暂无历史记录。已完成、已取消和失败的打印会显示在这里。';

  @override
  String get queueHistoryShowMore => '显示更多';

  @override
  String queueHistoryShowing(int shown, int total) {
    return '显示 $shown/$total';
  }

  @override
  String get queueHistorySort => '排序';

  @override
  String get queueHistorySortDate => '按日期';

  @override
  String get queueHistorySortName => '按名称';

  @override
  String get queueHistorySortPrinter => '按打印机';

  @override
  String get queueHistoryNewestFirst => '最新在前';

  @override
  String get queueHistoryOldestFirst => '最早在前';

  @override
  String get queueHistoryClear => '清除历史';

  @override
  String get queueHistoryClearTitle => '清除历史';

  @override
  String queueHistoryClearMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '从历史中移除全部 $count 项？',
    );
    return '$_temp0';
  }

  @override
  String queueHistoryCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已清除 $count 条历史记录。',
    );
    return '$_temp0';
  }

  @override
  String queueHistoryKeptForOrders(int kept) {
    return '保留了 $kept 条，批量订单仍需要它们。';
  }

  @override
  String get queueHistoryClearFailed => '无法清除历史记录。';

  @override
  String get queueHistoryNoClear => '你无权清除全部历史';

  @override
  String get queueHistoryRequeue => '重新排队';

  @override
  String get queueHistoryNoRequeue => '你无权重新排队';

  @override
  String get queueHistoryRemove => '移除';

  @override
  String get queueHistoryNoRemove => '你无权移除该队列项';

  @override
  String get queueHistoryRemoveTitle => '从历史中移除';

  @override
  String queueHistoryRemoveMessage(String name) {
    return '从队列历史中移除“$name”？';
  }

  @override
  String queueHistoryAddedBy(String name) {
    return '由 $name 添加';
  }

  @override
  String get queueHistoryBatch => '批量';

  @override
  String get queueHistoryRemoved => '队列项已移除';

  @override
  String get queueHistoryKeptForOrder => '已改为取消而非移除：这是该批量订单中该打印板唯一可重新排队的运行';

  @override
  String get queueBillingUseWeb =>
      '该服务器已启用计费，每个打印任务都需要成本中心，而此操作无法设置。请在应用中打开该任务进行选择，或使用浏览器访问 Bambuddy。';

  @override
  String get financeMenu => '财务';

  @override
  String get financeTitle => '财务';

  @override
  String get financeBalance => '个人账户余额';

  @override
  String get financeMyCostCenters => '我的成本中心';

  @override
  String get financeNoCostCenters => '未找到成本中心。';

  @override
  String financeAccountBalance(String amount) {
    return '账户余额：$amount';
  }

  @override
  String get financeUnlimited => '不限';

  @override
  String get financeBudgetMonthly => '月度预算';

  @override
  String get financeBudgetTotal => '总预算';

  @override
  String get financeBudgetNone => '无预算';

  @override
  String get financeRecentTransactions => '近期交易';

  @override
  String get financeType => '类型';

  @override
  String get financeAllTypes => '全部类型';

  @override
  String get financeCostCenter => '成本中心';

  @override
  String get financeAllCostCenters => '全部成本中心';

  @override
  String get financeTypePrintCharge => '打印扣费';

  @override
  String get financeTypeDeposit => '充值';

  @override
  String get financeTypeWithdraw => '提现';

  @override
  String get financeTypeAdjustment => '调整';

  @override
  String get financeNoTransactions => '暂无交易记录。';

  @override
  String get financeNoTransactionsForFilter => '没有符合所选筛选条件的交易。';

  @override
  String financeBalanceAfter(String amount) {
    return '变动后余额：$amount';
  }

  @override
  String get financePartialAborted => '已中止';

  @override
  String get financePartialFailed => '失败';

  @override
  String get financePartialCancelled => '已取消';

  @override
  String get financeLoadMore => '加载更多';

  @override
  String financeShowing(int shown, int total) {
    return '$shown/$total';
  }

  @override
  String get financeLoadFailed => '无法加载你的财务数据。';

  @override
  String get financeAddCharge => '添加扣费';

  @override
  String get financeButtonNewCenter => '新建中心';

  @override
  String get financeButtonWallet => '钱包';

  @override
  String get financeButtonManualPrint => '手动打印';

  @override
  String get financeAddManualPrint => '添加手动打印';

  @override
  String get financeAddMember => '添加成员';

  @override
  String get financeAdjustWallet => '调整钱包';

  @override
  String get financeAdminView => '管理员视图';

  @override
  String get financeAmount => '金额';

  @override
  String get financeAmountInvalid => '金额必须是有效数字';

  @override
  String get financeAmountPositive => '金额必须大于零';

  @override
  String get financeApplyAdjustment => '应用调整';

  @override
  String get financeBudgetType => '预算类型';

  @override
  String get financeCanPrint => '可打印';

  @override
  String financeConfirmDeleteCostCenter(String name) {
    return '删除成本中心“$name”？';
  }

  @override
  String get financeCostCenterCreated => '成本中心已创建';

  @override
  String get financeCostCenterDeleted => '成本中心已删除';

  @override
  String get financeCostCenterName => '名称';

  @override
  String get financeCostCenterNameRequired => '成本中心名称必填';

  @override
  String get financeCostCenterRequired => '请选择成本中心';

  @override
  String get financeCostCenters => '成本中心';

  @override
  String get financeCostCenterUpdated => '成本中心已更新';

  @override
  String get financeCreate => '创建';

  @override
  String get financeCreateCostCenter => '创建成本中心';

  @override
  String get financeDelete => '删除';

  @override
  String get financeDeleteBlockedReservations => '仍有排队任务占用该成本中心的部分预算，无法删除。';

  @override
  String get financeDeleteBlockedTransactions => '仍有交易关联该成本中心，无法删除。';

  @override
  String get financeDeleteCostCenter => '删除成本中心';

  @override
  String get financeDeleteTransaction => '删除交易';

  @override
  String get financeDeleteTransactionConfirm => '删除这笔交易？余额将自动重新计算。';

  @override
  String get financeRebuildLedger => '重建钱包流水';

  @override
  String get financeRebuildLedgerConfirm => '这将重建钱包流水的累计余额以修复历史数值。仅在你清楚后果时才执行。';

  @override
  String get financeRebuildLedgerRun => '执行';

  @override
  String get financeLedgerRebuilt => '钱包流水已重建';

  @override
  String get financeDepositDone => '充值成功';

  @override
  String get financeDescription => '描述（可选）';

  @override
  String get financeEdit => '编辑';

  @override
  String get financeEditCostCenter => '编辑成本中心';

  @override
  String get financeEditTransaction => '编辑交易';

  @override
  String get financeManageMembers => '管理成本中心成员';

  @override
  String get financeManualPrintDone => '已添加手动打印扣费并重新计算流水';

  @override
  String get financeMemberCanPrint => '成员可打印';

  @override
  String get financeMemberCanPrintHint => '未开启时，成员可以看到该成本中心，但不能向其记账打印。';

  @override
  String get financeMemberRemoved => '成员已移除';

  @override
  String get financeMembers => '成员';

  @override
  String get financeMemberSaved => '成员已保存';

  @override
  String get financeNoCostCenter => '无成本中心';

  @override
  String get financeNoEligibleUsers => '没有符合条件的用户';

  @override
  String get financeNoMembers => '未分配成员。';

  @override
  String get financePersonalView => '个人视图';

  @override
  String get financePrivateBudgetOnly => '个人成本中心不能改名，只能修改预算。设为 0 将停止其打印。';

  @override
  String get financeRemoveMember => '移除成员';

  @override
  String get financeSave => '保存';

  @override
  String get financeNoUser => '无用户';

  @override
  String get financeDeletedUser => '已删除的用户';

  @override
  String get financeShared => '共享';

  @override
  String get financeTransactionDeleted => '交易已删除';

  @override
  String get financeTransactionEdited => '交易已更新并重新计算流水';

  @override
  String get financeTransactions => '交易记录';

  @override
  String get financeUser => '用户';

  @override
  String get financeUserRequired => '请选择用户';

  @override
  String financeUserWithId(int id) {
    return '用户 #$id';
  }

  @override
  String get financeWithdrawDone => '提现成功';

  @override
  String get queueBillingCostCentersRefused =>
      '该服务器已启用计费，每个打印任务都需要成本中心，但该账号无法在应用中列出其成本中心。请在浏览器中的 Bambuddy 排队、编辑并启动该任务。';

  @override
  String get queueBillingNoCostCenter => '没有可用于打印的有效成本中心，请联系管理员授予打印权限。';

  @override
  String get queueCostCenterTitle => '成本中心';

  @override
  String queueCostCenterPersonal(String name) {
    return '$name（个人）';
  }

  @override
  String get queueCostCenterUnlimited => '不限，未设置预算上限。';

  @override
  String get queueCostCenterLoadFailed => '无法加载你的成本中心。';

  @override
  String queueEstimatedCost(String amount) {
    return '预估成本：$amount';
  }

  @override
  String get queueCostNotAvailable => '不适用';

  @override
  String queueEstimatedCostForCopies(String amount) {
    return '合计：$amount';
  }

  @override
  String get queueInsufficientBudget => '该成本中心预算不足。';

  @override
  String get queueBillingEstimateRequired =>
      '文件没有列出耗材用量，服务器无法计算该任务成本，而成本中心需要该数据。';

  @override
  String get queueBillingCostCenterInactive => '该成本中心已停用，请另选一个。';

  @override
  String get queueBillingCostCenterNoAccess => '你无权使用该成本中心打印，请另选一个。';

  @override
  String get queueBillingBudgetExceeded => '该任务费用超过该成本中心的剩余预算。';

  @override
  String get labelPrinterTitle => '标签打印机';

  @override
  String get labelPrinterIntro =>
      '为 Brother QL 标签打印机单独使用的打印服务器。料盘标签会直接发送到它，而不走系统打印对话框。';

  @override
  String get labelPrinterNotSet => '未选择标签打印机';

  @override
  String labelPrinterReady(String model, String label) {
    return '$model · $label 标签';
  }

  @override
  String get labelPrinterPrinterOff => '服务器有响应，但打印机未连接';

  @override
  String get labelPrinterOffline => '无响应';

  @override
  String labelPrinterWrongStock(String label) {
    return '已装载 $label 标签，料盘标签需要 62 × 29 毫米';
  }

  @override
  String get labelPrinterSearch => '搜索网络';

  @override
  String get labelPrinterSearching => '搜索中…';

  @override
  String get labelPrinterNoneFound => '未找到任何设备。请确认手机连接了同一 Wi-Fi，或在下方手动填写地址。';

  @override
  String get labelPrinterDiscoveryFailed => '该设备不支持网络搜索';

  @override
  String get labelPrinterAddress => '服务器地址';

  @override
  String get labelPrinterSave => '保存';

  @override
  String get labelPrinterRemove => '移除';

  @override
  String get labelPrinterNotAServer => '该地址没有响应为标签打印服务器的设备';

  @override
  String get labelPrinterVlanNote => '发现功能无法跨 VLAN 或访客 Wi-Fi，这些场景请手动填写地址。';

  @override
  String get labelPrinterPrintOn => '在标签打印机上打印';

  @override
  String get labelPrinterSent => '已发送到标签打印机';

  @override
  String get labelPrinterFailed => '标签打印机未接受该任务';

  @override
  String get labelPrinterUnreachable => '标签打印机无响应';

  @override
  String labelPrinterRefused(String detail) {
    return '标签打印机拒绝了该任务：$detail';
  }

  @override
  String get labelPrinterSetUp => '设置标签打印机';

  @override
  String get labelPrinterSetUpHint => '在网络中的 Brother QL 打印服务器上打印这些标签';

  @override
  String get labelOptionsTitle => '打印选项';

  @override
  String get labelFieldsTitle => '标签内容';

  @override
  String get labelFieldsReset => '恢复默认';

  @override
  String get labelFieldBrand => '品牌';

  @override
  String get labelFieldMaterial => '材料与子类型';

  @override
  String get labelFieldHex => '颜色代码';

  @override
  String get labelFieldName => '颜色或耗材名称';

  @override
  String get labelFieldLocation => '存放位置';

  @override
  String get labelFieldMaterialNumber => '材料编号';

  @override
  String get labelFieldTemps => '喷嘴温度';

  @override
  String get labelFieldWeight => '净重';

  @override
  String get labelFieldNote => '备注';

  @override
  String get labelFieldAdded => '添加日期';

  @override
  String get labelFieldQr => '二维码';

  @override
  String get labelFieldSpoolId => '料盘 ID';

  @override
  String get labelFormatTitle => '输出';

  @override
  String get labelFormatPngHint => '请与打印机的分辨率匹配。多枚标签会打包为 ZIP。';

  @override
  String get labelDpiTitle => '分辨率';

  @override
  String get labelSendToTitle => '发送到';

  @override
  String get labelSendSystem => '打印对话框';

  @override
  String get labelSendShare => '分享';

  @override
  String get labelSendSave => '保存为文件';

  @override
  String get labelSendPrinter => '标签打印机';

  @override
  String get labelPrinterCopies => '份数';

  @override
  String get labelPrinterCutAtEnd => '打印完后切纸';

  @override
  String get labelPrinterCutEvery => '每隔几枚标签切纸';

  @override
  String get labelPrinterCutEveryHint => '0 表示标签之间不切纸。';

  @override
  String get labelCutEveryLess => '切纸间隔减少一枚';

  @override
  String get labelCutEveryMore => '切纸间隔增加一枚';

  @override
  String get labelSaved => '标签已保存';

  @override
  String get printerLocationsMenu => '打印机位置';

  @override
  String printerLocationsSubtitle(int grouped, int ungrouped) {
    return '已分配位置：$grouped，未分配：$ungrouped';
  }

  @override
  String get printerLocationsSearch => '搜索位置';

  @override
  String get printerLocationsHideEmpty => '隐藏空位置';

  @override
  String get printerLocationsSortNameAsc => '名称 A→Z';

  @override
  String get printerLocationsSortNameDesc => '名称 Z→A';

  @override
  String get printerLocationsSortCountAsc => '打印机最少';

  @override
  String get printerLocationsSortCountDesc => '打印机最多';

  @override
  String get printerLocationsSort => '排序';

  @override
  String get printerLocationsSelect => '选择';

  @override
  String get printerLocationsDone => '完成';

  @override
  String get printerLocationsNew => '新建位置';

  @override
  String get printerLocationsCreateTitle => '创建位置';

  @override
  String get printerLocationsEditTitle => '编辑位置';

  @override
  String get printerLocationsCreate => '创建';

  @override
  String get printerLocationsSave => '保存';

  @override
  String get printerLocationsFieldName => '位置名称';

  @override
  String get printerLocationsFieldIcon => '图标';

  @override
  String get printerLocationsFieldColor => '颜色';

  @override
  String get printerLocationsNoColor => '无颜色';

  @override
  String get printerLocationsEmpty => '暂无打印机位置';

  @override
  String get printerLocationsNoResults => '没有符合搜索的位置';

  @override
  String printerLocationsPrinterCount(int count) {
    return '打印机：$count';
  }

  @override
  String get printerLocationsNoPrinters => '该位置没有打印机';

  @override
  String get printerLocationsSelectPrinter => '选择打印机';

  @override
  String get printerLocationsMove => '移动到其他位置';

  @override
  String get printerLocationsMoveButton => '移动';

  @override
  String get printerLocationsRemoveFromLocation => '从位置移除';

  @override
  String printerLocationsUngrouped(int count) {
    return '未分配位置的打印机：$count';
  }

  @override
  String get printerLocationsSelectAll => '全选';

  @override
  String get printerLocationsDeselectAll => '取消全选';

  @override
  String printerLocationsSelected(int count) {
    return '已选：$count';
  }

  @override
  String get printerLocationsDeleteSelected => '删除所选';

  @override
  String get printerLocationsMoveTitle => '移动打印机';

  @override
  String printerLocationsMoveTitleMany(int count) {
    return '移动打印机（$count）';
  }

  @override
  String get printerLocationsTargetHint => '请选择位置';

  @override
  String get printerLocationsNoLocation => '无位置';

  @override
  String get printerLocationsDeleteTitle => '删除位置';

  @override
  String printerLocationsDeleteTitleMany(int count) {
    return '删除位置（$count）';
  }

  @override
  String printerLocationsDeleteMessage(String names, int count) {
    return '删除 $names？将失去位置的打印机：$count。';
  }

  @override
  String get printerLocationsCreated => '位置已创建';

  @override
  String get printerLocationsSaved => '位置已保存';

  @override
  String printerLocationsDeleted(int count) {
    return '已删除位置：$count';
  }

  @override
  String printerLocationsMoved(int count) {
    return '已移动打印机：$count';
  }

  @override
  String get printerLocationsNameTaken => '已存在同名位置';

  @override
  String get printerLocationsReadOnly => '只有用户账号才能修改位置，API 密钥只能读取。';

  @override
  String get dashboardSortTitle => '排序方式';

  @override
  String get dashboardSortName => '名称';

  @override
  String get dashboardSortModel => '机型';

  @override
  String get dashboardSortLocation => '位置';

  @override
  String get dashboardSortEta => '剩余时间';

  @override
  String get dashboardSortAscending => '升序';

  @override
  String get dashboardSortDescending => '降序';

  @override
  String get dashboardLocationAll => '全部位置';

  @override
  String get dashboardGroupUngrouped => '无位置';

  @override
  String get dashboardGroupUnknownModel => '未知机型';

  @override
  String get announcementsTitle => '公告';

  @override
  String announcementsUnread(int count) {
    return '未读公告：$count';
  }

  @override
  String get announcementsEmpty => '当前没有公告。';

  @override
  String get linkedAppsTitle => '已关联应用';

  @override
  String get linkedAppsEmpty => '没有已关联的应用。';

  @override
  String announcementsEarlier(int count) {
    return '更早（$count）';
  }

  @override
  String get announcementsNew => '新';

  @override
  String get announcementsReadMore => '阅读全文';

  @override
  String get announcementsSource => '来自 Bambuddy 维护团队，从 GitHub 获取。';

  @override
  String get announcementLevelInfo => '信息';

  @override
  String get announcementLevelImportant => '重要';

  @override
  String get announcementLevelCritical => '严重';

  @override
  String get announcementsMarkAllRead => '全部标为已读';

  @override
  String archiveRunCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 次运行',
    );
    return '$_temp0';
  }

  @override
  String archiveLayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 层',
    );
    return '$_temp0';
  }

  @override
  String archiveObjectCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个对象',
    );
    return '$_temp0';
  }

  @override
  String get archivePrintCost => '打印成本';

  @override
  String archiveSlicedFor(String model) {
    return '为 $model 切片';
  }

  @override
  String archiveTimeDetail(String estimated, String actual) {
    return '预计 $estimated，实际 $actual';
  }

  @override
  String get archiveOpenLink => '链接';

  @override
  String archiveSlot(int slot) {
    return '槽位 $slot';
  }

  @override
  String get tourDemoNote => '演示数据：你在此处的任何操作都不会影响真实打印机。';

  @override
  String get tourSkip => '跳过引导';

  @override
  String get tourNext => '下一步';

  @override
  String get tourFinish => '完成';

  @override
  String tourStepCounter(int current, int total) {
    return '第 $current/$total 步';
  }

  @override
  String get tourStepTabs => '底部导航栏包含主要板块：队列、归档、维护和耗材。逐一打开看看。';

  @override
  String get tourStepDrawer => '打开菜单。其他板块都在这里：文件管理、统计、项目、模型来源以及设置。';

  @override
  String get tourStepEditPrinter => '长按打印机名称即可编辑该打印机。';

  @override
  String get tourStepReorder => '抓住左侧手柄拖动任务即可调整打印顺序。';

  @override
  String get tourStepSwipe => '向左滑动任务即可将其从队列中移除。';

  @override
  String get tourStepSelect => '长按一条打印记录可多选。文件管理和耗材的操作方式相同。';

  @override
  String get tourStepWall => '展示墙模式可在一屏内显示整个打印农场，例如放在打印机旁的平板上。从该菜单进入。';

  @override
  String get tourStepStats => '统计会显示耗材用量、成本和打印成功率。点击“统计”打开。';

  @override
  String get tourStepDone => '就这些。所有手势都列在“应用设置 → 提示”中，也可以在那里再次运行本引导。';

  @override
  String get tipsTitle => '提示';

  @override
  String get tipsSubtitle => '隐藏手势与操作引导';

  @override
  String get tipsRunTour => '运行操作引导';

  @override
  String get tipsEditPrinterTitle => '编辑打印机';

  @override
  String get tipsEditPrinterBody => '在打印机卡片上长按其名称。';

  @override
  String get tipsReorderTitle => '打印顺序';

  @override
  String get tipsReorderBody => '在队列中，通过左侧手柄拖动任务。';

  @override
  String get tipsSwipeTitle => '移除任务';

  @override
  String get tipsSwipeBody => '在队列中向左滑动任务，或在归档中向左滑动一条打印记录。';

  @override
  String get tipsSelectTitle => '多选';

  @override
  String get tipsSelectBody => '在归档、文件管理或耗材中长按某一项。';

  @override
  String get tipsZoomTitle => '跳过对象';

  @override
  String get tipsZoomBody => '双指捏合可放大打印板，双击可恢复原大小。';

  @override
  String get tipsTrimTitle => '裁剪延时摄影';

  @override
  String get tipsTrimBody => '拖动胶片条上的手柄；在其他位置点击或拖动可移动播放进度。';

  @override
  String get tipsWallTitle => '展示墙模式';

  @override
  String get tipsWallBody => '在打印机页面打开 ⋮ 菜单并选择展示墙模式。';

  @override
  String get archiveRunsTitle => '打印历史';

  @override
  String get archiveRunsEmpty => '该文件尚未打印过。';

  @override
  String archiveRunsBeforeLog(String status) {
    return 'Bambuddy 记录每次打印之前完成的打印：$status。';
  }

  @override
  String get archiveRunsPlateEmpty => '该打印板暂无打印记录。';

  @override
  String get archiveRunsAllPlates => '全部打印板';

  @override
  String archiveRunPlate(int plate) {
    return '打印板 $plate';
  }

  @override
  String get archiveRunNoPrinter => '打印机已移除';

  @override
  String archiveRunWithEstimate(String value, String estimate) {
    return '$value（预计 $estimate）';
  }

  @override
  String archiveRunTimeVsEstimate(String value, String estimate, String delta) {
    return '$value / 预计 $estimate（$delta）';
  }

  @override
  String archiveRunTimeOf(String value, String estimate) {
    return '$value / $estimate';
  }

  @override
  String get archiveRunStartedEnded => '开始 / 结束';

  @override
  String get archiveRunEnergy => '能耗';

  @override
  String get archiveRunFailureReason => '失败原因';

  @override
  String get archiveRunStartedBy => '发起人';

  @override
  String get archiveRunNote => '本次打印备注';

  @override
  String get archiveRunVideo => '延时视频';

  @override
  String archiveRunPhotos(int count) {
    return '照片（$count）';
  }

  @override
  String archiveGoodCount(int count) {
    return '成功：$count';
  }

  @override
  String archiveFailedCount(int count) {
    return '失败：$count';
  }

  @override
  String get archiveRunSetOutcome => '标记结果';

  @override
  String get archiveRunChangeOutcome => '修改结果';

  @override
  String get archiveRunAddNote => '添加备注';

  @override
  String get archiveRunEditNote => '编辑备注';

  @override
  String get archiveRunNoteSaved => '备注已保存';

  @override
  String get archivePlatesTitle => '打印板';

  @override
  String archivePlateEstimate(String value) {
    return '预计 $value';
  }

  @override
  String archivePlateLastVsEstimate(String value) {
    return '上次打印与预计对比：$value';
  }

  @override
  String get archivePrintThisPlate => '打印此板';

  @override
  String get archiveShowPlatePrints => '查看该板打印记录';

  @override
  String get archiveRunReprint => '重新打印';

  @override
  String archiveMergeBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 组重复归档',
      one: '1 组重复归档',
    );
    return '$_temp0';
  }

  @override
  String get archiveMergeButton => '合并';

  @override
  String get archiveMergeDismiss => '忽略';

  @override
  String get archiveMergeMenu => '合并重复项';

  @override
  String get archiveMergeTitle => '合并重复归档';

  @override
  String get archiveMergeEffectKeep => '每组中最早的归档保留，并并入其他归档的全部打印记录、照片、视频与文件。';

  @override
  String get archiveMergeEffectLinks => '其余归档将从归档列表移除；其原有链接会跳转到并入后的归档。';

  @override
  String get archiveMergeEffectMoney => '钱包扣款与预算占用仍保留在原记账位置。';

  @override
  String get archiveMergeNone => '没有可合并的重复项。';

  @override
  String archiveMergeMember(String name, String date, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 次打印',
      one: '1 次打印',
    );
    return '$name · 创建于 $date · $_temp0';
  }

  @override
  String get archiveMergeStays => '保留';

  @override
  String get archiveMergeWaiting => '暂不处理';

  @override
  String get archiveMergeLeftOut => '未参与合并';

  @override
  String get archiveMergeSkipBusy => '正在使用中：打印中、排队中或刚打印完成，请稍后再试。';

  @override
  String get archiveMergeSkipConflicting => '这些归档的源文件、设计文件或视频不一致，请先手动保留其中一个。';

  @override
  String get archiveMergeSkipFailed => '合并失败。';

  @override
  String get archiveMergeSkipNotAGroup => '已不再是重复分组。';

  @override
  String archiveMergeAction(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '合并 $count 组',
      one: '合并 1 组',
    );
    return '$_temp0';
  }

  @override
  String get archiveMergeConfirmBody => '此操作在应用内无法撤销。';

  @override
  String archiveMergeDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已合并 $count 组。',
      one: '已合并 1 组。',
    );
    return '$_temp0';
  }

  @override
  String archiveMergeDoneSome(int count, int left) {
    return '已合并：$count；未处理：$left。';
  }

  @override
  String get archiveCalendarView => '日历视图';

  @override
  String get archiveListView => '列表视图';

  @override
  String get archiveCalendarToday => '今天';

  @override
  String get archiveCalendarPrevious => '上个月';

  @override
  String get archiveCalendarNext => '下个月';

  @override
  String get archiveCalendarPrints => '本月打印';

  @override
  String get archiveCalendarSuccessful => '成功';

  @override
  String get archiveCalendarFailed => '失败';

  @override
  String get archiveCalendarNoPrints => '当天无打印记录';

  @override
  String get archiveCalendarSelectDay => '选择日期查看当天打印记录';

  @override
  String archiveCalendarDay(String date, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 次打印',
      one: '1 次打印',
      zero: '无打印',
    );
    return '$date：$_temp0';
  }

  @override
  String get serverSettingsWledSubtitle => '打印机状态对应的灯光预设';

  @override
  String get wledTitle => 'WLED';

  @override
  String get wledDescription => '颜色与灯效在 WLED 中设置；服务器仅切换与打印机状态对应的预设。';

  @override
  String get wledPrinter => '打印机';

  @override
  String get wledEnabled => 'WLED 联动';

  @override
  String get wledEnabledDesc => '随打印机状态变化切换预设';

  @override
  String get wledUrl => 'WLED 地址';

  @override
  String get wledUrlRequired => '开启联动时必填';

  @override
  String get wledLoadPresets => '加载预设';

  @override
  String get wledTestConnection => '测试连接';

  @override
  String wledConnected(String name) {
    return '已连接 $name';
  }

  @override
  String wledConnectedVersion(String name, String version) {
    return '已连接 $name，版本 $version';
  }

  @override
  String get wledUnreachable => 'WLED 无响应';

  @override
  String wledPresetsLoaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已加载 $count 个预设',
      one: '已加载 1 个预设',
      zero: 'WLED 暂无预设',
    );
    return '$_temp0';
  }

  @override
  String get wledPresetsOffline => '无法连接 WLED，已保存的预设保留不变。';

  @override
  String get wledMappingHeader => '各状态对应预设';

  @override
  String get wledSegmentHint => '在 WLED 中创建预设时，选中对应分段并开启“仅启用勾选分段”。';

  @override
  String get wledNoPreset => '无预设';

  @override
  String wledPresetSaved(int id) {
    return '已保存预设 $id';
  }

  @override
  String wledPresetOption(String name, int id) {
    return '$name（$id）';
  }

  @override
  String wledTestPreset(String state) {
    return '测试 $state 预设';
  }

  @override
  String get wledPresetTested => '预设已切换';

  @override
  String get wledPresetTestFailed => 'WLED 未能切换预设';

  @override
  String get wledFinishedTimeout => '打印结束后恢复空闲的等待时长（秒）';

  @override
  String get wledFinishedTimeoutHint => '打印结束后多久切换到空闲预设，单位为秒；填 0 表示关闭。';

  @override
  String get wledFinishedTimeoutInvalid => '0 到 86400 之间的整数';

  @override
  String get wledSave => '保存';

  @override
  String get wledSaved => 'WLED 设置已保存';

  @override
  String wledRefused(String reason) {
    return '未被接受：$reason';
  }

  @override
  String get wledNoPrinters => '没有可设置的打印机';

  @override
  String get wledStateIdle => '空闲';

  @override
  String get wledStatePrepare => '准备中';

  @override
  String get wledStatePrinting => '打印中';

  @override
  String get wledStatePaused => '已暂停';

  @override
  String get wledStateFinished => '已完成';

  @override
  String get wledStateError => '失败';

  @override
  String get wledStateQueueWaiting => '等待清理打印板';

  @override
  String get wledStateFilamentProblem => '耗材异常';

  @override
  String get wledStateHmsError => 'HMS 报错';

  @override
  String get wledStateOffline => '离线';

  @override
  String get fmMoveBlockedCurrent => '已在当前位置';

  @override
  String get fmMoveBlockedSelf => '正在移动的文件夹本身';

  @override
  String get fmMoveBlockedInside => '位于正在移动的文件夹内';

  @override
  String get fmMoveBlockedExternal => '外部文件夹';

  @override
  String get fmMoveBlockedNotWritable => '非本人且未共享';

  @override
  String get fmMoveBlockedReadOnly => '只读文件夹';

  @override
  String get fmNotMoved => '文件未移动';

  @override
  String fmNotMovedReason(String reason) {
    return '文件未移动：$reason';
  }

  @override
  String get aiDetectionSafe => '正常';

  @override
  String get aiDetectionWarning => '警告';

  @override
  String get aiDetectionFailure => '失败';

  @override
  String get aiDetectionNotChecking => '未检测';

  @override
  String get aiDetectionStarting => '启动中';

  @override
  String aiDetectionTipStatus(String status) {
    return 'AI 故障检测：$status';
  }

  @override
  String aiDetectionTipScore(String status, String score) {
    return 'AI 故障检测：$status（得分 $score）';
  }

  @override
  String aiDetectionTipQuality(String status, int quality) {
    return 'AI 故障检测：$status（打印质量 $quality/10）';
  }

  @override
  String aiDetectionTipError(String reason) {
    return 'AI 故障检测未检测本次打印：$reason';
  }

  @override
  String get aiDetectionTipErrorNoReason => 'AI 故障检测未检测本次打印';

  @override
  String get aiDetectionTipStarting => 'AI 故障检测：等待首个检测结果';

  @override
  String get aiDetectionLimitReached => '已达用量上限';

  @override
  String notifLowStockTitle(String percent) {
    return '耗材余量低于 $percent%';
  }

  @override
  String get notifLowStockDesc => '在服务器上为所有人统一设置；单个料盘的阈值优先。';

  @override
  String get notifLowStockEdit => '修改耗材低余量阈值';

  @override
  String get notifLowStockInputLabel => '占标签重量的百分比';

  @override
  String get notifLowStockInvalid => '请输入 0.1 到 99.9 之间的数字。';

  @override
  String get pandaBreath => 'Panda Breath';

  @override
  String get pandaBreathSent => '已发送到 Panda Breath';

  @override
  String get pandaBreathOffline => '加热器离线';

  @override
  String get pandaBreathTurnOn => '开启';

  @override
  String get pandaBreathTurnOff => '关闭';

  @override
  String get pandaBreathMode => '模式';

  @override
  String get pandaBreathModeOn => '常开';

  @override
  String get pandaBreathModeDrying => '干燥';

  @override
  String pandaBreathDryingLeft(int minutes) {
    return '干燥中，剩余 $minutes 分钟';
  }

  @override
  String pandaBreathTarget(int max) {
    return '目标温度 0–$max °C';
  }

  @override
  String get queueSettingsDispatchLabel => '通用任务的打印机';

  @override
  String get queueSettingsDispatchDesc => '分配整个模型队列任务时选择哪台打印机。忙碌或离线的打印机会被跳过。';

  @override
  String get queueSettingsDispatchFewestHours => '打印时长最少';

  @override
  String get queueSettingsDispatchMostHours => '打印时长最多';

  @override
  String get queueSettingsDispatchLeastRecentlyUsed => '空闲最久';

  @override
  String get queueSettingsDispatchPriority => '打印机优先级';

  @override
  String get editPrinterDispatchPriority => '通用任务优先级';

  @override
  String get editPrinterDispatchPriorityHelp =>
      '数字越小越优先，留空排最后。按打印机优先级分配通用任务时生效。';

  @override
  String get editPrinterDispatchPriorityInvalid => '请输入 0 到 100000 之间的整数';

  @override
  String nozzleSheetTitle(int position) {
    return '位置 $position';
  }

  @override
  String get nozzleSectionTitle => '喷嘴';

  @override
  String get nozzleLabelDiameter => '直径';

  @override
  String get nozzleLabelType => '类型';

  @override
  String get nozzleLabelFlow => '流量';

  @override
  String get nozzleLabelStatus => '状态';

  @override
  String get nozzleLabelWear => '磨损';

  @override
  String get nozzleLabelPrintTime => '打印时长';

  @override
  String get nozzleLabelMaxTemp => '最高温度';

  @override
  String get nozzleLabelSerial => '序列号';

  @override
  String get nozzleLabelFilament => '耗材';

  @override
  String get nozzleMaterialStainless => '不锈钢';

  @override
  String get nozzleMaterialHardened => '硬化钢';

  @override
  String get nozzleMaterialTungsten => '碳化钨';

  @override
  String get nozzleStatusDocked => '已归位';

  @override
  String get nozzleStatusMounted => '已装在喷头';

  @override
  String nozzleWearValue(int percent) {
    return '$percent%';
  }

  @override
  String nozzleMaxTempValue(int degrees) {
    return '$degrees °C';
  }

  @override
  String nozzleDiameterValue(String diameter) {
    return '$diameter mm';
  }

  @override
  String get errEdgeAccessRequired => '服务器位于 Cloudflare Access 之后';

  @override
  String get errEdgeAccessRejected => 'Cloudflare Access 未接受已保存的凭据';

  @override
  String get edgeAccessTitle => 'Cloudflare Access';

  @override
  String get edgeAccessSetUp => '设置';

  @override
  String get edgeAccessServiceToken => '服务令牌';

  @override
  String get edgeAccessServiceTokenHint => '可在后台运行，因此提醒和手表照常工作。';

  @override
  String get edgeAccessClientId => '客户端 ID';

  @override
  String get edgeAccessClientSecret => '客户端密钥';

  @override
  String edgeAccessFor(String host) {
    return '用于 $host';
  }

  @override
  String edgeAccessConfigured(String host) {
    return '$host 的服务令牌';
  }

  @override
  String get edgeAccessSave => '保存';

  @override
  String get edgeAccessRemove => '移除';

  @override
  String get edgeAccessRemoveTitle => '移除 Cloudflare Access？';

  @override
  String get edgeAccessRemoveMessage => '重新设置之前，应用无法连接此服务器。';

  @override
  String get edgeAccessRecommended => '推荐';

  @override
  String get edgeAccessBrowser => '浏览器登录';

  @override
  String get edgeAccessBrowserHint => '会过期，需要手动重新登录。';

  @override
  String get edgeAccessSignIn => '登录';

  @override
  String get edgeAccessWarnTitle => '浏览器登录会过期';

  @override
  String get edgeAccessWarnMessage =>
      'Cloudflare 会话结束后，提醒、常驻通知、小组件和手表将停止工作，直到重新登录。服务令牌无需登录。部分提供商（包括 Google）拒绝在内嵌浏览器中登录；此时请改用服务令牌。';

  @override
  String get edgeAccessWarnConfirm => '仍然继续';

  @override
  String get edgeAccessWarnUseToken => '使用服务令牌';

  @override
  String get edgeAccessSignInFailed => '页面未能加载。';

  @override
  String edgeAccessConfiguredBrowser(String host) {
    return '$host 的浏览器登录';
  }

  @override
  String get notifEdgeSessionTitle => 'Cloudflare 会话已过期';

  @override
  String get notifEdgeSessionBody => '提醒已关闭。请重新登录以恢复。';

  @override
  String get notifEvtEdgeSession => 'Cloudflare Access';

  @override
  String get notifEvtEdgeSessionDesc => 'Cloudflare 不再接受应用的登录或服务令牌、提醒停止时';

  @override
  String get edgeSessionBanner => 'Cloudflare 会话已过期';

  @override
  String get notifEdgeTokenTitle => 'Cloudflare 拒绝了服务令牌';

  @override
  String get notifEdgeTokenBody => '提醒已关闭。请更换服务令牌以恢复。';

  @override
  String get edgeTokenBanner => 'Cloudflare 拒绝了服务令牌';

  @override
  String get amsUnloadAll => '全部卸载';

  @override
  String get amsUnloadAllTitle => '卸载所有槽位？';

  @override
  String get amsUnloadAllMessage =>
      '打印机会依次卸载 AMS 3H 中所有已装载的槽位。打印机提示时，请手动将耗材从 AMS 3H 中拉出，因此请留在打印机旁。';

  @override
  String get amsUnloadAllStarted => '正在卸载所有已装载的槽位。打印机提示时，请手动将耗材从 AMS 3H 中拉出。';

  @override
  String get amsUnloadAllNoneLoaded => '没有槽位的耗材在热端中';

  @override
  String queueDuplicateAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已将 $count 份副本添加到队列末尾',
    );
    return '$_temp0';
  }

  @override
  String queueDuplicateSkipped(int count, int skipped) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已添加 $count 份副本',
    );
    String _temp1 = intl.Intl.pluralLogic(
      skipped,
      locale: localeName,
      other: '$skipped 项无法复制',
    );
    return '$_temp0；$_temp1';
  }

  @override
  String get queueDuplicateNone => '这些都无法复制';

  @override
  String get queueDuplicate => '复制';

  @override
  String get maintenanceLog => '维护日志';

  @override
  String maintenanceLogTitle(String printer) {
    return '日志 · $printer';
  }

  @override
  String get maintenanceLogEmpty => '这台打印机尚无维护记录';

  @override
  String maintenanceLogLoadMore(int shown, int total) {
    return '加载更多 · $shown/$total';
  }

  @override
  String maintenanceLogHours(int hours) {
    return '$hours 小时';
  }

  @override
  String get maintenanceLogExportPrinter => '导出 CSV（此打印机）';

  @override
  String get maintenanceLogExportAll => '导出 CSV（所有打印机）';

  @override
  String get maintenanceLogCleanUpPrinter => '清理（此打印机）…';

  @override
  String get maintenanceLogCleanUpAll => '清理（所有打印机）…';

  @override
  String maintenanceLogSaved(String name) {
    return '日志已保存：$name';
  }

  @override
  String get maintenanceLogCleanUpTitle => '删除旧记录？';

  @override
  String maintenanceLogCleanUpMessage(String printer) {
    return '将永久删除 $printer 中早于所选时间的记录。最近一天的记录始终保留，各任务的计数器不会改变。如需备份，请先导出日志。';
  }

  @override
  String get maintenanceLogCleanUpMessageAll =>
      '将永久删除你可见的所有打印机中早于所选时间的记录。最近一天的记录始终保留，各任务的计数器不会改变。如需备份，请先导出日志。';

  @override
  String maintenanceLogAge(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days 天',
    );
    return '$_temp0';
  }

  @override
  String maintenanceLogCleanedUp(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已删除 $count 条记录',
      zero: '没有删除任何记录',
    );
    return '$_temp0';
  }

  @override
  String get maintenanceLogDeleteEntryTitle => '删除这条日志记录？';

  @override
  String maintenanceLogDeleteEntryMessage(String task, String date) {
    return '「$task」（$date）将从日志中永久删除。任务最近一次重置保持不变：删除记录不会撤销它。';
  }

  @override
  String get maintenanceLogEntryDeleted => '记录已删除';

  @override
  String get maintenanceLogDelete => '删除';

  @override
  String get maintenanceLogYear => '1 年';

  @override
  String get spoolScanTitle => '扫描料盘';

  @override
  String get spoolScanModeCamera => '相机';

  @override
  String get spoolScanModeNfc => 'NFC';

  @override
  String get spoolScanNfcHint => '将料盘靠近手机背面';

  @override
  String get spoolScanNfcHelp => '标签在 NFC 天线处读取，通常靠近摄像头。';

  @override
  String get spoolScanNfcOff => 'NFC 已关闭';

  @override
  String get spoolScanNfcOffHelp => '请在系统设置中开启后再扫描标签。';

  @override
  String get spoolScanNfcOpenSettings => '打开设置';

  @override
  String get spoolScanTagUnknown => '没有料盘使用此标签';

  @override
  String spoolScanTagUnknownHelp(String tag) {
    return '标签 $tag 未与耗材中的任何料盘关联。请先在 SpoolBuddy 中关联，然后重试。';
  }

  @override
  String spoolScanOpening(String name) {
    return '正在打开 $name';
  }

  @override
  String get maintenanceLogPrinter => '打印机';

  @override
  String get compactAmsLayoutTitle => '紧凑 AMS 磁贴';

  @override
  String get compactAmsLayoutDesc => '耗材槽以小磁贴显示颜色、材质和槽位编号。任何打印机卡片都可以切换回详细列表。';

  @override
  String get amsViewCompact => '紧凑视图';

  @override
  String get amsViewDetailed => '详细视图';

  @override
  String get externalSpoolShort => '外';
}
