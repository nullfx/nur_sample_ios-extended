
import UIKit
import NurAPIBluetooth

let TID_LENGTH: UInt32 = 6

class InventoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, BluetoothDelegate {
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var inventoryButton: UIButton!
    @IBOutlet weak var tagsFoundLabel: UILabel!
    
    private var tags = [Tag]()
    
    // default scanning parameters
    private let rounds: Int32 = 0
    private let q: Int32 = 0
    private let session: Int32 = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // set up as a delegate
        Bluetooth.sharedInstance().register(self)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // no longer a delegate
        Bluetooth.sharedInstance().deregister( self )
    }
    
    @IBAction func toggleInventory(_ sender: Any) {
        guard let handle: HANDLE = Bluetooth.sharedInstance().nurapiHandle else {
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            if !NurApiIsInventoryExRunning(handle) {
                NSLog("starting inventory stream")
                
                // first clear the tags
                NurApiClearTags( handle )
                // Inventory ex parameters let are where you specify the q/session/rounds normally passed in to Start Inventory Session
                var params = NUR_INVEX_PARAMS(Q: self.q, session: self.session, rounds: self.rounds, transitTime: Int32(0), inventoryTarget: Int32(NUR_INVTARGET_AB.rawValue), inventorySelState: Int32(NUR_SELSTATE_ALL.rawValue))
                var filters = NUR_INVEX_FILTER()
                filters.truncate = false
                filters.address = 0
                filters.bank = UInt8(NUR_BANK_TID.rawValue)
                let tidLength = UInt32(TID_LENGTH)
                // When calling the inventory function that returns extra data (user data / TID) you have to call
                // InventoryRead first...
                if self.checkError( NurApiInventoryRead(handle, true, NUR_IR_EPCDATA.rawValue, UInt32(NUR_BANK_TID.rawValue), UInt32(0), tidLength), message: "Failed to start inventory read" ) {
                    // then call the StartInventoryEx passing in the filters and inventory ex parameters
                    if self.checkError(NurApiStartInventoryEx(handle, &params, &filters, Int32(1) ), message: "Failed to start inventory stream" ) {
                        // started ok
                        DispatchQueue.main.async {
                            self.inventoryButton.setTitle("Stop", for: UIControl.State.normal)
                        }
                    }
                }
            }
            else {
                NSLog("stopping inventory stream")
                if self.checkError( NurApiStopInventoryEx(handle), message: "Failed to stop inventory stream" ) {
                    // started ok
                    DispatchQueue.main.async {
                        self.inventoryButton.setTitle("Start", for: UIControl.State.normal)
                    }
                }
            }
        }
    }
    
    //
    //  MARK: - Table view datasource
    //
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tags.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell( withIdentifier: "TagCell" )! as UITableViewCell
        
        let tag = tags[indexPath.row]
        cell.textLabel?.text = tag.epc
        return cell
    }
    
    //
    //  MARK: - Table view delegate
    //
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // push a VC for showing some basic tag info
        let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "TagInfoViewController") as! TagInfoViewController
        vc.tag = tags[indexPath.row]
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    
    //
    //  MARK: - Bluetooth delegate
    //
    func notificationReceived(_ timestamp: DWORD, type: Int32, data: LPVOID!, length: Int32) {
        print("received notification: \(type)")
        switch NUR_NOTIFICATION(rawValue: UInt32(type)) {
        case NUR_NOTIFICATION_INVENTORYEX:
            handleTagEx(data: data, length: length)
            break
        default:
            NSLog("received notification: \(type)")
            break
        }
    }
    
    // add a new handle tag ex function to handle the notification
    private func handleTagEx (data: LPVOID!, length: Int32) {
        guard let handle: HANDLE = Bluetooth.sharedInstance().nurapiHandle else {
            return
        }
        
        // get number of tags read in this round
        var tagCount: Int32 = 0
        if !checkError(NurApiGetTagCount(handle, &tagCount), message: "Failed to clear tag storage" ) {
            return
        }
        
        print("tags found: \(tagCount)")
        
        if(tagCount < 1) { return }
        
        // iterate over the found tags, and look at the tag structure (containing the EPC)
        for i in 0 ... tagCount {
            var tag = NUR_TAG_DATA_EX()
            
            // fetch the TID (or user data if we set it up to read user data in the EX parameters)
            NurApiGetTagDataEx(handle, i, &tag, UInt32(MemoryLayout.size( ofValue: tag)))
            
            // use the utility to extract the tid from the tag
            let tidData = [UInt8](Utility.getEpcDataEx(tag))
            // convert the tid to a hex string
            let tidString = tidData.map { String(format: "%02x", $0) }.joined().uppercased()
            // just print it out to the console...
            print("Tag EPC: \(tag.epc), Tag TID: \(tidString)")
            let epcBytes = [UInt8](Utility.getEpcTagIDEx(tag))
            let epcString = epcBytes[0 ..< Int(tag.epcLen)].map { String(format: "%02x", $0) }.joined().uppercased()
            let tagEx = Tag(epc: epcString, rssi: tag.rssi, scaledRssi: tag.scaledRssi, antennaId: tag.antennaId, timestamp: tag.timestamp, frequency: tag.freq, channel: tag.channel, tid: tidString )
            
            DispatchQueue.main.async {
                if !self.tags.contains(where: { $0.epc == epcString } ) {
                    self.tags.append(tagEx)
                    self.tagsFoundLabel.text = String(self.tags.count)
                    self.tableView.reloadData()
                }
            }
        }
        
        
        
        // clear all tags
        _ = checkError(NurApiClearTags(handle), message: "Failed to clear tag storage" )
        _ = checkError(NurApiLockTagStorage(handle, false), message: "Failed to unlock tag storage" )
        
        print("tags fetched")
        
    }
}

