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
import 'package:flutter/foundation.dart'; // for compute
import 'package:another_flushbar/flushbar.dart';

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

  // Throttle camera frames for performance
  final int frameSkipMs = 300;
  DateTime lastProcessed = DateTime.now();

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
      ResolutionPreset.ultraHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _cameraController?.initialize();
    if (!mounted) return;
    setState(() {});

    await _cameraController?.startImageStream(_processCameraImage);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;
    if (DateTime.now().difference(lastProcessed).inMilliseconds < frameSkipMs) return;

    _isProcessing = true;
    lastProcessed = DateTime.now();

    try {
      // Move heavy conversion to background isolate
      final InputImage? inputImage = await compute(_convertToInputImage, image);

      if (inputImage != null) {
        final barcodes = await _barcodeScanner?.processImage(inputImage);

        if (barcodes != null && barcodes.isNotEmpty) {
          final code = barcodes.first.rawValue;
          if (code != null && code.isNotEmpty) {
            await _handleScan(code);
          }
        }
      }
    } catch (e) {
      debugPrint('Error in processing image: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // Runs in background isolate
  static InputImage? _convertToInputImage(CameraImage image) {
    try {
      final allBytes = image.planes.fold<Uint8List>(
        Uint8List(0),
            (prev, plane) => Uint8List.fromList([...prev, ...plane.bytes]),
      );

      return InputImage.fromBytes(
        bytes: allBytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
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
          Flushbar(
            messageText: Text(
              "$code",
              style: TextStyle(fontSize: 18.0, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(8),
            borderRadius: BorderRadius.circular(8),
            backgroundColor: Colors.black87,
            flushbarPosition: FlushbarPosition.TOP, // 👈 shows at top
          ).show(context);
        }
      } catch (_) {}
    }

    //context.read<ScannerBloc>().add(ScanCode(code));

    if (code.startsWith('MAT-DN')) {
      await _showGatepassPopup(code);
    } else if (code.startsWith('ACC-SINV')) {
      await _showCommentsPopup(code);
    } else {
      final bool continuous = settings.isContinuousScanning;
      final int delayMs = ((settings.scanDelay as num) * 1000).round().clamp(0, 60000);

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
    final gpNumberController = TextEditingController();
    final dateController = TextEditingController();
    DateTime? selectedDate;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Gatepass",
      pageBuilder: (context, animation1, animation2) {
        return Center(
          child: SingleChildScrollView(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Enter Gatepass Details for $scannedCode',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),

                      // Gatepass Number
                      TextFormField(
                        controller: gpNumberController,
                        decoration: const InputDecoration(labelText: 'Gatepass Number'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (value) => (value == null || value.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),

                      // Gatepass Date
                      TextFormField(
                        controller: dateController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Gatepass Date',
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        onTap: () async {
                          FocusScope.of(context).unfocus();
                          DateTime? pickedDate = await showDatePicker(
                            context: context,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (pickedDate != null) {
                            selectedDate = pickedDate;
                            dateController.text =
                            "${pickedDate.day}/${pickedDate.month}/${pickedDate.year}";
                          }
                        },
                        validator: (value) => selectedDate == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 24),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (_formKey.currentState!.validate()) {
                                final gpNumber = gpNumberController.text;
                                final gpDate = selectedDate?.toIso8601String();

                                context.read<ScannerBloc>().add(
                                  ScanCode(
                                    scannedCode,
                                    extra: {
                                      "gatepass_number": gpNumber,
                                      "gatepass_date": gpDate,
                                    },
                                  ),
                                );

                                Navigator.of(context).pop();
                              }
                            },
                            child: const Text('SUBMIT'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation1, animation2, child) {
        return FadeTransition(opacity: animation1, child: child);
      },
      transitionDuration: const Duration(milliseconds: 200),
    );
  }

  Future<void> _showCommentsPopup(String scannedCode) async {
    final commentsController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Comments (Optional) $scannedCode'),
          content: TextFormField(
            controller: commentsController,
            decoration: const InputDecoration(
              labelText: 'Comments',
              hintText: 'Enter your comments',
            ),
            maxLines: 4,
            keyboardType: TextInputType.multiline,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                context.read<ScannerBloc>().add(
                  ScanCode(
                    scannedCode,
                    extra: {
                      "comments": commentsController.text.trim(),
                    },
                  ),
                );
                Navigator.of(context).pop();
              },
              child: const Text('SUBMIT'),
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

    return BlocListener<ScannerBloc, ScannerState>(
      listener: (context, state) {
        if (state is ScannerFeedback) {
          Flushbar(
            messageText: Text(
              state.message,
              style: const TextStyle(fontSize: 18.0, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(8),
            borderRadius: BorderRadius.circular(8),
            backgroundColor: Colors.green.shade700,
            flushbarPosition: FlushbarPosition.TOP,
          ).show(context);
        }
        if (state is ScannerError) {
          Flushbar(
            messageText: Text(
              state.message,
              style: const TextStyle(fontSize: 18.0, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(8),
            borderRadius: BorderRadius.circular(8),
            backgroundColor: Colors.red.shade700,
            flushbarPosition: FlushbarPosition.TOP,
          ).show(context);
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(_cameraController!),

            // Transparent floating controls (torch + zoom)
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFloatingIcon(
                    icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                    onTap: _toggleTorch,
                  ),
                  const SizedBox(width: 30),
                  _buildFloatingIcon(icon: Icons.zoom_in, onTap: _toggleZoom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingIcon({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
        padding: const EdgeInsets.all(12),
        child: Icon(icon, color: Colors.white, size: 32),
      ),
    );
  }
}
