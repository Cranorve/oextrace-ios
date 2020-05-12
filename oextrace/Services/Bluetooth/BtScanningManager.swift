import Foundation
import CoreBluetooth
import UIKit

class BtScanningManager: NSObject {
    
    static let shared = BtScanningManager()
    
    private static let tag = "SCAN"
    
    var state: CBManagerState?
    
    private var manager: CBCentralManager!
    
    private var peripheralsRssi: [CBPeripheral: Int] = [:]

    private var foundDevices = [PeripheralDevice]()

    func setup() {
        manager = CBCentralManager(delegate: self, queue: nil, options: nil)
    }
    
    private func log(_ text: String) {
        BtLogsManager.append(tag: BtScanningManager.tag, text: text)
    }
}

extension BtScanningManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log(central.state.name())
        
        state = central.state
        
        if state == .poweredOn {
            manager.scanForPeripherals(withServices: [BtServiceDefinition.bleServiceUuid],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            
            log("Scanning has started")
        } else if state == .poweredOff {
            foundDevices.removeAll()
            if let rootViewController = RootViewController.instance {
                rootViewController.showBluetoothOffWarning()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        log("Found peripheral: \(peripheral.identifier.uuidString), RSSI: \(RSSI.stringValue), " +
            "advertisementData: \(advertisementData.debugDescription)")
        peripheralsRssi[peripheral] = RSSI.intValue
        let foundDevice = PeripheralDevice(peripheral: peripheral, rssi: RSSI.intValue)
        if foundDevices.contains(foundDevice) {
            log("Not connecting to \(peripheral.identifier.uuidString), duplicate RSSI \(RSSI.intValue)")
            
            return
        }

        foundDevices.append(foundDevice)
        peripheral.delegate = self
        
        log("Connecting to \(peripheral.identifier.uuidString), RSSI \(RSSI.intValue)")
        
        connect(to: peripheral)
    }
    
    // MARK: - Connect to peripheral
    
    private func connect(to peripheral: CBPeripheral) {
        manager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BtServiceDefinition.bleServiceUuid])
        log("Connected to: \(peripheral.identifier.uuidString)")
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Failed to connect to: \(peripheral.identifier.uuidString)")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Disconnected from: \(peripheral.identifier.uuidString)")
    }
    
}

extension BtScanningManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let errorValue = error {
            log("Error discovering services: \(errorValue.localizedDescription)")
            
            return
        }
        
        let bleService = peripheral.services?.first(where: { $0.uuid == BtServiceDefinition.bleServiceUuid })
        guard let unwrappedBleService = bleService else { return }
        
        peripheral.discoverCharacteristics([BtServiceDefinition.bleCharacteristicUuid], for: unwrappedBleService)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let errorValue = error {
            log("Error discovering services: \(errorValue.localizedDescription)")
            return
        }
        if let char = service.characteristics?.first(where: { $0.uuid == BtServiceDefinition.bleCharacteristicUuid }) {
            peripheral.readValue(for: char)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        if data.count != CryptoUtil.keyLength * 2 {
            log("Received unexpected data length: \(data.count)")
        } else {
            let rollingId = data.subdata(in: 0..<CryptoUtil.keyLength).base64EncodedString()
            let meta = data.subdata(in: 0..<(CryptoUtil.keyLength * 2))

            if let rssi = peripheralsRssi[peripheral] {
                let day = CryptoUtil.currentDayNumber()
                let encounter = BtEncounter(rssi: rssi, meta: meta)
                BtContactsManager.addContact(rollingId, day, encounter)
                
                log("Recorded a contact with \(peripheral.identifier.uuidString) RSSI \(rssi)")
            } else {
                log("Failed to record contact: no RSSI data")
            }
        }

        manager.cancelPeripheralConnection(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let errorValue = error {
            log("Error changing notification state: \(errorValue.localizedDescription)")

            return
        }

        if characteristic.isNotifying {
            log("Subscribed. Notification has begun for: \(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        
    }

}
