// lib/app/screens/full_screen_scanner.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../blocs/settings/settings_bloc.dart';
import '../blocs/scanner/scanner_bloc.dart';

/// Full-screen scanner that respects settings:
/// - settings.beepEnabled
/// - settings.copyToClipboard
/// - settings.isContinuousScanning
/// - settings.scanDelay (seconds)
class FullScreenScanner extends StatefulWidget {
  final String title;

  const FullScreenScanner({
    super.key,
    this.title = 'Default Scanner',
  });

  @override
  State<FullScreenScanner> createState() => _FullScreenScannerState();
}

class _FullScreenScannerState extends State<FullScreenScanner> {
  late final MobileScannerController _controller;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _audioPlayer.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _playBeep() async {
    try {
      // Ensure you have assets/sounds/beep.mp3 and it's declared in pubspec.yaml
      await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
    } catch (_) {
      // ignore playback errors silently
    }
  }


  Future<void> _handleScan(String code) async {
    // Prevent re-entrance
    if (_isProcessing) return;
    _isProcessing = true;

    // Read settings snapshot
    final settings = context.read<SettingsBloc>().state;

    // 1) Beep if enabled
    if (settings.beepEnabled) {
      await _playBeep();
    }

    // 2) Copy to clipboard if enabled
    if (settings.copyToClipboard) {
      try {
        await Clipboard.setData(ClipboardData(text: code));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied: $code'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (_) {
        // ignore clipboard errors
      }
    }

    // 3) Send to scanner bloc so the rest of the app can process it
    try {
      context.read<ScannerBloc>().add(ScanCode(code));
    } catch (_) {
      // ignore if bloc not available
    }

    // 4) Decide what to do based on continuous scanning setting
    final bool continuous = settings.isContinuousScanning;
    final double delaySeconds =
    (settings.scanDelay is num) ? (settings.scanDelay as num).toDouble() : 1.0;
    final int delayMs = (delaySeconds * 1000).round().clamp(0, 60000);

    if (continuous) {
      await Future.delayed(Duration(milliseconds: delayMs > 0 ? delayMs : 500));
      if (mounted) {
        _isProcessing = false;
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      Navigator.of(context).pop(code);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final code = barcodes.first.rawValue;
      if (code != null && code.isNotEmpty) {
        _handleScan(code);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Stack(
        children: [
          // Fullscreen camera
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            fit: BoxFit.cover,
          ),

          // Optional overlay: center guide
          // (You can remove or style this as you like)
          Center(
            child: Container(
              width: 400,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white70,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            left: 16,
            right: 16,
            bottom: 50,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close Scanner'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
