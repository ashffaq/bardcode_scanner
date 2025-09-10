import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Events
abstract class SettingsEvent {}

class LoadSettings extends SettingsEvent {}

class UpdateWebhookUrl extends SettingsEvent {
  final String url;
  UpdateWebhookUrl(this.url);
}

class UpdateWebhookUrlFromQr extends SettingsEvent {
  final String code;
  UpdateWebhookUrlFromQr(this.code);
}

class ToggleDarkMode extends SettingsEvent {}

class ToggleContinuousScanning extends SettingsEvent {}

class UpdateScanDelay extends SettingsEvent {
  final double delay;
  UpdateScanDelay(this.delay);
}

class ToggleBeep extends SettingsEvent {}

class UpdateWebhookTitle extends SettingsEvent {
  final String title;
  UpdateWebhookTitle(this.title);
}

class UpdateWebhookHeaders extends SettingsEvent {
  final Map<String, String> headers;
  UpdateWebhookHeaders(this.headers);
}

class AddWebhookHeader extends SettingsEvent {
  final String key;
  final String value;
  AddWebhookHeader(this.key, this.value);
}

class RemoveWebhookHeader extends SettingsEvent {
  final String key;
  RemoveWebhookHeader(this.key);
}

class ToggleClipboard extends SettingsEvent {}


class SaveFrappeCredentials extends SettingsEvent {
  final String apiKey;
  final String apiSecret;
  SaveFrappeCredentials(this.apiKey, this.apiSecret);
}

// State
class SettingsState {
  final String webhookUrl;
  final String webhookTitle;
  final Map<String, String> webhookHeaders;
  final bool isDarkMode;
  final bool isLoading;
  final bool isContinuousScanning;
  final double scanDelay;
  final bool beepEnabled;
  final bool copyToClipboard;
  final String apiKey;
  final String apiSecret;

  SettingsState({
    this.webhookUrl = 'https://n8n.afsonseeds.com/webhook/barcodescanner',
    this.webhookTitle = 'Default Webhook',
    this.webhookHeaders = const {'Content-Type': 'application/json'},
    this.isDarkMode = false,
    this.isLoading = false,
    this.isContinuousScanning = false,
    this.scanDelay = 2.0,
    this.beepEnabled = true,
    this.copyToClipboard = false,
    this.apiKey = '',
    this.apiSecret = '',
  });

  SettingsState copyWith({
    String? webhookUrl,
    String? webhookTitle,
    Map<String, String>? webhookHeaders,
    bool? isDarkMode,
    bool? isLoading,
    bool? isContinuousScanning,
    double? scanDelay,
    bool? beepEnabled,
    bool? copyToClipboard,
    String? apiKey,
    String? apiSecret,
  }) {
    return SettingsState(
      webhookUrl: webhookUrl ?? this.webhookUrl,
      webhookTitle: webhookTitle ?? this.webhookTitle,
      webhookHeaders: webhookHeaders ?? this.webhookHeaders,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isLoading: isLoading ?? this.isLoading,
      isContinuousScanning: isContinuousScanning ?? this.isContinuousScanning,
      scanDelay: scanDelay ?? this.scanDelay,
      beepEnabled: beepEnabled ?? this.beepEnabled,
      copyToClipboard: copyToClipboard ?? this.copyToClipboard,
      apiKey: apiKey ?? this.apiKey,
      apiSecret: apiSecret ?? this.apiSecret,
    );
  }
}

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final _storage = const FlutterSecureStorage();

  SettingsBloc() : super(SettingsState()) {
    on<LoadSettings>(_onLoadSettings);
    on<UpdateWebhookUrl>(_onUpdateWebhookUrl);
    on<UpdateWebhookUrlFromQr>(_onUpdateWebhookUrlFromQr);
    on<UpdateWebhookTitle>(_onUpdateWebhookTitle);
    on<UpdateWebhookHeaders>(_onUpdateWebhookHeaders);
    on<AddWebhookHeader>(_onAddWebhookHeader);
    on<RemoveWebhookHeader>(_onRemoveWebhookHeader);
    on<ToggleDarkMode>(_onToggleDarkMode);
    on<ToggleContinuousScanning>(_onToggleContinuousScanning);
    on<UpdateScanDelay>(_onUpdateScanDelay);
    on<ToggleBeep>(_onToggleBeep);
    on<ToggleClipboard>(_onToggleClipboard);
    on<SaveFrappeCredentials>(_onSaveFrappeCredentials);

    // Load settings when bloc is created
    add(LoadSettings());
  }

  Future<void> _onLoadSettings(
    LoadSettings event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));

    try {
      final url = await _storage.read(key: 'webhook_url');
      final title = await _storage.read(key: 'webhook_title');
      final headersJson = await _storage.read(key: 'webhook_headers');
      final isDarkMode = await _storage.read(key: 'dark_mode');
      final isContinuousScanning = await _storage.read(
        key: 'continuous_scanning',
      );
      final scanDelay = await _storage.read(key: 'scan_delay');
      final beepEnabled = await _storage.read(key: 'beep_enabled');
      final copyToClipboard = await _storage.read(key: 'copy_to_clipboard');
      final apiKey = await _storage.read(key: 'frappe_api_key');
      final apiSecret = await _storage.read(key: 'frappe_api_secret');

      // Parse headers from JSON
      Map<String, String> headers = {'Content-Type': 'application/json'};
      if (headersJson != null) {
        try {
          final Map<String, dynamic> parsedHeaders = jsonDecode(headersJson);
          headers = parsedHeaders.map(
            (key, value) => MapEntry(key, value.toString()),
          );
        } catch (e) {
          // Use default headers if parsing fails
        }
      }

      emit(
        state.copyWith(
          webhookUrl: url ?? state.webhookUrl,
          webhookTitle: title ?? state.webhookTitle,
          webhookHeaders: headers,
          isDarkMode: isDarkMode == 'true',
          isContinuousScanning: isContinuousScanning == 'true',
          scanDelay:
              scanDelay != null ? double.parse(scanDelay) : state.scanDelay,
          beepEnabled: beepEnabled == null ? true : beepEnabled == 'true',
          copyToClipboard: copyToClipboard == 'true',
          isLoading: false,
          apiKey: apiKey ?? '',
          apiSecret: apiSecret ?? '',
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> _onUpdateWebhookUrl(
    UpdateWebhookUrl event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _storage.write(key: 'webhook_url', value: event.url);
      emit(state.copyWith(webhookUrl: event.url));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onUpdateWebhookUrlFromQr(
    UpdateWebhookUrlFromQr event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final uri = Uri.parse(event.code);
      if (uri.scheme == 'barcodescanner' &&
          uri.host == 'setwebhookurl' &&
          uri.queryParameters.containsKey('url')) {
        final newUrl = uri.queryParameters['url']!;
        await _storage.write(key: 'webhook_url', value: newUrl);

        // Update title if provided in QR code
        if (uri.queryParameters.containsKey('title')) {
          final newTitle = uri.queryParameters['title']!;
          await _storage.write(key: 'webhook_title', value: newTitle);

          // Update state with both URL and title
          emit(state.copyWith(webhookUrl: newUrl, webhookTitle: newTitle));
        } else {
          // Update only URL
          emit(state.copyWith(webhookUrl: newUrl));
        }

        // Update headers if provided in QR code
        if (uri.queryParameters.containsKey('headers')) {
          try {
            final headersJson = uri.queryParameters['headers']!;
            final Map<String, dynamic> parsedHeaders = jsonDecode(headersJson);
            final headers = parsedHeaders.map(
              (key, value) => MapEntry(key, value.toString()),
            );

            final headersJsonToStore = jsonEncode(headers);
            await _storage.write(
              key: 'webhook_headers',
              value: headersJsonToStore,
            );

            // Update state with headers
            emit(state.copyWith(webhookHeaders: headers));
          } catch (e) {
            // Ignore header parsing errors
          }
        }
      }
    } catch (e) {
      // Handle error - invalid URL format
    }
  }

  Future<void> _onToggleDarkMode(
    ToggleDarkMode event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final newDarkMode = !state.isDarkMode;
      await _storage.write(key: 'dark_mode', value: newDarkMode.toString());
      emit(state.copyWith(isDarkMode: newDarkMode));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onToggleContinuousScanning(
    ToggleContinuousScanning event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final newValue = !state.isContinuousScanning;
      await _storage.write(
        key: 'continuous_scanning',
        value: newValue.toString(),
      );
      emit(state.copyWith(isContinuousScanning: newValue));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onUpdateScanDelay(
    UpdateScanDelay event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _storage.write(key: 'scan_delay', value: event.delay.toString());
      emit(state.copyWith(scanDelay: event.delay));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onToggleBeep(
    ToggleBeep event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final newValue = !state.beepEnabled;
      await _storage.write(key: 'beep_enabled', value: newValue.toString());
      emit(state.copyWith(beepEnabled: newValue));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onUpdateWebhookTitle(
    UpdateWebhookTitle event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _storage.write(key: 'webhook_title', value: event.title);
      emit(state.copyWith(webhookTitle: event.title));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onUpdateWebhookHeaders(
    UpdateWebhookHeaders event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final headersJson = jsonEncode(event.headers);
      await _storage.write(key: 'webhook_headers', value: headersJson);
      emit(state.copyWith(webhookHeaders: event.headers));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onAddWebhookHeader(
    AddWebhookHeader event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final updatedHeaders = Map<String, String>.from(state.webhookHeaders);
      updatedHeaders[event.key] = event.value;

      final headersJson = jsonEncode(updatedHeaders);
      await _storage.write(key: 'webhook_headers', value: headersJson);

      emit(state.copyWith(webhookHeaders: updatedHeaders));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onRemoveWebhookHeader(
    RemoveWebhookHeader event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      final updatedHeaders = Map<String, String>.from(state.webhookHeaders);
      updatedHeaders.remove(event.key);

      final headersJson = jsonEncode(updatedHeaders);
      await _storage.write(key: 'webhook_headers', value: headersJson);

      emit(state.copyWith(webhookHeaders: updatedHeaders));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onToggleClipboard(
    ToggleClipboard event,
    Emitter<SettingsState> emit,
  ) async {
    try {
      await _storage.write(
        key: 'copy_to_clipboard',
        value: (!state.copyToClipboard).toString(),
      );
      emit(state.copyWith(copyToClipboard: !state.copyToClipboard));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _onSaveFrappeCredentials(
      SaveFrappeCredentials event,
      Emitter<SettingsState> emit,
      ) async {
    try {
      await _storage.write(key: 'frappe_api_key', value: event.apiKey);
      await _storage.write(key: 'frappe_api_secret', value: event.apiSecret);
      emit(state.copyWith(apiKey: event.apiKey, apiSecret: event.apiSecret));
    } catch (e) {
      // Handle error
    }
  }
}
