//
//  ViewController.swift
//


import UIKit
import AVFoundation
import MapKit
import SwiftyJSON   // https://cocoapods.org/pods/SwiftyJSON


@available(iOS 10.0, *)
class ViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var mapView: MKMapView?

    
    override func viewDidAppear(_ animated: Bool) {
        self.mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: self.view.frame.width, height: self.view.frame.height-500))
        self.view.addSubview(self.mapView!)
    }
    
    
    
    
    // Function to handle users wish to scan QR and register with an AM service
    @IBAction func registerButton(_ sender: Any) {
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            print("Failued to capture video input")
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            print("Failed to capture video input")
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        captureSession.startRunning()
    }
    
    
    // Called when AVCapture system finds a QR code
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            
            // Attempt to register using the scanned QR code
            FRPushUtils().registerWithQRCode(code: stringValue, snsDeviceID: snsDeviceID!, successHandler: registrationSuccessHandler, failureHandler: registrationFailureHandler)
        }
    }
    
    
    func registrationSuccessHandler() {
        print("Registration successful")
        let ac = UIAlertController(title: "Registration Successful", message: "Your device is now registered for authentication.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
        DispatchQueue.main.async(execute: {
            self.previewLayer.removeFromSuperlayer()
        });
        
    }
    
    
    func registrationFailureHandler() {
        print("Registration failed")
        let ac = UIAlertController(title: "Registration Failed", message: "Something went wrong.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
        DispatchQueue.main.async(execute: {
            self.previewLayer.removeFromSuperlayer()
        });
    }
    
    
    // Send users decision to approve/reject the login request
    @objc func sendLoginResponse(approved: Bool, aps: [String: AnyObject])
    {
        let data = aps["data"] as! String
        let messageId = aps["messageId"] as! String
        FRPushUtils().responseToAuthNotification(deny: !approved, dataJWT: data, messageId: messageId, completionHandler: {
            DispatchQueue.main.async(execute: {
                self.dismiss(animated: true)
            })
        })
    }
    
    
    // Called by appDelegate to handle the incoming SNS message
    func handleNotification(aps: [String: AnyObject]){
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        if (aps["messageId"] as! String).starts(with: "AUTHENTICATE:") {
            print("Incoming authentication request")
            
            // Handle metadata such as geolocation sent with message payload
            if (aps["data"] != nil) {
                let data = aps["data"] as! String
                let payload: String = FRPushUtils().getPayload(dataJWT: data)
                let geo = JSON(parseJSON: (JSON(parseJSON: payload).rawString()!))
                if geo["location"].exists() {
                    let location = JSON(parseJSON: geo["location"].rawString()!)
                    print("LOCATION: \(location)")
                    let loc:CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: location["latitude"].double!, longitude: location["longitude"].double!)
                    let region = MKCoordinateRegion.init(center: loc, latitudinalMeters: 2000, longitudinalMeters: 2000)
                    self.mapView!.setRegion(region, animated: true)
                    
                    let annotation = MKPointAnnotation()
                    let centerCoordinate = CLLocationCoordinate2D(latitude: location["latitude"].double!, longitude:location["longitude"].double!)
                    annotation.coordinate = centerCoordinate
                    annotation.title = "Login"
                    self.mapView!.addAnnotation(annotation)
                }
            }
            
            let alert = UIAlertController(title: "Authentication Request", message: aps["alert"] as! String, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Approve", style: .default, handler: { action in self.sendLoginResponse(approved: true, aps:aps) }))
            alert.addAction(UIAlertAction(title: "Reject", style: .cancel, handler: { action in self.sendLoginResponse(approved: false, aps:aps) }))
            self.present(alert, animated: true)
        } else {
            print("Unexpected notification")
        }
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

   
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}

