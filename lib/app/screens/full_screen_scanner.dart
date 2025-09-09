// lib/app/screens/full_screen_scanner.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import '../blocs/settings/settings_bloc.dart';
import '../blocs/scanner/scanner_bloc.dart';

class FullScreenScanner extends StatefulWidget {
  const FullScreenScanner({super.key});

  @override
  State<FullScreenScanner> createState() => _FullScreenScannerState();
}

class _FullScreenScannerState extends State<FullScreenScanner> {
  CameraController? _cameraController;
  BarcodeScanner? _barcodeScanner;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isProcessing = false;
  bool _torchOn = false;
  double _zoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _initializeCamera();
    _barcodeScanner = BarcodeScanner();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _audioPlayer.dispose();
    _cameraController?.dispose();
    _barcodeScanner?.close();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController?.initialize();
    if (!mounted) return;
    setState(() {});

    await _cameraController?.startImageStream(_processCameraImage);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final allBytes = image.planes.fold<Uint8List>(
        Uint8List(0),
        (previous, plane) => Uint8List.fromList([...previous, ...plane.bytes]),
      );

      final inputImage = InputImage.fromBytes(
        bytes: allBytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final barcodes = await _barcodeScanner?.processImage(inputImage);

      if (barcodes != null && barcodes.isNotEmpty) {
        final code = barcodes.first.rawValue;
        if (code != null && code.isNotEmpty) {
          await _handleScan(code);
        }
      }
    } catch (_) {}
    _isProcessing = false;
  }

  Future<void> _playBeep() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/beep.mp3'));
    } catch (_) {}
  }

  Future<void> _handleScan(String code) async {
    final settings = context.read<SettingsBloc>().state;

    if (settings.beepEnabled) await _playBeep();

    if (settings.copyToClipboard) {
      try {
        await Clipboard.setData(ClipboardData(text: code));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Copied: $code'), duration: const Duration(seconds: 2)),
          );
        }
      } catch (_) {}
    }

    try {
      context.read<ScannerBloc>().add(ScanCode(code));
    } catch (_) {}

    // If code starts with MAT-DN, show popup
    if (code.startsWith('MAT-DN')) {
      await _showGatepassPopup(code);
    } else if (code.startsWith('ACC-SINV')) {
      await _showCommentsPopup(code);
    } else {
      final bool continuous = settings.isContinuousScanning;
      final double delaySeconds =
          (settings.scanDelay is num) ? (settings.scanDelay as num).toDouble() : 1.0;
      final int delayMs = (delaySeconds * 1000).round().clamp(0, 60000);

      if (!continuous) {
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        Navigator.of(context).pop(code);
      } else {
        await Future.delayed(Duration(milliseconds: delayMs > 0 ? delayMs : 500));
      }
    }
  }

  Future<void> _showGatepassPopup(String scannedCode) async {
    final _formKey = GlobalKey<FormState>();
    TextEditingController gpNumberController = TextEditingController();
    TextEditingController dateController = TextEditingController();
    DateTime? selectedDate;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Gatepass Details'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Gatepass Number
                    TextFormField(
                      controller: gpNumberController,
                      decoration: const InputDecoration(labelText: 'Gatepass Number'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Gatepass Date
                    TextFormField(
                      controller: dateController,
                      readOnly: true, // prevents keyboard from appearing
                      decoration: const InputDecoration(
                        labelText: 'Gatepass Date',
                        hintText: 'Select Date',
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: () async {
                        // Remove keyboard if open
                        FocusScope.of(context).unfocus();

                        DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );

                        if (pickedDate != null) {
                          setState(() {
                            selectedDate = pickedDate;
                            dateController.text =
                                "${pickedDate.day}/${pickedDate.month}/${pickedDate.year}";
                          });
                        }
                      },
                      validator: (value) {
                        if (selectedDate == null) return 'Required';
                        return null;
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  // TODO: Call webhook with scannedCode, gpNumberController.text, selectedDate
                  print('Submitting: $scannedCode, ${gpNumberController.text}, $selectedDate');
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCommentsPopup(String scannedCode) async {
    final _formKey = GlobalKey<FormState>();
    TextEditingController commentsController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Comments (Optional)'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Form(
                key: _formKey,
                child: TextFormField(
                  controller: commentsController,
                  decoration: const InputDecoration(
                    labelText: 'Comments',
                    hintText: 'Enter your comments',
                  ),
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                ),
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                // optional, so no validation needed
                final comments = commentsController.text.trim();
                // TODO: Call webhook with scannedCode and comments
                print('Submitting: $scannedCode, Comments: $comments');
                Navigator.of(context).pop();
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  void _toggleTorch() {
    if (_cameraController == null) return;
    setState(() {
      _torchOn = !_torchOn;
      _cameraController!.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
    });
  }

  void _toggleZoom() async {
    if (_cameraController == null) return;

    try {
      final minZoom = await _cameraController!.getMinZoomLevel();
      final maxZoom = await _cameraController!.getMaxZoomLevel();

      final targetZoom = _zoomLevel == 1.0 ? (2.0 <= maxZoom ? 2.0 : maxZoom) : 1.0;

      await _cameraController!.setZoomLevel(targetZoom);

      setState(() {
        _zoomLevel = targetZoom;
      });
    } catch (e) {
      debugPrint('Error setting zoom: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final double boxWidth = 350;
    final double boxHeight = 600;

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_cameraController!),
          // Dimmed overlay outside scanning box
          Center(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: (MediaQuery.of(context).size.height - boxHeight) / 2,
                  child: Container(color: Colors.black54),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: (MediaQuery.of(context).size.height - boxHeight) / 2,
                  child: Container(color: Colors.black54),
                ),
                Positioned(
                  left: 0,
                  top: (MediaQuery.of(context).size.height - boxHeight) / 2,
                  width: (MediaQuery.of(context).size.width - boxWidth) / 2,
                  height: boxHeight,
                  child: Container(color: Colors.black54),
                ),
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
          // White box with blinking red lines
          Center(
            child: Stack(
              children: [
                Container(
                  width: boxWidth,
                  height: boxHeight,
                  decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 2)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: boxHeight / 2 - 1,
                  child: const BlinkingLine(isHorizontal: true),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: boxWidth / 2 - 1,
                  child: const BlinkingLine(isHorizontal: false),
                ),
              ],
            ),
          ),
          // Flash and Zoom buttons
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _toggleTorch,
                  icon: Icon(
                    _torchOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 30),
                IconButton(
                  onPressed: _toggleZoom,
                  icon: const Icon(Icons.zoom_in, color: Colors.white, size: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BlinkingLine extends StatefulWidget {
  final bool isHorizontal;
  const BlinkingLine({super.key, required this.isHorizontal});

  @override
  State<BlinkingLine> createState() => _BlinkingLineState();
}

class _BlinkingLineState extends State<BlinkingLine> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
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
