# Konfiguracja środowiska deweloperskiego Flutter na Fedorze

Odpowiada milestone'owi **M0** z planu implementacji. Kolejność jest istotna — `flutter doctor` prowadzi przez braki.

## 1. Flutter SDK

Metoda oficjalnego tarballa — **nie** snap (nienaturalny na Fedorze) i **nie** pakiety dystrybucyjne (zalegają za stable):

```bash
mkdir -p ~/dev
cd ~/dev
# pobierz najnowszy stable z https://docs.flutter.dev/get-started/install/linux/android
tar xf ~/Pobrane/flutter_linux_*-stable.tar.xz -C ~/dev/
echo 'export PATH="$HOME/dev/flutter/bin:$PATH"' >> ~/.zshrc
exec zsh
flutter doctor
```

Zależności systemowe, których `flutter doctor` zwykle chce na świeżej Fedorze:

```bash
sudo dnf install git curl unzip xz zip mesa-libGLU clang cmake ninja-build gtk3-devel
```

## 2. Android toolchain

- **Android Studio z tarballa od Google lub przez JetBrains Toolbox — NIE Flatpak.** Sandbox Flatpaka powoduje problemy ze ścieżkami SDK i adb w połączeniu z Flutterem.
- Uruchom Android Studio raz i przez SDK Manager zainstaluj: Android SDK, SDK Command-line Tools, Platform-Tools, Build-Tools, platformę API 35.
- Java: Android Studio ma własny JBR; jeśli `flutter doctor` narzeka na JDK: `flutter config --jdk-dir <ścieżka-do-jbr-android-studio>`.
- Licencje: `flutter doctor --android-licenses` (zaakceptować wszystkie).

## 3. Edytor

**VS Code + rozszerzenia Dart i Flutter** do codziennej pracy (lżejszy). Android Studio zostaje zainstalowane wyłącznie jako menedżer SDK i emulatorów (AVD Manager).

## 4. Fizyczny telefon — urządzenie główne

To podstawowe urządzenie testowe, bo: kamera/WS/powiadomienia zachowują się realistycznie, a telefon jest w tym samym LAN-ie co serwer bambuddy — zero gimnastyki sieciowej. Od M6 to też jedyny uczciwy sposób testowania pusha.

```bash
sudo dnf install android-tools   # adb + reguły udev (Fedora dostarcza je w pakiecie)
```

Na telefonie: Ustawienia → Informacje → 7× tap w „Numer kompilacji" → Opcje programistyczne → **Debugowanie USB**. Potem `adb devices` i akceptacja odcisku na ekranie. Jeśli urządzenie ma status `unauthorized`/niewidoczne — sprawdzić reguły udev lub doinstalować `android-udev-rules`.

**Wireless adb (wygoda)**: Android 11+ → Opcje programistyczne → Debugowanie bezprzewodowe → `adb pair <ip:port>` — hot reload bez kabla.

## 5. Emulator — drugorzędny

- Wymaga KVM: `ls -l /dev/kvm`; jeśli brak dostępu — `sudo usermod -aG kvm $USER` i relogin.
- AVD tworzony w Android Studio (Device Manager).
- Sieć z emulatora: serwer bambuddy pod IP LAN działa bezpośrednio; serwer odpalony na maszynie deweloperskiej jest widoczny jako `10.0.2.2`.

## 6. Weryfikacja końcowa M0

```bash
flutter doctor -v        # wszystko zielone (ew. ostrzeżenie o Chrome — ignorować, web nie jest celem)
flutter create hello_test
cd hello_test
flutter run              # na podłączonym telefonie; sprawdzić hot reload (klawisz r)
```

Po sukcesie: utworzenie właściwego projektu aplikacji, LICENSE (AGPL-3.0), `flutter_lints` w `analysis_options.yaml`, GitHub Actions z `flutter analyze && flutter test`.
