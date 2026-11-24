import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() => runApp(const CyberNocApp());

class CyberNocApp extends StatelessWidget {
  const CyberNocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DWR-921 Cyber NOC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFF7B2CBF),
          tertiary: Color(0xFFFF007F),
          surface: Color(0xFF111827),
          surfaceContainerHigh: Color(0xFF1E293B),
        ),
      ),
      home: const VibrantLoginPage(),
    );
  }
}

Color vibrantSignalColor(double? rsrp) {
  if (rsrp == null) return const Color(0xFF64748B);
  if (rsrp >= -85) return const Color(0xFF00F5D4);
  if (rsrp >= -95) return const Color(0xFF38BDF8);
  if (rsrp >= -105) return const Color(0xFFFBBF24);
  if (rsrp >= -115) return const Color(0xFFFB7185);
  return const Color(0xFFFF2A5F);
}

String signalGrade(double? rsrp) {
  if (rsrp == null) return 'OFFLINE';
  if (rsrp >= -85) return 'ULTRA';
  if (rsrp >= -95) return 'STRONG';
  if (rsrp >= -105) return 'MODERATE';
  if (rsrp >= -115) return 'WEAK';
  return 'CRITICAL';
}

double rsrpNorm(double? v) =>
    v == null ? 0.0 : ((v + 130) / 60).clamp(0.0, 1.0).toDouble();

double rsrqNorm(double? v) =>
    v == null ? 0.0 : ((v + 25) / 22).clamp(0.0, 1.0).toDouble();

double sinrNorm(double? v) =>
    v == null ? 0.0 : ((v + 5) / 35).clamp(0.0, 1.0).toDouble();

double? estimateMbps(double? rsrp, double? rsrq, double? sinr) {
  if (rsrp == null) return null;
  final pNorm = ((rsrp + 125) / 55).clamp(0.0, 1.0);
  final qNorm = rsrq == null ? 0.65 : ((rsrq + 22) / 18).clamp(0.05, 1.0);
  final sNorm = sinr == null ? 0.6 : ((sinr + 5) / 30).clamp(0.1, 1.0);
  final score = math.pow(pNorm, 1.2) * (0.3 + 0.4 * qNorm + 0.3 * sNorm);
  return double.parse((2.0 + score * 138.0).toStringAsFixed(1));
}

int? bandFromEarfcn(int n) {
  const ranges = <List<int>>[
    [0, 599, 1], [600, 1199, 2], [1200, 1949, 3], [1950, 2399, 4], [2400, 2649, 5],
    [2750, 3449, 7], [3450, 3799, 8], [3800, 4149, 9], [4150, 4749, 10],
    [5010, 5179, 12], [5180, 5279, 13], [5730, 5849, 17], [6150, 6449, 20],
    [9210, 9659, 28], [37750, 38249, 38], [38650, 39649, 40], [39650, 41589, 41],
    [41590, 43589, 42], [43590, 45589, 43],
  ];
  for (final r in ranges) {
    if (n >= r[0] && n <= r[1]) return r[2];
  }
  return null;
}

class TowerNode {
  final int pci, earfcn;
  final double? rsrp, rsrq, sinr;
  final bool serving;
  const TowerNode({
    required this.pci,
    required this.earfcn,
    this.rsrp,
    this.rsrq,
    this.sinr,
    this.serving = false,
  });
  int? get band => bandFromEarfcn(earfcn);
  double? get mbps => estimateMbps(rsrp, rsrq, sinr);
}

class LanClient {
  final String ip, mac, name;
  const LanClient({required this.ip, required this.mac, required this.name});
}

class VibrantLoginPage extends StatefulWidget {
  const VibrantLoginPage({super.key});

  @override
  State<VibrantLoginPage> createState() => _VibrantLoginPageState();
}

class _VibrantLoginPageState extends State<VibrantLoginPage>
    with SingleTickerProviderStateMixin {
  final _store = const FlutterSecureStorage();
  final _hostCtrl = TextEditingController(text: '192.168.0.1');
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController();
  final _ttyCtrl = TextEditingController(text: '/tmp/dev/ttyUSB1');

  late final AnimationController _pulseCtrl;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _restoreSaved();
  }

  Future<void> _restoreSaved() async {
    final h = await _store.read(key: 'noc_host');
    final pt = await _store.read(key: 'noc_port');
    final u = await _store.read(key: 'noc_user');
    final p = await _store.read(key: 'noc_pass');
    final tty = await _store.read(key: 'noc_tty');
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
    _pulseCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _ttyCtrl.dispose();
    super.dispose();
  }

  Future<void> _launchNoc() async {
    if (_loading) return;
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final tty = _ttyCtrl.text.trim().isEmpty ? '/tmp/dev/ttyUSB1' : _ttyCtrl.text.trim();

    if (host.isEmpty || user.isEmpty) {
      setState(() => _error = 'يرجى إدخال عنوان الـ IP واسم المستخدم');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
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
      await client.run('echo OK').timeout(const Duration(seconds: 6));

      await _store.write(key: 'noc_host', value: host);
      await _store.write(key: 'noc_port', value: '$port');
      await _store.write(key: 'noc_user', value: user);
      await _store.write(key: 'noc_pass', value: pass);
      await _store.write(key: 'noc_tty', value: tty);

      if (!mounted) {
        client.close();
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CyberNocDashboard(
            host: host,
            port: port,
            username: user,
            password: pass,
            modemTty: tty,
            initialClient: client!,
          ),
        ),
      );
    } catch (e) {
      client?.close();
      if (mounted) {
        setState(() => _error = 'فشل الاتصال بالراوتر: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF090D16),
              Color(0xFF131B3A),
              Color(0xFF0B2536),
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
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) {
                        final glow = 14.0 + (_pulseCtrl.value * 16.0);
                        return Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00F5D4), Color(0xFF7B2CBF)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00F5D4).withOpacity(0.45),
                                blurRadius: glow,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: const Icon(Icons.radar, size: 46, color: Color(0xFF090D16)),
                    ),
                    const SizedBox(height: 18),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF00F5D4), Color(0xFF38BDF8), Color(0xFFFF007F)],
                      ).createShader(bounds),
                      child: const Text(
                        'DWR-921 CYBER NOC',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Hardware C3 • Firmware 4.0.2 Live Telemetry',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827).withOpacity(0.88),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFF00F5D4).withOpacity(0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7B2CBF).withOpacity(0.22),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _hostCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Router IP',
                                    prefixIcon: const Icon(Icons.router, color: Color(0xFF00F5D4)),
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
                              prefixIcon: const Icon(Icons.person, color: Color(0xFF38BDF8)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passCtrl,
                            obscureText: _obscure,
                            onSubmitted: (_) => _launchNoc(),
                            decoration: InputDecoration(
                              labelText: 'SSH Password',
                              prefixIcon: const Icon(Icons.key, color: Color(0xFFFF007F)),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
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
                              labelText: 'Modem Serial Port',
                              prefixIcon: const Icon(Icons.memory, color: Color(0xFFFBBF24)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF2A5F).withOpacity(0.18),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFF2A5F)),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Color(0xFFFF8FA3), fontSize: 12),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF00F5D4), Color(0xFF38BDF8), Color(0xFF7B2CBF)],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _loading ? null : _launchNoc,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: const Color(0xFF090D16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                icon: _loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Color(0xFF090D16),
                                        ),
                                      )
                                    : const Icon(Icons.bolt, size: 22),
                                label: Text(
                                  _loading ? 'CONNECTING...' : 'LAUNCH LIVE NOC',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
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
        ),
      ),
    );
  }
}

class CyberNocDashboard extends StatefulWidget {
  final String host;
  final int port;
  final String username;
  final String password;
  final String modemTty;
  final SSHClient initialClient;

  const CyberNocDashboard({
    super.key,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.modemTty,
    required this.initialClient,
  });

  @override
  State<CyberNocDashboard> createState() => _CyberNocDashboardState();
}

class _CyberNocDashboardState extends State<CyberNocDashboard>
    with SingleTickerProviderStateMixin {
  SSHClient? _ssh;
  Timer? _timer;
  late final AnimationController _liveDotCtrl;

  bool _busy = false;
  bool _live = true;
  bool _reconnecting = false;
  bool _recoveringData = false;
  int _pollMs = 1200;
  int _latencyMs = 0;

  int? _activeBand;
  int? _selectedBand;
  int? _servingPci;
  int? _servingEarfcn;
  String _cellHexId = '—';
  int? _enbId;
  int? _sectorId;
  String _operatorName = 'LTE';
  double _ramUsagePct = 0.0;

  double _liveDownMbps = 0.0;
  double _liveUpMbps = 0.0;
  int? _prevRxBytes;
  int? _prevTxBytes;
  DateTime? _prevTrafficTime;

  List<TowerNode> _towers = [];
  List<LanClient> _clients = [];
  final List<double> _rsrpHist = [];
  final List<double> _rsrqHist = [];
  final List<double> _sinrHist = [];
  final List<String> _feed = [];

  @override
  void initState() {
    super.initState();
    _ssh = widget.initialClient;
    _liveDotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _addFeed('NOC Linked -> ${widget.host}');
    _tick();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _liveDotCtrl.dispose();
    _ssh?.close();
    super.dispose();
  }

  void _addFeed(String msg) {
    final now = DateTime.now();
    final t =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _feed.insert(0, '$t  $msg');
    if (_feed.length > 30) _feed.removeLast();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_live) return;
    _timer = Timer.periodic(Duration(milliseconds: _pollMs), (_) {
      if (!_busy && _live && mounted) _tick();
    });
  }

  Future<bool> _ensureSsh() async {
    if (_ssh != null && !_ssh!.isClosed) return true;
    if (_reconnecting) return false;
    _reconnecting = true;
    try {
      _ssh?.close();
      final s = await SSHSocket.connect(
        widget.host,
        widget.port,
        timeout: const Duration(seconds: 4),
      );
      _ssh = SSHClient(
        s,
        username: widget.username,
        onPasswordRequest: () => widget.password,
      );
      _addFeed('Auto-reconnected SSH tunnel');
      return true;
    } catch (_) {
      _ssh = null;
      return false;
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _tick() async {
    if (_busy || !mounted) return;
    _busy = true;
    final sw = Stopwatch()..start();

    try {
      final ok = await _ensureSsh();
      if (!ok || _ssh == null) return;

      final dev = widget.modemTty.replaceAll("'", "'\\''");
      final cmd = '''
printf 'AT+CEREG=2;+BMTCELLINFO;+BMNEICELLINFO;\$QCRSRP?;\$QCRSRQ?;\$QCSNR?;+CEREG?;+COPS?\\r' | socat -t1 -T3 - file:$dev,raw,echo=0,b115200 2>&1
echo "===NET==="
cat /proc/net/dev 2>/dev/null | grep -E "usb0|wwan0|eth2\\.2" | head -n 1
echo "===MEM==="
free 2>/dev/null | grep Mem
echo "===ARP==="
cat /proc/net/arp 2>/dev/null | grep -v "00:00:00:00:00:00" | tail -n +2
''';

      final bytes = await _ssh!.run(cmd).timeout(const Duration(seconds: 5));
      final raw = utf8.decode(bytes, allowMalformed: true);
      sw.stop();

      final parts = raw.split('===NET===');
      final modemOut = parts[0];
      final rest1 = parts.length > 1 ? parts[1] : '';
      final netParts = rest1.split('===MEM===');
      final netLine = netParts[0].trim();
      final rest2 = netParts.length > 1 ? netParts[1] : '';
      final memParts = rest2.split('===ARP===');
      final memBlock = memParts[0].trim();
      final arpBlock = memParts.length > 1 ? memParts[1].trim() : '';

      final pci = _intField(modemOut, 'PCI');
      final earfcn = _intField(modemOut, 'EARFCN');
      final band = _intField(modemOut, 'ACTIVE BAND') ??
          (earfcn == null ? null : bandFromEarfcn(earfcn));

      final ceregMatch =
          RegExp(r'\+CEREG:\s*\d+,\d+,"([0-9A-Fa-f]+)","([0-9A-Fa-f]+)"')
              .firstMatch(modemOut);
      String hexCid = _cellHexId;
      int? enb = _enbId;
      int? sec = _sectorId;
      if (ceregMatch != null) {
        hexCid = ceregMatch[2]!.toUpperCase();
        final cidDec = int.tryParse(hexCid, radix: 16);
        if (cidDec != null) {
          enb = cidDec >> 8;
          sec = cidDec & 0xFF;
        }
      }

      final copsMatch = RegExp(r'\+COPS:\s*\d+,\d+,"([^"]+)"').firstMatch(modemOut);
      final opName = copsMatch != null ? copsMatch[1]! : _operatorName;

      double? sinrVal = _doubleField(modemOut, 'SINR') ?? _doubleField(modemOut, 'SNR');
      final qcsnrMatch = RegExp(r'\$QCSNR:\s*(-?[\d.]+)').firstMatch(modemOut);
      if (qcsnrMatch != null) {
        sinrVal ??= double.tryParse(qcsnrMatch[1]!);
      }

      final map = <String, TowerNode>{};
      final re = RegExp(
        r'pci:(\d+),rsrq:(-?\d+),rsrp:(-?\d+),rssi:(-?\d+),srxlev:(-?\d+),earfcn:(\d+)',
      );
      for (final m in re.allMatches(modemOut)) {
        final tPci = int.parse(m[1]!);
        final tEarfcn = int.parse(m[6]!);
        final isSrv = tPci == pci && tEarfcn == earfcn;
        map['$tPci:$tEarfcn'] = TowerNode(
          pci: tPci,
          earfcn: tEarfcn,
          rsrq: double.tryParse(m[2]!),
          rsrp: double.tryParse(m[3]!),
          sinr: isSrv ? sinrVal : null,
          serving: isSrv,
        );
      }

      if (pci != null && earfcn != null && !map.containsKey('$pci:$earfcn')) {
        map['$pci:$earfcn'] = TowerNode(
          pci: pci,
          earfcn: earfcn,
          rsrp: _doubleField(modemOut, 'RSRP'),
          rsrq: _doubleField(modemOut, 'RSRQ'),
          sinr: sinrVal,
          serving: true,
        );
      }

      final sortedTowers = map.values.toList()
        ..sort((a, b) => (b.rsrp ?? -999).compareTo(a.rsrp ?? -999));

      TowerNode? srv;
      for (final t in sortedTowers) {
        if (t.serving) {
          srv = t;
          break;
        }
      }

      final rsrp = srv?.rsrp ?? _doubleField(modemOut, 'RSRP');
      final rsrq = srv?.rsrq ?? _doubleField(modemOut, 'RSRQ');

      if (rsrp != null) {
        _rsrpHist.add(rsrp);
        if (_rsrpHist.length > 60) _rsrpHist.removeAt(0);
      }
      if (rsrq != null) {
        _rsrqHist.add(rsrq);
        if (_rsrqHist.length > 60) _rsrqHist.removeAt(0);
      }
      if (sinrVal != null) {
        _sinrHist.add(sinrVal);
        if (_sinrHist.length > 60) _sinrHist.removeAt(0);
      }

      double downMbps = _liveDownMbps;
      double upMbps = _liveUpMbps;
      if (netLine.contains(':')) {
        final afterColon = netLine.split(':')[1].trim();
        final nums = afterColon.split(RegExp(r'\s+'));
        if (nums.length >= 9) {
          final rxBytes = int.tryParse(nums[0]);
          final txBytes = int.tryParse(nums[8]);
          final now = DateTime.now();
          if (rxBytes != null &&
              txBytes != null &&
              _prevRxBytes != null &&
              _prevTxBytes != null &&
              _prevTrafficTime != null) {
            final dtSec = now.difference(_prevTrafficTime!).inMilliseconds / 1000.0;
            if (dtSec > 0.1) {
              final dRx = math.max(0, rxBytes - _prevRxBytes!);
              final dTx = math.max(0, txBytes - _prevTxBytes!);
              downMbps = (dRx * 8.0) / (dtSec * 1000000.0);
              upMbps = (dTx * 8.0) / (dtSec * 1000000.0);
            }
          }
          _prevRxBytes = rxBytes;
          _prevTxBytes = txBytes;
          _prevTrafficTime = now;
        }
      }

      double ramPct = _ramUsagePct;
      for (final line in memBlock.split('\n')) {
        if (line.startsWith('Mem:')) {
          final cols = line.split(RegExp(r'\s+'));
          if (cols.length >= 3) {
            final tot = double.tryParse(cols[1]) ?? 1;
            final used = double.tryParse(cols[2]) ?? 0;
            ramPct = (used / tot).clamp(0.0, 1.0);
          }
        }
      }

      final parsedClients = <LanClient>[];
      for (final line in arpBlock.split('\n')) {
        final cols = line.trim().split(RegExp(r'\s+'));
        if (cols.length >= 4 && cols[0].contains('.')) {
          parsedClients.add(
            LanClient(ip: cols[0], mac: cols[3].toUpperCase(), name: cols.last),
          );
        }
      }

      if (_servingPci != null && pci != null && _servingPci != pci) {
        _addFeed('⚡ Handover: PCI $_servingPci -> PCI $pci (B${band ?? '?'})');
      }

      if (!mounted) return;
      setState(() {
        _latencyMs = sw.elapsedMilliseconds;
        _servingPci = pci;
        _servingEarfcn = earfcn;
        _activeBand = band;
        _selectedBand ??= band;
        _cellHexId = hexCid;
        _enbId = enb;
        _sectorId = sec;
        _operatorName = opName;
        _towers = sortedTowers;
        _liveDownMbps = downMbps;
        _liveUpMbps = upMbps;
        _ramUsagePct = ramPct;
        _clients = parsedClients;
      });
    } catch (e) {
      sw.stop();
      if (e.toString().contains('SSHStateError') || e.toString().contains('closed')) {
        _ssh?.close();
        _ssh = null;
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _safeRefreshDataSession() async {
    if (_recoveringData) return;
    setState(() => _recoveringData = true);
    _addFeed('Refreshing LTE PDP data session safely…');
    try {
      final ok = await _ensureSsh();
      if (ok && _ssh != null) {
        final dev = widget.modemTty.replaceAll("'", "'\\''");
        await _ssh!
            .run("printf 'AT+CGACT=0,1\\r' | socat -t1 -T2 - file:$dev,raw,echo=0,b115200")
            .timeout(const Duration(seconds: 4));
        await Future.delayed(const Duration(seconds: 1));
        await _ssh!
            .run("printf 'AT+CGACT=1,1\\r' | socat -t1 -T2 - file:$dev,raw,echo=0,b115200")
            .timeout(const Duration(seconds: 4));
        _addFeed('✅ Data session reactivated (No Band Lock)');
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      _addFeed('Session refresh note: $e');
    } finally {
      if (mounted) setState(() => _recoveringData = false);
      _tick();
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

  @override
  Widget build(BuildContext context) {
    final targetBand = _selectedBand ?? _activeBand;
    final filteredTowers = targetBand == null
        ? _towers
        : _towers.where((t) => t.band == targetBand).toList();

    final bands = <int>{
      if (_activeBand != null) _activeBand!,
      for (final t in _towers)
        if (t.band != null) t.band!,
    }.toList()
      ..sort();

    final rsrp = _rsrpHist.isNotEmpty ? _rsrpHist.last : null;
    final rsrq = _rsrqHist.isNotEmpty ? _rsrqHist.last : null;
    final sinr = _sinrHist.isNotEmpty ? _sinrHist.last : null;
    final sigColor = vibrantSignalColor(rsrp);
    final estCapMbps = estimateMbps(rsrp, rsrq, sinr);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1322),
        title: Row(
          children: [
            AnimatedBuilder(
              animation: _liveDotCtrl,
              builder: (_, __) => Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _live ? const Color(0xFF00F5D4) : Colors.grey,
                  boxShadow: _live
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00F5D4)
                                .withOpacity(0.4 + 0.5 * _liveDotCtrl.value),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_operatorName • Band ${_activeBand != null ? 'B$_activeBand' : '—'}',
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${widget.host} • ${_latencyMs}ms • eNB ${_enbId ?? '—'}:${_sectorId ?? '—'}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _live ? 'Pause Live' : 'Resume Live',
            icon: Icon(
              _live ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: const Color(0xFF00F5D4),
            ),
            onPressed: () {
              setState(() => _live = !_live);
              _startTimer();
              if (_live) _tick();
            },
          ),
          IconButton(
            tooltip: 'Safe Data Reconnect',
            icon: _recoveringData
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.healing, color: Color(0xFFFBBF24)),
            onPressed: _safeRefreshDataSession,
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: Color(0xFFFF007F)),
            onPressed: () {
              _timer?.cancel();
              _ssh?.close();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const VibrantLoginPage()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _tick,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF7B2CBF).withOpacity(0.28),
                    const Color(0xFF00F5D4).withOpacity(0.14),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF7B2CBF).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Color(0xFFFBBF24), size: 20),
                  const SizedBox(width: 6),
                  const Text(
                    'LIVE PULSE:',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  const Spacer(),
                  ...[
                    ('0.8s', 800),
                    ('1.2s', 1200),
                    ('2.5s', 2500),
                  ].map((e) {
                    final sel = _pollMs == e.$2;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text(
                          e.$1,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: sel ? const Color(0xFF090D16) : Colors.white,
                          ),
                        ),
                        selected: sel,
                        selectedColor: const Color(0xFF00F5D4),
                        backgroundColor: const Color(0xFF1E293B),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setState(() => _pollMs = e.$2);
                          _startTimer();
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    sigColor.withOpacity(0.22),
                    const Color(0xFF111827),
                    const Color(0xFF1E1B4B),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: sigColor.withOpacity(0.55), width: 1.4),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: sigColor.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sigColor),
                        ),
                        child: Text(
                          signalGrade(rsrp),
                          style: TextStyle(
                            color: sigColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'PCI ${_servingPci ?? '—'} • EARFCN ${_servingEarfcn ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        'CID $_cellHexId',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _NeonGauge(
                        label: 'RSRP',
                        valueText: rsrp?.toStringAsFixed(0) ?? '—',
                        unit: 'dBm',
                        fraction: rsrpNorm(rsrp),
                        color: sigColor,
                      ),
                      _NeonGauge(
                        label: 'RSRQ',
                        valueText: rsrq?.toStringAsFixed(0) ?? '—',
                        unit: 'dB',
                        fraction: rsrqNorm(rsrq),
                        color: const Color(0xFF38BDF8),
                      ),
                      _NeonGauge(
                        label: 'SINR',
                        valueText: sinr?.toStringAsFixed(1) ?? '—',
                        unit: 'dB',
                        fraction: sinrNorm(sinr),
                        color: const Color(0xFFFF007F),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090D16).withOpacity(0.65),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SpeedPill(
                          icon: Icons.download_rounded,
                          label: 'LIVE DL',
                          val: '${_liveDownMbps.toStringAsFixed(2)} Mbps',
                          color: const Color(0xFF00F5D4),
                        ),
                        _SpeedPill(
                          icon: Icons.upload_rounded,
                          label: 'LIVE UL',
                          val: '${_liveUpMbps.toStringAsFixed(2)} Mbps',
                          color: const Color(0xFFFF007F),
                        ),
                        _SpeedPill(
                          icon: Icons.speed_rounded,
                          label: 'TOWER CAP',
                          val: estCapMbps != null ? '~${estCapMbps.toStringAsFixed(0)}M' : '—',
                          color: const Color(0xFFFBBF24),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.show_chart, color: Color(0xFF00F5D4), size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'REAL-TIME RSRP WAVEFORM',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        '${rsrp?.toStringAsFixed(1) ?? '—'} dBm',
                        style: TextStyle(
                          color: sigColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 110,
                    child: _GlowWaveChart(
                      values: List<double>.of(_rsrpHist),
                      minVal: -130,
                      maxVal: -60,
                      color: sigColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFFF007F).withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cell_tower, color: Color(0xFFFF007F), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'BAND ${targetBand != null ? 'B$targetBand' : ''} TOWERS (${filteredTowers.length})',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      const Spacer(),
                      if (bands.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          children: bands.map((b) {
                            final isSel = targetBand == b;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedBand = b),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? const Color(0xFFFF007F)
                                      : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'B$b',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: isSel ? Colors.white : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (filteredTowers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Scanning towers on selected band…',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                        ),
                      ),
                    )
                  else
                    ...filteredTowers.map((t) {
                      final tc = vibrantSignalColor(t.rsrp);
                      final speed = t.mbps;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withOpacity(0.75),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: t.serving ? tc : tc.withOpacity(0.25),
                            width: t.serving ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: tc.withOpacity(0.2),
                              child: Icon(
                                t.serving ? Icons.wifi_tethering : Icons.cell_tower,
                                color: tc,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'PCI ${t.pci}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (t.serving)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: tc.withOpacity(0.22),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'ACTIVE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                              color: tc,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'RSRP ${t.rsrp?.toStringAsFixed(0) ?? '—'} dBm • RSRQ ${t.rsrq?.toStringAsFixed(0) ?? '—'} dB',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (speed != null)
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      tc.withOpacity(0.25),
                                      const Color(0xFF7B2CBF).withOpacity(0.25),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: tc.withOpacity(0.6)),
                                ),
                                child: Text(
                                  '~${speed.toStringAsFixed(1)} Mbps',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    color: tc,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.devices, color: Color(0xFFFBBF24), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'CONNECTED DEVICES (${_clients.length})',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        'RAM ${(_ramUsagePct * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Color(0xFF00F5D4), fontSize: 11.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_clients.isEmpty)
                    const Text(
                      'No active LAN clients parsed yet',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    )
                  else
                    ..._clients.map(
                      (c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.circle, size: 8, color: Color(0xFF00F5D4)),
                            const SizedBox(width: 8),
                            Text(c.ip,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12.5)),
                            const Spacer(),
                            Text(c.mac,
                                style: const TextStyle(
                                    color: Color(0xFF94A3B8), fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LIVE TELEMETRY FEED',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Color(0xFF38BDF8)),
                  ),
                  const SizedBox(height: 6),
                  ..._feed.take(5).map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            e,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeonGauge extends StatelessWidget {
  final String label;
  final String valueText;
  final String unit;
  final double fraction;
  final Color color;

  const _NeonGauge({
    required this.label,
    required this.valueText,
    required this.unit,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: CircularProgressIndicator(
              value: fraction,
              strokeWidth: 7,
              backgroundColor: color.withOpacity(0.16),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
              ),
              Text(
                valueText,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, color: color, height: 1.1),
              ),
              Text(
                unit,
                style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String val;
  final Color color;

  const _SpeedPill({
    required this.icon,
    required this.label,
    required this.val,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8))),
            Text(
              val,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: color),
            ),
          ],
        ),
      ],
    );
  }
}

class _GlowWaveChart extends StatelessWidget {
  final List<double> values;
  final double minVal;
  final double maxVal;
  final Color color;

  const _GlowWaveChart({
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GlowWavePainter(
        values: values,
        minVal: minVal,
        maxVal: maxVal,
        color: color,
      ),
      size: Size.infinite,
    );
  }
}

class _GlowWavePainter extends CustomPainter {
  final List<double> values;
  final double minVal;
  final double maxVal;
  final Color color;

  _GlowWavePainter({
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (values.isEmpty) return;
    if (values.length == 1) {
      final y = _yOf(values.first, size.height);
      canvas.drawCircle(Offset(size.width / 2, y), 5, Paint()..color = color);
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
          colors: [color.withOpacity(0.35), color.withOpacity(0.0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );

    final lx = dx * (values.length - 1);
    final ly = _yOf(values.last, size.height);
    canvas.drawCircle(Offset(lx, ly), 7, Paint()..color = color.withOpacity(0.3));
    canvas.drawCircle(Offset(lx, ly), 4, Paint()..color = Colors.white);
  }

  double _yOf(double val, double h) {
    final norm = ((val - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);
    return h * (1.0 - norm);
  }

  @override
  bool shouldRepaint(covariant _GlowWavePainter oldDelegate) => true;
}
