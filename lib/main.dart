import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() => runApp(const GlobalTowerApp());

class GlobalTowerApp extends StatelessWidget {
  const GlobalTowerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);
    return MaterialApp(
      title: 'Global LTE Tower Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const GlobalLoginPage(),
    );
  }
}

Color rsrpColor(double? v) {
  if (v == null) return Colors.blueGrey;
  if (v >= -85) return const Color(0xFF16A34A);
  if (v >= -95) return const Color(0xFF65A30D);
  if (v >= -105) return const Color(0xFFD97706);
  if (v >= -115) return const Color(0xFFEA580C);
  return const Color(0xFFDC2626);
}

String rsrpLabel(double? v) {
  if (v == null) return 'No Signal';
  if (v >= -85) return 'Excellent';
  if (v >= -95) return 'Good';
  if (v >= -105) return 'Fair';
  if (v >= -115) return 'Poor';
  return 'Weak';
}

double rsrpFraction(double? v) {
  if (v == null) return 0.0;
  return ((v + 130) / 60).clamp(0.0, 1.0).toDouble();
}

double rsrqFraction(double? v) {
  if (v == null) return 0.0;
  return ((v + 25) / 22).clamp(0.0, 1.0).toDouble();
}

int? lteBandFromEarfcn(int n) {
  const ranges = <List<int>>[
    [0, 599, 1], [600, 1199, 2], [1200, 1949, 3], [1950, 2399, 4], [2400, 2649, 5],
    [2650, 2749, 6], [2750, 3449, 7], [3450, 3799, 8], [3800, 4149, 9], [4150, 4749, 10],
    [4750, 4949, 11], [5010, 5179, 12], [5180, 5279, 13], [5280, 5379, 14], [5730, 5849, 17],
    [5850, 5999, 18], [6000, 6149, 19], [6150, 6449, 20], [6450, 6599, 21], [6600, 7399, 22],
    [7500, 7699, 23], [7700, 8039, 24], [8040, 8689, 25], [8690, 9039, 26], [9040, 9209, 27],
    [9210, 9659, 28], [9660, 9769, 29], [9770, 9869, 30], [9870, 9919, 31], [9920, 10359, 32],
    [36000, 36199, 33], [36200, 36349, 34], [36350, 36949, 35], [36950, 37549, 36], [37550, 37749, 37],
    [37750, 38249, 38], [38250, 38649, 39], [38650, 39649, 40], [39650, 41589, 41], [41590, 43589, 42],
    [43590, 45589, 43], [45590, 46589, 44], [46590, 46789, 45], [46790, 54539, 46], [54540, 55239, 47],
    [55240, 56739, 48], [56740, 58239, 49], [58240, 59089, 50], [59090, 59139, 51], [59140, 60139, 52],
    [60140, 60254, 53], [65536, 66435, 65], [66436, 67335, 66], [67336, 67535, 67], [67536, 67835, 68],
    [67836, 68335, 69], [68336, 68585, 70], [68586, 68935, 71], [68936, 68985, 72], [68986, 69035, 73],
    [69036, 69465, 74], [69466, 70315, 75], [70316, 70365, 76], [70366, 70545, 85], [70546, 70595, 86],
    [70596, 70645, 87], [70646, 70695, 88],
  ];
  for (final r in ranges) {
    if (n >= r[0] && n <= r[1]) return r[2];
  }
  return null;
}

class CellTower {
  final int pci, earfcn;
  final double? rsrp, rsrq;
  final bool serving;
  const CellTower({
    required this.pci,
    required this.earfcn,
    this.rsrp,
    this.rsrq,
    this.serving = false,
  });
  int? get band => lteBandFromEarfcn(earfcn);
}

// ==================== واجهة تسجيل الدخول العالمية ====================

class GlobalLoginPage extends StatefulWidget {
  const GlobalLoginPage({super.key});

  @override
  State<GlobalLoginPage> createState() => _GlobalLoginPageState();
}

class _GlobalLoginPageState extends State<GlobalLoginPage> {
  final _store = const FlutterSecureStorage();
  final _hostCtrl = TextEditingController(text: '192.168.0.1');
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController();
  final _ttyCtrl = TextEditingController(text: '/tmp/dev/ttyUSB1');

  bool _obscure = true;
  bool _connecting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final h = await _store.read(key: 'g_host');
    final pt = await _store.read(key: 'g_port');
    final u = await _store.read(key: 'g_user');
    final p = await _store.read(key: 'g_pass');
    final tty = await _store.read(key: 'g_tty');
    if (!mounted) return;
    setState(() {
      if (h != null && h.isNotEmpty) _hostCtrl.text = h;
      if (pt != null && pt.isNotEmpty) _portCtrl.text = pt;
      if (u != null && u.isNotEmpty) _userCtrl.text = u;
      if (p != null) _passCtrl.text = p;
      if (tty != null && tty.isNotEmpty) _ttyCtrl.text = tty;
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _ttyCtrl.dispose();
    super.dispose();
  }

  Future<void> _connectGlobal() async {
    if (_connecting) return;
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final tty = _ttyCtrl.text.trim().isEmpty ? '/tmp/dev/ttyUSB1' : _ttyCtrl.text.trim();

    if (host.isEmpty || user.isEmpty) {
      setState(() => _errorText = 'Please enter Router IP/Host and SSH Username.');
      return;
    }

    setState(() {
      _connecting = true;
      _errorText = null;
    });

    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 8),
      );
      client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
      );
      await client.run('uname -a || echo ok').timeout(const Duration(seconds: 6));

      await _store.write(key: 'g_host', value: host);
      await _store.write(key: 'g_port', value: '$port');
      await _store.write(key: 'g_user', value: user);
      await _store.write(key: 'g_pass', value: pass);
      await _store.write(key: 'g_tty', value: tty);

      if (!mounted) {
        client.close();
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GlobalLiveDashboardPage(
            host: host,
            port: port,
            username: user,
            password: pass,
            modemDevice: tty,
            initialClient: client!,
          ),
        ),
      );
    } catch (e) {
      client?.close();
      if (mounted) {
        setState(() => _errorText = 'SSH connection failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withOpacity(0.15),
              cs.surface,
              cs.tertiaryContainer.withOpacity(0.16),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.symmetric(horizontal: 120),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cs.primary, cs.tertiary],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withOpacity(0.28),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.public, size: 42, color: Colors.white),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Global LTE Live Monitor',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Universal SSH telemetry • Instant charts • Band tower view',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 22),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: _hostCtrl,
                                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Host / IP',
                                      hintText: '192.168.0.1',
                                      prefixIcon: const Icon(Icons.dns_outlined),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 1,
                                  child: TextField(
                                    controller: _portCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Port',
                                      hintText: '22',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _userCtrl,
                              decoration: InputDecoration(
                                labelText: 'SSH Username',
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              onSubmitted: (_) => _connectGlobal(),
                              decoration: InputDecoration(
                                labelText: 'SSH Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure ? Icons.visibility : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _ttyCtrl,
                              decoration: InputDecoration(
                                labelText: 'Modem Port (Optional / Custom)',
                                hintText: '/tmp/dev/ttyUSB1',
                                prefixIcon: const Icon(Icons.settings_input_component),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            if (_errorText != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _errorText!,
                                  style: TextStyle(
                                    color: cs.onErrorContainer,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: FilledButton.icon(
                                onPressed: _connecting ? null : _connectGlobal,
                                icon: _connecting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.bolt),
                                label: Text(
                                  _connecting ? 'Connecting…' : 'Connect & Stream Live',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== لوحة المراقبة الفورية والمخططات ====================

class GlobalLiveDashboardPage extends StatefulWidget {
  final String host;
  final int port;
  final String username;
  final String password;
  final String modemDevice;
  final SSHClient initialClient;

  const GlobalLiveDashboardPage({
    super.key,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.modemDevice,
    required this.initialClient,
  });

  @override
  State<GlobalLiveDashboardPage> createState() => _GlobalLiveDashboardPageState();
}

class _GlobalLiveDashboardPageState extends State<GlobalLiveDashboardPage> {
  SSHClient? _ssh;
  Timer? _timer;
  bool _busy = false;
  bool _live = true;
  bool _reconnecting = false;
  int _intervalMs = 1500;
  int _lastLatencyMs = 0;

  int? _activeBand;
  int? _selectedBand;
  int? _servingPci;
  int? _servingEarfcn;
  String _status = 'Instant stream ready';
  DateTime? _lastUpdate;

  List<CellTower> _towers = [];
  final List<double> _rsrpHistory = [];
  final List<double> _rsrqHistory = [];
  final List<String> _events = [];

  @override
  void initState() {
    super.initState();
    _ssh = widget.initialClient;
    _pushEvent('Connected to ${widget.host}:${widget.port}');
    _pollNow();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ssh?.close();
    super.dispose();
  }

  void _pushEvent(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _events.insert(0, '[$ts] $msg');
    if (_events.length > 25) _events.removeLast();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!_live) return;
    _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) {
      if (!_busy && _live && mounted) {
        _pollNow();
      }
    });
  }

  Future<bool> _ensureSession() async {
    if (_ssh != null && !_ssh!.isClosed) return true;
    if (_reconnecting) return false;
    _reconnecting = true;
    try {
      _ssh?.close();
      final socket = await SSHSocket.connect(
        widget.host,
        widget.port,
        timeout: const Duration(seconds: 4),
      );
      _ssh = SSHClient(
        socket,
        username: widget.username,
        onPasswordRequest: () => widget.password,
      );
      _pushEvent('SSH session restored automatically');
      return true;
    } catch (_) {
      _ssh = null;
      return false;
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _pollNow() async {
    if (_busy || !mounted) return;
    _busy = true;
    final sw = Stopwatch()..start();

    try {
      final ready = await _ensureSession();
      if (!ready || _ssh == null) {
        if (mounted) {
          setState(() => _status = 'Reconnecting…');
        }
        return;
      }

      final dev = widget.modemDevice.replaceAll("'", "'\\''");
      final cmd =
          "printf 'AT+BMTCELLINFO;+BMNEICELLINFO;\$QCRSRP?;\$QCRSRQ?;+CEREG?;+COPS?\\r' | socat -t1 -T3 - file:$dev,raw,echo=0,b115200 2>&1";
      final bytes = await _ssh!.run(cmd).timeout(const Duration(seconds: 4));
      final out = utf8.decode(bytes, allowMalformed: true);
      sw.stop();

      final servingPci = _intField(out, 'PCI');
      final servingEarfcn = _intField(out, 'EARFCN');
      final band = _intField(out, 'ACTIVE BAND') ??
          (servingEarfcn == null ? null : lteBandFromEarfcn(servingEarfcn));

      final map = <String, CellTower>{};
      final re = RegExp(
        r'pci:(\d+),rsrq:(-?\d+),rsrp:(-?\d+),rssi:(-?\d+),srxlev:(-?\d+),earfcn:(\d+)',
      );
      for (final m in re.allMatches(out)) {
        final pci = int.parse(m[1]!);
        final earfcn = int.parse(m[6]!);
        map['$pci:$earfcn'] = CellTower(
          pci: pci,
          earfcn: earfcn,
          rsrq: double.tryParse(m[2]!),
          rsrp: double.tryParse(m[3]!),
          serving: pci == servingPci && earfcn == servingEarfcn,
        );
      }

      if (servingPci != null &&
          servingEarfcn != null &&
          !map.containsKey('$servingPci:$servingEarfcn')) {
        map['$servingPci:$servingEarfcn'] = CellTower(
          pci: servingPci,
          earfcn: servingEarfcn,
          rsrp: _doubleField(out, 'RSRP'),
          rsrq: _doubleField(out, 'RSRQ'),
          serving: true,
        );
      }

      final sorted = map.values.toList()
        ..sort((a, b) => (b.rsrp ?? -999).compareTo(a.rsrp ?? -999));

      CellTower? srv;
      for (final t in sorted) {
        if (t.serving) {
          srv = t;
          break;
        }
      }

      final rsrp = srv?.rsrp ?? _doubleField(out, 'RSRP');
      final rsrq = srv?.rsrq ?? _doubleField(out, 'RSRQ');

      if (rsrp != null) {
        _rsrpHistory.add(rsrp);
        if (_rsrpHistory.length > 80) _rsrpHistory.removeAt(0);
      }
      if (rsrq != null) {
        _rsrqHistory.add(rsrq);
        if (_rsrqHistory.length > 80) _rsrqHistory.removeAt(0);
      }

      if ((_activeBand != null && band != null && _activeBand != band) ||
          (_servingPci != null && servingPci != null && _servingPci != servingPci)) {
        _pushEvent(
          'Cell/Band changed -> Band: ${band != null ? 'B$band' : '—'}, PCI: ${servingPci ?? '—'}',
        );
      }

      if (!mounted) return;
      setState(() {
        _lastLatencyMs = sw.elapsedMilliseconds;
        _servingPci = servingPci;
        _servingEarfcn = servingEarfcn;
        _activeBand = band;
        _selectedBand ??= band;
        _towers = sorted;
        _lastUpdate = DateTime.now();
        _status = 'LIVE • ${_lastLatencyMs}ms';
      });
    } catch (e) {
      sw.stop();
      if (e.toString().contains('SSHStateError') || e.toString().contains('closed')) {
        _ssh?.close();
        _ssh = null;
      }
      if (mounted) {
        setState(() {
          _lastLatencyMs = sw.elapsedMilliseconds;
          _status = 'Syncing…';
        });
      }
    } finally {
      _busy = false;
    }
  }

  int? _intField(String s, String key) {
    final m = RegExp('^${RegExp.escape(key)}\\s*:\\s*(-?\\d+)', multiLine: true)
        .firstMatch(s);
    return m == null ? null : int.tryParse(m[1]!);
  }

  double? _doubleField(String s, String key) {
    final m = RegExp('^${RegExp.escape(key)}\\s*:\\s*(-?[\\d.]+)', multiLine: true)
        .firstMatch(s);
    return m == null ? null : double.tryParse(m[1]!);
  }

  void _copySnapshot() {
    final rsrp = _rsrpHistory.isNotEmpty ? _rsrpHistory.last.toStringAsFixed(1) : '—';
    final rsrq = _rsrqHistory.isNotEmpty ? _rsrqHistory.last.toStringAsFixed(1) : '—';
    final text = [
      'Host: ${widget.host}:${widget.port}',
      'Band: ${_activeBand != null ? 'B$_activeBand' : '—'}',
      'PCI: ${_servingPci ?? '—'}',
      'EARFCN: ${_servingEarfcn ?? '—'}',
      'RSRP: $rsrp dBm',
      'RSRQ: $rsrq dB',
    ].join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telemetry snapshot copied')),
    );
  }

  void _logout() {
    _timer?.cancel();
    _ssh?.close();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const GlobalLoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final targetBand = _selectedBand ?? _activeBand;

    // عرض الأبراج المرتبطة بالباند المحدد فقط
    final bandTowers = targetBand == null
        ? _towers
        : _towers.where((t) => t.band == targetBand).toList();

    final bands = <int>{
      if (_activeBand != null) _activeBand!,
      for (final t in _towers)
        if (t.band != null) t.band!,
    }.toList()
      ..sort();

    final latestRsrp = _rsrpHistory.isNotEmpty ? _rsrpHistory.last : null;
    final latestRsrq = _rsrqHistory.isNotEmpty ? _rsrqHistory.last : null;
    final sigColor = rsrpColor(latestRsrp);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Global LTE Live Monitor',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.host} • $_status',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Instant refresh now',
            icon: const Icon(Icons.sync),
            onPressed: _pollNow,
          ),
          IconButton(
            tooltip: _live ? 'Pause live stream' : 'Start live stream',
            icon: Icon(
              _live ? Icons.sensors : Icons.sensors_off,
              color: _live ? const Color(0xFF16A34A) : null,
            ),
            onPressed: () {
              setState(() {
                _live = !_live;
                _status = _live ? 'LIVE stream active' : 'Paused';
              });
              _restartTimer();
              if (_live) _pollNow();
            },
          ),
          IconButton(
            tooltip: 'Copy snapshot',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _copySnapshot,
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _pollNow,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // شريط سرعة التحديث الفوري
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.speed, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Poll Rate:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const Spacer(),
                    ...[
                      ('1.0s', 1000),
                      ('1.5s', 1500),
                      ('3.0s', 3000),
                    ].map((opt) {
                      final selected = _intervalMs == opt.$2;
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(opt.$1, style: const TextStyle(fontSize: 12)),
                          selected: selected,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() => _intervalMs = opt.$2);
                            _restartTimer();
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // بطاقة القراءات الرئيسية ومخطط RSRP الحي
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [sigColor.withOpacity(0.18), cs.surfaceContainerLow],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: sigColor.withOpacity(0.35)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cell_tower, color: sigColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Live RSRP Signal',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: sigColor.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          rsrpLabel(latestRsrp),
                          style: TextStyle(
                            color: sigColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        latestRsrp?.toStringAsFixed(1) ?? '—',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: sigColor,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('dBm', style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Band ${_activeBand != null ? 'B$_activeBand' : '—'} • PCI ${_servingPci ?? '—'}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            'EARFCN ${_servingEarfcn ?? '—'} • RSRQ ${latestRsrq?.toStringAsFixed(1) ?? '—'} dB',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: rsrpFraction(latestRsrp),
                      minHeight: 7,
                      color: sigColor,
                      backgroundColor: sigColor.withOpacity(0.15),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 115,
                    child: _MetricLineChart(
                      values: List<double>.of(_rsrpHistory),
                      minVal: -130,
                      maxVal: -60,
                      color: sigColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // مخطط جودة الإشارة RSRQ الحي
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.graphic_eq, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Live RSRQ Quality (-25 to -3 dB)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const Spacer(),
                        Text(
                          '${latestRsrq?.toStringAsFixed(1) ?? '—'} dB',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: rsrqFraction(latestRsrq),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 85,
                      child: _MetricLineChart(
                        values: List<double>.of(_rsrqHistory),
                        minVal: -25,
                        maxVal: -3,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // اختيار الباند لعرض الأبراج المشبوكة/المرتبطة به فقط
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.filter_list, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Selected Band Towers Filter',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                          ),
                        ),
                        if (targetBand != null)
                          Chip(
                            label: Text('Band B$targetBand'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (bands.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: bands.map((b) {
                          return ChoiceChip(
                            label: Text('B$b${b == _activeBand ? ' • Active' : ''}'),
                            selected: targetBand == b,
                            onSelected: (_) => setState(() => _selectedBand = b),
                          );
                        }).toList(),
                      )
                    else
                      Text(
                        'Detecting bands from modem…',
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // مخطط مقارنة الأبراج على الباند المحدد
            if (bandTowers.isNotEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Band ${targetBand != null ? 'B$targetBand' : ''} Tower RSRP Bars',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 115,
                        child: _TowerBarChart(towers: bandTowers),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // قائمة الأبراج على الباند المحدد فقط
            Text(
              'Towers on ${targetBand != null ? 'B$targetBand' : 'Current Band'} (${bandTowers.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
            ),
            const SizedBox(height: 8),

            if (bandTowers.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'No towers on ${targetBand != null ? 'Band B$targetBand' : 'selected band'} yet.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              )
            else
              ...bandTowers.map((t) {
                final c = rsrpColor(t.rsrp);
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: t.serving ? c.withOpacity(0.6) : cs.outlineVariant.withOpacity(0.4),
                      width: t.serving ? 1.5 : 1,
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: c.withOpacity(0.15),
                      child: Icon(
                        t.serving ? Icons.cell_tower : Icons.signal_cellular_alt,
                        color: c,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text('PCI ${t.pci}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        if (t.band != null)
                          Text(
                            'B${t.band}',
                            style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.bold),
                          ),
                        if (t.serving) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'SERVING',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: c),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      'EARFCN ${t.earfcn} • RSRP ${t.rsrp?.toStringAsFixed(1) ?? '—'} dBm • RSRQ ${t.rsrq?.toStringAsFixed(1) ?? '—'} dB',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                );
              }),

            const SizedBox(height: 12),

            // سجل الأحداث المباشر
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Event Stream',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    ..._events.take(6).map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              e,
                              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== المخططات البيانية ====================

class _MetricLineChart extends StatelessWidget {
  final List<double> values;
  final double minVal;
  final double maxVal;
  final Color color;

  const _MetricLineChart({
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LinePainter(
        values: values,
        minVal: minVal,
        maxVal: maxVal,
        color: color,
        gridColor: Theme.of(context).dividerColor.withOpacity(0.35),
      ),
      size: Size.infinite,
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final double minVal;
  final double maxVal;
  final Color color;
  final Color gridColor;

  _LinePainter({
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gp = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }

    if (values.isEmpty) return;
    if (values.length == 1) {
      final y = _yOf(values.first, size.height);
      canvas.drawCircle(Offset(size.width / 2, y), 4.5, Paint()..color = color);
      return;
    }

    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = _yOf(values[i], size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withOpacity(0.26), color.withOpacity(0.02)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final lx = dx * (values.length - 1);
    final ly = _yOf(values.last, size.height);
    canvas.drawCircle(Offset(lx, ly), 6, Paint()..color = color.withOpacity(0.24));
    canvas.drawCircle(Offset(lx, ly), 3.6, Paint()..color = color);
  }

  double _yOf(double val, double h) {
    final norm = ((val - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);
    return h * (1.0 - norm);
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) => true;
}

class _TowerBarChart extends StatelessWidget {
  final List<CellTower> towers;
  const _TowerBarChart({required this.towers});

  @override
  Widget build(BuildContext context) {
    final slice = towers.take(6).toList();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: slice.map((t) {
        final frac = rsrpFraction(t.rsrp);
        final c = rsrpColor(t.rsrp);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  t.rsrp?.toStringAsFixed(0) ?? '—',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: c),
                ),
                const SizedBox(height: 3),
                Container(
                  height: math.max(10.0, 66.0 * frac),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'PCI ${t.pci}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
