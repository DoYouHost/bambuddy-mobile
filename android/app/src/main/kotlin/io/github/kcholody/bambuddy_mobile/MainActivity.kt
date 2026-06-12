package io.github.kcholody.bambuddy_mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Most do natywnego stanu optymalizacji baterii. Strona Dart pyta, czy apka
 * jest zwolniona, i (na życzenie użytkownika) wystrzeliwuje systemowy ekran
 * prośby — to właśnie zwolnienie z optymalizacji baterii odblokowuje na
 * Androidzie 12+ start foreground service z tła i ratuje proces przed OEM-owym
 * zabójcą (na Samsungu krytyczne).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "io.github.kcholody.bambuddy/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        // Bezpośrednia prośba o zwolnienie konkretnej apki (dialog systemowy).
        // Gdyby producent ją zablokował/ukrył — fallback na ogólną listę.
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        try {
            startActivity(direct)
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                // Brak ekranu na tym urządzeniu — nic więcej nie zrobimy.
            }
        }
    }
}
