import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';

import 'models/google_calendar_connection.dart';
import 'services/google_calendar_service.dart';
import 'services/oauth_url_opener.dart';
import 'google_calendar_sync_events_page.dart';

class GoogleCalendarSettingsPage extends StatefulWidget {
  GoogleCalendarSettingsPage({super.key, GoogleCalendarService? service})
    : service = service ?? GoogleCalendarService();

  final GoogleCalendarService service;

  @override
  State<GoogleCalendarSettingsPage> createState() =>
      _GoogleCalendarSettingsPageState();
}

class _GoogleCalendarSettingsPageState
    extends State<GoogleCalendarSettingsPage> {
  static const Duration _initialLoadTimeout = Duration(seconds: 15);

  bool _busy = false;
  bool _loadingCalendars = false;
  bool _forceDisconnectedFallback = false;
  bool _hasResolvedInitialState = false;
  bool _loadingAuthDiagnostics = true;
  String _authUid = '';
  String _authEmail = '';
  bool _authEmailVerified = false;
  bool _adminClaimPresent = false;
  bool _adminClaimValue = false;
  String _authDiagnosticsError = '';
  List<GoogleCalendarOption> _calendars = const <GoogleCalendarOption>[];
  late Stream<GoogleCalendarConnection> _connectionStream;
  late DateTime _connectionLoadStartedAt;
  Timer? _connectionLoadTicker;
  Timer? _forceFallbackTimer;

  @override
  void initState() {
    super.initState();
    _connectionStream = widget.service.watchConnection();
    _connectionLoadStartedAt = DateTime.now();
    _startLoadTicker();
    _startForceFallbackTimer();
    _loadAuthDiagnostics();
  }

  @override
  void dispose() {
    _connectionLoadTicker?.cancel();
    _forceFallbackTimer?.cancel();
    super.dispose();
  }

  void _startForceFallbackTimer() {
    _forceFallbackTimer?.cancel();
    _forceFallbackTimer = Timer(_initialLoadTimeout, () {
      if (!mounted || _hasResolvedInitialState) return;
      setState(() {
        _forceDisconnectedFallback = true;
      });
    });
  }

  void _startLoadTicker() {
    _connectionLoadTicker?.cancel();
    _connectionLoadTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  String _describeError(Object error) {
    if (error is FirebaseFunctionsException) {
      return 'Functions error [${error.code}]: ${error.message ?? 'Nepoznata greška.'}';
    }
    if (error is FirebaseException) {
      return 'Firebase error [${error.code}]: ${error.message ?? 'Nepoznata greška.'}';
    }
    return 'Greška: $error';
  }

  Future<void> _loadAuthDiagnostics() async {
    setState(() {
      _loadingAuthDiagnostics = true;
      _authDiagnosticsError = '';
    });

    try {
      final result = await widget.service.getAuthDiagnostics(
        forceRefreshToken: true,
      );
      if (!mounted) return;
      setState(() {
        _authUid = result.uid;
        _authEmail = result.email;
        _authEmailVerified = result.emailVerified;
        _adminClaimPresent = result.adminClaimPresent;
        _adminClaimValue = result.adminClaimValue;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authDiagnosticsError = _describeError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingAuthDiagnostics = false;
        });
      }
    }
  }

  void _retryConnectionLoad() {
    setState(() {
      _connectionStream = widget.service.watchConnection();
      _connectionLoadStartedAt = DateTime.now();
      _hasResolvedInitialState = false;
      _forceDisconnectedFallback = false;
    });
    _startLoadTicker();
    _startForceFallbackTimer();
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final uri = await widget.service.getAuthorizationUrl();
      if (!mounted) return;
      await openOAuthUrl(uri);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dovršite prijavu u pregledniku, pa se vratite u aplikaciju.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Povezivanje nije uspjelo: ${_describeError(error)}'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refreshCalendars() async {
    if (_loadingCalendars) return;

    setState(() => _loadingCalendars = true);
    try {
      final calendars = await widget.service.listCalendars();
      if (!mounted) return;
      setState(() {
        _calendars = calendars;
      });
    } catch (_) {
      // Ignore transient errors while OAuth callback is still finishing.
    } finally {
      if (mounted) {
        setState(() => _loadingCalendars = false);
      }
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await widget.service.disconnect();
      if (!mounted) return;
      setState(() {
        _calendars = const <GoogleCalendarOption>[];
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Odspajanje nije uspjelo: ${_describeError(error)}'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      final response = await widget.service.syncNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sinkronizirano: novi ${response.newEvents}, promijenjeni ${response.updatedEvents}, otkazani ${response.cancelledEvents}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sinkronizacija nije uspjela: ${_describeError(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _syncStatusLabel(GoogleCalendarSyncStatus status) {
    switch (status) {
      case GoogleCalendarSyncStatus.idle:
        return 'Miruje';
      case GoogleCalendarSyncStatus.syncing:
        return 'Sinkronizacija u tijeku';
      case GoogleCalendarSyncStatus.success:
        return 'Uspješno';
      case GoogleCalendarSyncStatus.error:
        return 'Greška';
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google kalendar'),
        actions: [
          IconButton(
            tooltip: 'Sinkronizirani događaji',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GoogleCalendarSyncEventsPage(),
                ),
              );
            },
            icon: const Icon(Icons.event_note),
          ),
        ],
      ),
      body: StreamBuilder<GoogleCalendarConnection>(
        stream: _connectionStream,
        builder: (context, snapshot) {
          if (_loadingAuthDiagnostics) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_authDiagnosticsError.isNotEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    Text(_authDiagnosticsError, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadAuthDiagnostics,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Pokušaj ponovno'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!_adminClaimValue) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const ListTile(
                  title: Text('Administratorska ovlast'),
                  subtitle: Text('Vaš račun nema administratorsku ovlast.'),
                ),
                ListTile(
                  title: const Text('Email'),
                  subtitle: Text(_authEmail.isEmpty ? '-' : _authEmail),
                ),
                ListTile(
                  title: const Text('UID'),
                  subtitle: Text(_authUid.isEmpty ? '-' : _authUid),
                ),
                ListTile(
                  title: const Text('Email verified'),
                  subtitle: Text(_authEmailVerified ? 'true' : 'false'),
                ),
                ListTile(
                  title: const Text('Admin claim present'),
                  subtitle: Text(_adminClaimPresent ? 'true' : 'false'),
                ),
                ListTile(
                  title: const Text('Admin claim value'),
                  subtitle: Text(_adminClaimValue ? 'true' : 'false'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadAuthDiagnostics,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Osvježi token i provjeri claim'),
                ),
              ],
            );
          }

          if ((snapshot.hasData || snapshot.hasError) &&
              !_hasResolvedInitialState) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _hasResolvedInitialState = true;
              });
            });
          }

          final loadingTimedOut =
              !snapshot.hasData &&
              !snapshot.hasError &&
              DateTime.now().difference(_connectionLoadStartedAt) >=
                  _initialLoadTimeout;

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Nije moguće učitati status Google kalendara.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _describeError(snapshot.error!),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _retryConnectionLoad,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Pokušaj ponovno'),
                    ),
                  ],
                ),
              ),
            );
          }

          final connection = snapshot.data;

          if (!snapshot.hasData) {
            if (_forceDisconnectedFallback || loadingTimedOut) {
              final fallbackConnection = GoogleCalendarConnection.empty('');
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ListTile(
                    title: const Text('Status veze'),
                    subtitle: const Text('Nije povezano'),
                    trailing: const Icon(Icons.link_off, color: Colors.grey),
                  ),
                  const ListTile(
                    title: Text('Povezani Google račun'),
                    subtitle: Text('-'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _connect,
                          icon: const Icon(Icons.link),
                          label: const Text('Poveži Google račun'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: Icon(Icons.link_off),
                          label: Text('Odspoji račun'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const ListTile(
                    title: Text('Status učitavanja'),
                    subtitle: Text(
                      'Firebase error [deadline-exceeded]: Učitavanje statusa je trajalo dulje od 15 sekundi. Prikazano je sigurno fallback stanje.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _retryConnectionLoad,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Pokušaj ponovno'),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    title: const Text('Status sinkronizacije'),
                    subtitle: Text(
                      _syncStatusLabel(fallbackConnection.syncStatus),
                    ),
                  ),
                ],
              );
            }

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!loadingTimedOut)
                      const CircularProgressIndicator()
                    else
                      const Icon(
                        Icons.timer_off,
                        color: Colors.orange,
                        size: 36,
                      ),
                    const SizedBox(height: 12),
                    Text(
                      loadingTimedOut
                          ? 'Učitavanje statusa traje predugo (više od 15 sekundi).'
                          : 'Učitavanje statusa Google kalendara...',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ako dokument veze ne postoji, koristite Poveži Google račun. Ako postoji problem s pravima, pokušajte ponovno.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy ? null : _connect,
                      icon: const Icon(Icons.link),
                      label: const Text('Poveži Google račun'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _retryConnectionLoad,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Pokušaj ponovno'),
                    ),
                  ],
                ),
              ),
            );
          }

          final selectedCalendarId = connection!.selectedCalendarId;

          if (connection.connected &&
              _calendars.isEmpty &&
              !_loadingCalendars) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _refreshCalendars();
            });
          }

          final selected =
              _calendars
                  .where((item) => item.id == selectedCalendarId)
                  .isNotEmpty
              ? _calendars.firstWhere((item) => item.id == selectedCalendarId)
              : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                title: const Text('Status veze'),
                subtitle: Text(
                  connection.connected ? 'Povezano' : 'Nije povezano',
                ),
                trailing: connection.connected
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.link_off, color: Colors.grey),
              ),
              ListTile(
                title: const Text('Povezani Google račun'),
                subtitle: Text(
                  connection.googleAccountEmail.isEmpty
                      ? '-'
                      : connection.googleAccountEmail,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _connect,
                      icon: const Icon(Icons.link),
                      label: const Text('Poveži Google račun'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy || !connection.connected
                          ? null
                          : _disconnect,
                      icon: const Icon(Icons.link_off),
                      label: const Text('Odspoji račun'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: (_busy || !connection.connected || _loadingCalendars)
                    ? null
                    : _refreshCalendars,
                icon: const Icon(Icons.refresh),
                label: const Text('Osvježi kalendare'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GoogleCalendarOption>(
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Odabir kalendara',
                ),
                items: _calendars
                    .map(
                      (item) => DropdownMenuItem<GoogleCalendarOption>(
                        value: item,
                        child: Text(
                          item.primary ? '${item.name} (primarni)' : item.name,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (_busy || !connection.connected)
                    ? null
                    : (value) async {
                        if (value == null) return;
                        await widget.service.selectCalendar(value);
                      },
              ),
              const SizedBox(height: 12),
              ListTile(
                title: const Text('Zadnja sinkronizacija'),
                subtitle: Text(_formatDate(connection.lastSyncAt)),
              ),
              ListTile(
                title: const Text('Status sinkronizacije'),
                subtitle: Text(_syncStatusLabel(connection.syncStatus)),
              ),
              SwitchListTile(
                value: connection.autoSyncEnabled,
                onChanged: (_busy || !connection.connected)
                    ? null
                    : (value) => widget.service.setAutoSyncEnabled(value),
                title: const Text('Automatska sinkronizacija'),
              ),
              ListTile(
                title: const Text('Broj novih događaja'),
                trailing: Text(connection.newEventsCount.toString()),
              ),
              ListTile(
                title: const Text('Broj događaja koji trebaju provjeru'),
                trailing: Text(connection.needsReviewCount.toString()),
              ),
              if (connection.lastError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    connection.lastError,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy || !connection.connected ? null : _syncNow,
                icon: const Icon(Icons.sync),
                label: const Text('Sinkroniziraj sada'),
              ),
            ],
          );
        },
      ),
    );
  }
}
