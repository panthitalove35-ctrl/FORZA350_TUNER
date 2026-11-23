
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ForzaRemapStudio());
}

// ============================================================
// FORZA REMAP STUDIO
// Local map editor - ECU communication not implemented
// ============================================================

const Color bg = Color(0xFF0B0F14);
const Color panel = Color(0xFF151C25);
const Color panel2 = Color(0xFF1C2632);
const Color blue = Color(0xFF258BFF);
const Color cyan = Color(0xFF36C9E8);
const Color green = Color(0xFF39C982);
const Color orange = Color(0xFFFFB74D);
const Color red = Color(0xFFEF5350);
const Color muted = Color(0xFF8C9AAA);

final List<int> rpmAxis =
    List<int>.generate(35, (i) => 1500 + i * 250);
final List<int> tpsAxis =
    List<int>.generate(51, (i) => i * 2);

enum MapType { fuel, ignition, afr }
enum GraphMode { twoD, threeD }

class ForzaRemapStudio extends StatelessWidget {
  const ForzaRemapStudio({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FORZA REMAP STUDIO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: blue,
          secondary: cyan,
          surface: panel,
        ),
        useMaterial3: true,
      ),
      home: const StudioHome(),
    );
  }
}

class StudioHome extends StatefulWidget {
  const StudioHome({super.key});

  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  int page = 0;
  MapType activeMap = MapType.fuel;
  GraphMode graphMode = GraphMode.twoD;

  late List<List<double>> fuelMap;
  late List<List<double>> ignitionMap;
  late List<List<double>> afrMap;

  bool saved = true;
  bool rangeSelectMode = false;
  bool autoScrollEnabled = true;

  double zoom = 1.0;
  double graphRotation = 0;

  String orientationMode = 'Auto Rotate';

  int? selectionStartRow;
  int? selectionStartCol;
  int? selectionEndRow;
  int? selectionEndCol;

  final ScrollController mapHorizontalController =
      ScrollController();
  final ScrollController mapVerticalController =
      ScrollController();

  final GlobalKey mapViewportKey = GlobalKey();
  final GlobalKey mapContentKey = GlobalKey();

  Timer? autoScrollTimer;
  Offset? lastPointerGlobal;
  Offset? lastPointerLocal;

  final List<List<List<List<double>>>> undoStack = [];
  final List<List<List<List<double>>>> redoStack = [];

  @override
  void initState() {
    super.initState();
    fuelMap = _createMap(100);
    ignitionMap = _createMap(0);
    afrMap = _createMap(14.7);
    _loadMaps();
    _loadSettings();
  }

  @override
  void dispose() {
    autoScrollTimer?.cancel();
    mapHorizontalController.dispose();
    mapVerticalController.dispose();
    super.dispose();
  }

  List<List<double>> _createMap(double value) {
    return List.generate(
      35,
      (_) => List.generate(51, (_) => value),
    );
  }

  List<List<double>> _copyMap(List<List<double>> source) {
    return source.map((r) => List<double>.from(r)).toList();
  }

  List<List<List<double>>> _snapshot() => [
        _copyMap(fuelMap),
        _copyMap(ignitionMap),
        _copyMap(afrMap),
      ];

  void _restoreSnapshot(List<List<List<double>>> snapshot) {
    fuelMap = _copyMap(snapshot[0]);
    ignitionMap = _copyMap(snapshot[1]);
    afrMap = _copyMap(snapshot[2]);
  }

  List<List<double>> _map(MapType type) {
    switch (type) {
      case MapType.fuel:
        return fuelMap;
      case MapType.ignition:
        return ignitionMap;
      case MapType.afr:
        return afrMap;
    }
  }

  String _mapName(MapType type) {
    switch (type) {
      case MapType.fuel:
        return 'FUEL MAP';
      case MapType.ignition:
        return 'IGNITION MAP';
      case MapType.afr:
        return 'AFR TARGET MAP';
    }
  }

  String _mapUnit(MapType type) {
    switch (type) {
      case MapType.fuel:
        return '%';
      case MapType.ignition:
        return '°';
      case MapType.afr:
        return 'AFR';
    }
  }

  double _minimum(MapType type) {
    switch (type) {
      case MapType.fuel:
        return 0;
      case MapType.ignition:
        return -40;
      case MapType.afr:
        return 8;
    }
  }

  double _maximum(MapType type) {
    switch (type) {
      case MapType.fuel:
        return 250;
      case MapType.ignition:
        return 80;
      case MapType.afr:
        return 25;
    }
  }

  void _history() {
    undoStack.add(_snapshot());
    if (undoStack.length > 30) undoStack.removeAt(0);
    redoStack.clear();
  }

  void _undo() {
    if (undoStack.isEmpty) return;
    setState(() {
      redoStack.add(_snapshot());
      _restoreSnapshot(undoStack.removeLast());
      saved = false;
    });
  }

  void _redo() {
    if (redoStack.isEmpty) return;
    setState(() {
      undoStack.add(_snapshot());
      _restoreSnapshot(redoStack.removeLast());
      saved = false;
    });
  }

  Future<void> _saveMaps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fuel_map_v2', jsonEncode(fuelMap));
    await prefs.setString(
        'ignition_map_v2', jsonEncode(ignitionMap));
    await prefs.setString('afr_map_v1', jsonEncode(afrMap));

    if (!mounted) return;
    setState(() => saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('บันทึกแผนที่เรียบร้อย')),
    );
  }

  Future<void> _loadMaps() async {
    final prefs = await SharedPreferences.getInstance();

    List<List<double>> readMap(String key, double fallback) {
      final raw = prefs.getString(key);
      if (raw == null) return _createMap(fallback);

      try {
        final decoded = jsonDecode(raw) as List;
        if (decoded.length != 35) return _createMap(fallback);

        return decoded.map<List<double>>((row) {
          final values = (row as List)
              .map((v) => (v as num).toDouble())
              .toList();
          if (values.length != 51) {
            throw const FormatException('Invalid map size');
          }
          return values;
        }).toList();
      } catch (_) {
        return _createMap(fallback);
      }
    }

    if (!mounted) return;
    setState(() {
      fuelMap = readMap('fuel_map_v2', 100);
      ignitionMap = readMap('ignition_map_v2', 0);
      afrMap = readMap('afr_map_v1', 14.7);
      saved = true;
    });
  }

  // ==========================================================
  // SETTINGS
  // ==========================================================

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('orientation_mode') ?? 'Auto Rotate';
    final savedZoom = prefs.getDouble('map_zoom') ?? 1.0;

    if (!mounted) return;
    setState(() {
      orientationMode = mode;
      zoom = savedZoom.clamp(0.65, 1.5).toDouble();
    });

    await _applyOrientation(mode);
  }

  Future<void> _saveOrientation(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('orientation_mode', mode);
    if (!mounted) return;

    setState(() => orientationMode = mode);
    await _applyOrientation(mode);
  }

  Future<void> _applyOrientation(String mode) async {
    if (mode == 'Portrait') {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } else if (mode == 'Landscape') {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  Future<void> _saveZoom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('map_zoom', zoom);
  }

  void _changeZoom(double amount) {
    setState(() {
      zoom = (zoom + amount).clamp(0.65, 1.5).toDouble();
    });
    _saveZoom();
  }

  // ==========================================================
  // CELL EDIT
  // ==========================================================

  Future<void> _editCell(int row, int col) async {
    final data = _map(activeMap);
    final controller = TextEditingController(
      text: data[row][col].toStringAsFixed(2),
    );

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: panel,
        title: Text(
          'แก้ไข ${_mapName(activeMap)}',
          style: const TextStyle(color: cyan),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RPM: ${rpmAxis[row]}'),
            Text('TPS: ${tpsAxis[col]}%'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: 'ค่าใหม่ (${_mapUnit(activeMap)})',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null) Navigator.pop(context, value);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    if (result == null) return;
    _history();

    setState(() {
      data[row][col] = result
          .clamp(_minimum(activeMap), _maximum(activeMap))
          .toDouble();
      saved = false;
    });
  }

  // ==========================================================
  // RANGE SELECTION
  // ==========================================================

  int get selectedCellCount {
    if (selectionStartRow == null ||
        selectionStartCol == null ||
        selectionEndRow == null ||
        selectionEndCol == null) {
      return 0;
    }

    final rows =
        (selectionEndRow! - selectionStartRow!).abs() + 1;
    final cols =
        (selectionEndCol! - selectionStartCol!).abs() + 1;
    return rows * cols;
  }

  int get minSelectedRow =>
      math.min(selectionStartRow!, selectionEndRow!);

  int get maxSelectedRow =>
      math.max(selectionStartRow!, selectionEndRow!);

  int get minSelectedCol =>
      math.min(selectionStartCol!, selectionEndCol!);

  int get maxSelectedCol =>
      math.max(selectionStartCol!, selectionEndCol!);

  bool _isSelected(int row, int col) {
    if (selectedCellCount == 0) return false;
    return row >= minSelectedRow &&
        row <= maxSelectedRow &&
        col >= minSelectedCol &&
        col <= maxSelectedCol;
  }

  void _selectCell(int row, int col) {
    setState(() {
      selectionStartRow = row;
      selectionStartCol = col;
      selectionEndRow = row;
      selectionEndCol = col;
    });
  }

  void _clearSelection() {
    setState(() {
      selectionStartRow = null;
      selectionStartCol = null;
      selectionEndRow = null;
      selectionEndCol = null;
    });
  }

  double _selectionAverage() {
    if (selectedCellCount == 0) return 0;

    final data = _map(activeMap);
    double total = 0;
    int count = 0;

    for (int r = minSelectedRow; r <= maxSelectedRow; r++) {
      for (int c = minSelectedCol; c <= maxSelectedCol; c++) {
        total += data[r][c];
        count++;
      }
    }
    return count == 0 ? 0 : total / count;
  }

  void _selectFromGlobal(Offset globalPosition) {
    final box = mapContentKey.currentContext?.findRenderObject()
        as RenderBox?;
    if (box == null || !box.hasSize) return;

    final p = box.globalToLocal(globalPosition);

    final rpmWidth = 78.0 * zoom;
    final cellWidth = 48.0 * zoom;
    final headerHeight = 34.0 * zoom;
    final rowHeight = 31.0 * zoom;

    if (p.dx < rpmWidth || p.dy < headerHeight) return;

    final col = ((p.dx - rpmWidth) / cellWidth)
        .floor()
        .clamp(0, 50)
        .toInt();

    final row = ((p.dy - headerHeight) / rowHeight)
        .floor()
        .clamp(0, 34)
        .toInt();

    if (selectionStartRow == null) {
      _selectCell(row, col);
    } else {
      setState(() {
        selectionEndRow = row;
        selectionEndCol = col;
      });
    }
  }

  void _startSelectionPointer(PointerEvent event) {
    if (!rangeSelectMode) return;

    lastPointerGlobal = event.position;
    lastPointerLocal = event.localPosition;

    final box = mapContentKey.currentContext?.findRenderObject()
        as RenderBox?;
    if (box == null) return;

    final p = box.globalToLocal(event.position);
    final rpmWidth = 78.0 * zoom;
    final headerHeight = 34.0 * zoom;

    if (p.dx < rpmWidth || p.dy < headerHeight) return;

    final col = ((p.dx - rpmWidth) / (48.0 * zoom))
        .floor()
        .clamp(0, 50)
        .toInt();
    final row = ((p.dy - headerHeight) / (31.0 * zoom))
        .floor()
        .clamp(0, 34)
        .toInt();

    _selectCell(row, col);
    _startAutoScroll();
  }

  void _moveSelectionPointer(PointerEvent event) {
    if (!rangeSelectMode || selectionStartRow == null) return;
    lastPointerGlobal = event.position;
    lastPointerLocal = event.localPosition;
    _selectFromGlobal(event.position);
  }

  void _endSelectionPointer(PointerEvent event) {
    _stopAutoScroll();
    lastPointerGlobal = null;
    lastPointerLocal = null;
  }

  // Auto scroll while dragging near the visible edges.
  void _startAutoScroll() {
    if (!autoScrollEnabled || autoScrollTimer != null) return;

    autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) {
        if (!mounted ||
            !rangeSelectMode ||
            lastPointerLocal == null) {
          return;
        }

        final viewport = mapViewportKey.currentContext
            ?.findRenderObject() as RenderBox?;

        if (viewport == null || !viewport.hasSize) return;

        final p = lastPointerLocal!;
        final width = viewport.size.width;
        final height = viewport.size.height;

        const edge = 45.0;
        const step = 28.0;

        if (p.dx < edge && mapHorizontalController.hasClients) {
          final next = (mapHorizontalController.offset - step)
              .clamp(
                0.0,
                mapHorizontalController.position.maxScrollExtent,
              )
              .toDouble();
          mapHorizontalController.jumpTo(next);
        } else if (p.dx > width - edge &&
            mapHorizontalController.hasClients) {
          final next = (mapHorizontalController.offset + step)
              .clamp(
                0.0,
                mapHorizontalController.position.maxScrollExtent,
              )
              .toDouble();
          mapHorizontalController.jumpTo(next);
        }

        if (p.dy < edge && mapVerticalController.hasClients) {
          final next = (mapVerticalController.offset - step)
              .clamp(
                0.0,
                mapVerticalController.position.maxScrollExtent,
              )
              .toDouble();
          mapVerticalController.jumpTo(next);
        } else if (p.dy > height - edge &&
            mapVerticalController.hasClients) {
          final next = (mapVerticalController.offset + step)
              .clamp(
                0.0,
                mapVerticalController.position.maxScrollExtent,
              )
              .toDouble();
          mapVerticalController.jumpTo(next);
        }

        if (lastPointerGlobal != null) {
          _selectFromGlobal(lastPointerGlobal!);
        }
      },
    );
  }

  void _stopAutoScroll() {
    autoScrollTimer?.cancel();
    autoScrollTimer = null;
  }

  void _applyAverage() {
    if (selectedCellCount == 0) return;
    final average = _selectionAverage();
    final data = _map(activeMap);
    _history();

    setState(() {
      for (int r = minSelectedRow; r <= maxSelectedRow; r++) {
        for (int c = minSelectedCol; c <= maxSelectedCol; c++) {
          data[r][c] = average;
        }
      }
      saved = false;
    });
  }

  void _applyRangeInterpolation() {
    if (selectedCellCount < 2) return;

    final data = _map(activeMap);
    _history();

    setState(() {
      final r1 = minSelectedRow;
      final r2 = maxSelectedRow;
      final c1 = minSelectedCol;
      final c2 = maxSelectedCol;

      if (c1 != c2) {
        for (int r = r1; r <= r2; r++) {
          final start = data[r][c1];
          final end = data[r][c2];

          for (int c = c1; c <= c2; c++) {
            final t = (c - c1) / (c2 - c1);
            data[r][c] = start + (end - start) * t;
          }
        }
      } else if (r1 != r2) {
        final start = data[r1][c1];
        final end = data[r2][c1];

        for (int r = r1; r <= r2; r++) {
          final t = (r - r1) / (r2 - r1);
          data[r][c1] = start + (end - start) * t;
        }
      }
      saved = false;
    });
  }

  Future<void> _applyMath(String operation) async {
    if (selectedCellCount == 0) return;

    final controller = TextEditingController();

    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: panel,
        title: Text('ปรับค่า: $operation'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: const InputDecoration(
            labelText: 'ใส่ตัวเลข',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              final n = double.tryParse(controller.text);
              if (n != null) Navigator.pop(context, n);
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );

    if (value == null) return;

    final data = _map(activeMap);
    _history();

    setState(() {
      for (int r = minSelectedRow; r <= maxSelectedRow; r++) {
        for (int c = minSelectedCol; c <= maxSelectedCol; c++) {
          double result = data[r][c];
          if (operation == '+') result += value;
          if (operation == '-') result -= value;
          if (operation == '×') result *= value;

          data[r][c] = result
              .clamp(_minimum(activeMap), _maximum(activeMap))
              .toDouble();
        }
      }
      saved = false;
    });
  }

  void _smoothSelection() {
    if (selectedCellCount == 0) return;

    final data = _map(activeMap);
    final old = _copyMap(data);
    _history();

    setState(() {
      for (int r = minSelectedRow; r <= maxSelectedRow; r++) {
        for (int c = minSelectedCol; c <= maxSelectedCol; c++) {
          double total = 0;
          int count = 0;

          for (int dr = -1; dr <= 1; dr++) {
            for (int dc = -1; dc <= 1; dc++) {
              final rr = r + dr;
              final cc = c + dc;

              if (rr >= minSelectedRow &&
                  rr <= maxSelectedRow &&
                  cc >= minSelectedCol &&
                  cc <= maxSelectedCol) {
                total += old[rr][cc];
                count++;
              }
            }
          }

          if (count > 0) data[r][c] = total / count;
        }
      }
      saved = false;
    });
  }

  // ==========================================================
  // MAIN UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _sidebar(),
            Expanded(
              child: Container(
                color: bg,
                child: _content(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar() {
    final items = [
      ['Dashboard', Icons.dashboard],
      ['Fuel Map', Icons.local_gas_station],
      ['Ignition Map', Icons.bolt],
      ['AFR Target', Icons.speed],
      ['Graph', Icons.show_chart],
      ['Data Logger', Icons.analytics],
      ['File Manager', Icons.folder],
      ['ECU Connection', Icons.bluetooth],
      ['Settings', Icons.settings],
    ];

    return Container(
      width: 155,
      color: panel,
      child: Column(
        children: [
          const SizedBox(height: 18),
          const Icon(Icons.memory, color: blue, size: 32),
          const SizedBox(height: 8),
          const Text(
            'FORZA',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          const Text(
            'REMAP STUDIO',
            style: TextStyle(
              fontSize: 10,
              color: cyan,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: panel2),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final selected = page == index;
                return InkWell(
                  onTap: () {
                    _stopAutoScroll();
                    setState(() {
                      page = index;
                      if (index == 1) activeMap = MapType.fuel;
                      if (index == 2) activeMap = MapType.ignition;
                      if (index == 3) activeMap = MapType.afr;
                      rangeSelectMode = false;
                      _clearSelection();
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? blue.withOpacity(0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: selected
                          ? Border.all(color: blue.withOpacity(0.7))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          items[index][1] as IconData,
                          size: 17,
                          color: selected ? cyan : muted,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            items[index][0] as String,
                            style: TextStyle(
                              fontSize: 11,
                              color: selected ? Colors.white : muted,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              'LOCAL EDITOR\nNO ECU LINK',
              textAlign: TextAlign.center,
              style: TextStyle(color: orange, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    switch (page) {
      case 0:
        return _dashboard();
      case 1:
      case 2:
      case 3:
        return _mapEditor();
      case 4:
        return _graphPage();
      case 5:
        return _infoPage(
          'DATA LOGGER',
          'ระบบบันทึกข้อมูลการทำงาน\nยังไม่มีข้อมูลจาก ECU จริง',
          Icons.analytics,
        );
      case 6:
        return _fileManager();
      case 7:
        return _ecuPage();
      default:
        return _settingsPage();
    }
  }

  Widget _header(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            saved ? Icons.cloud_done : Icons.edit_note,
            color: saved ? green : orange,
          ),
          const SizedBox(width: 5),
          Text(
            saved ? 'SAVED' : 'UNSAVED',
            style: TextStyle(
              color: saved ? green : orange,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'DASHBOARD',
          'FORZA REMAP STUDIO  |  PROFESSIONAL ECU',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _statusCard(
                      'ENGINE',
                      'FORZA 350',
                      Icons.motorcycle,
                      cyan,
                    ),
                    const SizedBox(width: 10),
                    _statusCard(
                      'MAP SIZE',
                      '35 × 51',
                      Icons.grid_on,
                      blue,
                    ),
                    const SizedBox(width: 10),
                    _statusCard(
                      'CELLS',
                      '1,785',
                      Icons.table_chart,
                      green,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: panel2),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MAP CONFIGURATION',
                        style: TextStyle(
                          color: cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 15),
                      Text('RPM: 1,500 – 10,000 / 250 RPM'),
                      SizedBox(height: 7),
                      Text('TPS: 0 – 100% / 2%'),
                      SizedBox(height: 7),
                      Text('Fuel Map: 1,785 cells'),
                      SizedBox(height: 7),
                      Text('Ignition Map: 1,785 cells'),
                      SizedBox(height: 7),
                      Text('AFR Target Map: 1,785 cells'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: orange.withOpacity(0.08),
                    border: Border.all(
                      color: orange.withOpacity(0.5),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'คำเตือน: ค่านี้เป็นข้อมูลตัวอย่างสำหรับแก้ไขแผนที่ในแอปเท่านั้น '
                    'ยังไม่ได้เชื่อมต่อ ECU จริง และไม่ใช่ค่าจูนที่รับรองความปลอดภัย',
                    style: TextStyle(color: orange, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: panel2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 9, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rangeButton(
    String label,
    IconData icon,
    VoidCallback action,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton.icon(
        onPressed: selectedCellCount == 0 ? null : action,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 10)),
        style: OutlinedButton.styleFrom(
          foregroundColor: cyan,
          padding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 8,
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  // ==========================================================
  // MAP EDITOR WITH ZOOM AND AUTO SCROLL
  // ==========================================================

  Widget _mapEditor() {
    final data = _map(activeMap);
    final rpmWidth = 78.0 * zoom;
    final cellWidth = 48.0 * zoom;
    final headerHeight = 34.0 * zoom;
    final rowHeight = 31.0 * zoom;
    final canSelectRange = activeMap != MapType.afr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          _mapName(activeMap),
          '35 RPM POINTS × 51 TPS POINTS',
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 7,
            children: [
              _mapChip('FUEL', MapType.fuel),
              _mapChip('IGNITION', MapType.ignition),
              _mapChip('AFR TARGET', MapType.afr),
            ],
          ),
        ),

        const SizedBox(height: 5),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              FilterChip(
                label: Text(
                  rangeSelectMode ? 'RANGE ON' : 'RANGE SELECT',
                  style: const TextStyle(fontSize: 10),
                ),
                selected: rangeSelectMode,
                selectedColor: blue.withOpacity(0.3),
                onSelected: canSelectRange
                    ? (value) {
                        _stopAutoScroll();
                        setState(() {
                          rangeSelectMode = value;
                          _clearSelection();
                        });
                      }
                    : null,
              ),
              const SizedBox(width: 6),
              if (rangeSelectMode) ...[
                _rangeButton(
                  'AVERAGE',
                  Icons.functions,
                  _applyAverage,
                ),
                _rangeButton(
                  'INTERPOLATE',
                  Icons.linear_scale,
                  _applyRangeInterpolation,
                ),
                _rangeButton(
                  'SMOOTH',
                  Icons.blur_on,
                  _smoothSelection,
                ),
                PopupMenuButton<String>(
                  tooltip: 'Math',
                  enabled: selectedCellCount > 0,
                  onSelected: _applyMath,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: '+',
                      child: Text('Add (+)'),
                    ),
                    PopupMenuItem(
                      value: '-',
                      child: Text('Subtract (-)'),
                    ),
                    PopupMenuItem(
                      value: '×',
                      child: Text('Multiply (×)'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Icon(Icons.calculate, color: cyan, size: 18),
                        SizedBox(width: 4),
                        Text('MATH'),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearSelection,
                  child: const Text('CLEAR'),
                ),
              ],
              IconButton(
                tooltip: 'Zoom out',
                onPressed: () => _changeZoom(-0.1),
                icon: const Icon(Icons.zoom_out),
              ),
              Text(
                '${(zoom * 100).round()}%',
                style: const TextStyle(
                  color: cyan,
                  fontSize: 10,
                ),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: () => _changeZoom(0.1),
                icon: const Icon(Icons.zoom_in),
              ),
              IconButton(
                tooltip: 'Reset zoom',
                onPressed: () {
                  setState(() => zoom = 1.0);
                  _saveZoom();
                },
                icon: const Icon(Icons.fit_screen),
              ),
              IconButton(
                tooltip: 'Undo',
                onPressed: undoStack.isEmpty ? null : _undo,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: redoStack.isEmpty ? null : _redo,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: 'Save',
                onPressed: _saveMaps,
                icon: const Icon(Icons.save, color: green),
              ),
            ],
          ),
        ),

        if (rangeSelectMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'เลือกแล้ว $selectedCellCount ช่อง'
                    '${selectedCellCount > 0 ? '  |  เฉลี่ย ${_selectionAverage().toStringAsFixed(2)}' : ''}',
                    style: const TextStyle(
                      color: cyan,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Text(
                  'AUTO SCROLL',
                  style: TextStyle(color: muted, fontSize: 9),
                ),
                Switch(
                  value: autoScrollEnabled,
                  onChanged: (v) {
                    setState(() => autoScrollEnabled = v);
                    if (!v) _stopAutoScroll();
                  },
                ),
              ],
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 2, 14, 7),
            child: Text(
              'ดับเบิลแทปที่ช่องเพื่อแก้ไขค่า | ใช้ปุ่ม + / − เพื่อซูม',
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ),

        Expanded(
          child: Container(
            key: mapViewportKey,
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: panel2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _startSelectionPointer,
              onPointerMove: _moveSelectionPointer,
              onPointerUp: _endSelectionPointer,
              onPointerCancel: _endSelectionPointer,
              child: SingleChildScrollView(
                controller: mapHorizontalController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SingleChildScrollView(
                  controller: mapVerticalController,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    key: mapContentKey,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: rpmWidth,
                            height: headerHeight,
                            alignment: Alignment.center,
                            color: panel2,
                            child: Text(
                              'RPM / TPS',
                              style: TextStyle(
                                color: cyan,
                                fontSize: 10 * zoom,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...List.generate(51, (col) {
                            return Container(
                              width: cellWidth,
                              height: headerHeight,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: panel2,
                                border: Border(
                                  right: BorderSide(
                                    color: bg,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Text(
                                '${tpsAxis[col]}',
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 9 * zoom,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                      ...List.generate(35, (row) {
                        return Row(
                          children: [
                            Container(
                              width: rpmWidth,
                              height: rowHeight,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: panel2,
                                border: Border(
                                  top: BorderSide(
                                    color: bg,
                                    width: 0.5,
                                  ),
                                  right: BorderSide(
                                    color: blue,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: Text(
                                '${rpmAxis[row]}',
                                style: TextStyle(
                                  color: cyan,
                                  fontSize: 9 * zoom,
                                ),
                              ),
                            ),
                            ...List.generate(51, (col) {
                              final selected = _isSelected(row, col);
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onDoubleTap: rangeSelectMode
                                    ? null
                                    : () => _editCell(row, col),
                                child: Container(
                                  width: cellWidth,
                                  height: rowHeight,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? blue.withOpacity(0.48)
                                        : _cellColor(data[row][col]),
                                    border: Border.all(
                                      color: selected ? cyan : bg,
                                      width: selected ? 1.5 : 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    data[row][col].toStringAsFixed(1),
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 9 * zoom,
                                      fontWeight: selected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Text(
                '${_mapName(activeMap)}  |  ${_mapUnit(activeMap)}',
                style: const TextStyle(color: muted, fontSize: 9),
              ),
              const Spacer(),
              const Text(
                'DOUBLE TAP = EDIT',
                style: TextStyle(color: muted, fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mapChip(String label, MapType type) {
    final selected = activeMap == type;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: selected,
      selectedColor: blue.withOpacity(0.3),
      onSelected: (_) {
        setState(() {
          activeMap = type;
          _clearSelection();
          if (type == MapType.afr) rangeSelectMode = false;
        });
      },
    );
  }

  Color _cellColor(double value) {
    if (activeMap == MapType.afr) {
      if (value < 12) return red.withOpacity(0.3);
      if (value < 14) return orange.withOpacity(0.25);
      return green.withOpacity(0.2);
    }
    if (value < 30) return red.withOpacity(0.25);
    if (value < 80) return orange.withOpacity(0.22);
    if (value < 140) return green.withOpacity(0.2);
    return blue.withOpacity(0.25);
  }

  // ==========================================================
  // GRAPH PAGE
  // ==========================================================

  Widget _graphPage() {
    final data = _map(activeMap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('GRAPH', 'LIVE VIEW OF SELECTED LOCAL MAP'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(
            spacing: 8,
            children: [
              _mapChip('FUEL', MapType.fuel),
              _mapChip('IGNITION', MapType.ignition),
              _mapChip('AFR', MapType.afr),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SegmentedButton<GraphMode>(
            segments: const [
              ButtonSegment(
                value: GraphMode.twoD,
                label: Text('2D GRAPH'),
                icon: Icon(Icons.show_chart),
              ),
              ButtonSegment(
                value: GraphMode.threeD,
                label: Text('3D SURFACE'),
                icon: Icon(Icons.view_in_ar),
              ),
            ],
            selected: {graphMode},
            onSelectionChanged: (selection) {
              setState(() => graphMode = selection.first);
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: panel2),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_mapName(activeMap)}  (${_mapUnit(activeMap)})',
                        style: const TextStyle(
                          color: cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (graphMode == GraphMode.threeD)
                      IconButton(
                        tooltip: 'หมุนกราฟ',
                        onPressed: () {
                          setState(() => graphRotation += 0.15);
                        },
                        icon: const Icon(Icons.rotate_right),
                      ),
                  ],
                ),
                Expanded(
                  child: ClipRect(
                    child: CustomPaint(
                      painter: MapGraphPainter(
                        data: data,
                        mode: graphMode,
                        rotation: graphRotation,
                        minimum: _minimum(activeMap),
                        maximum: _maximum(activeMap),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  graphMode == GraphMode.twoD
                      ? 'กราฟ 2D: แสดงค่าเฉลี่ยตามรอบเครื่องยนต์'
                      : 'กราฟ 3D: แสดงพื้นผิวของ Map ที่เลือก',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SETTINGS PAGE
  // ==========================================================

  Widget _settingsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header('SETTINGS', 'APPLICATION CONFIGURATION'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: panel2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.screen_rotation, color: cyan),
                        SizedBox(width: 10),
                        Text(
                          'SCREEN ORIENTATION',
                          style: TextStyle(
                            color: cyan,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'เลือกรูปแบบการหมุนหน้าจอ',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: orientationMode,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Orientation',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Portrait',
                          child: Text('Portrait - แนวตั้ง'),
                        ),
                        DropdownMenuItem(
                          value: 'Landscape',
                          child: Text('Landscape - แนวนอน'),
                        ),
                        DropdownMenuItem(
                          value: 'Auto Rotate',
                          child: Text('Auto Rotate - หมุนอัตโนมัติ'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _saveOrientation(value);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'ค่าปัจจุบัน: $orientationMode',
                      style: const TextStyle(
                        color: green,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: panel2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.zoom_in, color: cyan),
                        SizedBox(width: 10),
                        Text(
                          'MAP ZOOM',
                          style: TextStyle(
                            color: cyan,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'ขนาดตาราง ${(zoom * 100).round()}%',
                      style: const TextStyle(color: muted),
                    ),
                    Slider(
                      value: zoom,
                      min: 0.65,
                      max: 1.5,
                      divisions: 17,
                      label: '${(zoom * 100).round()}%',
                      onChanged: (value) {
                        setState(() => zoom = value);
                      },
                      onChangeEnd: (_) => _saveZoom(),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() => zoom = 1.0);
                            _saveZoom();
                          },
                          child: const Text('RESET ZOOM'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: panel2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MAP EDITOR',
                      style: TextStyle(
                        color: cyan,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Auto Scroll while selecting',
                        style: TextStyle(fontSize: 12),
                      ),
                      subtitle: const Text(
                        'เลื่อนตารางอัตโนมัติเมื่อลากเลือกใกล้ขอบ',
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                      value: autoScrollEnabled,
                      onChanged: (value) {
                        setState(() => autoScrollEnabled = value);
                        if (!value) _stopAutoScroll();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: orange.withOpacity(0.4),
                  ),
                ),
                child: const Text(
                  'หมายเหตุ: แอปในเวอร์ชันนี้เป็น Local Map Editor '
                  'ยังไม่มีระบบสื่อสารกับ ECU จริง การแสดงกราฟใช้ข้อมูลใน Map '
                  'ที่จัดเก็บอยู่ภายในแอปเท่านั้น',
                  style: TextStyle(
                    color: orange,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // OTHER PAGES
  // ==========================================================

  Widget _infoPage(
    String title,
    String description,
    IconData icon,
  ) {
    return Column(
      children: [
        _header(title, 'FORZA REMAP STUDIO'),
        Expanded(
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(30),
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: panel2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 50, color: blue),
                  const SizedBox(height: 15),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'NOT IMPLEMENTED',
                    style: TextStyle(
                      color: orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fileManager() {
    return Column(
      children: [
        _header('FILE MANAGER', 'LOCAL MAP STORAGE'),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.folder_open,
                  size: 48,
                  color: blue,
                ),
                const SizedBox(height: 12),
                const Text('จัดเก็บแผนที่ไว้ในเครื่อง'),
                const SizedBox(height: 15),
                FilledButton.icon(
                  onPressed: _saveMaps,
                  icon: const Icon(Icons.save),
                  label: const Text('SAVE ALL MAPS'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadMaps,
                  icon: const Icon(Icons.refresh),
                  label: const Text('LOAD SAVED MAPS'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'JSON / CSV Import-Export ยังไม่เปิดใช้งาน',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ecuPage() {
    return Column(
      children: [
        _header('ECU CONNECTION', 'HARDWARE INTERFACE'),
        Expanded(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: panel2),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bluetooth_disabled,
                    color: orange,
                    size: 50,
                  ),
                  SizedBox(height: 15),
                  Text(
                    'NOT CONNECTED',
                    style: TextStyle(
                      color: orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'ยังไม่มีการกำหนด Protocol ของ ECU\n'
                    'ไม่มีการอ่านหรือเขียนข้อมูลไปยังกล่องจริง\n\n'
                    'ต้องตรวจสอบฮาร์ดแวร์และ Protocol '
                    'ก่อนพัฒนาระบบเชื่อมต่อ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: muted,
                      height: 1.6,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// GRAPH PAINTER
// 2D line graph and 3D projected surface
// ============================================================

class MapGraphPainter extends CustomPainter {
  final List<List<double>> data;
  final GraphMode mode;
  final double rotation;
  final double minimum;
  final double maximum;

  MapGraphPainter({
    required this.data,
    required this.mode,
    required this.rotation,
    required this.minimum,
    required this.maximum,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (mode == GraphMode.twoD) {
      _paint2D(canvas, size);
    } else {
      _paint3D(canvas, size);
    }
  }

  void _paintGrid(Canvas canvas, Size size, Rect area) {
    final paint = Paint()
      ..color = panel2
      ..strokeWidth = 1;

    for (int i = 0; i <= 5; i++) {
      final y = area.top + area.height * i / 5;
      canvas.drawLine(
        Offset(area.left, y),
        Offset(area.right, y),
        paint,
      );
    }

    for (int i = 0; i <= 5; i++) {
      final x = area.left + area.width * i / 5;
      canvas.drawLine(
        Offset(x, area.top),
        Offset(x, area.bottom),
        paint,
      );
    }
  }

  void _paint2D(Canvas canvas, Size size) {
    final area = Rect.fromLTWH(
      48,
      18,
      math.max(1, size.width - 65),
      math.max(1, size.height - 55),
    );

    _paintGrid(canvas, size, area);

    final line = Paint()
      ..color = cyan
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = blue.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    final minValue = data
        .expand((row) => row)
        .reduce(math.min);
    final maxValue = data
        .expand((row) => row)
        .reduce(math.max);

    final range = math.max(0.001, maxValue - minValue);

    for (int r = 0; r < data.length; r++) {
      double total = 0;
      for (int c = 0; c < data[r].length; c++) {
        total += data[r][c];
      }

      final average = total / data[r].length;
      final x = area.left + area.width * r / (data.length - 1);
      final y = area.bottom -
          ((average - minValue) / range) * area.height;

      if (r == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, area.bottom);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(area.right, area.bottom);
    fillPath.close();

    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, line);

    final dotPaint = Paint()..color = cyan;
    for (int r = 0; r < data.length; r += 4) {
      final average =
          data[r].reduce((a, b) => a + b) / data[r].length;
      final x = area.left + area.width * r / (data.length - 1);
      final y = area.bottom -
          ((average - minValue) / range) * area.height;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }

    _drawText(
      canvas,
      'RPM',
      Offset(area.center.dx, size.height - 14),
    );
    _drawText(
      canvas,
      'VALUE',
      Offset(8, area.top + 5),
    );
  }

  void _paint3D(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final baseY = size.height * 0.78;
    final scaleX = size.width * 0.78 / 50;
    final scaleY = size.height * 0.55 / 34;
    final heightScale = size.height * 0.48;

    final minValue = data
        .expand((row) => row)
        .reduce(math.min);
    final maxValue = data
        .expand((row) => row)
        .reduce(math.max);
    final range = math.max(0.001, maxValue - minValue);

    Offset project(int r, int c, double value) {
      final x = (c - 25) * scaleX;
      final z = (r - 17) * scaleY;
      final h = ((value - minValue) / range) * heightScale;

      final cosR = math.cos(rotation);
      final sinR = math.sin(rotation);

      final rotatedX = x * cosR - z * sinR;
      final rotatedZ = x * sinR + z * cosR;

      return Offset(
        centerX + rotatedX,
        baseY - h - rotatedZ * 0.42,
      );
    }

    final gridPaint = Paint()
      ..color = panel2
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    final surfacePaint = Paint()
      ..color = cyan.withOpacity(0.85)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Draw longitudinal surface lines.
    for (int r = 0; r < 35; r += 2) {
      final path = Path();
      for (int c = 0; c < 51; c += 2) {
        final point = project(r, c, data[r][c]);
        if (c == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, surfacePaint);
    }

    // Draw cross surface lines.
    for (int c = 0; c < 51; c += 3) {
      final path = Path();
      for (int r = 0; r < 35; r += 2) {
        final point = project(r, c, data[r][c]);
        if (r == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, gridPaint);
    }

    // Base axes.
    final axisPaint = Paint()
      ..color = muted
      ..strokeWidth = 1.2;

    canvas.drawLine(
      Offset(centerX - size.width * 0.38, baseY),
      Offset(centerX + size.width * 0.38, baseY),
      axisPaint,
    );

    _drawText(
      canvas,
      'TPS',
      Offset(size.width - 30, baseY + 12),
    );
    _drawText(
      canvas,
      'RPM',
      Offset(22, baseY + 10),
    );
  }

  void _drawText(Canvas canvas, String text, Offset position) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: muted,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant MapGraphPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.mode != mode ||
        oldDelegate.rotation != rotation ||
        oldDelegate.minimum != minimum ||
        oldDelegate.maximum != maximum;
  }
}
