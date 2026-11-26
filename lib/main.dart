
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
// FORZA REMAP STUDIO PRO
// Compact Professional ECU Interface
// Local Map Editor - ECU communication not implemented
// ============================================================

const Color bg = Color(0xFF07111C);
const Color panel = Color(0xFF101D2B);
const Color panel2 = Color(0xFF17283A);
const Color panel3 = Color(0xFF20364C);

const Color blue = Color(0xFF168BFF);
const Color cyan = Color(0xFF25C9E8);
const Color green = Color(0xFF35D39A);
const Color orange = Color(0xFFFFA940);
const Color red = Color(0xFFFF5B64);
const Color muted = Color(0xFF8EA4B8);

const int rpmStart = 1500;
const int rpmStep = 250;
const int rpmCount = 55;
const int tpsCount = 51;

final List<int> rpmAxis =
    List<int>.generate(rpmCount, (i) => rpmStart + i * rpmStep);

final List<int> tpsAxis =
    List<int>.generate(tpsCount, (i) => i * 2);

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

  double zoom = 0.85;
  double graphRotation = 0;

  String orientationMode = 'Landscape';

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
  Offset? lastPointerViewport;

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

  // ==========================================================
  // MAP DATA
  // ==========================================================

  List<List<double>> _createMap(double value) {
    return List.generate(
      rpmCount,
      (_) => List.generate(tpsCount, (_) => value),
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
        return 'DEG';
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

  // ==========================================================
  // SAVE / LOAD
  // ==========================================================

  Future<void> _saveMaps() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'fuel_map_v2',
      jsonEncode(fuelMap),
    );

    await prefs.setString(
      'ignition_map_v2',
      jsonEncode(ignitionMap),
    );

    await prefs.setString(
      'afr_map_v1',
      jsonEncode(afrMap),
    );

    if (!mounted) return;

    setState(() => saved = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('บันทึกแผนที่เรียบร้อย'),
      ),
    );
  }

  Future<void> _loadMaps() async {
    final prefs = await SharedPreferences.getInstance();

    List<List<double>> readMap(
      String key,
      double fallback,
    ) {
      final raw = prefs.getString(key);

      if (raw == null) {
        return _createMap(fallback);
      }

      try {
        final decoded = jsonDecode(raw) as List;

        if (decoded.isEmpty || decoded.length > rpmCount) {
          return _createMap(fallback);
        }

        final result = decoded.map<List<double>>((row) {
          final values = (row as List)
              .map((v) => (v as num).toDouble())
              .toList();

          if (values.length != tpsCount) {
            throw const FormatException('Invalid map size');
          }

          return values;
        }).toList();

        // Preserve old maps and extend to 55 RPM rows.
        final lastRow = List<double>.from(result.last);

        while (result.length < rpmCount) {
          result.add(List<double>.from(lastRow));
        }

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
      saved = true;
    });
  }

  // ==========================================================
  // SETTINGS
  // ==========================================================

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final mode =
        prefs.getString('orientation_mode') ?? 'Landscape';

    final savedZoom = prefs.getDouble('map_zoom') ?? 0.85;

    if (!mounted) return;

    setState(() {
      orientationMode = mode;
      zoom = savedZoom.clamp(0.55, 1.5).toDouble();
    });

    await _applyOrientation(mode);
  }

  Future<void> _saveOrientation(String mode) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('orientation_mode', mode);

    if (!mounted) return;

    setState(() {
      orientationMode = mode;
    });

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
      zoom = (zoom + amount).clamp(0.55, 1.5).toDouble();
    });

    _saveZoom();
  }

  // ==========================================================
  // UNDO / REDO
  // ==========================================================

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
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: Text(
            'EDIT ${_mapName(activeMap)}',
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
                  labelText: 'New value (${_mapUnit(activeMap)})',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(controller.text);

                if (value != null && value.isFinite) {
                  Navigator.pop(dialogContext, value);
                }
              },
              child: const Text('SAVE'),
            ),
          ],
        );
      },
    );

    controller.dispose();

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
    selectionStartRow = null;
    selectionStartCol = null;
    selectionEndRow = null;
    selectionEndCol = null;
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

  int? _cellRowFromGlobal(Offset globalPosition) {
    final box = mapContentKey.currentContext?.findRenderObject()
        as RenderBox?;

    if (box == null || !box.hasSize) return null;

    final p = box.globalToLocal(globalPosition);

    final rpmWidth = 64.0 * zoom;
    final headerHeight = 28.0 * zoom;
    final rowHeight = 25.0 * zoom;
    final cellWidth = 42.0 * zoom;

    if (p.dx < rpmWidth || p.dy < headerHeight) {
      return null;
    }

    final col = ((p.dx - rpmWidth) / cellWidth)
        .floor()
        .clamp(0, tpsCount - 1)
        .toInt();

    final row = ((p.dy - headerHeight) / rowHeight)
        .floor()
        .clamp(0, rpmCount - 1)
        .toInt();

    return row * tpsCount + col;
  }

  void _selectFromGlobal(Offset globalPosition) {
    final box = mapContentKey.currentContext?.findRenderObject()
        as RenderBox?;

    if (box == null || !box.hasSize) return;

    final p = box.globalToLocal(globalPosition);

    final rpmWidth = 64.0 * zoom;
    final cellWidth = 42.0 * zoom;
    final headerHeight = 28.0 * zoom;
    final rowHeight = 25.0 * zoom;

    if (p.dx < rpmWidth || p.dy < headerHeight) return;

    final col = ((p.dx - rpmWidth) / cellWidth)
        .floor()
        .clamp(0, tpsCount - 1)
        .toInt();

    final row = ((p.dy - headerHeight) / rowHeight)
        .floor()
        .clamp(0, rpmCount - 1)
        .toInt();

    setState(() {
      selectionEndRow = row;
      selectionEndCol = col;
    });
  }

  void _startSelectionPointer(PointerEvent event) {
    if (!rangeSelectMode) return;

    lastPointerGlobal = event.position;

    final viewport = mapViewportKey.currentContext
        ?.findRenderObject() as RenderBox?;

    if (viewport != null && viewport.hasSize) {
      lastPointerViewport = viewport.globalToLocal(event.position);
    }

    final box = mapContentKey.currentContext?.findRenderObject()
        as RenderBox?;

    if (box == null || !box.hasSize) return;

    final p = box.globalToLocal(event.position);

    final rpmWidth = 64.0 * zoom;
    final headerHeight = 28.0 * zoom;

    if (p.dx < rpmWidth || p.dy < headerHeight) return;

    final col = ((p.dx - rpmWidth) / (42.0 * zoom))
        .floor()
        .clamp(0, tpsCount - 1)
        .toInt();

    final row = ((p.dy - headerHeight) / (25.0 * zoom))
        .floor()
        .clamp(0, rpmCount - 1)
        .toInt();

    _selectCell(row, col);
    _startAutoScroll();
  }

  void _moveSelectionPointer(PointerEvent event) {
    if (!rangeSelectMode || selectionStartRow == null) return;

    lastPointerGlobal = event.position;

    final viewport = mapViewportKey.currentContext
        ?.findRenderObject() as RenderBox?;

    if (viewport != null && viewport.hasSize) {
      lastPointerViewport = viewport.globalToLocal(event.position);
    }

    _selectFromGlobal(event.position);
  }

  void _endSelectionPointer(PointerEvent event) {
    _stopAutoScroll();
    lastPointerGlobal = null;
    lastPointerViewport = null;
  }

  void _startAutoScroll() {
    if (!autoScrollEnabled || autoScrollTimer != null) return;

    autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) {
        if (!mounted ||
            !rangeSelectMode ||
            lastPointerViewport == null) {
          return;
        }

        final viewport = mapViewportKey.currentContext
            ?.findRenderObject() as RenderBox?;

        if (viewport == null || !viewport.hasSize) return;

        final p = lastPointerViewport!;
        final width = viewport.size.width;
        final height = viewport.size.height;

        const edge = 38.0;
        const step = 24.0;

        if (p.dx < edge && mapHorizontalController.hasClients) {
          final next =
              (mapHorizontalController.offset - step)
                  .clamp(
                    0.0,
                    mapHorizontalController.position.maxScrollExtent,
                  )
                  .toDouble();

          mapHorizontalController.jumpTo(next);
        } else if (p.dx > width - edge &&
            mapHorizontalController.hasClients) {
          final next =
              (mapHorizontalController.offset + step)
                  .clamp(
                    0.0,
                    mapHorizontalController.position.maxScrollExtent,
                  )
                  .toDouble();

          mapHorizontalController.jumpTo(next);
        }

        if (p.dy < edge && mapVerticalController.hasClients) {
          final next =
              (mapVerticalController.offset - step)
                  .clamp(
                    0.0,
                    mapVerticalController.position.maxScrollExtent,
                  )
                  .toDouble();

          mapVerticalController.jumpTo(next);
        } else if (p.dy > height - edge &&
            mapVerticalController.hasClients) {
          final next =
              (mapVerticalController.offset + step)
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

  // ==========================================================
  // RANGE OPERATIONS
  // ==========================================================

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
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: Text('MATH $operation'),
          content: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Enter number',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                final n = double.tryParse(controller.text);

                if (n != null && n.isFinite) {
                  Navigator.pop(dialogContext, n);
                }
              },
              child: const Text('APPLY'),
            ),
          ],
        );
      },
    );

    controller.dispose();

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

          if (count > 0) {
            data[r][c] = total / count;
          }
        }
      }

      saved = false;
    });
  }

  // ==========================================================
  // MAIN LAYOUT
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
    final items = <Map<String, dynamic>>[
      {'name': 'Dashboard', 'icon': Icons.home_rounded},
      {'name': 'Fuel Map', 'icon': Icons.local_gas_station},
      {'name': 'Ignition Map', 'icon': Icons.bolt},
      {'name': 'AFR Target', 'icon': Icons.speed},
      {'name': 'Graph', 'icon': Icons.bar_chart},
      {'name': 'Data Logger', 'icon': Icons.monitor_heart},
      {'name': 'File Manager', 'icon': Icons.folder},
      {'name': 'ECU Connection', 'icon': Icons.bluetooth},
      {'name': 'Settings', 'icon': Icons.settings},
    ];

    return Container(
      width: 126,
      color: panel,
      child: Column(
        children: [
          const SizedBox(height: 12),
          const Icon(
            Icons.memory,
            color: blue,
            size: 30,
          ),
          const SizedBox(height: 5),
          const Text(
            'FORZA',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
          const Text(
            'REMAP STUDIO',
            style: TextStyle(
              fontSize: 9,
              color: cyan,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: panel2, height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 5),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final selected = page == index;

                return InkWell(
                  onTap: () {
                    _stopAutoScroll();

                    setState(() {
                      page = index;

                      if (index == 1) {
                        activeMap = MapType.fuel;
                      }

                      if (index == 2) {
                        activeMap = MapType.ignition;
                      }

                      if (index == 3) {
                        activeMap = MapType.afr;
                      }

                      rangeSelectMode = false;
                      _clearSelection();
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? blue.withOpacity(0.20)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: selected
                          ? Border.all(
                              color: blue.withOpacity(0.8),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          items[index]['icon'] as IconData,
                          size: 16,
                          color: selected ? cyan : muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            items[index]['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
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
            padding: EdgeInsets.all(8),
            child: Text(
              'LOCAL EDITOR\nNO ECU LINK',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: orange,
                fontSize: 8,
                height: 1.4,
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

  // ==========================================================
  // HEADER
  // ==========================================================

  Widget _header(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            saved ? Icons.cloud_done : Icons.edit_note,
            color: saved ? green : orange,
            size: 19,
          ),
          const SizedBox(width: 4),
          Text(
            saved ? 'SAVED' : 'UNSAVED',
            style: TextStyle(
              color: saved ? green : orange,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // DASHBOARD
  // ==========================================================

  Widget _dashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'DASHBOARD',
          'FORZA REMAP STUDIO  |  PROFESSIONAL ECU',
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 430;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 3, 12, 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 10,
                          child: _statusCard(
                            'ENGINE',
                            'FORZA 350',
                            Icons.motorcycle,
                            cyan,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          flex: 9,
                          child: _statusCard(
                            'RPM CURRENT',
                            '----',
                            Icons.speed,
                            blue,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          flex: 8,
                          child: _statusCard(
                            'TPS CURRENT',
                            '--.- %',
                            Icons.tune,
                            green,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          flex: 8,
                          child: _statusCard(
                            'ECT',
                            '--.- °C',
                            Icons.thermostat,
                            orange,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          flex: 8,
                          child: _statusCard(
                            'AFR',
                            '--.-',
                            Icons.opacity,
                            cyan,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 7 : 11),
                    _dashboardRangeCard(compact),
                    SizedBox(height: compact ? 7 : 11),
                    Row(
                      children: [
                        Expanded(
                          child: _statusCard(
                            'FUEL MAP',
                            '2,805 CELLS',
                            Icons.local_gas_station,
                            green,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: _statusCard(
                            'IGNITION MAP',
                            '2,805 CELLS',
                            Icons.bolt,
                            blue,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: _statusCard(
                            'AFR TARGET',
                            '2,805 CELLS',
                            Icons.speed,
                            cyan,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 7 : 11),
                    _dashboardWarning(),
                  ],
                ),
              );
            },
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
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: panel2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 8,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardRangeCard(bool compact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 13),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: panel2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                'TUNING RANGE',
                style: TextStyle(
                  color: cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 5),
              Text(
                '(DASHBOARD)',
                style: TextStyle(
                  color: muted,
                  fontSize: 9,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          Row(
            children: [
              Expanded(
                child: _rangeInfo(
                  Icons.speed,
                  'RPM RANGE',
                  '1,500 – 15,000 RPM',
                ),
              ),
              Expanded(
                child: _rangeInfo(
                  Icons.tune,
                  'TPS RANGE',
                  '0 – 100 %',
                ),
              ),
              Expanded(
                child: _rangeInfo(
                  Icons.grid_view,
                  'MAP SIZE',
                  '55 × 51',
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          SizedBox(
            height: compact ? 28 : 42,
            child: CustomPaint(
              size: Size.infinite,
              painter: DashboardGraphPainter(),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'RPM STEP: 250  |  TPS STEP: 2%',
            style: TextStyle(
              color: muted,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeInfo(
    IconData icon,
    String title,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, color: cyan, size: 19),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: muted,
                  fontSize: 8,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dashboardWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: orange.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: orange.withOpacity(0.35),
        ),
      ),
      child: const Text(
        'LOCAL EDITOR / NO ECU LINK\n'
        'RPM, TPS, ECT และ AFR ยังไม่มีข้อมูลจากเซนเซอร์จริง '
        'จะแสดงเป็นเครื่องหมาย ---- จนกว่าจะพัฒนาระบบเชื่อมต่อ ECU',
        style: TextStyle(
          color: orange,
          fontSize: 9,
          height: 1.5,
        ),
      ),
    );
  }

  // ==========================================================
  // MAP TOOL BUTTONS
  // ==========================================================

  Widget _smallToolButton(
    String label,
    IconData icon,
    VoidCallback? action, {
    Color color = cyan,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: OutlinedButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 13),
        label: Text(
          label,
          style: const TextStyle(fontSize: 9),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 7,
          ),
          minimumSize: const Size(0, 30),
          visualDensity: VisualDensity.compact,
          side: BorderSide(
            color: color.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _iconTool(
    String tooltip,
    IconData icon,
    VoidCallback? action, {
    Color color = muted,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: action,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(
        minWidth: 31,
        minHeight: 31,
      ),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 19, color: color),
    );
  }

  // ==========================================================
  // MAP EDITOR
  // ==========================================================

  Widget _mapEditor() {
    final data = _map(activeMap);

    final rpmWidth = 64.0 * zoom;
    final cellWidth = 42.0 * zoom;
    final headerHeight = 28.0 * zoom;
    final rowHeight = 25.0 * zoom;

    final canSelectRange = activeMap != MapType.afr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          _mapName(activeMap),
          '55 RPM POINTS × 51 TPS POINTS',
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _mapChip('FUEL', MapType.fuel),
              _mapChip('IGNITION', MapType.ignition),
              _mapChip('AFR TARGET', MapType.afr),
            ],
          ),
        ),

        const SizedBox(height: 2),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(
            children: [
              _smallToolButton(
                rangeSelectMode ? 'RANGE ON' : 'RANGE SELECT',
                Icons.select_all,
                canSelectRange
                    ? () {
                        _stopAutoScroll();

                        setState(() {
                          rangeSelectMode = !rangeSelectMode;
                          _clearSelection();
                        });
                      }
                    : null,
                color: rangeSelectMode ? blue : cyan,
              ),

              if (rangeSelectMode) ...[
                _smallToolButton(
                  'AVERAGE',
                  Icons.functions,
                  selectedCellCount > 0 ? _applyAverage : null,
                ),
                _smallToolButton(
                  'INTERPOLATE',
                  Icons.linear_scale,
                  selectedCellCount > 1
                      ? _applyRangeInterpolation
                      : null,
                ),
                _smallToolButton(
                  'SMOOTH',
                  Icons.blur_on,
                  selectedCellCount > 0
                      ? _smoothSelection
                      : null,
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
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calculate,
                          color: cyan,
                          size: 18,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'MATH',
                          style: TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ),
                _iconTool(
                  'Clear selection',
                  Icons.clear,
                  _clearSelection,
                ),
              ],

              _iconTool(
                'Zoom out',
                Icons.zoom_out,
                () => _changeZoom(-0.1),
              ),

              Text(
                '${(zoom * 100).round()}%',
                style: const TextStyle(
                  color: cyan,
                  fontSize: 9,
                ),
              ),

              _iconTool(
                'Zoom in',
                Icons.zoom_in,
                () => _changeZoom(0.1),
              ),

              _iconTool(
                'Reset zoom',
                Icons.fit_screen,
                () {
                  setState(() => zoom = 0.85);
                  _saveZoom();
                },
              ),

              _iconTool(
                'Undo',
                Icons.undo,
                undoStack.isEmpty ? null : _undo,
              ),

              _iconTool(
                'Redo',
                Icons.redo,
                redoStack.isEmpty ? null : _redo,
              ),

              _iconTool(
                'Save maps',
                Icons.save,
                _saveMaps,
                color: green,
              ),
            ],
          ),
        ),

        if (rangeSelectMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'SELECTED: $selectedCellCount'
                    '${selectedCellCount > 0 ? '  |  AVG: ${_selectionAverage().toStringAsFixed(2)}' : ''}',
                    style: const TextStyle(
                      color: cyan,
                      fontSize: 9,
                    ),
                  ),
                ),
                const Text(
                  'AUTO SCROLL',
                  style: TextStyle(
                    color: muted,
                    fontSize: 8,
                  ),
                ),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: autoScrollEnabled,
                    onChanged: (value) {
                      setState(() {
                        autoScrollEnabled = value;
                      });

                      if (!value) _stopAutoScroll();
                    },
                  ),
                ),
              ],
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 3),
            child: Text(
              'DOUBLE TAP CELL TO EDIT  |  ZOOM + / -',
              style: TextStyle(
                color: muted,
                fontSize: 8,
              ),
            ),
          ),

        Expanded(
          child: Container(
            key: mapViewportKey,
            margin: const EdgeInsets.fromLTRB(6, 0, 6, 5),
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
                                fontSize: 8 * zoom,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...List.generate(tpsCount, (col) {
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
                                  fontSize: 8 * zoom,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),

                      ...List.generate(rpmCount, (row) {
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
                                  fontSize: 8 * zoom,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            ...List.generate(tpsCount, (col) {
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
                                        ? blue.withOpacity(0.55)
                                        : _cellColor(data[row][col]),
                                    border: Border.all(
                                      color: selected ? cyan : bg,
                                      width: selected ? 1.2 : 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    data[row][col].toStringAsFixed(1),
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 7.5 * zoom,
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
          padding: const EdgeInsets.fromLTRB(9, 0, 9, 5),
          child: Row(
            children: [
              Text(
                '${_mapName(activeMap)}  |  ${_mapUnit(activeMap)}',
                style: const TextStyle(
                  color: muted,
                  fontSize: 8,
                ),
              ),
              const Spacer(),
              Text(
                'RPM 1,500–15,000',
                style: const TextStyle(
                  color: muted,
                  fontSize: 8,
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

    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: ChoiceChip(
        label: Text(
          label,
          style: const TextStyle(fontSize: 9),
        ),
        selected: selected,
        selectedColor: blue.withOpacity(0.35),
        backgroundColor: panel,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        onSelected: (_) {
          setState(() {
            activeMap = type;
            _clearSelection();

            if (type == MapType.afr) {
              rangeSelectMode = false;
            }
          });
        },
      ),
    );
  }

  Color _cellColor(double value) {
    if (activeMap == MapType.afr) {
      if (value < 12) return red.withOpacity(0.30);
      if (value < 14) return orange.withOpacity(0.25);
      return green.withOpacity(0.20);
    }

    if (value < 30) return red.withOpacity(0.25);
    if (value < 80) return orange.withOpacity(0.22);
    if (value < 140) return green.withOpacity(0.20);

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
        _header(
          'GRAPH',
          'LOCAL MAP VISUALIZATION',
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: [
              _mapChip('FUEL', MapType.fuel),
              _mapChip('IGNITION', MapType.ignition),
              _mapChip('AFR', MapType.afr),
            ],
          ),
        ),

        const SizedBox(height: 5),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SegmentedButton<GraphMode>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(
                value: GraphMode.twoD,
                label: Text(
                  '2D GRAPH',
                  style: TextStyle(fontSize: 10),
                ),
                icon: Icon(Icons.show_chart, size: 16),
              ),
              ButtonSegment(
                value: GraphMode.threeD,
                label: Text(
                  '3D SURFACE',
                  style: TextStyle(fontSize: 10),
                ),
                icon: Icon(Icons.view_in_ar, size: 16),
              ),
            ],
            selected: {graphMode},
            onSelectionChanged: (selection) {
              setState(() {
                graphMode = selection.first;
              });
            },
          ),
        ),

        const SizedBox(height: 5),

        Expanded(
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: panel2),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_mapName(activeMap)} (${_mapUnit(activeMap)})',
                        style: const TextStyle(
                          color: cyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (graphMode == GraphMode.threeD)
                      IconButton(
                        tooltip: 'Rotate graph',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            graphRotation += 0.15;
                          });
                        },
                        icon: const Icon(
                          Icons.rotate_right,
                          size: 20,
                        ),
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
                const Text(
                  'RPM RANGE: 1,500 – 15,000',
                  style: TextStyle(
                    color: muted,
                    fontSize: 9,
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
        _header(
          'SETTINGS',
          'APPLICATION CONFIGURATION',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _settingsCard(
                title: 'SCREEN ORIENTATION',
                icon: Icons.screen_rotation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'เลือกรูปแบบการหมุนหน้าจอ',
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: orientationMode,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Orientation',
                        isDense: true,
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
                  ],
                ),
              ),

              const SizedBox(height: 10),

              _settingsCard(
                title: 'MAP ZOOM',
                icon: Icons.zoom_in,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ขนาดตาราง ${(zoom * 100).round()}%',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 11,
                      ),
                    ),
                    Slider(
                      value: zoom,
                      min: 0.55,
                      max: 1.5,
                      divisions: 19,
                      label: '${(zoom * 100).round()}%',
                      onChanged: (value) {
                        setState(() {
                          zoom = value;
                        });
                      },
                      onChangeEnd: (_) => _saveZoom(),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          zoom = 0.85;
                        });
                        _saveZoom();
                      },
                      child: const Text('RESET ZOOM'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              _settingsCard(
                title: 'MAP EDITOR',
                icon: Icons.grid_on,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Auto Scroll while selecting',
                    style: TextStyle(fontSize: 11),
                  ),
                  subtitle: const Text(
                    'เลื่อนตารางอัตโนมัติเมื่อลากเลือกใกล้ขอบ',
                    style: TextStyle(
                      fontSize: 9,
                      color: muted,
                    ),
                  ),
                  value: autoScrollEnabled,
                  onChanged: (value) {
                    setState(() {
                      autoScrollEnabled = value;
                    });

                    if (!value) _stopAutoScroll();
                  },
                ),
              ),

              const SizedBox(height: 10),

              _settingsCard(
                title: 'ENGINE MAP CONFIGURATION',
                icon: Icons.memory,
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RPM: 1,500 – 15,000'),
                    SizedBox(height: 5),
                    Text('RPM STEP: 250'),
                    SizedBox(height: 5),
                    Text('RPM POINTS: 55'),
                    SizedBox(height: 5),
                    Text('TPS: 0 – 100%'),
                    SizedBox(height: 5),
                    Text('TPS STEP: 2%'),
                    SizedBox(height: 5),
                    Text('TPS POINTS: 51'),
                    SizedBox(height: 5),
                    Text('MAP SIZE: 2,805 CELLS / MAP'),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: orange.withOpacity(0.4),
                  ),
                ),
                child: const Text(
                  'หมายเหตุ: แอปเป็น Local Map Editor '
                  'ยังไม่มีระบบสื่อสาร ECU จริง '
                  'ข้อมูลในกราฟเป็นข้อมูลจาก Map ภายในแอปเท่านั้น',
                  style: TextStyle(
                    color: orange,
                    fontSize: 10,
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

  Widget _settingsCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: panel2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cyan, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
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
              padding: const EdgeInsets.all(25),
              margin: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: panel2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 45, color: blue),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      height: 1.7,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
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
        _header(
          'FILE MANAGER',
          'LOCAL MAP STORAGE',
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.folder_open,
                  size: 45,
                  color: blue,
                ),
                const SizedBox(height: 10),
                const Text('จัดเก็บแผนที่ไว้ในเครื่อง'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saveMaps,
                  icon: const Icon(Icons.save),
                  label: const Text('SAVE ALL MAPS'),
                ),
                const SizedBox(height: 7),
                OutlinedButton.icon(
                  onPressed: _loadMaps,
                  icon: const Icon(Icons.refresh),
                  label: const Text('LOAD SAVED MAPS'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'JSON / CSV Import-Export ยังไม่เปิดใช้งาน',
                  style: TextStyle(
                    color: muted,
                    fontSize: 9,
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
        _header(
          'ECU CONNECTION',
          'HARDWARE INTERFACE',
        ),
        Expanded(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(15),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: panel2),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bluetooth_disabled,
                    color: orange,
                    size: 45,
                  ),
                  SizedBox(height: 12),
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
                      fontSize: 10,
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
// DASHBOARD DECORATIVE GRAPH
// ============================================================

class DashboardGraphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final grid = Paint()
      ..color = panel2
      ..strokeWidth = 0.6;

    for (int i = 0; i <= 3; i++) {
      final y = size.height * i / 3;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        grid,
      );
    }

    final path = Path();

    final points = <Offset>[
      Offset(0, size.height * 0.88),
      Offset(size.width * 0.12, size.height * 0.72),
      Offset(size.width * 0.28, size.height * 0.48),
      Offset(size.width * 0.47, size.height * 0.20),
      Offset(size.width * 0.66, size.height * 0.10),
      Offset(size.width * 0.82, size.height * 0.15),
      Offset(size.width, size.height * 0.22),
    ];

    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    final line = Paint()
      ..color = blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, line);

    final dot = Paint()..color = cyan;

    for (final point in points) {
      canvas.drawCircle(point, 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant DashboardGraphPainter oldDelegate) {
    return false;
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
    if (size.width <= 0 ||
        size.height <= 0 ||
        data.isEmpty) {
      return;
    }

    if (mode == GraphMode.twoD) {
      _paint2D(canvas, size);
    } else {
      _paint3D(canvas, size);
    }
  }

  void _paintGrid(Canvas canvas, Rect area) {
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
      42,
      15,
      math.max(1.0, size.width - 58),
      math.max(1.0, size.height - 45),
    );

    _paintGrid(canvas, area);

    final averages = <double>[];

    for (final row in data) {
      double total = 0;

      for (final value in row) {
        total += value;
      }

      averages.add(total / row.length);
    }

    double minValue = averages.reduce(math.min);
    double maxValue = averages.reduce(math.max);

    if (maxValue - minValue < 0.001) {
      minValue -= 0.5;
      maxValue += 0.5;
    }

    final range = maxValue - minValue;

    final path = Path();
    final fillPath = Path();

    for (int r = 0; r < averages.length; r++) {
      final x = area.left +
          area.width * r / math.max(1, averages.length - 1);

      final y = area.bottom -
          ((averages[r] - minValue) / range) * area.height;

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

    final fill = Paint()
      ..color = blue.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final line = Paint()
      ..color = cyan
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, line);

    final dotPaint = Paint()..color = cyan;

    for (int r = 0; r < averages.length; r += 5) {
      final x = area.left +
          area.width * r / math.max(1, averages.length - 1);

      final y = area.bottom -
          ((averages[r] - minValue) / range) * area.height;

      canvas.drawCircle(
        Offset(x, y),
        2.5,
        dotPaint,
      );
    }

    _drawText(
      canvas,
      'RPM 1,500 - 15,000',
      Offset(area.center.dx - 55, size.height - 14),
    );

    _drawText(
      canvas,
      'VALUE',
      const Offset(3, 4),
    );
  }

  void _paint3D(Canvas canvas, Size size) {
    final rows = data.length;
    final cols = data.first.length;

    if (rows < 2 || cols < 2) return;

    final centerX = size.width / 2;
    final baseY = size.height * 0.78;

    final scaleX = size.width * 0.78 / (cols - 1);
    final scaleY = size.height * 0.55 / (rows - 1);

    final heightScale = size.height * 0.48;

    double minValue = data.first.first;
    double maxValue = data.first.first;

    for (final row in data) {
      for (final value in row) {
        if (value < minValue) minValue = value;
        if (value > maxValue) maxValue = value;
      }
    }

    final range = math.max(0.001, maxValue - minValue);

    Offset project(int r, int c, double value) {
      final x = (c - (cols - 1) / 2) * scaleX;
      final z = (r - (rows - 1) / 2) * scaleY;

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
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int r = 0; r < rows; r += 2) {
      final path = Path();

      for (int c = 0; c < cols; c += 2) {
        final point = project(r, c, data[r][c]);

        if (c == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }

      canvas.drawPath(path, surfacePaint);
    }

    for (int c = 0; c < cols; c += 3) {
      final path = Path();

      for (int r = 0; r < rows; r += 2) {
        final point = project(r, c, data[r][c]);

        if (r == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }

      canvas.drawPath(path, gridPaint);
    }

    final axisPaint = Paint()
      ..color = muted
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(centerX - size.width * 0.38, baseY),
      Offset(centerX + size.width * 0.38, baseY),
      axisPaint,
    );

    _drawText(
      canvas,
      'TPS',
      Offset(size.width - 28, baseY + 10),
    );

    _drawText(
      canvas,
      'RPM',
      Offset(5, baseY + 8),
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: muted,
          fontSize: 9,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant MapGraphPainter oldDelegate) {
    // Always repaint because map cells are edited in place.
    return true;
  }
}
