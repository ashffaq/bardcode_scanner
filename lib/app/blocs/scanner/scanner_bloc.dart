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
  ScanCode(this.code);
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

  // REPLACE the existing _onScanCode method with this one.

// REPLACE the existing _onScanCode method with this DEFINITIVE version.

  Future<void> _onScanCode(ScanCode event, Emitter<ScannerState> emit) async {
    emit(ScannerLoading());
    try {
      final webhookUrl = _settingsBloc.state.webhookUrl;

      // Using the keys you provided.
      const String apiKey = '34542297d5fb715';
      const String apiSecret = '6e67f65533a29ce';

      // Headers for Frappe.
      final Map<String, String> frappeHeaders = {
        'Authorization': 'token $apiKey:$apiSecret',
        'Content-Type': 'application/x-www-form-urlencoded',
      };

      // The data we want to send, as a Map.
      final Map<String, String> bodyMap = {
        'doc_name': event.code,
      };

      // --- THIS IS THE CRUCIAL FIX ---
      // Manually encode the Map into a String in the format "key1=value1&key2=value2".
      // This creates a String like "doc_name=SI-00123".
      // This is the STRING the http.post function needs.
      final String encodedBody = bodyMap.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      // Make the POST request.
      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: frappeHeaders,
        body: encodedBody, // We are now correctly passing a STRING.
      );

      // --- The rest of the logic remains the same ---
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = jsonDecode(utf8.decode(response.bodyBytes));

        final scan = ScanResult(
          code: event.code,
          codeValue: responseData['message'],
          timestamp: DateTime.now(),
        );
        await _db.create(scan);
        final scans = await _db.getAllScans();
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
