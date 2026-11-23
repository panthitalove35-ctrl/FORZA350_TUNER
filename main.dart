import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ForzaRemapStudio());
}

const Color bg = Color(0xFF0B0F14);
const Color panel = Color(0xFF151C25);
const Color panel2 = Color(0xFF1C2632);
const Color blue = Color(0xFF258BFF);
const Color cyan = Color(0xFF36C9E8);
const Color green = Color(0xFF39C982);
const Color orange = Color(0xFFFFB74D);
const Color red = Color(0xFFEF5350);
const Color muted = Color(0xFF8C9AAA);

final List<int> rpmAxis = List<int>.generate(35, (i) => 1500 + i * 250);
final List<int> tpsAxis = List<int>.generate(51, (i) => i * 2);

enum MapType { fuel, ignition, afr }
enum GraphMode { twoD, threeD }

class ForzaRemapStudio extends StatelessWidget {
  const ForzaRemapStudio({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FORZA REMAP STUDIO',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: blue, secondary: cyan, surface: panel),
          useMaterial3: true,
        ),
        home: const StudioHome(),
      );
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
  String orientationMode = 'landscape';
  double zoom = 1.0;
  double _zoomStart = 1.0;
  int graphTpsIndex = 25;
  double graphRotationX = -0.75;
  double graphRotationZ = -0.55;
  int? selectionStartRow, selectionStartCol, selectionEndRow, selectionEndCol;
  final ScrollController mapHorizontalController = ScrollController();
  final ScrollController mapVerticalController = ScrollController();
  final List<List<List<List<double>>>> undoStack = [];
  final List<List<List<List<double>>>> redoStack = [];

  @override
  void initState() {
    super.initState();
    fuelMap = _createMap(100);
    ignitionMap = _createMap(0);
    afrMap = _createMap(14.7);
    _loadMaps();
    _loadOrientation();
  }

  @override
  void dispose() {
    mapHorizontalController.dispose();
    mapVerticalController.dispose();
    super.dispose();
  }

  List<List<double>> _createMap(double value) =>
      List.generate(35, (_) => List.generate(51, (_) => value));
  List<List<double>> _copyMap(List<List<double>> source) =>
      source.map((r) => List<double>.from(r)).toList();
  List<List<List<double>>> _snapshot() => [_copyMap(fuelMap), _copyMap(ignitionMap), _copyMap(afrMap)];
  void _restoreSnapshot(List<List<List<double>>> s) {
    fuelMap = _copyMap(s[0]);
    ignitionMap = _copyMap(s[1]);
    afrMap = _copyMap(s[2]);
  }

  List<List<double>> _map(MapType type) {
    switch (type) {
      case MapType.fuel: return fuelMap;
      case MapType.ignition: return ignitionMap;
      case MapType.afr: return afrMap;
    }
  }
  String _mapName(MapType type) {
    switch (type) {
      case MapType.fuel: return 'FUEL MAP';
      case MapType.ignition: return 'IGNITION MAP';
      case MapType.afr: return 'AFR TARGET MAP';
    }
  }
  String _mapUnit(MapType type) {
    switch (type) {
      case MapType.fuel: return '%';
      case MapType.ignition: return '°';
      case MapType.afr: return 'AFR';
    }
  }
  double _minimum(MapType type) {
    switch (type) {
      case MapType.fuel: return 0;
      case MapType.ignition: return -40;
      case MapType.afr: return 8;
    }
  }
  double _maximum(MapType type) {
    switch (type) {
      case MapType.fuel: return 250;
      case MapType.ignition: return 80;
      case MapType.afr: return 25;
    }
  }

  void _history() {
    undoStack.add(_snapshot());
    if (undoStack.length > 30) undoStack.removeAt(0);
    redoStack.clear();
  }
  void _undo() {
    if (undoStack.isEmpty) return;
    setState(() { redoStack.add(_snapshot()); _restoreSnapshot(undoStack.removeLast()); saved = false; });
  }
  void _redo() {
    if (redoStack.isEmpty) return;
    setState(() { undoStack.add(_snapshot()); _restoreSnapshot(redoStack.removeLast()); saved = false; });
  }

  Future<void> _saveMaps() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('fuel_map_v2', jsonEncode(fuelMap));
    await p.setString('ignition_map_v2', jsonEncode(ignitionMap));
    await p.setString('afr_map_v1', jsonEncode(afrMap));
    if (!mounted) return;
    setState(() => saved = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกแผนที่เรียบร้อย')));
  }

  Future<void> _loadMaps() async {
    final p = await SharedPreferences.getInstance();
    List<List<double>> readMap(String key, double fallback) {
      final raw = p.getString(key);
      if (raw == null) return _createMap(fallback);
      try {
        final decoded = jsonDecode(raw) as List;
        if (decoded.length != 35) return _createMap(fallback);
        return decoded.map<List<double>>((row) {
          final values = (row as List).map((v) => (v as num).toDouble()).toList();
          if (values.length != 51) throw const FormatException('Invalid map size');
          return values;
        }).toList();
      } catch (_) { return _createMap(fallback); }
    }
    if (!mounted) return;
    setState(() {
      fuelMap = readMap('fuel_map_v2', 100);
      ignitionMap = readMap('ignition_map_v2', 0);
      afrMap = readMap('afr_map_v1', 14.7);
    });
  }

  Future<void> _loadOrientation() async {
    final p = await SharedPreferences.getInstance();
    await _applyOrientation(p.getString('orientation_mode') ?? 'landscape', save: false);
  }
  Future<void> _applyOrientation(String mode, {bool save = true}) async {
    final orientations = mode == 'portrait'
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : mode == 'auto'
            ? <DeviceOrientation>[]
            : const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
    await SystemChrome.setPreferredOrientations(orientations);
    if (save) {
      final p = await SharedPreferences.getInstance();
      await p.setString('orientation_mode', mode);
    }
    if (mounted) setState(() => orientationMode = mode);
  }

  Future<void> _editCell(int row, int col) async {
    final data = _map(activeMap);
    final c = TextEditingController(text: data[row][col].toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panel,
        title: Text('แก้ไข ${_mapName(activeMap)}', style: const TextStyle(color: cyan)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('RPM: ${rpmAxis[row]}'), Text('TPS: ${tpsAxis[col]}%'), const SizedBox(height: 12),
          TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true), decoration: InputDecoration(labelText: 'ค่าใหม่ (${_mapUnit(activeMap)})', border: const OutlineInputBorder())),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')), FilledButton(onPressed: () { final v = double.tryParse(c.text); if (v != null) Navigator.pop(ctx, v); }, child: const Text('บันทึก'))],
      ),
    );
    if (result == null) return;
    _history();
    setState(() { data[row][col] = result.clamp(_minimum(activeMap), _maximum(activeMap)).toDouble(); saved = false; });
  }

  int get selectedCellCount {
    if (selectionStartRow == null || selectionStartCol == null || selectionEndRow == null || selectionEndCol == null) return 0;
    return ((selectionEndRow! - selectionStartRow!).abs() + 1) * ((selectionEndCol! - selectionStartCol!).abs() + 1);
  }
  int get minSelectedRow => math.min(selectionStartRow!, selectionEndRow!).toInt();
  int get maxSelectedRow => math.max(selectionStartRow!, selectionEndRow!).toInt();
  int get minSelectedCol => math.min(selectionStartCol!, selectionEndCol!).toInt();
  int get maxSelectedCol => math.max(selectionStartCol!, selectionEndCol!).toInt();
  bool _isSelected(int r, int c) => selectedCellCount > 0 && r >= minSelectedRow && r <= maxSelectedRow && c >= minSelectedCol && c <= maxSelectedCol;
  void _selectCell(int r, int c) => setState(() { selectionStartRow = r; selectionStartCol = c; selectionEndRow = r; selectionEndCol = c; });
  void _clearSelection() => setState(() { selectionStartRow = null; selectionStartCol = null; selectionEndRow = null; selectionEndCol = null; });

  double _selectionAverage() {
    final d = _map(activeMap); double total = 0; int count = 0;
    for (int r = minSelectedRow; r <= maxSelectedRow; r++) { for (int c = minSelectedCol; c <= maxSelectedCol; c++) { total += d[r][c]; count++; } }
    return count == 0 ? 0 : total / count;
  }
  void _applyAverage() {
    if (selectedCellCount == 0) return;
    final avg = _selectionAverage(); final d = _map(activeMap); _history();
    setState(() { for (int r=minSelectedRow;r<=maxSelectedRow;r++) { for (int c=minSelectedCol;c<=maxSelectedCol;c++) { d[r][c]=avg; } } saved=false; });
  }
  void _applyInterpolation() {
    if (selectedCellCount < 2) return;
    final d = _map(activeMap); _history();
    setState(() {
      if (minSelectedCol != maxSelectedCol) {
        for (int r=minSelectedRow;r<=maxSelectedRow;r++) { final a=d[r][minSelectedCol], b=d[r][maxSelectedCol]; for (int c=minSelectedCol;c<=maxSelectedCol;c++) { final t=(c-minSelectedCol)/(maxSelectedCol-minSelectedCol); d[r][c]=a+(b-a)*t; } }
      } else if (minSelectedRow != maxSelectedRow) {
        final a=d[minSelectedRow][minSelectedCol], b=d[maxSelectedRow][minSelectedCol];
        for (int r=minSelectedRow;r<=maxSelectedRow;r++) { final t=(r-minSelectedRow)/(maxSelectedRow-minSelectedRow); d[r][minSelectedCol]=a+(b-a)*t; }
      }
      saved=false;
    });
  }
  Future<void> _applyMath(String op) async {
    if (selectedCellCount == 0) return;
    final c = TextEditingController();
    final value = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: panel, title: Text('ปรับค่า: $op'),
      content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal:true,signed:true), decoration: const InputDecoration(labelText:'ใส่ตัวเลข',border:OutlineInputBorder())),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('ยกเลิก')),FilledButton(onPressed:(){final v=double.tryParse(c.text);if(v!=null)Navigator.pop(ctx,v);},child:const Text('ตกลง'))],
    ));
    if(value==null)return; final d=_map(activeMap); _history();
    setState(() { for(int r=minSelectedRow;r<=maxSelectedRow;r++){for(int col=minSelectedCol;col<=maxSelectedCol;col++){double v=d[r][col];if(op=='+')v+=value;if(op=='-')v-=value;if(op=='×')v*=value;d[r][col]=v.clamp(_minimum(activeMap),_maximum(activeMap)).toDouble();}} saved=false; });
  }
  void _smoothSelection() {
    if(selectedCellCount==0)return; final d=_map(activeMap), old=_copyMap(_map(activeMap)); _history();
    setState(() { for(int r=minSelectedRow;r<=maxSelectedRow;r++){for(int c=minSelectedCol;c<=maxSelectedCol;c++){double sum=0;int n=0;for(int dr=-1;dr<=1;dr++){for(int dc=-1;dc<=1;dc++){final rr=r+dr,cc=c+dc;if(rr>=minSelectedRow&&rr<=maxSelectedRow&&cc>=minSelectedCol&&cc<=maxSelectedCol){sum+=old[rr][cc];n++;}}}if(n>0)d[r][c]=sum/n;}} saved=false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Row(children:[_sidebar(),Expanded(child:Container(color:bg,child:_content()))])));

  Widget _sidebar() {
    final items = <List<dynamic>>[
      ['Dashboard',Icons.dashboard],['Fuel Map',Icons.local_gas_station],['Ignition Map',Icons.bolt],['AFR Target',Icons.speed],['Graph',Icons.show_chart],['Data Logger',Icons.analytics],['File Manager',Icons.folder],['ECU Connection',Icons.bluetooth],['Settings',Icons.settings],
    ];
    return Container(width:155,color:panel,child:Column(children:[
      const SizedBox(height:18),const Icon(Icons.memory,color:blue,size:32),const SizedBox(height:8),
      const Text('FORZA',style:TextStyle(fontWeight:FontWeight.bold,letterSpacing:2,color:Colors.white)),
      const Text('REMAP STUDIO',style:TextStyle(fontSize:10,color:cyan,letterSpacing:1)),const SizedBox(height:20),const Divider(color:panel2),
      Expanded(child:ListView.builder(itemCount:items.length,itemBuilder:(ctx,i){final selected=page==i;return InkWell(onTap:(){setState((){page=i;if(i==1)activeMap=MapType.fuel;if(i==2)activeMap=MapType.ignition;if(i==3)activeMap=MapType.afr;rangeSelectMode=false;selectionStartRow=null;selectionStartCol=null;selectionEndRow=null;selectionEndCol=null;});},child:Container(margin:const EdgeInsets.symmetric(horizontal:7,vertical:3),padding:const EdgeInsets.symmetric(horizontal:9,vertical:12),decoration:BoxDecoration(color:selected?blue.withOpacity(.18):Colors.transparent,borderRadius:BorderRadius.circular(7),border:selected?Border.all(color:blue.withOpacity(.7)):null),child:Row(children:[Icon(items[i][1] as IconData,size:17,color:selected?cyan:muted),const SizedBox(width:9),Expanded(child:Text(items[i][0] as String,style:TextStyle(fontSize:11,color:selected?Colors.white:muted,fontWeight:selected?FontWeight.bold:FontWeight.normal)))])));})),
      const Padding(padding:EdgeInsets.all(10),child:Text('LOCAL EDITOR\nNO ECU LINK',textAlign:TextAlign.center,style:TextStyle(color:orange,fontSize:9))),
    ]));
  }

  Widget _content() {
    switch(page){
      case 0:return _dashboard();
      case 1:case 2:case 3:return _mapEditor();
      case 4:return _graphPage();
      case 5:return _infoPage('DATA LOGGER','ระบบบันทึกข้อมูลยังไม่มีข้อมูลจาก ECU จริง',Icons.analytics);
      case 6:return _fileManager();
      case 7:return _ecuPage();
      default:return _settingsPage();
    }
  }
  Widget _header(String title,String subtitle) => Padding(padding:const EdgeInsets.fromLTRB(18,15,18,12),child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold,letterSpacing:1)),const SizedBox(height:3),Text(subtitle,style:const TextStyle(color:muted,fontSize:10))])),Icon(saved?Icons.cloud_done:Icons.edit_note,color:saved?green:orange),const SizedBox(width:5),Text(saved?'SAVED':'UNSAVED',style:TextStyle(color:saved?green:orange,fontSize:10))]));

  Widget _dashboard() => Column(crossAxisAlignment:CrossAxisAlignment.start,children:[_header('DASHBOARD','FORZA REMAP STUDIO | PROFESSIONAL ECU'),Expanded(child:SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(children:[Row(children:[_statusCard('ENGINE','FORZA 350',Icons.motorcycle,cyan),const SizedBox(width:10),_statusCard('MAP SIZE','35 × 51',Icons.grid_on,blue),const SizedBox(width:10),_statusCard('CELLS','1,785',Icons.table_chart,green)]),const SizedBox(height:14),Container(width:double.infinity,padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(12),border:Border.all(color:panel2)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('MAP CONFIGURATION',style:TextStyle(color:cyan,fontWeight:FontWeight.bold)),SizedBox(height:15),Text('RPM: 1,500 – 10,000 / 250 RPM'),SizedBox(height:7),Text('TPS: 0 – 100% / 2%'),SizedBox(height:7),Text('Fuel / Ignition / AFR Target: 1,785 cells each')])),const SizedBox(height:14),Container(width:double.infinity,padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:orange.withOpacity(.08),border:Border.all(color:orange.withOpacity(.5)),borderRadius:BorderRadius.circular(10)),child:const Text('คำเตือน: ค่าในแอปเป็นข้อมูลแก้ไขแผนที่ในเครื่องเท่านั้น ยังไม่ได้เชื่อมต่อ ECU จริง และไม่ใช่ค่าจูนที่รับรองความปลอดภัย',style:TextStyle(color:orange,fontSize:11)))])))]);
  Widget _statusCard(String title,String value,IconData icon,Color color)=>Expanded(child:Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(10),border:Border.all(color:panel2)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:color,size:22),const SizedBox(height:12),Text(value,style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),Text(title,style:const TextStyle(fontSize:9,color:muted))])));

  void _selectAtViewport(Offset p, Size viewport) {
    final rpmW = 78.0 * zoom;
    final cellW = 48.0 * zoom;
    final headH = 34.0 * zoom;
    final rowH = 31.0 * zoom;
    final x = p.dx + (mapHorizontalController.hasClients ? mapHorizontalController.offset : 0) - rpmW;
    final y = p.dy + (mapVerticalController.hasClients ? mapVerticalController.offset : 0) - headH;
    if (x < 0 || y < 0) return;
    final col = (x / cellW).floor().clamp(0, 50).toInt();
    final row = (y / rowH).floor().clamp(0, 34).toInt();
    if (selectionStartRow == null) {
      _selectCell(row, col);
    } else {
      setState(() { selectionEndRow = row; selectionEndCol = col; });
    }

    // Auto-scroll while dragging close to the visible viewport edges.
    const edge = 30.0;
    if (mapVerticalController.hasClients) {
      var next = mapVerticalController.offset;
      if (p.dy < edge) next -= 18;
      if (p.dy > viewport.height - edge) next += 18;
      next = next.clamp(0.0, mapVerticalController.position.maxScrollExtent).toDouble();
      if (next != mapVerticalController.offset) mapVerticalController.jumpTo(next);
    }
    if (mapHorizontalController.hasClients) {
      var next = mapHorizontalController.offset;
      if (p.dx < edge) next -= 18;
      if (p.dx > viewport.width - edge) next += 18;
      next = next.clamp(0.0, mapHorizontalController.position.maxScrollExtent).toDouble();
      if (next != mapHorizontalController.offset) mapHorizontalController.jumpTo(next);
    }
  }

  Widget _mapEditor() {
    final data=_map(activeMap); final canRange=activeMap!=MapType.afr;
    final scale=zoom;
    final rpmW=78.0*scale, cellW=48.0*scale, headH=34.0*scale, rowH=31.0*scale;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _header(_mapName(activeMap),'35 RPM POINTS × 51 TPS POINTS'),
      Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Wrap(spacing:7,children:[_mapChip('FUEL',MapType.fuel),_mapChip('IGNITION',MapType.ignition),_mapChip('AFR TARGET',MapType.afr)])),
      const SizedBox(height:5),
      SingleChildScrollView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.symmetric(horizontal:8),child:Row(children:[
        FilterChip(label:Text(rangeSelectMode?'RANGE ON':'RANGE SELECT',style:const TextStyle(fontSize:10)),selected:rangeSelectMode,selectedColor:blue.withOpacity(.3),onSelected:canRange?(v)=>setState(()=>rangeSelectMode=v):null),
        _toolButton('AVG',Icons.functions,selectedCellCount==0?null:_applyAverage),_toolButton('INTERPOLATE',Icons.linear_scale,selectedCellCount<2?null:_applyInterpolation),_toolButton('SMOOTH',Icons.blur_on,selectedCellCount==0?null:_smoothSelection),
        PopupMenuButton<String>(enabled:selectedCellCount>0,onSelected:_applyMath,itemBuilder:(ctx)=>const [PopupMenuItem(value:'+',child:Text('Add (+)')),PopupMenuItem(value:'-',child:Text('Subtract (-)')),PopupMenuItem(value:'×',child:Text('Multiply (×)'))],child:const Padding(padding:EdgeInsets.all(8),child:Text('MATH',style:TextStyle(color:cyan)))),
        TextButton(onPressed:_clearSelection,child:const Text('CLEAR')),
        IconButton(onPressed:undoStack.isEmpty?null:_undo,icon:const Icon(Icons.undo)),IconButton(onPressed:redoStack.isEmpty?null:_redo,icon:const Icon(Icons.redo)),IconButton(onPressed:_saveMaps,icon:const Icon(Icons.save,color:green)),
      ])),
      Padding(padding:const EdgeInsets.fromLTRB(12,0,12,6),child:Row(children:[Text(rangeSelectMode?'เลือกแล้ว $selectedCellCount ช่อง':'ดับเบิลแทปเพื่อแก้ไขค่า',style:const TextStyle(color:muted,fontSize:10)),const Spacer(),IconButton(visualDensity:VisualDensity.compact,onPressed:()=>setState(()=>zoom=(zoom-.1).clamp(.5,2.0).toDouble()),icon:const Icon(Icons.zoom_out,size:18)),Text('${(zoom*100).round()}%',style:const TextStyle(fontSize:10,color:cyan)),IconButton(visualDensity:VisualDensity.compact,onPressed:()=>setState(()=>zoom=(zoom+.1).clamp(.5,2.0).toDouble()),icon:const Icon(Icons.zoom_in,size:18)),TextButton(onPressed:()=>setState(()=>zoom=1),child:const Text('RESET')),TextButton(onPressed:(){if(mapHorizontalController.hasClients)mapHorizontalController.jumpTo(0);if(mapVerticalController.hasClients)mapVerticalController.jumpTo(0);},child:const Text('TOP'))])),
      Expanded(child:Container(margin:const EdgeInsets.fromLTRB(8,0,8,8),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(8),border:Border.all(color:panel2)),clipBehavior:Clip.antiAlias,child:LayoutBuilder(builder:(ctx,constraints){
        final grid=Column(children:[
          Row(children:[Container(width:rpmW,height:headH,alignment:Alignment.center,color:panel2,child:Text('RPM / TPS',style:TextStyle(color:cyan,fontSize:10*scale,fontWeight:FontWeight.bold))),...List.generate(51,(c)=>Container(width:cellW,height:headH,alignment:Alignment.center,color:panel2,child:Text('${tpsAxis[c]}',style:TextStyle(color:muted,fontSize:9*scale))))]),
          ...List.generate(35,(r)=>Row(children:[Container(width:rpmW,height:rowH,alignment:Alignment.center,color:panel2,child:Text('${rpmAxis[r]}',style:TextStyle(color:cyan,fontSize:9*scale))),...List.generate(51,(c){final selected=_isSelected(r,c);return GestureDetector(onDoubleTap:rangeSelectMode?null:()=>_editCell(r,c),onLongPress:rangeSelectMode?()=>_selectCell(r,c):null,child:Container(width:cellW,height:rowH,alignment:Alignment.center,decoration:BoxDecoration(color:selected?blue.withOpacity(.45):_cellColor(data[r][c]),border:Border.all(color:selected?cyan:bg,width:selected?1.5:.5)),child:Text(data[r][c].toStringAsFixed(1),style:TextStyle(color:selected?Colors.white:Colors.white70,fontSize:9*scale,fontWeight:selected?FontWeight.bold:FontWeight.normal))));}))])),
        ]);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: rangeSelectMode ? (d) { _clearSelection(); _selectAtViewport(d.localPosition, constraints.biggest); } : null,
          onPanUpdate: rangeSelectMode ? (d) => _selectAtViewport(d.localPosition, constraints.biggest) : null,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && mapVerticalController.hasClients) {
                final target = (mapVerticalController.offset + event.scrollDelta.dy).clamp(0.0, mapVerticalController.position.maxScrollExtent).toDouble();
                mapVerticalController.jumpTo(target);
              }
            },
            child: GestureDetector(
              onScaleStart: rangeSelectMode ? null : (_) { _zoomStart = zoom; },
              onScaleUpdate: rangeSelectMode ? null : (d) {
                if (d.pointerCount >= 2) setState(() => zoom = (_zoomStart * d.scale).clamp(.5, 2.0).toDouble());
              },
              child: SingleChildScrollView(
                controller: mapHorizontalController,
                scrollDirection: Axis.horizontal,
                physics: rangeSelectMode ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                child: SingleChildScrollView(
                  controller: mapVerticalController,
                  physics: rangeSelectMode ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
                  child: grid,
                ),
              ),
            ),
          ),
        );
      }))),
      Padding(padding:const EdgeInsets.fromLTRB(12,0,12,7),child:Text('${_mapName(activeMap)} | ${_mapUnit(activeMap)} | แตะค้างเพื่อเลือกเซลล์ใน RANGE SELECT',style:const TextStyle(color:muted,fontSize:9))),
    ]);
  }
  Widget _toolButton(String label,IconData icon,VoidCallback? action)=>Padding(padding:const EdgeInsets.only(left:4),child:OutlinedButton.icon(onPressed:action,icon:Icon(icon,size:14),label:Text(label,style:const TextStyle(fontSize:9)),style:OutlinedButton.styleFrom(foregroundColor:cyan,visualDensity:VisualDensity.compact,padding:const EdgeInsets.symmetric(horizontal:8))));
  Widget _mapChip(String label,MapType type){final selected=activeMap==type;return ChoiceChip(label:Text(label,style:const TextStyle(fontSize:10)),selected:selected,selectedColor:blue.withOpacity(.3),onSelected:(_){setState(()=>activeMap=type);});}
  Color _cellColor(double v){if(activeMap==MapType.afr){if(v<12)return red.withOpacity(.3);if(v<14)return orange.withOpacity(.25);return green.withOpacity(.2);}if(v<30)return red.withOpacity(.25);if(v<80)return orange.withOpacity(.22);if(v<140)return green.withOpacity(.2);return blue.withOpacity(.25);}

  Widget _graphPage(){
    final data=_map(activeMap);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _header('GRAPH STUDIO','LIVE PREVIEW FROM LOCAL MAP DATA'),
      Padding(padding:const EdgeInsets.symmetric(horizontal:14),child:Wrap(spacing:7,runSpacing:5,children:[_mapChip('FUEL',MapType.fuel),_mapChip('IGNITION',MapType.ignition),_mapChip('AFR TARGET',MapType.afr)])),
      Padding(padding:const EdgeInsets.fromLTRB(14,8,14,8),child:Row(children:[ChoiceChip(label:const Text('2D LINE'),selected:graphMode==GraphMode.twoD,onSelected:(_)=>setState(()=>graphMode=GraphMode.twoD)),const SizedBox(width:8),ChoiceChip(label:const Text('3D SURFACE'),selected:graphMode==GraphMode.threeD,onSelected:(_)=>setState(()=>graphMode=GraphMode.threeD)),const Spacer(),Text(_mapUnit(activeMap),style:const TextStyle(color:cyan))])),
      if(graphMode==GraphMode.twoD) Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Row(children:[const Text('TPS',style:TextStyle(color:muted)),Expanded(child:Slider(value:graphTpsIndex.toDouble(),min:0,max:50,divisions:50,label:'${tpsAxis[graphTpsIndex]}%',onChanged:(v)=>setState(()=>graphTpsIndex=v.round()))),Text('${tpsAxis[graphTpsIndex]}%') ])),
      Expanded(child:Container(margin:const EdgeInsets.fromLTRB(12,4,12,12),padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(12),border:Border.all(color:panel2)),child:graphMode==GraphMode.twoD?CustomPaint(painter:Map2DPainter(values:List.generate(35,(r)=>data[r][graphTpsIndex]),labels:rpmAxis,unit:_mapUnit(activeMap)),child:const SizedBox.expand()):GestureDetector(onPanUpdate:(d)=>setState((){graphRotationZ+=d.delta.dx*.008;graphRotationX=(graphRotationX+d.delta.dy*.008).clamp(-1.5,.2);}),child:CustomPaint(painter:Map3DPainter(values:data,unit:_mapUnit(activeMap),rotationX:graphRotationX,rotationZ:graphRotationZ),child:const SizedBox.expand())))),
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,8),child:Text(graphMode==GraphMode.twoD?'กราฟ 2D: ค่า ${_mapName(activeMap)} ตาม RPM ที่ TPS ${tpsAxis[graphTpsIndex]}%':'กราฟ 3D: แกน X = TPS, แกน Y = RPM, แกน Z = ค่าแผนที่ | ลากเพื่อหมุน',style:const TextStyle(color:muted,fontSize:10))),
    ]);
  }

  Widget _settingsPage()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[_header('SETTINGS','DISPLAY & APPLICATION'),Expanded(child:ListView(padding:const EdgeInsets.all(16),children:[Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(12),border:Border.all(color:panel2)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Row(children:[Icon(Icons.screen_rotation,color:cyan),SizedBox(width:10),Text('DISPLAY ORIENTATION',style:TextStyle(color:cyan,fontWeight:FontWeight.bold))]),const SizedBox(height:12),RadioListTile<String>(value:'portrait',groupValue:orientationMode,activeColor:cyan,title:const Text('Portrait'),subtitle:const Text('แนวตั้ง'),onChanged:(v){if(v!=null)_applyOrientation(v);}),RadioListTile<String>(value:'landscape',groupValue:orientationMode,activeColor:cyan,title:const Text('Landscape'),subtitle:const Text('แนวนอน'),onChanged:(v){if(v!=null)_applyOrientation(v);}),RadioListTile<String>(value:'auto',groupValue:orientationMode,activeColor:cyan,title:const Text('Auto Rotate'),subtitle:const Text('หมุนตามอุปกรณ์'),onChanged:(v){if(v!=null)_applyOrientation(v);})])),const SizedBox(height:12),Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(12)),child:const Text('แอปนี้ยังเป็น Local Map Editor ไม่มีการเชื่อมต่อหรือสั่งงาน ECU จริง',style:TextStyle(color:orange))) ]))]);

  Widget _infoPage(String title,String description,IconData icon)=>Column(children:[_header(title,'FORZA REMAP STUDIO'),Expanded(child:Center(child:Container(padding:const EdgeInsets.all(30),margin:const EdgeInsets.all(20),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(12),border:Border.all(color:panel2)),child:Column(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:50,color:blue),const SizedBox(height:15),Text(description,textAlign:TextAlign.center,style:const TextStyle(color:muted,height:1.7)),const SizedBox(height:15),const Text('NOT CONNECTED TO ECU',style:TextStyle(color:orange,fontWeight:FontWeight.bold))])))]);
  Widget _fileManager()=>Column(children:[_header('FILE MANAGER','LOCAL MAP STORAGE'),Expanded(child:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.folder_open,size:48,color:blue),const SizedBox(height:12),const Text('จัดเก็บแผนที่ไว้ในเครื่อง'),const SizedBox(height:15),FilledButton.icon(onPressed:_saveMaps,icon:const Icon(Icons.save),label:const Text('SAVE ALL MAPS')),const SizedBox(height:8),OutlinedButton.icon(onPressed:_loadMaps,icon:const Icon(Icons.refresh),label:const Text('LOAD SAVED MAPS')),const SizedBox(height:12),const Text('JSON / CSV Import-Export ยังไม่เปิดใช้งาน',style:TextStyle(color:muted,fontSize:10))])))]);
  Widget _ecuPage()=>Column(children:[_header('ECU CONNECTION','HARDWARE INTERFACE'),Expanded(child:Center(child:Container(margin:const EdgeInsets.all(20),padding:const EdgeInsets.all(25),decoration:BoxDecoration(color:panel,borderRadius:BorderRadius.circular(12),border:Border.all(color:panel2)),child:const Column(mainAxisSize:MainAxisSize.min,children:[Icon(Icons.bluetooth_disabled,color:orange,size:50),SizedBox(height:15),Text('NOT CONNECTED',style:TextStyle(color:orange,fontWeight:FontWeight.bold)),SizedBox(height:10),Text('ยังไม่มีการกำหนด Protocol ของ ECU\nไม่มีการอ่านหรือเขียนข้อมูลไปยังกล่องจริง\n\nต้องตรวจสอบฮาร์ดแวร์และ Protocol ก่อนพัฒนาระบบเชื่อมต่อ',textAlign:TextAlign.center,style:TextStyle(color:muted,height:1.6,fontSize:11))])))]);
}

class Map2DPainter extends CustomPainter {
  final List<double> values; final List<int> labels; final String unit;
  Map2DPainter({required this.values,required this.labels,required this.unit});
  @override
  void paint(Canvas canvas,Size size){
    const left=58.0,top=24.0,right=18.0,bottom=42.0;
    final rect=Rect.fromLTRB(left,top,size.width-right,size.height-bottom);
    if(rect.width<=0||rect.height<=0)return;
    final minV=values.reduce((a,b)=>math.min(a,b).toDouble()),maxV=values.reduce((a,b)=>math.max(a,b).toDouble());
    final span=(maxV-minV).abs()<.001?1.0:(maxV-minV);
    final grid=Paint()..color=panel2..strokeWidth=1;
    final text=TextPainter(textDirection:TextDirection.ltr);
    for(int i=0;i<=4;i++){
      final y=rect.bottom-rect.height*i/4;canvas.drawLine(Offset(rect.left,y),Offset(rect.right,y),grid);
      final v=minV+span*i/4;text.text=TextSpan(text:v.toStringAsFixed(1),style:const TextStyle(color:muted,fontSize:9));text.layout();text.paint(canvas,Offset(4,y-6));
    }
    final path=Path();
    for(int i=0;i<values.length;i++){
      final x=rect.left+rect.width*i/(values.length-1);final y=rect.bottom-((values[i]-minV)/span)*rect.height;
      if(i==0)path.moveTo(x,y);else path.lineTo(x,y);
    }
    canvas.drawPath(path,Paint()..color=cyan..style=PaintingStyle.stroke..strokeWidth=2.5..strokeCap=StrokeCap.round);
    for(int i=0;i<values.length;i+=4){final x=rect.left+rect.width*i/(values.length-1);final y=rect.bottom-((values[i]-minV)/span)*rect.height;canvas.drawCircle(Offset(x,y),3,Paint()..color=blue);}
    text.text=TextSpan(text:'RPM',style:const TextStyle(color:muted,fontSize:10));text.layout();text.paint(canvas,Offset(size.width/2-12,size.height-18));
    text.text=TextSpan(text:labels.first.toString(),style:const TextStyle(color:muted,fontSize:9));text.layout();text.paint(canvas,Offset(rect.left,rect.bottom+7));
    text.text=TextSpan(text:labels.last.toString(),style:const TextStyle(color:muted,fontSize:9));text.layout();text.paint(canvas,Offset(rect.right-30,rect.bottom+7));
    text.text=TextSpan(text:unit,style:const TextStyle(color:cyan,fontSize:10));text.layout();text.paint(canvas,const Offset(5,5));
  }
  @override
  bool shouldRepaint(covariant Map2DPainter old)=>old.values!=values||old.unit!=unit;
}

class Map3DPainter extends CustomPainter {
  final List<List<double>> values; final String unit; final double rotationX,rotationZ;
  Map3DPainter({required this.values,required this.unit,required this.rotationX,required this.rotationZ});
  @override
  void paint(Canvas canvas,Size size){
    final rows=values.length,cols=values.first.length;
    double minV=values.first.first,maxV=values.first.first;
    for(final row in values){for(final v in row){minV=math.min(minV,v).toDouble();maxV=math.max(maxV,v).toDouble();}}
    final span=(maxV-minV).abs()<.001?1.0:maxV-minV;
    final sx=math.min(size.width*.78/cols,size.height*.72/rows).toDouble();
    final scale=math.min(size.width,size.height)*.0065;
    Offset project(int r,int c){
      final x=(c-(cols-1)/2)*scale;final y=(r-(rows-1)/2)*scale;final z=((values[r][c]-minV)/span-0.5)*scale*12;
      final x1=x*math.cos(rotationZ)-y*math.sin(rotationZ);final y1=x*math.sin(rotationZ)+y*math.cos(rotationZ);
      final yy=y1*math.cos(rotationX)-z*math.sin(rotationX);final zz=y1*math.sin(rotationX)+z*math.cos(rotationX);
      return Offset(size.width/2+x1*sx/scale,size.height*.53+yy*sx/scale-zz*sx/scale*.55);
    }
    final line=Paint()..style=PaintingStyle.stroke..strokeWidth=.7;
    for(int r=0;r<rows;r+=2){final p=Path();for(int c=0;c<cols;c++){final q=project(r,c);if(c==0)p.moveTo(q.dx,q.dy);else p.lineTo(q.dx,q.dy);}line.color=cyan.withOpacity(.75);canvas.drawPath(p,line);}
    for(int c=0;c<cols;c+=3){final p=Path();for(int r=0;r<rows;r++){final q=project(r,c);if(r==0)p.moveTo(q.dx,q.dy);else p.lineTo(q.dx,q.dy);}line.color=blue.withOpacity(.65);canvas.drawPath(p,line);}
    final tp=TextPainter(textDirection:TextDirection.ltr);
    tp.text=TextSpan(text:'${minV.toStringAsFixed(1)} – ${maxV.toStringAsFixed(1)} $unit',style:const TextStyle(color:cyan,fontSize:11));tp.layout();tp.paint(canvas,const Offset(12,10));
    tp.text=const TextSpan(text:'ลากเพื่อหมุนพื้นผิว 3D',style:TextStyle(color:muted,fontSize:10));tp.layout();tp.paint(canvas,Offset(12,size.height-22));
  }
  @override
  bool shouldRepaint(covariant Map3DPainter old)=>old.values!=values||old.rotationX!=rotationX||old.rotationZ!=rotationZ||old.unit!=unit;
}
