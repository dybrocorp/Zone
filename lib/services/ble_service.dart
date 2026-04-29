import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:uuid/uuid.dart' as uuid_pkg;

class BleDiscoveryService {
  static final BleDiscoveryService _instance = BleDiscoveryService._internal();
  factory BleDiscoveryService() => _instance;
  BleDiscoveryService._internal();

  final _ble = FlutterReactiveBle();
  StreamSubscription? _scanSubscription;
  final uuid_pkg.Uuid _uuid = const uuid_pkg.Uuid();
  
  late String myUniqueId;
  final List<DiscoveredDevice> discoveredUsers = [];

  // UUID de servicio custom para nuestra app (usado para filtrar)
  static final Uuid zoneServiceUuid = Uuid.parse('11111111-2222-3333-4444-555555555555');

  void initialize() {
    // Generar un ID único local (En producción esto debería leerse/guardarse con SharedPreferences)
    myUniqueId = _uuid.v4();
    print('BLE Service inicializado con ID: $myUniqueId');
  }

  void startScanning() {
    discoveredUsers.clear();
    // Escaneamos pidiendo latencia baja
    _scanSubscription = _ble.scanForDevices(
      withServices: [], // Para modo global de momento. Luego usaremos [zoneServiceUuid]
      scanMode: ScanMode.lowLatency
    ).listen((device) {
      
      final index = discoveredUsers.indexWhere((d) => d.id == device.id);
      if (index >= 0) {
        discoveredUsers[index] = device;
      } else {
        discoveredUsers.add(device);
        print('¡Usuario descubierto en Zone!: ${device.id} con señal ${device.rssi} dBm');
      }

    }, onError: (Object e) {
      print('Error al escanear BLE: $e');
    });
  }

  void stopScanning() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    print('Escaneo detenido.');
  }

  Future<void> startAdvertising() async {
    print('Iniciando modo Anunciante (Advertising)...');
    // TODO: Implementar lógica de anuncio mediante paquete ble_peripheral
    // La idea es enviar myUniqueId como parte de la data del Peripheral.
  }

  Future<void> stopAdvertising() async {
    print('Modo Anunciante detenido.');
  }
}
