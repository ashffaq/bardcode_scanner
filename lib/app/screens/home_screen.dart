// lib/app/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import '../providers/scanning_state_provider.dart';
import '../blocs/settings/settings_bloc.dart';
import '../widgets/scan_button.dart';
import '../widgets/scans_list.dart';
import 'package:go_router/go_router.dart';

// Import the new full screen scanner (same folder -> relative import)
import 'full_screen_scanner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScanningStateProvider(),
      child: Scaffold(
        appBar: AppBar(
          title: BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, state) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Image(
                    image: AssetImage('assets/images/logo.png'),
                    width: 40,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      state.webhookTitle.isNotEmpty
                          ? state.webhookTitle
                          : 'AllCodeRelay',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => context.go('/settings'),
            ),
          ],
        ),
        body: Column(
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _isExpanded
                                  ? Icons.keyboard_arrow_down
                                  : Icons.keyboard_arrow_right,
                            ),
                            onPressed: () {
                              setState(() {
                                _isExpanded = !_isExpanded;
                              });
                            },
                          ),
                          Text(
                            'Scan Mode',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const Spacer(),
                        ],
                      ),
                      if (_isExpanded)
                        SizedBox(
                          height: 260,
                          child: Row(
                            children: [
                              // First card: Sales Invoice -> opens full screen scanner
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () async {
                                    // open full screen scanner
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                        const FullScreenScanner(),
                                      ),
                                    );

                                    // Optional: after returning from scanner, you can inspect
                                    // your provider or bloc for the latest scanned value.
                                    // Replace `lastScanValue` with the real property name
                                    // that your ScanningStateProvider exposes (if any).
                                    final provider = Provider.of<ScanningStateProvider>(context, listen: false);
                                    // TODO: change `.lastScanValue` to your provider's property:
                                    // final scanned = provider.lastScanValue;
                                    // if (scanned != null) { show snackbar or handle it }
                                  },
                                  child: const ScanButton(),
                                ),
                              ),

                              const SizedBox(width: 16),

                              // Second card: Delivery Note -> same full screen scanner for now
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                        const FullScreenScanner(),
                                      ),
                                    );

                                    // same optional provider check as above
                                    final provider = Provider.of<ScanningStateProvider>(context, listen: false);
                                    // TODO: check provider for the latest scanned value here if needed
                                  },
                                  child: const ScanButton(),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Expanded(child: ScansList()),
          ],
        ),
      ),
    );
  }
}