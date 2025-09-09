// lib/app/screens/full_screen_scanner.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../blocs/settings/settings_bloc.dart';
import '../blocs/scanner/scanner_bloc.dart';

class FullScreenScanner extends StatefulWidget {
  const FullScreenScanner({super.key});

  @override
  State<FullScreenScanner> createState() => _FullScreenScannerState();
}

class _FullScreenScannerState extends State<FullScreenScanner> {
  late final MobileScannerController _controller;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isProcessing = false;
  bool _torchOn = false;
  double _zoomLevel = 1.0; // Simulated zoom

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
      await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
    } catch (_) {}
  }

  Future<void> _handleScan(String code) async {
    if (_isProcessing) return;
    _isProcessing = true;

    final settings = context.read<SettingsBloc>().state;

    if (settings.beepEnabled) await _playBeep();

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
      } catch (_) {}
    }

    try {
      context.read<ScannerBloc>().add(ScanCode(code));
    } catch (_) {}

    final bool continuous = settings.isContinuousScanning;
    final double delaySeconds =
    (settings.scanDelay is num) ? (settings.scanDelay as num).toDouble() : 1.0;
    final int delayMs = (delaySeconds * 1000).round().clamp(0, 60000);

    if (continuous) {
      await Future.delayed(Duration(milliseconds: delayMs > 0 ? delayMs : 500));
      if (mounted) _isProcessing = false;
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

  void _toggleTorch() {
    setState(() {
      _torchOn = !_torchOn;
      _controller.toggleTorch();
    });
  }

  void _toggleZoom() {
    setState(() {
      _zoomLevel = _zoomLevel == 1.0 ? 2.0 : 1.0; // Toggle between 1x and 2x
    });
  }

  @override
  Widget build(BuildContext context) {
    final double boxWidth = 350;
    final double boxHeight = 600;

    return Scaffold(
      body: Stack(
        children: [
          // Fullscreen camera with simulated zoom
          Transform.scale(
            scale: _zoomLevel,
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              fit: BoxFit.cover,
            ),
          ),

          // Dimming overlay outside the box
          Center(
            child: Stack(
              children: [
                // Top overlay
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: (MediaQuery.of(context).size.height - boxHeight) / 2,
                  child: Container(color: Colors.black54),
                ),
                // Bottom overlay
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: (MediaQuery.of(context).size.height - boxHeight) / 2,
                  child: Container(color: Colors.black54),
                ),
                // Left overlay
                Positioned(
                  left: 0,
                  top: (MediaQuery.of(context).size.height - boxHeight) / 2,
                  width: (MediaQuery.of(context).size.width - boxWidth) / 2,
                  height: boxHeight,
                  child: Container(color: Colors.black54),
                ),
                // Right overlay
                Positioned(
                  right: 0,
                  top: (MediaQuery.of(context).size.height - boxHeight) / 2,
                  width: (MediaQuery.of(context).size.width - boxWidth) / 2,
                  height: boxHeight,
                  child: Container(color: Colors.black54),
                ),
              ],
            ),
          ),

          // White rectangle with blinking lines
          Center(
            child: Stack(
              children: [
                // White border box
                Container(
                  width: boxWidth,
                  height: boxHeight,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white70,
                      width: 2,
                    ),
                  ),
                ),

                // Horizontal blinking line
                Positioned(
                  left: 0,
                  right: 0,
                  top: boxHeight / 2 - 1,
                  child: const BlinkingLine(isHorizontal: true),
                ),

                // Vertical blinking line
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: boxWidth / 2 - 1,
                  child: const BlinkingLine(isHorizontal: false),
                ),
              ],
            ),
          ),

          // Flash and Zoom buttons at bottom
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Flash button
                IconButton(
                  onPressed: _toggleTorch,
                  icon: Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 30),
                // Zoom button
                IconButton(
                  onPressed: _toggleZoom,
                  icon: Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    size: 32,
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

// Blinking line widget
class BlinkingLine extends StatefulWidget {
  final bool isHorizontal;
  const BlinkingLine({super.key, required this.isHorizontal});

  @override
  State<BlinkingLine> createState() => _BlinkingLineState();
}

class _BlinkingLineState extends State<BlinkingLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: widget.isHorizontal ? double.infinity : 2,
        height: widget.isHorizontal ? 2 : double.infinity,
        color: Colors.red,
      ),
    );
  }
}
