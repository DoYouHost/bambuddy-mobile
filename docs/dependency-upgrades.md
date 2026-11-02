# Dependency upgrades that need more than a version bump

Most of `pubspec.yaml` moves with `flutter pub upgrade --major-versions` and a
green CI run. The entries below do not: each one is held down by something a
bump alone does not solve. This file says what, and what unblocks it.

## flutter_secure_storage 11 — pending, and it must not be rushed

**State:** the app is on **10.3.4** (since 2026-09-17), one major behind.

**Why not 11 yet.** Version 11 drops the ciphers that version 9 wrote with. An
install that goes from a build on 9 straight to a build on 11 cannot read its
own saved credentials — no migration runs, the entries are simply unreadable.
Version 10 is the bridge: it re-encrypts v9 entries on the first read
([lib/core/auth/credentials_store.dart](../lib/core/auth/credentials_store.dart)
configures that migration with `resetOnError: false` and
`migrateWithBackup: true`).

**So 11 may only ship in a release that follows one which ran 10 long enough to
migrate the installed base.** The release that first carried 10 is the one on
Play as of 2026-09-17; the longer it sits there before 11 goes out, the fewer
users skip the bridge. Whoever takes the jump decides how long is long enough —
it is a judgement about the update habits of the installed base, not a number
this file can fix.

Users who skip the bridge anyway are not silently broken: the dashboard raises
the `SignInReason.credentialsMissing` dialog and sends them to sign in again.
That is a lost session, not lost data, and it is the failure mode to weigh when
picking the moment.

**What else is waiting on it — the win32 knot.** secure_storage 10 still pins
`win32 ^5`; only 11 moves to `^6`. `share_plus` 13, `package_info_plus` >=10.1
and `device_info_plus` 13 all want `win32 ^6`, so pub resolves none of them
while secure_storage sits at 10. They move as one block, after 11. (Windows is
not a target of this app — the constraint still binds, because pub resolves the
whole dependency graph regardless of platform.)

## file_picker stops at 10

11 replaced `FilePicker.platform.x()` with static methods and 13 dropped
`withData`. Both are call-site rewrites, in
[lib/features/common/device_files.dart](../lib/features/common/device_files.dart) and in
`app_report_ui` over in app-shared — so the bump is two repos, not one.

## Built-in Kotlin waits on five plugins

Every build warns that plugins "apply Kotlin Gradle Plugin (KGP)" and that a
future Flutter will refuse them. The app itself is already migrated (no
`kotlin-android`, a `kotlin { compilerOptions }` block); what is left is
`android.builtInKotlin=false` in `android/gradle.properties`. Most plugins on the
list — patrol, home_widget, mobile_scanner, flutter_file_dialog — apply KGP only
*because* that flag is false, and stop on their own once it is true.

Flipping it today fails the build: AGP 9 refuses `kotlin-android` outright, and
five plugins still apply it unconditionally. `device_info_plus`,
`package_info_plus` and `share_plus` are migrated in their latest majors, which
wait on the win32 knot above; `file_picker` is migrated in 13, which waits on
its own rewrite below; `nsd_android` 2.2.0 is not migrated at all
(sebastianhaberey/nsd#88). Once all five move, set the flag to true.

## flutter_riverpod stays at 2

Riverpod 3 is a migration across every screen. It is a project, not a bump.
