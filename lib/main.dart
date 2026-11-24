import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() => runApp(const TowerMasterApp());

class TowerMasterApp extends StatelessWidget {
  const TowerMasterApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DWR-921 Tower Master',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f9c)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff087f9c),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const DashboardPage(),
      );
}

Color rsrpColor(double? v) {
  if (v == null) return Colors.grey;
  if (v >= -85) return const Color(0xff2e9e4f);
  if (v >= -95) return const Color(0xff8bc34a);
  if (v >= -105) return const Color(0xfff2a900);
  if (v >= -115) return const Color(0xffef6c00);
  return const Color(0xffd32f2f);
}

String rsrpLabel(double? v) {
  if (v == null) return 'No signal data';
  if (v >= -85) return 'Excellent';
  if (v >= -95) return 'Good';
  if (v >= -105) return 'Fair';
  if (v >= -115) return 'Poor';
  return 'Very poor';
}

double rsrpFraction(double? v) {
  if (v == null) return 0.0;
  return ((v + 130) / 60).clamp(0.0, 1.0).toDouble();
}

class SignalChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  const SignalChart({super.key, required this.values, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ChartPainter(values, color, Theme.of(context).dividerColor),
        size: Size.infinite,
      );
}

class _ChartPainter extends CustomPainter {
  final List<double> v;
  final Color color, grid;
  _ChartPainter(this.v, this.color, this.grid);
  @override
  void paint(Canvas canvas, Size size) {
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }
    if (v.length < 2) return;
    const lo = -130.0, hi = -60.0;
    double yOf(double x) =>
        size.height * (1 - ((x - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble());
    final dx = size.width / (v.length - 1);
    final path = Path()..moveTo(0, yOf(v[0]));
    for (var i = 1; i < v.length; i++) {
      path.lineTo(dx * i, yOf(v[i]));
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withOpacity(0.15));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      Offset(dx * (v.length - 1), yOf(v.last)),
      4,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
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

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _store = const FlutterSecureStorage();
  final _host = TextEditingController(text: '192.168.0.1');
  final _user = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  SSHClient? _ssh;
  bool _busy = false, _connected = false, _sameBandOnly = false, _rebootAfter = false;
  String _message = 'Enter your router SSH details to connect.';
  int? _activeBand, _servingPci, _servingEarfcn, _selectedBand;
  List<CellTower> _towers = [];
  final List<double> _history = [];
  Timer? _timer;

  static const List<int> _commonBands = [1, 3, 5, 7, 8, 20, 28, 38, 40, 41];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    _host.text = await _store.read(key: 'host') ?? _host.text;
    _user.text = await _store.read(key: 'user') ?? _user.text;
    _password.text = await _store.read(key: 'password') ?? '';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ssh?.close();
    _host.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<String> _exec(String command, {Duration timeout = const Duration(seconds: 18)}) async {
    final ssh = _ssh;
    if (ssh == null) throw Exception('Not connected');
    final bytes = await ssh.run(command).timeout(timeout);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = 'Connecting to router…';
    });
    try {
      final socket = await SSHSocket.connect(
        _host.text.trim(),
        22,
        timeout: const Duration(seconds: 10),
      );
      final client = SSHClient(
        socket,
        username: _user.text.trim(),
        onPasswordRequest: () => _password.text,
      );
      _ssh?.close();
      _ssh = client;
      await _store.write(key: 'host', value: _host.text.trim());
      await _store.write(key: 'user', value: _user.text.trim());
      await _store.write(key: 'password', value: _password.text);
      if (!mounted) return;
      setState(() {
        _connected = true;
        _message = 'SSH connected. Reading modem…';
      });
      await _refresh();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!_busy && _connected) _refresh();
      });
    } catch (e) {
      _ssh?.close();
      _ssh = null;
      if (mounted) {
        setState(() {
          _connected = false;
          _message = 'Connection failed: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    _timer?.cancel();
    _ssh?.close();
    _ssh = null;
    if (mounted) {
      setState(() {
        _connected = false;
        _message = 'Disconnected';
      });
    }
  }

  Future<void> _refresh() async {
    if (_ssh == null || _busy) return;
    setState(() => _busy = true);
    try {
      const cmd =
          "printf 'AT+BMTCELLINFO;+BMNEICELLINFO;\$QCRSRP?;\$QCRSRQ?;+BMSETCELLID;+CEREG?;+COPS?;+BMBANDPREF?\\r' | socat -t2 -T7 - file:/tmp/dev/ttyUSB1,raw,echo=0,b115200 2>&1";
      final out = await _exec(cmd);
      final servingPci = _intField(out, 'PCI');
      final servingEarfcn = _intField(out, 'EARFCN');
      final band = _intField(out, 'ACTIVE BAND') ??
          (servingEarfcn == null ? null : lteBandFromEarfcn(servingEarfcn));
      final towers = <String, CellTower>{};
      final re = RegExp(
        r'pci:(\d+),rsrq:(-?\d+),rsrp:(-?\d+),rssi:(-?\d+),srxlev:(-?\d+),earfcn:(\d+)',
      );
      for (final m in re.allMatches(out)) {
        final pci = int.parse(m[1]!);
        final earfcn = int.parse(m[6]!);
        towers['$pci:$earfcn'] = CellTower(
          pci: pci,
          earfcn: earfcn,
          rsrq: double.tryParse(m[2]!),
          rsrp: double.tryParse(m[3]!),
          serving: pci == servingPci && earfcn == servingEarfcn,
        );
      }
      if (servingPci != null &&
          servingEarfcn != null &&
          !towers.containsKey('$servingPci:$servingEarfcn')) {
        towers['$servingPci:$servingEarfcn'] = CellTower(
          pci: servingPci,
          earfcn: servingEarfcn,
          rsrp: _doubleField(out, 'RSRP'),
          rsrq: _doubleField(out, 'RSRQ'),
          serving: true,
        );
      }
      final sorted = towers.values.toList()
        ..sort((a, b) => (b.rsrp ?? -999).compareTo(a.rsrp ?? -999));
      final srvList = sorted.where((t) => t.serving).toList();
      if (srvList.isNotEmpty && srvList.first.rsrp != null) {
        _history.add(srvList.first.rsrp!);
        if (_history.length > 60) _history.removeAt(0);
      }
      if (!mounted) return;
      setState(() {
        _servingPci = servingPci;
        _servingEarfcn = servingEarfcn;
        _activeBand = band;
        _towers = sorted;
        _message = 'Last update: ${DateTime.now().toLocal()}';
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'Read failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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

  Future<void> _sendAt(String command) async {
    if (_ssh == null) throw Exception('Connect first');
    if (!RegExp(r'^AT[A-Z0-9+=,;?]*$').hasMatch(command)) {
      throw Exception('Invalid AT command');
    }
    final escaped = command.replaceAll("'", "'\\''");
    final out = await _exec(
      "printf '${escaped}\\r' | socat -t3 -T8 - file:/tmp/dev/ttyUSB1,raw,echo=0,b115200 2>&1",
    );
    if (!RegExp(r'(^|\n)OK\b').hasMatch(out) || out.contains('ERROR')) {
      throw Exception('Modem rejected command: $out');
    }
  }

  Future<void> _lockBand(int? band) async {
    if (_ssh == null || _busy) return;
    setState(() {
      _busy = true;
      _message = band == null
          ? 'Resetting band preference to Auto…'
          : 'Locking LTE Band B$band…';
    });
    try {
      final String mask = band == null
          ? '0'
          : (BigInt.one << (band - 1)).toRadixString(16).toUpperCase();
      await _sendAt('AT+BMBANDPREF=0,$mask');
      if (mounted) {
        setState(() {
          _selectedBand = band;
          _message = band == null
              ? 'Band set to Auto (All Bands).'
              : 'Band B$band locked (mask: 0x$mask).';
        });
      }
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() => _busy = false);
        await _refresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Band lock failed: $e';
        });
      }
    }
  }

  Future<void> _rebootAndReconnect() async {
    if (mounted) setState(() => _message = 'Rebooting router…');
    try {
      await _exec('(sleep 2; reboot) >/dev/null 2>&1 &',
          timeout: const Duration(seconds: 8));
    } catch (_) {}
    _timer?.cancel();
    _ssh?.close();
    _ssh = null;
    if (mounted) {
      setState(() {
        _connected = false;
        _busy = false;
        _message = 'Router is rebooting. Reconnecting automatically…';
      });
    }
    await Future.delayed(const Duration(seconds: 45));
    for (var i = 1; i <= 20 && mounted && !_connected; i++) {
      await _connect();
      if (_connected) {
        if (mounted) setState(() => _message = 'Reconnected after reboot.');
        return;
      }
      if (mounted) setState(() => _message = 'Waiting for router… attempt $i/20');
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  Future<void> _lock(CellTower t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lock this tower?'),
        content:
            Text('Store PCI ${t.pci}, EARFCN ${t.earfcn} and enable the modem lock?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Send lock commands'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _message = 'Sending tower-lock commands…';
    });
    try {
      await _sendAt('AT+BMSETCELLID=1,${t.pci},${t.earfcn}');
      final verify = await _exec(
        "printf 'AT+BMSETCELLID\\r' | socat -t3 -T8 - file:/tmp/dev/ttyUSB1,raw,echo=0,b115200 2>&1",
      );
      if (!verify.contains('${t.pci},${t.earfcn}')) {
        throw Exception('Modem did not confirm stored tower. Response: $verify');
      }
      await _sendAt('AT+BMLOCKCELL=1');
      if (_rebootAfter) {
        await _rebootAndReconnect();
      } else if (mounted) {
        setState(() => _message = 'Lock stored for PCI ${t.pci}. Restart router if needed.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Lock failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove tower lock?'),
        content: const Text('Clear modem tower lock?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove lock'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _message = 'Removing lock…';
    });
    try {
      await _sendAt('AT+BMLOCKCELL=0');
      await _sendAt('AT+BMSETCELLID=1,0,0');
      if (_rebootAfter) {
        await _rebootAndReconnect();
      } else if (mounted) {
        setState(() => _message = 'Lock removal commands accepted.');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Unlock failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _sameBandOnly && _activeBand != null
        ? _towers.where((t) => t.band == _activeBand).toList()
        : _towers;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DWR-921 Tower & Band Master'),
        actions: [
          IconButton(
            onPressed: _connected && !_busy ? _refresh : null,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _connected ? _disconnect : null,
            icon: const Icon(Icons.link_off),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Router connection',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _host,
                      decoration: const InputDecoration(
                        labelText: 'Router IP / Host',
                        hintText: '192.168.0.1',
                      ),
                    ),
                    TextField(
                      controller: _user,
                      decoration: const InputDecoration(labelText: 'SSH username'),
                    ),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'SSH password'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                _busy ? null : (_connected ? _disconnect : _connect),
                            icon: Icon(_connected ? Icons.link_off : Icons.link),
                            label: Text(_connected ? 'Disconnect' : 'Connect'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _busy || !_connected ? null : _refresh,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_message, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            _bandLockCard(),
            _servingCard(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show towers on current band only'),
              subtitle: Text(
                _activeBand == null
                    ? 'Band not available yet'
                    : 'Filtering to LTE Band $_activeBand',
              ),
              value: _sameBandOnly,
              onChanged: (v) => setState(() => _sameBandOnly = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reboot router after tower lock/unlock'),
              subtitle: const Text('Reboots via SSH, then reconnects automatically'),
              value: _rebootAfter,
              onChanged: (v) => setState(() => _rebootAfter = v),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Detected towers (${visible.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: _connected && !_busy ? _unlock : null,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Remove lock'),
                ),
              ],
            ),
            if (visible.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No tower readings yet. Connect and refresh.'),
                ),
              ),
            ...visible.map(
              (t) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: rsrpColor(t.rsrp).withOpacity(0.15),
                    child: Icon(
                      t.serving ? Icons.cell_tower : Icons.signal_cellular_alt,
                      color: rsrpColor(t.rsrp),
                    ),
                  ),
                  title: Text(
                    'PCI ${t.pci}  •  ${t.band == null ? 'Unknown band' : 'B${t.band}'}',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EARFCN ${t.earfcn}  •  RSRP ${t.rsrp?.toStringAsFixed(1) ?? '—'} dBm  •  RSRQ ${t.rsrq?.toStringAsFixed(1) ?? '—'} dB${t.serving ? '  •  CONNECTED' : ''}',
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: rsrpFraction(t.rsrp),
                          minHeight: 6,
                          color: rsrpColor(t.rsrp),
                          backgroundColor: rsrpColor(t.rsrp).withOpacity(0.15),
                        ),
                      ),
                    ],
                  ),
                  trailing: t.serving
                      ? const Chip(label: Text('Serving'))
                      : IconButton(
                          tooltip: 'Lock tower',
                          onPressed: _connected && !_busy ? () => _lock(t) : null,
                          icon: const Icon(Icons.lock),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bandLockCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_input_antenna),
                const SizedBox(width: 8),
                Text('LTE Band Lock', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (_activeBand != null) Chip(label: Text('Active: B$_activeBand')),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Select a band to lock immediately, or choose Auto for all bands:'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Auto (All)'),
                  selected: _selectedBand == null,
                  onSelected: _connected && !_busy ? (_) => _lockBand(null) : null,
                ),
                ..._commonBands.map(
                  (b) => ChoiceChip(
                    label: Text('B$b'),
                    selected: _selectedBand == b,
                    onSelected: _connected && !_busy ? (_) => _lockBand(b) : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _servingCard() {
    final list = _towers.where((t) => t.serving).toList();
    final CellTower? srv = list.isEmpty ? null : list.first;
    final c = rsrpColor(srv?.rsrp);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c.withOpacity(0.18), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cell_tower, color: c),
                const SizedBox(width: 8),
                Text('Serving cell', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    rsrpLabel(srv?.rsrp),
                    style: TextStyle(color: c, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  srv?.rsrp?.toStringAsFixed(0) ?? '—',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: c,
                  ),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('dBm RSRP'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: rsrpFraction(srv?.rsrp),
                minHeight: 8,
                color: c,
                backgroundColor: c.withOpacity(0.15),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metric('Band', _activeBand == null ? '—' : 'B$_activeBand'),
                _metric('PCI', '${_servingPci ?? '—'}'),
                _metric('EARFCN', '${_servingEarfcn ?? '—'}'),
                _metric('RSRQ', srv?.rsrq == null ? '—' : '${srv!.rsrq!.toStringAsFixed(0)} dB'),
              ],
            ),
            const SizedBox(height: 14),
            Text('Signal history', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            SizedBox(
              height: 90,
              child: SignalChart(values: List<double>.of(_history), color: c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      );
}
