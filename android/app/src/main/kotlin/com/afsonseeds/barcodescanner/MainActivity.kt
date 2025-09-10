package com.afsonseeds.barcodescanner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private lateinit var nfcHandler: NfcHandler

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.afsonseeds.barcodescanner/nfc")
        nfcHandler = NfcHandler(this, channel)
        channel.setMethodCallHandler { call, result ->
            nfcHandler.handle(call, result)
        }
    }
}
