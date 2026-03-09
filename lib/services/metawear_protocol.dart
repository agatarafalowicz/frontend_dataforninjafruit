// metawear_protocol.dart — tylko ACC + GYRO, bez LED

const String kServiceUuid  = '326a9000-85cb-9195-d9dd-464cfbbae75a';
const String kCommandUuid  = '326a9001-85cb-9195-d9dd-464cfbbae75a';
const String kNotifyUuid   = '326a9006-85cb-9195-d9dd-464cfbbae75a';

class SensorSample {
  final DateTime time;
  final double x, y, z;
  SensorSample(this.time, this.x, this.y, this.z);
}

// ── Akcelerometr (moduł 0x03) ──────────────────────────────────────────────
List<int> accConfig()       => [0x03, 0x03, 0x27, 0x05]; // 50Hz, ±4g
List<int> accSubscribe()    => [0x03, 0x04, 0x01];
List<int> accEnable()       => [0x03, 0x02, 0x01, 0x00];
List<int> accStart()        => [0x03, 0x01, 0x01];
List<int> accStop()         => [0x03, 0x01, 0x00];
List<int> accDisable()      => [0x03, 0x02, 0x00, 0x01];
List<int> accUnsubscribe()  => [0x03, 0x04, 0x00];

SensorSample? parseAcc(List<int> b) {
  if (b.length < 8 || b[0] != 0x03 || (b[1] & 0x7F) != 0x04) return null;
  return SensorSample(DateTime.now(), _i16(b,2)/8192, _i16(b,4)/8192, _i16(b,6)/8192);
}

// ── Żyroskop (moduł 0x13) ──────────────────────────────────────────────────
List<int> gyroConfig()      => [0x13, 0x03, 0x27, 0x02]; // 50Hz, ±500dps
List<int> gyroSubscribe()   => [0x13, 0x05, 0x01];
List<int> gyroEnable()      => [0x13, 0x02, 0x01, 0x00];
List<int> gyroStart()       => [0x13, 0x01, 0x01];
List<int> gyroStop()        => [0x13, 0x01, 0x00];
List<int> gyroDisable()     => [0x13, 0x02, 0x00, 0x01];
List<int> gyroUnsubscribe() => [0x13, 0x05, 0x00];

SensorSample? parseGyro(List<int> b) {
  if (b.length < 8 || b[0] != 0x13 || (b[1] & 0x7F) != 0x05) return null;
  return SensorSample(DateTime.now(), _i16(b,2)/65.536, _i16(b,4)/65.536, _i16(b,6)/65.536);
}

double _i16(List<int> b, int i) {
  int v = b[i] | (b[i+1] << 8);
  return v >= 32768 ? (v - 65536).toDouble() : v.toDouble();
}