import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const ForzaApp());

class ForzaApp extends StatelessWidget {
  const ForzaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FORZA 350 TUNER',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE53935), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF101318),
      useMaterial3: true,
    ),
    home: const TunerHome(),
  );
}

class TunerHome extends StatefulWidget {
  const TunerHome({super.key});
  @override
  State<TunerHome> createState() => _TunerHomeState();
}

class _TunerHomeState extends State<TunerHome> {
  int tab = 0;
  int rpm = 5000, tps = 40;
  bool saved = false;
  final rpms = [2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000];
  final tpsAxis = [0, 10, 20, 40, 60, 80, 100];
  late List<List<double>> fuel;
  late List<List<double>> ignition;

  @override
  void initState() {
    super.initState();
    fuel = List.generate(rpms.length, (r) => List.generate(tpsAxis.length, (c) => 100.0));
    ignition = List.generate(rpms.length, (r) => List.generate(tpsAxis.length, (c) => 0.0));
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final f = p.getString('fuel_map_v1');
    final i = p.getString('ignition_map_v1');
    if (!mounted) return;
    setState(() {
      if (f != null) fuel = (jsonDecode(f) as List).map((r) => (r as List).map((v) => (v as num).toDouble()).toList()).toList();
      if (i != null) ignition = (jsonDecode(i) as List).map((r) => (r as List).map((v) => (v as num).toDouble()).toList()).toList();
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('fuel_map_v1', jsonEncode(fuel));
    await p.setString('ignition_map_v1', jsonEncode(ignition));
    if (mounted) {
      setState(() => saved = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกแผนที่จำลองไว้ในโทรศัพท์แล้ว')));
    }
  }

  Future<void> _editCell(int r, int c, bool isFuel) async {
    final controller = TextEditingController(text: (isFuel ? fuel[r][c] : ignition[r][c]).toString());
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${isFuel ? "Fuel" : "Ignition"} • ${rpms[r]} RPM / ${tpsAxis[c]}% TPS'),
        content: TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'ค่าทดลอง')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text)), child: const Text('ตกลง')),
        ],
      ),
    );
    if (value != null && mounted) {
      setState(() {
        (isFuel ? fuel : ignition)[r][c] = value;
        saved = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_dashboard(), _mapPage(true), _mapPage(false), _bluetooth()];
    return Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('FORZA 350', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          Text('ECU TUNER • PROTOTYPE', style: TextStyle(fontSize: 10, color: Color(0xFFEF5350))),
        ]),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Chip(label: const Text('SIMULATION', style: TextStyle(fontSize: 10)), backgroundColor: Colors.orange.shade900))],
      ),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: 'หน้าหลัก'),
          NavigationDestination(icon: Icon(Icons.local_gas_station), label: 'Fuel'),
          NavigationDestination(icon: Icon(Icons.flash_on), label: 'Ignition'),
          NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Bluetooth'),
        ],
      ),
    );
  }

  Widget _panel(Widget child) => Card(color: const Color(0xFF20252D), child: Padding(padding: const EdgeInsets.all(16), child: child));

  Widget _dashboard() => ListView(padding: const EdgeInsets.all(16), children: [
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('ENGINE SPEED • SIMULATED', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 11)),
      const SizedBox(height: 8),
      Text('$rpm', textAlign: TextAlign.center, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFFEF5350))),
      const Text('RPM', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Text('รอบเครื่องจำลอง  $rpm RPM'),
      Slider(value: rpm.toDouble(), min: 1000, max: 10000, divisions: 90, onChanged: (v) => setState(() => rpm = v.round())),
      const SizedBox(height: 8),
      Text('ตำแหน่งคันเร่ง TPS  $tps%'),
      Slider(value: tps.toDouble(), min: 0, max: 100, divisions: 20, onChanged: (v) => setState(() => tps = v.round())),
    ])),
    _panel(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('สถานะระบบ', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Row(children: [Icon(Icons.circle, size: 10, color: Colors.orange), SizedBox(width: 8), Text('Simulation mode — ไม่มีข้อมูลจากเครื่องยนต์จริง')]),
      SizedBox(height: 6),
      Text('Bluetooth: ยังไม่เชื่อมต่อ', style: TextStyle(color: Colors.white70)),
    ])),
    const Padding(padding: EdgeInsets.all(8), child: Text('คำเตือน: ค่าทั้งหมดเป็นข้อมูลจำลอง ไม่ใช่ค่าจูนสำหรับ Forza 350 จริง', style: TextStyle(color: Colors.orange))),
  ]);

  Widget _mapPage(bool isFuel) {
    final data = isFuel ? fuel : ignition;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Row(children: [
        Expanded(child: Text(isFuel ? 'FUEL MAP' : 'IGNITION MAP', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save, size: 18), label: const Text('บันทึก')),
      ])),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Align(alignment: Alignment.centerLeft, child: Text('แตะช่องเพื่อแก้ไข • ตารางจำลองเท่านั้น', style: TextStyle(color: Colors.orange, fontSize: 12)))),
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SingleChildScrollView(child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFF292F39)),
        columns: [const DataColumn(label: Text('RPM / TPS')), ...tpsAxis.map((v) => DataColumn(label: Text('$v%')))],
        rows: List.generate(rpms.length, (r) => DataRow(cells: [
          DataCell(Text('${rpms[r]}')),
          ...List.generate(tpsAxis.length, (c) => DataCell(
            InkWell(onTap: () => _editCell(r, c, isFuel), child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(color: (r == 3 && c == 3) ? Colors.red.withOpacity(.25) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
              child: Text(data[r][c].toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w600)),
            )),
          )),
        ])),
      )))),
      const Padding(padding: EdgeInsets.all(12), child: Text('ยังไม่ส่งค่าตารางไปยังกล่อง ECU', style: TextStyle(color: Colors.white54))),
    ]);
  }

  Widget _bluetooth() => ListView(padding: const EdgeInsets.all(16), children: [
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
      Icon(Icons.bluetooth, size: 42, color: Color(0xFF64B5F6)),
      SizedBox(height: 12),
      Text('Bluetooth BLE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text('สถานะ: ยังไม่เปิดใช้งาน'),
      SizedBox(height: 12),
      Text('ขั้นตอนต่อไปจะกำหนด BLE service/characteristics และโปรโตคอลสื่อสารกับ ESP32-C3 พร้อมตรวจสอบเวอร์ชันและ checksum ก่อนอนุญาตการรับส่งข้อมูล'),
    ])),
    const Text('เพื่อความปลอดภัย รุ่นนี้ไม่ส่งคำสั่งจูนหรือควบคุมหัวฉีด/คอยล์จริง', style: TextStyle(color: Colors.orange)),
  ]);
}
