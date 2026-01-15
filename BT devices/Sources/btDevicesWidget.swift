//
//  btDevicesWidget.swift
//  BT devices
//
//  Created by GeekTek on 15/10/23.
//  

import Foundation
import PockKit
import AppKit

import IOBluetooth

enum DeviceType {
    case headset
    case keyboard
    case mouse
    case generic
    case none
}

extension NSImage {
    /// Returns an NSImage snapshot of the passed view in 2x resolution.
    convenience init?(frame: NSRect, view: NSView) {
        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: frame) else {
            return nil
        }
        self.init()
        view.cacheDisplay(in: frame, to: bitmapRep)
        addRepresentation(bitmapRep)
        bitmapRep.size = frame.size
    }
}

class btDevicesWidget: PKWidget {
    
    static var identifier: String = "com.geektek.BT-devices"
    var customizationLabel: String = "BT devices"
    var view: NSView!
    var iterations = 0
    private var refreshTimer: Timer?
    
    private var stackView: NSStackView {
        guard let stack = view as? NSStackView else { fatalError("Expected NSStackView") }
        return stack
    }
    
    private lazy var powerItem = SPowerItem()
    
    private var loadedItems: [btDevicesItem] = []
    
    var imageForCustomization: NSImage {
        let stackView = NSStackView(frame: .zero)
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 8
        stackView.addArrangedSubview(SPowerItem().view)
        
        return NSImage(frame: NSRect(origin: .zero, size: stackView.fittingSize), view: stackView) ?? NSImage()
    }
    
    required init() {
        view = NSStackView(frame: .zero)
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 8
        
        /// Timer: every 10 seconds refresh

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.loadStatusElements()
        }

    }
    
    deinit {
        clearItems()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func viewDidAppear() {
        loadStatusElements()
        NotificationCenter.default.addObserver(self, selector: #selector(loadStatusElements), name: NSNotification.Name("shouldReloadStatusWidget"), object: nil)
        
        // ! kIOBluetoothDeviceNotificationNameConnected doesn't work properly. Disconnection works
        NotificationCenter.default.addObserver(self, selector: #selector(detectChange), name: NSNotification.Name(kIOBluetoothDeviceNotificationNameConnected), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(detectChange), name: NSNotification.Name(kIOBluetoothDeviceNotificationNameDisconnected), object: nil)
        
        // ! another way to register for change. Could be reason for double changes detected
        IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(detectChange))
    }
        
    func viewWillDisappear() {
        clearItems()
        NotificationCenter.default.removeObserver(self)
    }
        
    private func clearItems() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in loadedItems {
            item.didUnload()
        }
        loadedItems.removeAll()
    }
        
    @objc private func loadStatusElements() {
        // sometimes a change is detected 2 times in a row. This can create an iterating loop and crash the app
        // add a timer from one change to another in order to listen to single changes and avoid double changes
        iterations = 0
        
        if loadedItems.isEmpty {
            loadedItems.append(powerItem)
            stackView.addArrangedSubview(powerItem.view)
        }
//        clearItems()
//        let item = SPowerItem()
//        loadedItems.append(item)
//        stackView.addArrangedSubview(item.view)
        stackView.height(30)
        powerItem.reload()
    }
    
    @objc private func detectChange() {
        // print("[bt devices]: change Detected")
        
        if iterations == 0 {
            loadStatusElements()
        }
        iterations += 1
    }
}

internal class SPowerItem: btDevicesItem {
    
    private let stackView: NSStackView = NSStackView(frame: .zero)
    private let imageViews: [NSImageView] = [
        NSImageView(),
        NSImageView(),
        NSImageView()
    ]

    private var used = 0

    init() {
        imageViews.forEach{
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.imageScaling = .scaleProportionallyUpOrDown
        }
        
        for imageView in imageViews {
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 30),
                imageView.heightAnchor.constraint(equalToConstant: 30)
            ])
        }
        didLoad()
    }
    
    deinit {
        didUnload()
    }
    
    func didLoad() {
        reload()
        configureStackView()
    }
    
    func didUnload() {}
    
    func action() {
        reload()
    }
    
    var view: NSView { return stackView }
    
    private func configureStackView() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 8
        
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        
        for i in 0..<max(used, 1) {
            stackView.addArrangedSubview(imageViews[i])
        }
    }
    
    @objc func reload() {
        guard let devices = IOBluetoothDevice.pairedDevices() else { return }

        var type: [DeviceType] = Array(repeating: .none, count: 3)
        var n = 0
        for d in devices {
            // print(d)
            if let device = d as? IOBluetoothDevice {
                if ( n < 3 ) {
                    if device.isConnected() {
                        // print(device.remoteNameRequest(Any?.self))
                        // print("\(String(device.addressString))")
                        
                        // Contains Headset service
                        type[n] = .generic
                        for serv in device.services {
                            guard let service = serv as? IOBluetoothSDPServiceRecord else { continue }
                            if (service.getServiceName() == "Headset") {
                                type[n] = .headset
                                break
                            } else if (service.getServiceName() == "Broadcom Bluetooth Wireless Keyboard SDP Server") {
                                type[n] = .keyboard
                                break
                            } else if (service.getServiceName() == "Apple Wireless Mouse") {
                                type[n] = .mouse
                                break
                            }
                        }
                        n += 1
                    }
                }
            }
        }
        used = n
        updateIcon(items: n, type: type)
        configureStackView()
    }
    
    private func updateIcon(items: Int, type: [DeviceType]) {
        for i in 0...2 {
            imageViews[i].subviews.forEach({ $0.removeFromSuperview() })
            switch type[i] {
                case .headset:
                    imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "AirPro.png")
                case .keyboard:
                    imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "Keyboard.png")
                case .mouse:
                    imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "magic_mouse.png")
                case .generic:
                    imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "BTconnection.png")
                default:
                    if ( items == 0 ) {
                        imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "cross.png")
                    // if ( Preferences[.shouldShowX] ) {

                    // } else {
                        // imageViews[i].image = nil
                    // }
                }
            }
        }
    }
}


// DeviceItem.swift

class btDevicesItemView: PKView {
    weak var item: btDevicesItem?
    override func didTapHandler() {
        item?.action()
    }
}

protocol btDevicesItem: AnyObject {
    var view: NSView {get}
    func action()
    func reload()
    func didLoad()
    func didUnload()
}
