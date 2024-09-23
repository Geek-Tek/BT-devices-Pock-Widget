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
        return view as! NSStackView
    }
    
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
        refreshTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: #selector(self.loadStatusElements), userInfo: nil, repeats: true)
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
        
        clearItems()
        let item = SPowerItem()
        loadedItems.append(item)
        stackView.addArrangedSubview(item.view)
        stackView.height(30)
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
    private let bodyView: NSView = NSView(frame: NSRect(x: 2, y: 2, width: 1, height: 1))
    private let imageViews: [NSImageView] = [ NSImageView(frame: NSRect(x:0, y:0, width: 30, height: 30)), NSImageView(frame: NSRect(x:0, y:0, width: 30, height: 30)), NSImageView(frame: NSRect(x:0, y:0, width: 30, height: 30)) ]
    private var used = 0
    
    init() {
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
        stackView.distribution = .fillProportionally
        stackView.spacing = 8
        // !
        // stackView.addArrangedSubview(valueLabel)
        
        /* for d in devicesLabel {
            stackView.addArrangedSubview(d)
        } */
        /* devicesIcon.append(image)
        print(devicesIcon)
        for i in devicesIcon {
            stackView.addArrangedSubview(i)
        } */
        if ( used > 0 ) {
            for i in 0...used-1 {
                stackView.addArrangedSubview(imageViews[i])
            }
        } else {
            stackView.addArrangedSubview(imageViews[0])
        }
        print(used)
    }
    
    @objc func reload() {
        guard let devices = IOBluetoothDevice.pairedDevices() else { return }

        var type: [String] = ["", "", ""]
        var n = 0
        for d in devices {
            // print(d)
            if let device = d as? IOBluetoothDevice {
                if ( n < 3 ) {
                    if device.isConnected() {
                        // print(device.remoteNameRequest(Any?.self))
                        // print("\(String(device.addressString))")
                        
                        // Contains Headset service
                        type[n] = "Connection"
                        for serv in device.services {
                            if ((serv as! IOBluetoothSDPServiceRecord).getServiceName() == "Headset") {
                                type[n] = "Headset"
                                break
                            } else if ((serv as! IOBluetoothSDPServiceRecord).getServiceName() == "Broadcom Bluetooth Wireless Keyboard SDP Server") {
                                type[n] = "Keyboard"
                                break
                            } else if ((serv as! IOBluetoothSDPServiceRecord).getServiceName() == "Apple Wireless Mouse") {
                                type[n] = "Mouse"
                                break
                            }
                        }
                        n += 1
                    }
                }
            }
        }
        used = n
        self.updateIcon(items: n, type: type)
    }
    
    private func updateIcon(items: Int, type: [String]) {
        for i in 0...2 {
            imageViews[i].subviews.forEach({ $0.removeFromSuperview() })
            switch type[i] {
                case "Headset":
                    imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "AirPro.png")
                case "Keyboard":
                    imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "Keyboard.png")
                case "Mouse":
                    imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "magic_mouse.png")
                case "Connection":
                    imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "BTconnection.png")
                default:
                if ( items == 0 ) {
                    // if ( Preferences[.shouldShowX] ) {
                        // imageViews[i].image = Bundle(for: btDevicesWidget.self).image(forResource: "cross.png")
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
