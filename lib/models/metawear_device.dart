class MetawearDevice {
  final String id;
  final String name;
  final int rssi;

  const MetawearDevice({
    required this.id,
    required this.name,
    this.rssi = 0,
  });
}

