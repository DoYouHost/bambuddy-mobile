import '../../l10n/app_localizations.dart';

/// Remediation actions the printer offers for an HMS fault, as the server
/// reports them in `HMSError.actions`.
///
/// The list is a whitelist of the keys the server actually turns into an MQTT
/// command (`bambu_mqtt.py::execute_hms_action`). Everything else Bambu's
/// catalog can name — `CHECK_ASSISTANT`, `JUMP_TO_LIVEVIEW`, `CANCLE`, … —
/// reaches its `case … pass` branch: the printer's own screen owns those, and a
/// button that publishes nothing is worse than no button. An unknown key the
/// firmware starts sending later lands outside the whitelist too, where the
/// server would answer 400.
const Set<String> hmsEffectiveActions = {
  'RESUME_PRINTING',
  'RESUME_PRINTING_DEFECTS',
  'RESUME_PRINTING_PROBELM_SOLVED', // sic — BambuStudio's own spelling
  'PROBLEM_SOLVED_RESUME',
  'FILAMENT_LOAD_RESUME',
  'PROCEED',
  'STOP_PRINTING',
  'IGNORE_RESUME',
  'IGNORE_NO_REMINDER_NEXT_TIME',
  'DONT_REMIND_NEXT_TIME',
  'NO_REMINDER_NEXT_TIME',
  'FILAMENT_EXTRUDED',
  'RETRY_FILAMENT_EXTRUDED',
  'CONTINUE',
  'RETRY_PROBLEM_SOLVED',
  'DBL_CHECK_DONE',
  'DBL_CHECK_RETRY',
  'DBL_CHECK_RESUME',
  'DBL_CHECK_OK',
  'ABORT',
  'OK_BUTTON',
  'REFRESH_NOZZLE',
  'TURN_OFF_FIRE_ALARM',
  'STOP_DRYING',
  'DISABLE_PURIFICATION',
};

/// Kills a running print, so it never fires on a single tap — the card asks
/// first, and the notification opens the app to ask there.
const String hmsStopAction = 'STOP_PRINTING';

/// Actions that get the print going again, one way or another.
///
/// They are not the same command as the plain `/print/resume` behind the
/// lifecycle button: these carry the fault's code and job id, and the
/// `IGNORE_RESUME` among them tells the firmware to stop re-checking the fault
/// it just resumed past. A plain resume means "I fixed it, check again", which
/// is why a wrong-plate pause used to come straight back (server #1869). Where
/// both would be on screen at once, the fault's own button is the one that
/// works.
const Set<String> hmsResumeActions = {
  'RESUME_PRINTING',
  'RESUME_PRINTING_DEFECTS',
  'RESUME_PRINTING_PROBELM_SOLVED',
  'PROBLEM_SOLVED_RESUME',
  'FILAMENT_LOAD_RESUME',
  'IGNORE_RESUME',
  'DBL_CHECK_RESUME',
  'PROCEED',
};

/// The actions worth drawing for [error] — offered by the firmware, understood
/// by the server, deduplicated, in the order the server sent them.
List<String> hmsRenderableActions(Iterable<String> actions) {
  final seen = <String>{};
  return [
    for (final a in actions)
      if (hmsEffectiveActions.contains(a) && seen.add(a)) a,
  ];
}

/// Button text for an action key. Mirrors bambuddy's own wording so a user who
/// has seen the web UI recognises the button (`frontend/src/i18n/locales`).
String hmsActionLabel(AppLocalizations l10n, String action) => switch (action) {
      'RESUME_PRINTING' => l10n.hmsActionResume,
      'RESUME_PRINTING_DEFECTS' => l10n.hmsActionResumeDefects,
      'RESUME_PRINTING_PROBELM_SOLVED' => l10n.hmsActionResumeSolved,
      'PROBLEM_SOLVED_RESUME' => l10n.hmsActionProblemSolvedResume,
      'FILAMENT_LOAD_RESUME' => l10n.hmsActionFilamentLoadedResume,
      'PROCEED' => l10n.hmsActionProceed,
      'STOP_PRINTING' => l10n.hmsActionStopPrinting,
      'IGNORE_RESUME' => l10n.hmsActionIgnoreResume,
      'IGNORE_NO_REMINDER_NEXT_TIME' => l10n.hmsActionIgnoreNoReminder,
      'DONT_REMIND_NEXT_TIME' => l10n.hmsActionDontRemind,
      'NO_REMINDER_NEXT_TIME' => l10n.hmsActionNoReminder,
      'FILAMENT_EXTRUDED' => l10n.hmsActionFilamentExtruded,
      'RETRY_FILAMENT_EXTRUDED' => l10n.hmsActionRetryFilamentExtruded,
      'CONTINUE' => l10n.hmsActionContinue,
      'RETRY_PROBLEM_SOLVED' => l10n.hmsActionRetrySolved,
      'DBL_CHECK_DONE' => l10n.hmsActionDone,
      'DBL_CHECK_RETRY' => l10n.hmsActionRetry,
      'DBL_CHECK_RESUME' => l10n.hmsActionResumePlain,
      'DBL_CHECK_OK' => l10n.hmsActionConfirm,
      'ABORT' => l10n.hmsActionAbort,
      'OK_BUTTON' => l10n.hmsActionOk,
      'REFRESH_NOZZLE' => l10n.hmsActionRecheck,
      'TURN_OFF_FIRE_ALARM' => l10n.hmsActionTurnOffFireAlarm,
      'STOP_DRYING' => l10n.hmsActionStopDrying,
      'DISABLE_PURIFICATION' => l10n.hmsActionDisablePurification,
      // Unreachable for a whitelisted key; the raw key beats an empty button.
      _ => action,
    };
