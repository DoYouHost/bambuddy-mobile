import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/common/dash_async.dart';
import 'package:bambuddy_mobile/features/common/photo_pager.dart';
import 'package:bambuddy_mobile/features/common/print_run_labels.dart';
import 'package:bambuddy_mobile/features/common/print_thumbnail.dart';
import 'package:bambuddy_mobile/features/common/qr_scanner_screen.dart';
import 'package:bambuddy_mobile/features/common/spool_colour_wheel.dart';
import 'package:bambuddy_mobile/features/common/web_link.dart';
import 'package:bambuddy_mobile/features/projects/project_common.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for what many screens share
/// (`lib/features/common/` and the `dash_kit` widgets the app builds on), each
/// in a minimal host with realistic content: every field and select (closed,
/// open, with an error, disabled, filterable), the selection controls, cards,
/// notes, pills and buttons, the async and empty states, thumbnails and
/// the photo viewer, the colour wheel dialog, the sheets (`dashSheet`, the
/// draggable and fitted surfaces), every dialog (confirmation plain and
/// stacked, name prompt, date and time pickers) and the snack bars. The QR
/// scanner is hosted on a camera plugin that answers "refused" or "cannot
/// start", so only its two error views are measured. Not covered: the live
/// camera preview with its viewfinder (a texture a host test cannot get) and
/// the system file pickers behind `device_files.dart` and `file_export.dart`.
void main() {
  group('fields and selects', () {
    a11ySurface(
      'common, text fields and pickers',
      demo: false,
      home: () => const _Shelf(_FieldsShelf()),
      shows: find.text(pl.projectName),
    );

    a11ySurface(
      'common, select open',
      demo: false,
      home: () => const _Shelf(_FieldsShelf()),
      arrange: (tester) async {
        await tester.tap(byLogId('common.select'));
      },
      shows: byLogId('common.select.option'),
    );

    a11ySurface(
      'common, any-or-one select open',
      demo: false,
      home: () => const _Shelf(_FieldsShelf()),
      arrange: (tester) async {
        await tester.tap(byLogId('common.any_or_one'));
      },
      shows: byLogId('common.any_or_one.any'),
    );

    a11ySurface(
      'common, filterable select open',
      demo: false,
      home: () => const _Shelf(_FieldsShelf()),
      arrange: (tester) async {
        await tester.tap(byLogId('common.filterable'));
      },
      shows: byLogId('common.filterable.option'),
    );

    a11ySurface(
      'common, failure cause select open',
      demo: false,
      home: () => const _Shelf(_FieldsShelf()),
      arrange: (tester) async {
        await tester.tap(byLogId('common.failure_cause'));
      },
      shows: byLogId('common.failure_cause.legacy'),
    );

    a11ySurface(
      'common, search field with text',
      demo: false,
      home: () => const _Shelf(_FieldsShelf()),
      arrange: (tester) async {
        await tester.enterText(
          find.descendant(
            of: byLogId('common.search'),
            matching: find.byType(TextField),
          ),
          'gridfinity',
        );
      },
      shows: byLogId('common.search.clear'),
    );
  });

  group('controls and content', () {
    a11ySurface(
      'common, selection controls',
      demo: false,
      home: () => const _Shelf(_ControlsShelf()),
      shows: byLogId('common.seg_toggle'),
    );

    a11ySurface(
      'common, cards, notes and pills',
      demo: false,
      home: () => const _Shelf(_CardsShelf()),
      shows: find.text(pl.projectNotes),
    );

    a11ySurface(
      'common, buttons',
      demo: false,
      home: () => const _Shelf(_ButtonsShelf()),
      shows: byLogId('common.filled'),
    );

    a11ySurface(
      'common, app bar with save action',
      demo: false,
      home: () => const _SaveBar(busy: false),
      shows: byLogId('common.save'),
    );

    a11ySurface(
      'common, app bar with save action in flight',
      demo: false,
      home: () => const _SaveBar(busy: true),
      shows: byLogId('common.save'),
    );
  });

  group('async and empty states', () {
    a11ySurface(
      'common, load failed, server unreachable',
      demo: false,
      home: () => const _AsyncPage(
        AsyncValue<int>.error(
          ApiException(AppErrorCode.serverUnreachable),
          StackTrace.empty,
        ),
      ),
      shows: byLogId('error.retry'),
    );

    a11ySurface(
      'common, load failed, tonal retry',
      demo: false,
      home: () => const _AsyncPage(
        AsyncValue<int>.error(
          ApiException(AppErrorCode.serverUnreachable),
          StackTrace.empty,
        ),
        tonal: true,
      ),
      shows: byLogId('error.retry'),
    );

    a11ySurface(
      'common, loading',
      demo: false,
      home: () => const _AsyncPage(AsyncValue<int>.loading()),
      shows: find.byType(DashLoading),
    );

    a11ySurface(
      'common, empty list',
      demo: false,
      home: () => const _EmptyPage(),
      shows: find.text(pl.projectsEmpty),
    );

    a11ySurface(
      'common, sections: failed, waiting and busy',
      demo: false,
      home: () => const _Shelf(_StripsShelf()),
      shows: find.byType(BusyLine),
    );
  });

  group('pictures', () {
    a11ySurface(
      'common, thumbnails',
      home: () => const _Shelf(_ThumbnailsShelf()),
      shows: find.byType(PrintThumbnail),
    );

    a11ySurface(
      'common, photo viewer',
      home: () => const _PhotoViewer([
        '/api/v1/archives/1/thumbnail',
        '/api/v1/archives/2/thumbnail',
        '/api/v1/archives/3/thumbnail',
      ]),
      shows: find.text('1 / 3'),
    );

    a11ySurface(
      'common, photo viewer, picture missing',
      home: () => const _PhotoViewer(['/api/v1/archives/9999/photos/gone.jpg']),
      shows: find.text(pl.archivePhotoFailed),
    );
  });

  group('sheets and dialogs', () {
    a11ySurface(
      'common, sheet',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('sheet'));
      },
      shows: find.text(pl.projectLinkFolder),
    );

    a11ySurface(
      'common, surface sheet',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('surface sheet'));
      },
      shows: byLogId('common.sheet_save'),
    );

    a11ySurface(
      'common, fitted surface sheet',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('fitted sheet'));
      },
      shows: byLogId('common.fitted_save'),
    );

    a11ySurface(
      'common, confirmation',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('confirm'));
      },
      shows: byLogId('common.confirm.confirm'),
    );

    a11ySurface(
      'common, confirmation with stacked answers',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('confirm stacked'));
      },
      shows: byLogId('common.stacked.confirm'),
    );

    a11ySurface(
      'common, name prompt',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('prompt'));
      },
      shows: byLogId('common.prompt.field'),
    );

    a11ySurface(
      'common, date picker',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('date'));
      },
      shows: find.byType(DatePickerDialog),
    );

    a11ySurface(
      'common, time picker',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('date and time'));
        await a11ySettle(tester, const Duration(milliseconds: 500));
        // Past the date step: its confirm button is Material's own "OK".
        final ok = MaterialLocalizations.of(
          tester.element(find.byType(DatePickerDialog)),
        ).okButtonLabel;
        await tester.tap(find.text(ok));
      },
      shows: find.byType(TimePickerDialog),
    );

    a11ySurface(
      'common, colour wheel dialog',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('colour wheel'));
      },
      shows: find.byType(SpoolColourWheel),
    );

    a11ySurface(
      'common, snack bar',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('snack'));
      },
      shows: find.text(pl.linkOpenFailed),
    );

    a11ySurface(
      'common, snack bar with an action',
      demo: false,
      home: () => const _Launcher(),
      arrange: (tester) async {
        await tester.tap(find.text('snack with action'));
      },
      shows: find.text(pl.mwViewInFiles),
    );
  });

  group('QR scanner', () {
    // The scanner talks to the camera plugin over this channel. Answering it
    // here is what lets the surface be reached at all: the plugin's own error
    // views are what the screen shows when the camera cannot start.
    const scanner = MethodChannel(
      'dev.steenbakker.mobile_scanner/scanner/method',
    );

    // Its two event channels only need to accept `listen` and `cancel`.
    const eventChannels = [
      MethodChannel('dev.steenbakker.mobile_scanner/scanner/event'),
      MethodChannel('dev.steenbakker.mobile_scanner/scanner/deviceOrientation'),
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void answerScanner(Future<Object?> Function(MethodCall call) handler) {
      messenger.setMockMethodCallHandler(scanner, handler);
      for (final channel in eventChannels) {
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
    }

    tearDown(() {
      for (final channel in [scanner, ...eventChannels]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });

    Widget scannerScreen() => QrScannerScreen<String>(
      title: pl.scanApiKeyTitle,
      hint: pl.scanApiKeyHint,
      extract: (raw) => raw,
    );

    group('permission refused', () {
      setUp(
        () => answerScanner(
          // `state` is the authorization query (2 = denied), `request` asks.
          (call) async => call.method == 'state' ? 2 : false,
        ),
      );

      a11ySurface(
        'common, QR scanner, camera permission refused',
        demo: false,
        home: scannerScreen,
        shows: find.text(pl.cameraPermissionTitle),
      );
    });

    group('camera cannot start', () {
      setUp(
        () => answerScanner((call) async {
          if (call.method == 'state') return 1;
          if (call.method == 'start') {
            throw PlatformException(code: 'CAMERA_BROKEN', message: 'busy');
          }
          return null;
        }),
      );

      a11ySurface(
        'common, QR scanner, camera failed to start',
        demo: false,
        home: scannerScreen,
        shows: find.text(pl.scanApiKeyTitle),
      );
    });
  });
}

/// The screen ground every real screen sits on, with [child] as its list.
class _Shelf extends StatelessWidget {
  const _Shelf(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => DashBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: dashAppBar(context, title: pl.projectsTitle),
      body: ListView(padding: screenListPadding(context), children: [child]),
    ),
  );
}

class _FieldsShelf extends StatelessWidget {
  const _FieldsShelf();

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    const gap = SizedBox(height: DashSpace.md);
    final statuses = [
      for (final s in projectStatusValues)
        DropdownMenuEntry(value: s, label: s),
    ];
    DropdownMenuEntry<String> row(String id, String label) => DropdownMenuEntry(
      value: label,
      label: label,
      labelWidget: logTag('$id.option', Text(label)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: 'Workshop organizers',
          style: t.bodyStrong,
          decoration: dashDecoration(t, labelText: pl.projectName),
        ).tagged('common.text'),
        gap,
        TextFormField(
          style: t.bodyStrong,
          decoration: dashDecoration(
            t,
            labelText: pl.projectDescription,
            helperText: pl.projectTargetSetsHint,
          ),
        ).tagged('common.text_helper'),
        gap,
        TextFormField(
          initialValue: '12x',
          style: t.bodyStrong,
          decoration: dashDecoration(
            t,
            labelText: pl.projectBudget,
            errorText: pl.financeAmountInvalid,
          ),
        ).tagged('common.text_error'),
        gap,
        dashCombo<String>(
          context,
          id: 'common.select',
          label: Text(pl.projectStatus),
          initialSelection: 'active',
          entries: [
            for (final s in statuses)
              row('common.select', projectStatusLabel(pl, s.value)),
          ],
        ),
        gap,
        dashCombo<String>(
          context,
          id: 'common.select_error',
          label: Text(pl.projectPriority),
          errorText: pl.financeUserRequired,
          entries: [row('common.select_error', pl.projectPriorityHigh)],
        ),
        gap,
        dashCombo<String>(
          context,
          id: 'common.select_disabled',
          label: Text(pl.projectParent),
          enabled: false,
          initialSelection: pl.projectParentNone,
          entries: [row('common.select_disabled', pl.projectParentNone)],
        ),
        gap,
        dashCombo<String>(
          context,
          id: 'common.filterable',
          label: Text(pl.financeUser),
          filterable: true,
          entries: [
            for (final name in ['anna', 'leo', 'demo'])
              row('common.filterable', name),
          ],
        ),
        gap,
        dashAnyOrOne<int>(
          context,
          id: 'common.any_or_one',
          label: Text(pl.financeCostCenter),
          anyLabel: pl.financeAllCostCenters,
          selected: 2,
          options: const [(1, 'Workshop'), (2, 'Maker club')],
          onPick: (_) {},
        ),
        gap,
        dashCombo<String>(
          context,
          id: 'common.failure_cause',
          label: Text(pl.printLogStatusFailed),
          initialSelection: 'Bed peeled off',
          entries: failureReasonEntries(
            pl,
            none: pl.failureReasonUnknown,
            carries: 'Bed peeled off',
            ids: (
              none: 'common.failure_cause.none',
              option: 'common.failure_cause.option',
              legacy: 'common.failure_cause.legacy',
            ),
          ),
        ),
        gap,
        dashPickerField(
          context,
          id: 'common.picker_value',
          label: pl.projectParent,
          placeholder: pl.projectParentNone,
          value: 'Garage',
          prefixIcon: Icons.folder_outlined,
          onTap: () {},
        ),
        dashPickerField(
          context,
          id: 'common.picker_empty',
          label: pl.projectParent,
          placeholder: pl.projectParentNone,
          onTap: () {},
        ),
        dashPickerField(
          context,
          id: 'common.picker_clear',
          label: pl.projectParent,
          placeholder: pl.projectParentNone,
          value: 'Drawer bins',
          helperText: pl.projectTargetSetsHint,
          clear: (
            id: 'common.picker_clear.clear',
            tooltip: pl.projectDueDateClear,
            onPressed: () {},
          ),
          onTap: () {},
        ),
        gap,
        DashSearchField(
          id: 'common.search',
          hintText: pl.mfSearchPlaceholder,
          onChanged: (_) {},
          trailing: [
            FilterButton(
              count: 2,
              tooltip: pl.projectStatus,
              id: 'common.search_filter',
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _ControlsShelf extends StatefulWidget {
  const _ControlsShelf();

  @override
  State<_ControlsShelf> createState() => _ControlsShelfState();
}

class _ControlsShelfState extends State<_ControlsShelf> {
  var _mode = 'week';
  var _count = 3;
  var _on = true;
  var _level = 40;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: DashSpace.lg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterGroupLabel(label: pl.projectStatus),
        DashSegToggle<String>(
          id: 'common.seg_toggle',
          selected: _mode,
          segments: [
            (value: 'week', label: pl.statsRangeLast7Days, icon: null),
            (value: 'month', label: pl.statsRangeLast30Days, icon: null),
            (value: 'year', label: pl.statsRangeThisYear, icon: Icons.event),
          ],
          onChanged: (v) => setState(() => _mode = v),
        ),
        gap,
        Row(
          children: [
            DashStepper(
              value: _count,
              min: 1,
              max: 9,
              onChanged: (v) => setState(() => _count = v),
              lessTooltip: pl.cancel,
              moreTooltip: pl.projectCreate,
              lessId: 'common.step_less',
              moreId: 'common.step_more',
            ),
            const Spacer(),
            DashStepper(
              value: 1,
              min: 1,
              max: 9,
              compact: true,
              onChanged: (_) {},
              lessTooltip: pl.cancel,
              moreTooltip: pl.projectCreate,
              lessId: 'common.step_less_compact',
              moreId: 'common.step_more_compact',
            ),
            const Spacer(),
            DashStepper(
              value: 9,
              min: 1,
              max: 9,
              onChanged: null,
              lessTooltip: pl.cancel,
              moreTooltip: pl.projectCreate,
              lessId: 'common.step_less_off',
              moreId: 'common.step_more_off',
            ),
          ],
        ),
        gap,
        Row(
          children: [
            FilterButton(
              count: 0,
              tooltip: pl.projectStatus,
              id: 'common.filter_idle',
              onTap: () {},
            ),
            const SizedBox(width: DashSpace.lg),
            FilterButton(
              count: 3,
              tooltip: pl.projectStatus,
              id: 'common.filter_active',
              onTap: () {},
            ),
          ],
        ),
        gap,
        SettingsCard(
          rows: [
            SettingsSwitchRow(
              tag: 'common.switch_on',
              title: pl.projectNotes,
              subtitle: pl.projectTargetSetsHint,
              value: _on,
              onChanged: (v) => setState(() => _on = v),
            ),
            SettingsSwitchRow(
              tag: 'common.switch_off',
              title: pl.projectTags,
              subtitle: pl.projectTargetSetsHint,
              value: false,
              onChanged: (_) {},
            ),
            SettingsSwitchRow(
              tag: 'common.switch_disabled',
              title: pl.projectUrl,
              subtitle: pl.projectTargetSetsHint,
              value: true,
              onChanged: null,
            ),
            SettingsSlider(
              tag: 'common.slider',
              label: pl.projectBudget,
              subtitle: pl.projectTargetSetsHint,
              bubble: '$_level %',
              value: _level,
              min: 0,
              max: 100,
              step: 5,
              enabled: true,
              onChanged: (v) => setState(() => _level = v),
            ),
            SettingsSlider(
              tag: 'common.slider_off',
              label: pl.projectBudget,
              value: 20,
              min: 0,
              max: 100,
              enabled: false,
              onChanged: (_) {},
            ),
          ],
        ),
      ],
    );
  }
}

class _CardsShelf extends StatelessWidget {
  const _CardsShelf();

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    const gap = SizedBox(height: DashSpace.lg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(pl.projectNotes),
        SectionHeading(pl.projectNotes, style: t.titleMd),
        gap,
        SettingsEntryTile(
          id: 'common.entry',
          icon: Icons.folder_open_outlined,
          title: pl.projectTabFiles,
          subtitle: pl.projectFilesEmpty,
          onTap: () {},
        ),
        TappableCard(
          id: 'common.card',
          onTap: () {},
          child: Row(
            children: [
              const DashIconTile(
                icon: Icons.bolt_outlined,
                size: 40,
                radius: 12,
              ),
              const SizedBox(width: DashSpace.md),
              Expanded(child: Text(pl.projectStatEnergy, style: t.body)),
            ],
          ),
        ),
        TappableCard(
          id: 'common.card_off',
          onTap: null,
          child: Text(pl.projectNotesEmpty, style: t.bodySoft),
        ),
        gap,
        InlineNote(pl.projectTargetSetsHint),
        InlineNote(pl.financeNoEligibleUsers, urgent: true),
        InlineNote(
          pl.financeUserRequired,
          icon: Icons.info_outline,
          announce: true,
        ),
        gap,
        Wrap(
          spacing: DashSpace.sm,
          runSpacing: DashSpace.sm,
          children: [
            DashPill(
              label: pl.projectStatusActive,
              accent: t.accentGreen,
              accentInk: t.accentGreenInk,
              leadingDot: true,
            ),
            DashPill(
              label: pl.projectStatusOnHold,
              accent: t.accentOrange,
              accentInk: t.accentOrangeInk,
              icon: Icons.pause_circle_outline,
            ),
            DashPill(
              label: pl.projectStatusArchived,
              accent: t.textTertiary,
              dense: true,
            ),
            DashPill(
              label: pl.printLogStatusFailed,
              accent: t.danger,
              accentInk: t.dangerInk,
            ),
          ],
        ),
        gap,
        const DashProgressBar(value: 0.64, height: 8),
        const SizedBox(height: DashSpace.sm),
        DashProgressBar(value: 1, height: 6, color: t.dangerInk),
        const SizedBox(height: DashSpace.sm),
        const DashProgressBar(value: null, height: 6),
      ],
    );
  }
}

class _ButtonsShelf extends StatelessWidget {
  const _ButtonsShelf();

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: DashSpace.md,
      children: [
        FilledButton(
          onPressed: () {},
          child: Text(pl.projectSave),
        ).tagged('common.filled'),
        FilledButton.icon(
          style: dashPrimaryButtonStyle(t),
          onPressed: () {},
          icon: const Icon(Icons.arrow_forward),
          label: Text(pl.mwResolve),
        ).tagged('common.primary'),
        FilledButton.tonal(
          onPressed: () {},
          child: Text(pl.mfImport),
        ).tagged('common.tonal'),
        FilledButton(
          style: dashNeutralButtonStyle(t),
          onPressed: () {},
          child: Text(pl.cancel),
        ).tagged('common.neutral'),
        FilledButton(
          style: dashDangerButtonStyle(t),
          onPressed: () {},
          child: Text(pl.projectDelete),
        ).tagged('common.danger'),
        OutlinedButton(
          onPressed: () {},
          child: Text(pl.mfTest),
        ).tagged('common.outlined'),
        TextButton(
          onPressed: () {},
          child: Text(pl.retry),
        ).tagged('common.text_button'),
        FilledButton(
          onPressed: null,
          child: Text(pl.projectSave),
        ).tagged('common.filled_disabled'),
        FilledButton.icon(
          onPressed: null,
          icon: DashSpinner(size: 16, color: t.onAccent),
          label: Text(pl.mfImporting),
        ).tagged('common.filled_busy'),
        ButtonPair(
          primaryLabel: pl.mfImportModels,
          secondaryLabel: pl.mfClearSelection,
          primary: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download),
            label: Text(pl.mfImportModels),
          ).tagged('common.pair_primary'),
          secondary: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.clear),
            label: Text(pl.mfClearSelection),
          ).tagged('common.pair_secondary'),
        ),
        ButtonPair(
          primaryLabel: pl.financeRebuildLedgerRun,
          secondaryLabel: pl.mfDisconnectTitle,
          primary: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.build_outlined),
            label: Text(pl.financeRebuildLedgerRun),
          ).tagged('common.pair_long_primary'),
          secondary: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.link_off),
            label: Text(
              '${pl.mfDisconnectTitle} ${pl.financeRebuildLedgerConfirm}',
            ),
          ).tagged('common.pair_long_secondary'),
        ),
      ],
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context) => DashBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: dashAppBar(
        context,
        title: pl.projectCreate,
        actions: [
          dashSaveAction(
            id: 'common.save',
            label: pl.projectSave,
            busy: busy,
            onPressed: () {},
          ),
        ],
      ),
      body: const SizedBox.expand(),
    ),
  );
}

/// [value] through `dashAsync`, as every list screen words its three states.
class _AsyncPage extends StatelessWidget {
  const _AsyncPage(this.value, {this.tonal = false});

  final AsyncValue<int> value;
  final bool tonal;

  @override
  Widget build(BuildContext context) => DashBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: dashAppBar(context, title: pl.statsTitle),
      body: dashAsync(
        context,
        value,
        onRetry: () {},
        tonalRetry: tonal,
        data: (_) => const SizedBox.shrink(),
      ),
    ),
  );
}

class _EmptyPage extends StatelessWidget {
  const _EmptyPage();

  @override
  Widget build(BuildContext context) => DashBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: dashAppBar(context, title: pl.projectsTitle),
      body: EmptyStateView(
        message: pl.projectsEmpty,
        icon: Icons.folder_special_outlined,
      ),
    ),
  );
}

/// The section-sized states of `dashAsyncStrip`, and the one-line busy note.
class _StripsShelf extends StatelessWidget {
  const _StripsShelf();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      dashAsyncStrip<int>(
        context,
        const AsyncValue.error(
          ApiException(AppErrorCode.malformedResponse),
          StackTrace.empty,
        ),
        data: (_) => const SizedBox.shrink(),
      ),
      dashAsyncStrip<int>(
        context,
        const AsyncValue.error('refused', StackTrace.empty),
        failureMessage: pl.financeLoadFailed,
        height: 80,
        data: (_) => const SizedBox.shrink(),
      ),
      dashAsyncStrip<int>(
        context,
        const AsyncValue.loading(),
        height: 80,
        data: (_) => const SizedBox.shrink(),
      ),
      const SizedBox(height: DashSpace.lg),
      BusyLine(pl.mfImportProgress(3, 9)),
      const SizedBox(height: DashSpace.lg),
      EmptyStateView(
        message: pl.projectNotesEmpty,
        icon: Icons.notes_outlined,
        scrollable: false,
      ),
    ],
  );
}

/// Thumbnails in the sizes lists use: a demo render, one the server cannot
/// serve, none at all, and the bare placeholder.
class _ThumbnailsShelf extends StatelessWidget {
  const _ThumbnailsShelf();

  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: DashSpace.md,
    runSpacing: DashSpace.md,
    children: [
      PrintThumbnail(archiveId: 1),
      PrintThumbnail(archiveId: 2, size: 72),
      PrintThumbnail(archiveId: 9999),
      PrintThumbnail(archiveId: null),
      PrintThumbnail.path(path: '/api/v1/archives/3/thumbnail', size: 48),
      ThumbnailPlaceholder(size: 56, icon: Icons.image_outlined),
      ThumbnailPlaceholder(size: 96, icon: Icons.broken_image_outlined),
    ],
  );
}

/// The full-screen photo viewer as the archive and file screens host it.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer(this.paths);

  final List<String> paths;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: photoViewerAppBar(pl.archivePhotosTitle),
    body: PhotoPager(paths: paths),
  );
}

/// Opens each shared sheet, dialog and snack bar by its label, filled the way
/// the app fills them.
class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) {
    Widget open(String label, VoidCallback onTap) =>
        TextButton(onPressed: onTap, child: Text(label));
    return Scaffold(
      body: ListView(
        children: [
          open(
            'sheet',
            () => dashSheet<void>(
              context,
              builder: (sheet) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(DashSpace.lg),
                    child: Text(
                      pl.projectLinkFolder,
                      style: Theme.of(sheet).textTheme.titleMedium,
                    ),
                  ),
                  for (final name in ['Gridfinity', 'Rails', 'Lids'])
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(name),
                      subtitle: Text(pl.projectFolderFileCount(4)),
                      onTap: () => Navigator.pop(sheet),
                    ).tagged('common.sheet_option'),
                ],
              ),
            ),
          ),
          open(
            'surface sheet',
            () => dashSurfaceSheet<void>(
              context,
              builder: (_) => DraggableSheetSurface(
                builder: (sheet, controller) => ListView(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(
                    horizontal: DashSpace.gutter,
                  ),
                  children: [
                    Text(
                      pl.financeCreateCostCenter,
                      style: DashTokens.of(sheet).display,
                    ),
                    const SizedBox(height: DashSpace.md),
                    TextFormField(
                      style: DashTokens.of(sheet).body,
                      decoration: dashDecoration(
                        DashTokens.of(sheet),
                        labelText: pl.financeCostCenterName,
                      ),
                    ).tagged('common.sheet_name'),
                    const SizedBox(height: DashSpace.xl),
                    FilledButton(
                      onPressed: () {},
                      child: Text(pl.financeSave),
                    ).tagged('common.sheet_save'),
                  ],
                ),
              ),
            ),
          ),
          open(
            'fitted sheet',
            () => dashSurfaceSheet<void>(
              context,
              builder: (_) => FittedSheetSurface(
                child: Padding(
                  padding: const EdgeInsets.all(DashSpace.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        pl.financeRebuildLedger,
                        style: DashTokens.of(context).titleMd,
                      ),
                      const SizedBox(height: DashSpace.sm),
                      Text(pl.financeRebuildLedgerConfirm),
                      const SizedBox(height: DashSpace.lg),
                      FilledButton(
                        onPressed: () {},
                        child: Text(pl.financeRebuildLedgerRun),
                      ).tagged('common.fitted_save'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          open(
            'confirm',
            () => confirmDialog(
              context,
              id: 'common.confirm',
              title: pl.financeRebuildLedger,
              message: pl.financeRebuildLedgerConfirm,
              confirmLabel: pl.financeRebuildLedgerRun,
              icon: Icons.build_outlined,
            ),
          ),
          open(
            'confirm stacked',
            () => confirmDialog(
              context,
              id: 'common.stacked',
              title: pl.projectDeleteTitle,
              message: pl.projectDeleteBody('Workshop organizers'),
              confirmLabel: '${pl.projectDelete} ${pl.projectDeleteTitle}',
              cancelLabel: '${pl.cancel} ${pl.projectDeleteTitle}',
              destructive: true,
            ),
          ),
          open(
            'prompt',
            () => promptName(
              context,
              id: 'common.prompt',
              title: pl.projectCreate,
              label: pl.projectName,
              initial: 'Workshop organizers',
            ),
          ),
          open(
            'date',
            () => pickDate(
              context,
              initial: DateTime(2030, 3, 14),
              firstDate: DateTime(2030),
              lastDate: DateTime(2031),
            ),
          ),
          open(
            'date and time',
            () => pickDateTime(
              context,
              initial: DateTime(2030, 3, 14, 6, 30),
              firstDate: DateTime(2030),
            ),
          ),
          open(
            'colour wheel',
            () => showDialog<void>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: Text(pl.inventoryColorPickTitle),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: DashSpace.lg,
                ),
                content: SingleChildScrollView(
                  child: SpoolColourWheel(
                    color: const Color(0xFF2E7D32),
                    onChanged: (_) {},
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: Text(pl.cancel),
                  ).tagged('common.wheel_cancel'),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: Text(pl.inventoryColorSelect),
                  ).tagged('common.wheel_confirm'),
                ],
              ),
            ),
          ),
          // A link the app refuses to open says so in a snack bar.
          open('snack', () => openWebLink(context, 'ftp://example.com/model')),
          open(
            'snack with action',
            () => ScaffoldMessenger.of(context).snack(
              pl.mfImported('dragon.3mf'),
              action: SnackBarAction(label: pl.mwViewInFiles, onPressed: () {}),
              persist: false,
              duration: const Duration(seconds: 5),
            ),
          ),
        ],
      ),
    );
  }
}
