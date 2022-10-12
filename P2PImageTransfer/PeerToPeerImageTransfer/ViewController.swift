import UIKit
import MultipeerConnectivity

class ViewController: UIViewController, MCSessionDelegate, MCBrowserViewControllerDelegate, MCNearbyServiceAdvertiserDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    
    @IBOutlet weak var transferStatusLabel: UILabel!
    @IBOutlet weak var connectionStateLabel: UILabel!
    @IBOutlet weak var imageView: UIImageView!
    
    private var number = 0
    private var peerID: MCPeerID!
    private var mcSession: MCSession!
    private var mcAdvertiserAssistant: MCNearbyServiceAdvertiser!
    private var imagePicker = UIImagePickerController()
    private var progress: Progress?
    private var checkProgressTimer: Timer?
    private var bytesExpectedToExchange = 0
    private var transferTimeElapsed = 0.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        peerID = MCPeerID(displayName: UIDevice.current.name)
        mcSession = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self
    }

    
    // MARK: - Buttons Actions
    
    @IBAction func didTapConnect(_ sender: Any) {
        let actionSheet = UIAlertController(title: "Image Transfer", message: "Do you want to Start a session or connect to an existing one ?", preferredStyle: .actionSheet)
        
        actionSheet.addAction(UIAlertAction(title: "Start Session", style: .default, handler: { (action:UIAlertAction) in
            
            self.mcAdvertiserAssistant = MCNearbyServiceAdvertiser(peer: self.peerID, discoveryInfo: nil, serviceType: "mp-numbers")
            self.mcAdvertiserAssistant.delegate = self
            self.mcAdvertiserAssistant.startAdvertisingPeer()
            
        }))
        
        actionSheet.addAction(UIAlertAction(title: "Connect to Existing Session", style: .default, handler: { (action:UIAlertAction) in
            let mcBrowser = MCBrowserViewController(serviceType: "mp-numbers", session: self.mcSession)
            mcBrowser.delegate = self
            self.present(mcBrowser, animated: true)
        }))
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        self.present(actionSheet, animated: true, completion: nil)
    }
  
    // A new action added to send the image stored in the bundle
    @IBAction func sendImageAsResource(_ sender: Any) {
        if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum){
            
            imagePicker.delegate = self
            imagePicker.sourceType = .savedPhotosAlbum
            imagePicker.allowsEditing = false
            
            present(imagePicker, animated: true, completion: nil)
        }
        
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        var selectedFileName = ""
        if let imageUrl = info[.imageURL] as? URL {
            selectedFileName = imageUrl.lastPathComponent
            sendPhoto(withURL: imageUrl, fileName: selectedFileName)
        }
        
        picker.dismiss(animated: true, completion: nil)
        
        
    }
    
    // MARK: - Functions
    
    func sendPhoto(withURL url: URL, fileName: String)
    {
        guard let guestPeerID = mcSession.connectedPeers.first else {
            return
        }
        
        if let fileSizeToTransfer = getFileSize(atURL: url)
        {
            bytesExpectedToExchange = fileSizeToTransfer
            let fileTransferMeta = ["fileSize": bytesExpectedToExchange]
        
            let encoder = JSONEncoder()
            
            if let JSONData = try? encoder.encode(fileTransferMeta)
            {
                
                try? mcSession.send(JSONData, toPeers: mcSession.connectedPeers,
                                    with: .reliable)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1)
        { [weak self] in
            self?.initiateFileTransfer(ofImage: url, fileName: fileName , to: guestPeerID)
        }
    }
    
    func initiateFileTransfer(ofImage imageURL: URL, fileName: String, to guestPeerID: MCPeerID)
    {
        // Initialize and fire a timer to check the status of the file
        // transfer every 0.1 second
        checkProgressTimer = Timer.scheduledTimer(timeInterval: 0.1,
                                                  target: self,
                                                  selector: #selector(updateProgressStatus),
                                                  userInfo: nil,
                                                  repeats: true)
        
        progress = mcSession.sendResource(at: imageURL,
                                          withName: fileName,
                                          toPeer: guestPeerID,
                                          withCompletionHandler: { (error) in
                                            
                                            // Handle errors
                                            if let error = error as NSError?
                                            {
                                                print("Error: \(error.userInfo)")
                                                print("Error: \(error.localizedDescription)")
                                            }
                                            
                                          })
    }
    
    func getFileSize(atURL url: URL) -> Int?
    {
        let urlResourceValue = try? url.resourceValues(forKeys: [.fileSizeKey])
        
        return urlResourceValue?.fileSize
    }
    
    @objc
    func updateProgressStatus()
    {
        transferTimeElapsed += 0.1
        
        if let progress = progress {

            let percentCompleted = 100 * progress.fractionCompleted
            let dataExchangedInMB = (Double(bytesExpectedToExchange)
                                     * progress.fractionCompleted) / 1000000

            let megabytesPerSecond = (1 * dataExchangedInMB) / transferTimeElapsed
            
            // Convert dataExchangedInMB into a string rounded to 2 decimal places
            let dataExchangedInMBString = String(format: "%.2f", dataExchangedInMB)
            // Convert megabytesPerSecond into a string rounded to 2 decimal places
            let megabytesPerSecondString = String(format: "%.2f", megabytesPerSecond)
            
            transferStatusLabel.text = "\(percentCompleted.rounded())% - \(dataExchangedInMBString) MB @ \(megabytesPerSecondString) MB/s"

            if percentCompleted >= 100
            {
                transferStatusLabel.text = "Transfer finished!"
                checkProgressTimer?.invalidate()
                checkProgressTimer = nil
                transferTimeElapsed = 0.0
            }
        }
    }

    // MARK: - Session Delegate
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case MCSessionState.connected:
            print("Connected: \(peerID.displayName)")
            DispatchQueue.main.async {
                self.connectionStateLabel.text = "Connected"
                self.connectionStateLabel.textColor = .green
            }
            
            
        case MCSessionState.connecting:
            print("Connecting: \(peerID.displayName)")
            
        case MCSessionState.notConnected:
            print("Not connected: \(peerID.displayName)")
            DispatchQueue.main.async {
                self.connectionStateLabel.text = "Not Connected"
                self.connectionStateLabel.textColor = .black
            }
            
        @unknown default:
            fatalError()
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID)
    {
        if let fileTransferMeta = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Int],
           let fileSizeToReceive = fileTransferMeta["fileSize"]
        {
            bytesExpectedToExchange = fileSizeToReceive
            print("Bytes expected to receive: \(fileSizeToReceive)")
            return
        }
        
        
        if let text = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                //display the text in the label
                self.transferStatusLabel.text = text
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        
    }
    
    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) {
        
        self.progress = progress
        
        DispatchQueue.main.async { [unowned self] in
            
            self.checkProgressTimer = Timer.scheduledTimer(timeInterval: 0.1,
                                                           target: self,
                                                           selector: #selector(updateProgressStatus),
                                                           userInfo: nil,
                                                           repeats: true)
        }
    }
    
    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) {
        
        if let url = localURL
        {
            DispatchQueue.main.async { [weak self] in
                self?.handleDownloadCompletion(withImageURL: url)
            }
        }
    }
    
    func handleDownloadCompletion(withImageURL url: URL) {
            
        transferStatusLabel.text = "Transfer complete!"
        checkProgressTimer?.invalidate()
        checkProgressTimer = nil
        transferTimeElapsed = 0.0
        
        imageView.image = UIImage(contentsOfFile: url.path)
    }
    
    // MARK: - Browser Delegate
    
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        dismiss(animated: true)
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        dismiss(animated: true)
    }
    
    // MARK: - Advertiser Delegate
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        //accept the connection/invitation
        invitationHandler(true, mcSession)
    }
        
}

