# FORZA 350 TUNER — ต้นแบบแอป Android

รุ่น 0.1.0 เป็น **โหมดจำลองเท่านั้น** ใช้ทดลองหน้าจอและแก้ไขตารางบนมือถือ ยังไม่เชื่อมต่อ ECU และห้ามนำค่าตัวอย่างไปใช้กับเครื่องยนต์จริง

## สิ่งที่มี
- Dashboard จำลอง RPM / TPS
- Fuel Map และ Ignition Map แบบตาราง RPM × TPS
- แตะช่องเพื่อแก้ค่า
- บันทึกและโหลดแผนที่ในเครื่องด้วย SharedPreferences
- หน้าสถานะ Bluetooth (ยังไม่เปิดส่งคำสั่ง)

## วิธีเปิดโปรเจกต์บน Windows
1. ติดตั้ง Flutter SDK และ Android Studio
2. แตก ZIP นี้
3. เปิดโฟลเดอร์ `forza350_tuner` ด้วย Android Studio หรือ VS Code
4. เปิด Terminal ในโฟลเดอร์ แล้วรัน:
   `flutter pub get`
   `flutter run`
5. สร้าง APK ทดสอบด้วย:
   `flutter build apk --debug`
   ไฟล์จะอยู่ที่ `build/app/outputs/flutter-apk/app-debug.apk`

## ข้อควรระวัง
ยังไม่มี protocol BLE, driver หัวฉีด/คอยล์, การอ่าน CKP/CMP, การคาลิเบรต หรือระบบ fail-safe ที่ผ่านการทดสอบ
ห้ามต่อกับ ECU/เครื่องยนต์จริงหรือส่งค่าจูนจริง จนกว่าจะออกแบบและทดสอบระบบฮาร์ดแวร์และเฟิร์มแวร์อย่างครบถ้วน

## สร้าง APK โดยใช้มือถือ + GitHub Actions
1. สร้าง GitHub repository ใหม่ แล้วอัปโหลดไฟล์ทั้งหมดใน ZIP นี้ (รวมโฟลเดอร์ `.github`).
2. เปิดแท็บ Actions ของ repository และเลือก workflow `Build FORZA 350 TUNER APK`.
3. ถ้า workflow ยังไม่ทำงานอัตโนมัติ ให้กด `Run workflow`.
4. เมื่อทำงานสำเร็จ เปิดรายการ workflow run แล้วดาวน์โหลด Artifact ชื่อ `FORZA350-TUNER-debug-apk`.
5. แตกไฟล์ artifact แล้วติดตั้ง `app-debug.apk` บน Android (อนุญาตติดตั้งจากแหล่งนี้เมื่อ Android ถาม).

การ build ใช้เครื่อง runner ของ GitHub ไม่ได้คอมไพล์บนโทรศัพท์เอง ต้องมีบัญชี GitHub และอินเทอร์เน็ต
