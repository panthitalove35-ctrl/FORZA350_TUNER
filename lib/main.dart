
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ForzaRemapStudio());
}

// ============================================================
// FORZA REMAP STUDIO
// Local map editor - no real ECU communication implemented
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

  late List<List<double>> fuelMap;
  late List<List<double>> ignitionMap;
  late List<List<double>> afrMap;

  bool saved = true;
  bool rangeSelectMode = false;

  int? selectionStartRow;
  int? selectionStartCol;
  int? selectionEndRow;
  int? selectionEndCol;

  final ScrollController mapHorizontalController =
      ScrollController();
  final ScrollController mapVerticalController =
      ScrollController();

  final List<List<List<List<double>>>> undoStack = [];
  final List<List<List<List<double>>>> redoStack = [];

  @override
  void initState() {
    super.initState();
    fuelMap = _createMap(100.0);
    ignitionMap = _createMap(0.0);
    afrMap = _createMap(14.7);
    _loadMaps();
  }

  @override
  void dispose() {
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
    return source.map((row) => List<double>.from(row)).toList();
  }

  List<List<List<double>>> _snapshot() {
    return [
      _copyMap(fuelMap),
      _copyMap(ignitionMap),
      _copyMap(afrMap),
    ];
  }

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
    if (undoStack.length > 30) {
      undoStack.removeAt(0);
    }
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

        final result = decoded.map<List<double>>((row) {
          final values = (row as List)
              .map((v) => (v as num).toDouble())
              .toList();

          if (values.length != 51) {
            throw const FormatException('Invalid map size');
          }
          return values;
        }).toList();

        return result;
      } catch (_) {
        return _createMap(fallback);
      }
    }

    if (!mounted) return;
    setState(() {
      fuelMap = readMap('fuel_map_v2', 100);
      ignitionMap = readMap('ignition_map_v2', 0);
      afrMap = readMap('afr_map_v1', 14.7);
    });
  }

  // ----------------------------------------------------------
  // CELL EDIT
  // ----------------------------------------------------------

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
      data[row][col] =
          result.clamp(_minimum(activeMap), _maximum(activeMap));
      saved = false;
    });
  }

  // ----------------------------------------------------------
  // RANGE SELECTION
  // ----------------------------------------------------------

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
      [selectionStartRow!, selectionEndRow!].reduce(
        (a, b) => a < b ? a : b,
      );

  int get maxSelectedRow =>
      [selectionStartRow!, selectionEndRow!].reduce(
        (a, b) => a > b ? a : b,
      );

  int get minSelectedCol =>
      [selectionStartCol!, selectionEndCol!].reduce(
        (a, b) => a < b ? a : b,
      );

  int get maxSelectedCol =>
      [selectionStartCol!, selectionEndCol!].reduce(
        (a, b) => a > b ? a : b,
      );

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

  void _updateSelection(Offset position) {
    const rpmWidth = 78.0;
    const cellWidth = 48.0;
    const headerHeight = 34.0;
    const rowHeight = 31.0;

    if (position.dx < rpmWidth ||
        position.dy < headerHeight) {
      return;
    }

    final col =
        ((position.dx - rpmWidth) / cellWidth).floor();
    final row =
        ((position.dy - headerHeight) / rowHeight).floor();

    final safeRow = row.clamp(0, 34).toInt();
    final safeCol = col.clamp(0, 50).toInt();

    setState(() {
      selectionEndRow = safeRow;
      selectionEndCol = safeCol;
    });
  }

  double _selectionAverage() {
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
      final rows = minSelectedRow;
      final rowEnd = maxSelectedRow;
      final cols = minSelectedCol;
      final colEnd = maxSelectedCol;

      if (cols != colEnd) {
        for (int r = rows; r <= rowEnd; r++) {
          final start = data[r][cols];
          final end = data[r][colEnd];

          for (int c = cols; c <= colEnd; c++) {
            final t = (c - cols) / (colEnd - cols);
            data[r][c] = start + (end - start) * t;
          }
        }
      } else if (rows != rowEnd) {
        final start = data[rows][cols];
        final end = data[rowEnd][cols];

        for (int r = rows; r <= rowEnd; r++) {
          final t = (r - rows) / (rowEnd - rows);
          data[r][cols] = start + (end - start) * t;
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
              final number = double.tryParse(controller.text);
              if (number != null) Navigator.pop(context, number);
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

          data[r][c] = result.clamp(
            _minimum(activeMap),
            _maximum(activeMap),
          );
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

  // ----------------------------------------------------------
  // UI
  // ----------------------------------------------------------

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
                    setState(() {
                      page = index;

                      if (index == 1) activeMap = MapType.fuel;
                      if (index == 2) activeMap = MapType.ignition;
                      if (index == 3) activeMap = MapType.afr;

                      rangeSelectMode = false;
                      selectionStartRow = null;
                      selectionStartCol = null;
                      selectionEndRow = null;
                      selectionEndCol = null;
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
                              color: selected
                                  ? Colors.white
                                  : muted,
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
              style: TextStyle(
                color: orange,
                fontSize: 9,
              ),
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
        return _infoPage(
          'GRAPH',
          'พื้นที่แสดงกราฟ 2D / 3D\nอยู่ระหว่างพัฒนา',
          Icons.show_chart,
        );
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
        return _infoPage(
          'SETTINGS',
          'ตั้งค่าระบบแอปพลิเคชัน',
          Icons.settings,
        );
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
                    style: TextStyle(
                      color: orange,
                      fontSize: 11,
                    ),
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
              style: const TextStyle(
                fontSize: 9,
                color: muted,
              ),
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

  Widget _mapEditor() {
    final data = _map(activeMap);

    const rpmWidth = 78.0;
    const cellWidth = 48.0;
    const headerHeight = 34.0;
    const rowHeight = 31.0;

    final canSelectRange = activeMap != MapType.afr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          _mapName(activeMap),
          '35 RPM POINTS × 51 TPS POINTS',
        ),

        // MAP SELECTOR
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

        const SizedBox(height: 8),

        // TOOLBAR
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
                        setState(() {
                          rangeSelectMode = value;
                          _clearSelection();
                        });
                      }
                    : null,
              ),
              const SizedBox(width: 8),
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
            child: Text(
              'เลือกแล้ว $selectedCellCount ช่อง'
              '${selectedCellCount > 0 ? '  |  เฉลี่ย ${_selectionAverage().toStringAsFixed(2)}' : ''}',
              style: const TextStyle(
                color: cyan,
                fontSize: 11,
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 2, 14, 7),
            child: Text(
              'ดับเบิลแทปที่ช่องเพื่อแก้ไขค่า',
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ),

        // MAP GRID
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: panel2),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              controller: mapHorizontalController,
              scrollDirection: Axis.horizontal,
              physics: rangeSelectMode
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              child: SingleChildScrollView(
                controller: mapVerticalController,
                physics: rangeSelectMode
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: rangeSelectMode
                      ? (details) {
                          final p = details.localPosition;
                          if (p.dx < rpmWidth ||
                              p.dy < headerHeight) {
                            return;
                          }

                          final col = ((p.dx - rpmWidth) /
                                  cellWidth)
                              .floor()
                              .clamp(0, 50)
                              .toInt();
                          final row = ((p.dy - headerHeight) /
                                  rowHeight)
                              .floor()
                              .clamp(0, 34)
                              .toInt();

                          _selectCell(row, col);
                        }
                      : null,
                  onPanUpdate: rangeSelectMode
                      ? (details) {
                          _updateSelection(details.localPosition);
                        }
                      : null,
                  onTapUp: rangeSelectMode
                      ? (details) {
                          final p = details.localPosition;
                          if (p.dx < rpmWidth ||
                              p.dy < headerHeight) {
                            return;
                          }

                          final col = ((p.dx - rpmWidth) /
                                  cellWidth)
                              .floor()
                              .clamp(0, 50)
                              .toInt();
                          final row = ((p.dy - headerHeight) /
                                  rowHeight)
                              .floor()
                              .clamp(0, 34)
                              .toInt();

                          _selectCell(row, col);
                        }
                      : null,
                  child: Column(
                    children: [
                      // TPS HEADER
                      Row(
                        children: [
                          Container(
                            width: rpmWidth,
                            height: headerHeight,
                            alignment: Alignment.center,
                            color: panel2,
                            child: const Text(
                              'RPM / TPS',
                              style: TextStyle(
                                color: cyan,
                                fontSize: 10,
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
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 9,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),

                      // RPM ROWS + MAP CELLS
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
                                style: const TextStyle(
                                  color: cyan,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                            ...List.generate(51, (col) {
                              final selected =
                                  _isSelected(row, col);

                              return GestureDetector(
                                onDoubleTap: rangeSelectMode
                                    ? null
                                    : () => _editCell(row, col),
                                child: Container(
                                  width: cellWidth,
                                  height: rowHeight,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? blue.withOpacity(0.38)
                                        : _cellColor(data[row][col]),
                                    border: Border.all(
                                      color: selected
                                          ? cyan
                                          : bg,
                                      width: selected ? 1.5 : 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    data[row][col].toStringAsFixed(1),
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 9,
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
                style: const TextStyle(
                  color: muted,
                  fontSize: 9,
                ),
              ),
              const Spacer(),
              const Text(
                'DOUBLE TAP = EDIT',
                style: TextStyle(
                  color: muted,
                  fontSize: 9,
                ),
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
          selectionStartRow = null;
          selectionStartCol = null;
          selectionEndRow = null;
          selectionEndCol = null;

          if (type == MapType.afr) {
            rangeSelectMode = false;
          }
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
                  style: TextStyle(
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
