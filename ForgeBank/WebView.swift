//
//  WebView.swift
//  ForgeBank
//
//  Created by Jon Knight on 03/07/2016.
//  Copyright © 2016 Identity Hipsters. All rights reserved.
//

import UIKit

class WebView: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        let defaults = UserDefaults.standard
        let rawOpenamUrl = defaults.string(forKey: "openam_url")!
        let rawOpenamUrl1 = rawOpenamUrl.components(separatedBy: "/")[2]
        let openamUrl = rawOpenamUrl1.components(separatedBy: ":")[0]
        print("OpenAM URL: " + openamUrl)
        
        var cookieProperties = [HTTPCookiePropertyKey: AnyObject]()
        cookieProperties[HTTPCookiePropertyKey.name] = "iPlanetDirectoryPro" as AnyObject
        cookieProperties[HTTPCookiePropertyKey.value] = SessionManager.currentSession.tokenId as AnyObject
        cookieProperties[HTTPCookiePropertyKey.domain] = openamUrl as AnyObject
        cookieProperties[HTTPCookiePropertyKey.originURL] = openamUrl as AnyObject
        cookieProperties[HTTPCookiePropertyKey.path] = "/" as AnyObject
        cookieProperties[HTTPCookiePropertyKey.version] = NSNumber(value: 0 as Int)
        cookieProperties[HTTPCookiePropertyKey.expires] = NSNull.self
        
        // Setting a Cookie
        if let newCookie = HTTPCookie(properties: cookieProperties) {
            // Made a copy of cookie (cookie can't be set)
            print("Newcookie: \(newCookie)")
            HTTPCookieStorage.shared.setCookie(newCookie)            
        }
        
        let myWebView:UIWebView = UIWebView(frame: CGRect(x: 0, y: 20, width: self.view.frame.size.width, height: self.view.frame.size.height))
        //            let myWebView:UIWebView = UIWebView(frame: CGRectMake(0, 0, UIScreen.mainScreen().bounds.width, UIScreen.mainScreen().bounds.height))
//        myWebView.loadRequest(NSURLRequest(URL: NSURL(string: "http://www.hsbc-uma.com:28080/openam/XUI/#uma/resources/")!))
        myWebView.loadRequest(URLRequest(url: URL(string: rawOpenamUrl + "/XUI/#uma/resources/")!))
        self.view.addSubview(myWebView)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

}
