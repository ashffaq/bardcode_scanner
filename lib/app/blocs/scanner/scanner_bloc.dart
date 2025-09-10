import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/scan_result.dart';
import '../../services/database_service.dart';
import '../settings/settings_bloc.dart';

// Events
abstract class ScannerEvent {}

class ScanCode extends ScannerEvent {
  final String code;
  final Map<String, dynamic>? extra;  // optional extra data

  ScanCode(this.code, {this.extra});
}

class LoadScans extends ScannerEvent {}

class UpdateScan extends ScannerEvent {
  final ScanResult scan;
  UpdateScan(this.scan);
}

class DeleteScan extends ScannerEvent {
  final int id;
  DeleteScan(this.id);
}

class ScannerFeedback extends ScannerState {
  final String message;
  ScannerFeedback(this.message);
}

class DeleteAllScans extends ScannerEvent {}

// States
abstract class ScannerState {}

class ScannerInitial extends ScannerState {}

class ScannerLoading extends ScannerState {}

class ScannerSuccess extends ScannerState {
  final List<ScanResult> scans;
  ScannerSuccess(this.scans);
}

class ScannerError extends ScannerState {
  final String message;
  ScannerError(this.message);
}

class ScannerBloc extends Bloc<ScannerEvent, ScannerState> {
  final DatabaseService _db = DatabaseService.instance;
  final SettingsBloc _settingsBloc;

  ScannerBloc({required SettingsBloc settingsBloc})
      : _settingsBloc = settingsBloc,
        super(ScannerInitial()) {
    on<ScanCode>(_onScanCode);
    on<LoadScans>(_onLoadScans);
    on<UpdateScan>(_onUpdateScan);
    on<DeleteScan>(_onDeleteScan);
    on<DeleteAllScans>(_onDeleteAllScans);
  }


  Future<void> _onScanCode(ScanCode event, Emitter<ScannerState> emit) async {
    emit(ScannerLoading());
    try {
      // --- STEP 1: Get all required values from the Settings Bloc ---
      final settings = _settingsBloc.state;
      final webhookUrl = settings.webhookUrl;
      final apiKey = settings.apiKey;
      final apiSecret = settings.apiSecret;

      // --- STEP 2: Add a check to ensure keys are not empty ---
      if (apiKey.isEmpty || apiSecret.isEmpty) {
        emit(ScannerError('API Key and Secret must be set in settings.'));
        // Create a local scan result to show the user what's wrong
        final scan = ScanResult(
          code: event.code,
          codeValue: 'Configuration Error: API Key or Secret is missing.',
          timestamp: DateTime.now(),
        );
        await _db.create(scan);
        final scans = await _db.getAllScans();
        emit(ScannerSuccess(scans));
        return; // Stop execution
      }

      // --- STEP 3: The rest of the code is the same, just using the variables from settings ---
      final Map<String, String> frappeHeaders = {
        'Authorization': 'token $apiKey:$apiSecret',
        'Content-Type': 'application/x-www-form-urlencoded',
      };

      final Map<String, String> bodyMap = {
        'doc_name': event.code,
        // spread extra key-values if provided
        ...?event.extra?.map((k, v) => MapEntry(k, v.toString())),
      };

      final String encodedBody = bodyMap.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: frappeHeaders,
        body: encodedBody,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));
        final String messageFromServer = responseData['message']['message'];

        final scan = ScanResult(
          code: event.code,
          codeValue: messageFromServer,
          timestamp: DateTime.now(),
        );
        await _db.create(scan);
        final scans = await _db.getAllScans();
        emit(ScannerFeedback("✅ $messageFromServer"));
        emit(ScannerSuccess(scans));
      } else {
        emit(ScannerError('Server error: ${response.statusCode} - ${response.body}'));
        final scan = ScanResult(
          code: event.code,
          codeValue: 'Failed: ${response.statusCode}',
          timestamp: DateTime.now(),
        );
        await _db.create(scan);
        final scans = await _db.getAllScans();
        emit(ScannerFeedback("❌ Failed: ${response.statusCode}"));
        await Future.delayed(const Duration(seconds: 2));

        emit(ScannerSuccess(scans));
      }
    } catch (e) {
      emit(ScannerError(e.toString()));
      final scan = ScanResult(
        code: event.code,
        codeValue: 'Network Error',
        timestamp: DateTime.now(),
      );
      await _db.create(scan);
      final scans = await _db.getAllScans();
      await Future.delayed(const Duration(seconds: 2));

      emit(ScannerSuccess(scans));
    }
  }

  Future<void> _onLoadScans(LoadScans event, Emitter<ScannerState> emit) async {
    emit(ScannerLoading());
    try {
      final scans = await _db.getAllScans();
      emit(ScannerSuccess(scans));
    } catch (e) {
      emit(ScannerError(e.toString()));
    }
  }

  Future<void> _onUpdateScan(
      UpdateScan event,
      Emitter<ScannerState> emit,
      ) async {
    emit(ScannerLoading());
    try {
      await _db.update(event.scan);
      final scans = await _db.getAllScans();
      emit(ScannerSuccess(scans));
    } catch (e) {
      emit(ScannerError(e.toString()));
    }
  }

  Future<void> _onDeleteScan(
      DeleteScan event,
      Emitter<ScannerState> emit,
      ) async {
    emit(ScannerLoading());
    try {
      await _db.delete(event.id);
      final scans = await _db.getAllScans();
      emit(ScannerSuccess(scans));
    } catch (e) {
      emit(ScannerError(e.toString()));
    }
  }

  Future<void> _onDeleteAllScans(
      DeleteAllScans event,
      Emitter<ScannerState> emit,
      ) async {
    emit(ScannerLoading());
    try {
      await _db.deleteAll();
      emit(ScannerSuccess([]));
    } catch (e) {
      emit(ScannerError(e.toString()));
    }
  }
}
