
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );

  runApp(const ForzaApp());
}

const bg = Color(0xFF101318);
const panel = Color(0xFF202630);
const red = Color(0xFFEF5350);
const green = Color(0xFF4CAF50);

class ForzaApp extends StatelessWidget {
  const ForzaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FORZA 350 TUNER PRO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: red,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const TunerHome(),
    );
  }
}

class TunerHome extends StatefulWidget {
  const TunerHome({super.key});

  @override
  State<TunerHome> createState() => _TunerHomeState();
}

class _TunerHomeState extends State<TunerHome> {
  int tab = 0;
  int rpm = 5000;
  int tps = 40;

  bool saved = true;
  bool busy = false;

  double globalAdjust = 0;

  final rpms = [2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000];
  final tpsAxis = [0, 10, 20, 40, 60, 80, 100];

  late List<List<double>> fuel;
  late List<List<double>> ignition;

  final List<Map<String, dynamic>> undoStack = [];
  final List<Map<String, dynamic>> redoStack = [];

  @override
  void initState() {
    super.initState();

    fuel = List.generate(
      rpms.length,
      (_) => List.filled(tpsAxis.length, 100.0),
    );

    ignition = List.generate(
      rpms.length,
      (_) => List.filled(tpsAxis.length, 0.0),
    );

    _load();
  }

  List<List<double>> _copy(List<List<double>> source) {
    return source.map((r) => List<double>.from(r)).toList();
  }

  void _history() {
    undoStack.add({
      'fuel': _copy(fuel),
      'ignition': _copy(ignition),
    });

    if (undoStack.length > 30) {
      undoStack.removeAt(0);
    }

    redoStack.clear();
  }

  void _undo() {
    if (undoStack.isEmpty) return;

    redoStack.add({
      'fuel': _copy(fuel),
      'ignition': _copy(ignition),
    });

    final old = undoStack.removeLast();

    setState(() {
      fuel = _copy(old['fuel']);
      ignition = _copy(old['ignition']);
      saved = false;
    });
  }

  void _redo() {
    if (redoStack.isEmpty) return;

    undoStack.add({
      'fuel': _copy(fuel),
      'ignition': _copy(ignition),
    });

    final next = redoStack.removeLast();

    setState(() {
      fuel = _copy(next['fuel']);
      ignition = _copy(next['ignition']);
      saved = false;
    });
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();

    try {
      final f = p.getString('fuel_map_v2');
      final i = p.getString('ignition_map_v2');

      if (!mounted) return;

      setState(() {
        if (f != null) {
          fuel = _decodeMap(f);
        }

        if (i != null) {
          ignition = _decodeMap(i);
        }

        rpm = p.getInt('saved_rpm') ?? 5000;
        tps = p.getInt('saved_tps') ?? 40;
        saved = true;
      });

      _message('โหลดข้อมูลเรียบร้อย');
    } catch (_) {
      _message('ไม่สามารถโหลดข้อมูลได้');
    }
  }

  List<List<double>> _decodeMap(String value) {
    final decoded = jsonDecode(value) as List;

    return decoded.map((row) {
      return (row as List)
          .map((v) => (v as num).toDouble())
          .toList();
    }).toList();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();

      await p.setString('fuel_map_v2', jsonEncode(fuel));
      await p.setString('ignition_map_v2', jsonEncode(ignition));
      await p.setInt('saved_rpm', rpm);
      await p.setInt('saved_tps', tps);

      if (!mounted) return;

      setState(() => saved = true);
      _message('บันทึกข้อมูลลงโทรศัพท์เรียบร้อย');
    } catch (_) {
      _message('บันทึกไม่สำเร็จ');
    }
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<List<double>> _activeMap(bool isFuel) {
    return isFuel ? fuel : ignition;
  }

  String _unit(bool isFuel) {
    return isFuel ? '%' : '°';
  }

  double _min(bool isFuel) {
    return isFuel ? 0 : -20;
  }

  double _max(bool isFuel) {
    return isFuel ? 200 : 60;
  }

  Future<void> _editCell(
    int r,
    int c,
    bool isFuel,
  ) async {
    final data = _activeMap(isFuel);

    final controller = TextEditingController(
      text: data[r][c].toStringAsFixed(1),
    );

    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${isFuel ? "FUEL" : "IGNITION"} • '
          '${rpms[r]} RPM / ${tpsAxis[c]}% TPS',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: InputDecoration(
            labelText: 'ค่าจำลอง (${_unit(isFuel)})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                ctx,
                double.tryParse(controller.text),
              );
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );

    if (value == null || !mounted) return;

    _history();

    setState(() {
      data[r][c] = value.clamp(
        _min(isFuel),
        _max(isFuel),
      ).toDouble();

      saved = false;
    });
  }

  // คำนวณค่ารอบข้างแบบ Local interpolation
  void _interpolate(int r, int c, bool isFuel) {
    final data = _activeMap(isFuel);

    _history();

    final anchor = data[r][c];

    setState(() {
      for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
          if (x == 0 && y == 0) continue;

          final rr = r + y;
          final cc = c + x;

          if (rr < 0 ||
              rr >= rpms.length ||
              cc < 0 ||
              cc >= tpsAxis.length) {
            continue;
          }

          final distance = (x.abs() + y.abs()).toDouble();
          final factor = 0.45 / (distance + 0.5);

          data[rr][cc] =
              data[rr][cc] * (1 - factor) + anchor * factor;
        }
      }

      saved = false;
    });

    _message('คำนวณค่าโดยรอบแล้ว');
  }

  // Smooth map แบบ 3 x 3
  void _smooth(bool isFuel) {
    final data = _activeMap(isFuel);
    final old = _copy(data);

    _history();

    setState(() {
      for (int r = 1; r < rpms.length - 1; r++) {
        for (int c = 1; c < tpsAxis.length - 1; c++) {
          double total = 0;
          int count = 0;

          for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
              total += old[r + y][c + x];
              count++;
            }
          }

          data[r][c] = total / count;
        }
      }

      saved = false;
    });

    _message('Smooth Map เรียบร้อย');
  }

  // ปรับทั้งตารางด้วย Slider
  void _adjustAll(bool isFuel, double amount) {
    final data = _activeMap(isFuel);

    if (amount == 0) return;

    _history();

    setState(() {
      for (int r = 0; r < data.length; r++) {
        for (int c = 0; c < data[r].length; c++) {
          data[r][c] = (data[r][c] + amount).clamp(
            _min(isFuel),
            _max(isFuel),
          ).toDouble();
        }
      }

      saved = false;
    });
  }

  Widget _button(
    String text,
    IconData icon,
    VoidCallback action, {
    Color color = panel,
  }) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      onPressed: action,
      icon: Icon(icon, size: 17),
      label: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _sidebar() {
    final items = [
      (Icons.speed, 'DASHBOARD'),
      (Icons.local_gas_station, 'FUEL MAP'),
      (Icons.flash_on, 'IGNITION'),
      (Icons.bluetooth, 'BLUETOOTH'),
    ];

    return Container(
      width: 160,
      color: const Color(0xFF191E26),
      child: Column(
        children: [
          const SizedBox(height: 18),
          const Text(
            'FORZA 350',
            style: TextStyle(
              color: red,
              fontWeight: FontWeight.w900,
              fontSize: 19,
              letterSpacing: 1,
            ),
          ),
          const Text(
            'TUNER PRO',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 22),
          ...List.generate(items.length, (index) {
            final selected = tab == index;

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              child: ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: red.withOpacity(.18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                leading: Icon(
                  items[index].$1,
                  color: selected ? red : Colors.white60,
                  size: 20,
                ),
                title: Text(
                  items[index].$2,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                onTap: () => setState(() => tab = index),
              ),
            );
          }),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'SIMULATION ONLY',
              style: TextStyle(
                fontSize: 9,
                color: Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String title) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white12),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Icon(
            saved ? Icons.cloud_done : Icons.edit,
            size: 16,
            color: saved ? green : Colors.orange,
          ),
          const SizedBox(width: 6),
          Text(
            saved ? 'SAVED' : 'UNSAVED',
            style: const TextStyle(fontSize: 10),
          ),
          const SizedBox(width: 15),
          const Chip(
            label: Text(
              'SIMULATION',
              style: TextStyle(fontSize: 9),
            ),
            backgroundColor: Color(0xFF653A10),
          ),
        ],
      ),
    );
  }

  Widget _dashboard() {
    return Column(
      children: [
        _header('ENGINE DASHBOARD'),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Card(
                  color: panel,
                  margin: const EdgeInsets.all(12),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'ENGINE SPEED',
                          style: TextStyle(color: Colors.white60),
                        ),
                        Text(
                          '$rpm',
                          style: const TextStyle(
                            fontSize: 65,
                            fontWeight: FontWeight.w900,
                            color: red,
                          ),
                        ),
                        const Text(
                          'RPM',
                          style: TextStyle(letterSpacing: 4),
                        ),
                        SizedBox(
                          width: 240,
                          child: Slider(
                            value: rpm.toDouble(),
                            min: 1000,
                            max: 10000,
                            divisions: 90,
                            onChanged: (v) {
                              setState(() {
                                rpm = v.round();
                                saved = false;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _metric('TPS', '$tps%', red),
                      Slider(
                        value: tps.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 20,
                        onChanged: (v) {
                          setState(() {
                            tps = v.round();
                            saved = false;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      _metric(
                        'MODE',
                        'SIMULATION',
                        Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _button(
                              'SAVE',
                              Icons.save,
                              _save,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _button(
                              'LOAD',
                              Icons.folder_open,
                              _load,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Card(
      color: panel,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapPage(bool isFuel) {
    final data = _activeMap(isFuel);

    return Column(
      children: [
        _header(isFuel ? 'FUEL MAP EDITOR' : 'IGNITION MAP EDITOR'),

        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _button(
                  'SAVE',
                  Icons.save,
                  _save,
                  color: const Color(0xFF285D3A),
                ),
                const SizedBox(width: 6),
                _button('LOAD', Icons.folder_open, _load),
                const SizedBox(width: 6),
                _button('UNDO', Icons.undo, _undo),
                const SizedBox(width: 6),
                _button('REDO', Icons.redo, _redo),
                const SizedBox(width: 6),
                _button(
                  'SMOOTH MAP',
                  Icons.waves,
                  () => _smooth(isFuel),
                ),
              ],
            ),
          ),
        ),

        // Table
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  horizontalMargin: 12,
                  columnSpacing: 20,
                  dataRowMinHeight: 38,
                  dataRowMaxHeight: 44,
                  headingRowHeight: 40,
                  headingRowColor:
                      WidgetStateProperty.all(
                    const Color(0xFF303946),
                  ),
                  columns: [
                    const DataColumn(
                      label: Text(
                        'RPM / TPS',
                        style: TextStyle(color: red),
                      ),
                    ),
                    ...tpsAxis.map(
                      (v) => DataColumn(
                        label: Text('$v%'),
                      ),
                    ),
                  ],
                  rows: List.generate(rpms.length, (r) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            '${rpms[r]}',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...List.generate(tpsAxis.length, (c) {
                          return DataCell(
                            InkWell(
                              borderRadius: BorderRadius.circular(5),
                              onTap: () => _editCell(r, c, isFuel),
                              child: Container(
                                width: 62,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: data[r][c] > 0
                                      ? const Color(0xFF293747)
                                      : panel,
                                  borderRadius:
                                      BorderRadius.circular(5),
                                  border: Border.all(
                                    color: Colors.white10,
                                  ),
                                ),
                                child: Text(
                                  data[r][c].toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),

        // Group adjustment slider
        Container(
          color: const Color(0xFF1C222B),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 5,
          ),
          child: Row(
            children: [
              const Text(
                'GROUP ADJUST',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                ),
              ),
              Expanded(
                child: Slider(
                  value: globalAdjust,
                  min: -10,
                  max: 10,
                  divisions: 200,
                  onChanged: (v) {
                    final delta = v - globalAdjust;

                    setState(() {
                      globalAdjust = v;
                    });

                    if (delta.abs() > 0.0001) {
                      _adjustAll(isFuel, delta);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 55,
                child: Text(
                  '${globalAdjust.toStringAsFixed(1)}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Reset adjustment',
                onPressed: () {
                  setState(() => globalAdjust = 0);
                },
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),

        const Padding(
          padding: EdgeInsets.only(bottom: 5),
          child: Text(
            'แตะช่องเพื่อแก้ค่า • GROUP ADJUST ปรับทุกช่องพร้อมกัน',
            style: TextStyle(
              fontSize: 10,
              color: Colors.orange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _bluetooth() {
    return Column(
      children: [
        _header('BLUETOOTH STATUS'),
        const Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bluetooth_disabled,
                  size: 60,
                  color: Colors.blue,
                ),
                SizedBox(height: 12),
                Text(
                  'BLUETOOTH NOT CONNECTED',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Simulation only • No ECU communication',
                  style: TextStyle(color: Colors.orange),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _sidebar(),
            Expanded(
              child: IndexedStack(
                index: tab,
                children: [
                  _dashboard(),
                  _mapPage(true),
                  _mapPage(false),
                  _bluetooth(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
