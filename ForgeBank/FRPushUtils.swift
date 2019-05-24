//
//  PushUtilities.swift
//  ForgeBank
//
//  Created by Jon Knight on 03/05/2019.
//  Copyright © 2019 Identity Hipsters. All rights reserved.
//

import Foundation
import JWT          // https://github.com/kylef/JSONWebToken.swift
import SwiftyJSON   // https://cocoapods.org/pods/SwiftyJSON

class FRPushUtils {

    // These values need to be stored in the user's defaults database to they persist across application runs
    let SNS_SECRET: String = "SNSsecret"
    let SNS_AUTHENDPOINT: String = "SNSauthEndpoint"
    let SNS_LOADBALANCECOOKIE: String = "SNSloadBalancerCookieData"


    // Return values specified as URL query parameter
    func getQueryStringParameter(url: URL, param: String) -> String? {
        guard let urlComponents = NSURLComponents(url: url, resolvingAgainstBaseURL: false),
            let queryItems = urlComponents.queryItems else {
                return nil
        }
        return queryItems.first(where: { $0.name == param })?.value
    }
    

    // Base64 decode and pad secrets and challenges sent by the Push Notification service
    func base64UrlDecode(url: String) -> Data? {
        var base64 = url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let length = Double(base64.lengthOfBytes(using: String.Encoding.utf8))
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = requiredLength - length
        if paddingLength > 0 {
            let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
            base64 += padding
        }
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }
    
    
    // Calculate a response to Push Notification service challenges using mutual secret
    func generateChallengeResponse(challenge: String, secret: String) -> String {
        let saltData:NSData = base64UrlDecode(url: secret)! as NSData
        let paramData:NSData = base64UrlDecode(url: challenge)! as NSData

        let data = NSMutableData(length: Int(CC_SHA256_DIGEST_LENGTH))!
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), saltData.bytes, saltData.length, paramData.bytes, paramData.length, data.mutableBytes)

        let hashResponseString = data.base64EncodedString(options: [])
        return hashResponseString;
    }

    
    // Main function which takes contents of a scanned QR code, then handles registration flow with ForgeRock AM
    // Requires suitable success and failure handlers
    func registerWithQRCode(code: String, snsDeviceID: String, successHandler:@escaping ()->Void, failureHandler:@escaping ()->Void) {
        let uri:URL = URL(string:code)!
        
        // Test we have a relevant QR code
        let scheme = uri.scheme
        if (scheme!.isEmpty || !(scheme == "pushauth")) {
            print("QR code does not contain a valid registration scheme")
            failureHandler()
        }
        
        // Extract parameters needed to generate and return a challenge response
        let regEndpoint = String(data: base64UrlDecode(url: getQueryStringParameter(url:uri, param: "r")!)!, encoding: .utf8)
        let authEndpoint = String(data: base64UrlDecode(url: getQueryStringParameter(url:uri, param: "a")!)!, encoding: .utf8)
        let messageId = getQueryStringParameter(url:uri, param: "m")
        let loadBalancerCookieData = String(data: base64UrlDecode(url: getQueryStringParameter(url:uri, param: "l")!)!, encoding: .utf8)
        let secret = getQueryStringParameter(url:uri, param: "s")!
        let challenge = getQueryStringParameter(url:uri, param: "c")
        let response = generateChallengeResponse(challenge: challenge!, secret: secret)
        
        let mechanismUid = NSUUID().uuidString
        
        // Construct the response object
        var claims = ClaimSet()
        claims["deviceId"] = snsDeviceID
        claims["mechanismUid"] = mechanismUid
        claims["response"] = response
        claims["communicationType"] = "apns"
        claims["deviceType"] = "ios"
                
        let jwt = JWT.encode(claims: claims, algorithm: .hs256(base64UrlDecode(url:secret)!))
        let data:JSON = [ "messageId": messageId, "jwt": jwt ]
        
        // POST response back to AM
        let request = NSMutableURLRequest(url: URL(string: regEndpoint!)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("resource=1.0, protocol=1.0", forHTTPHeaderField: "Accept-API-Version")
        request.addValue(loadBalancerCookieData!, forHTTPHeaderField: "Set-Cookie")
        request.httpBody = data.rawString()?.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request as URLRequest, completionHandler: {
            data, response, error in
            
            // A client-side error occured
            if error != nil {
                print("Failed to send registration request: \(String(describing: error?.localizedDescription))!")
                failureHandler()
            } else {
                let responseCode = (response as! HTTPURLResponse).statusCode
                let responseData = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
                
                // On success, store mutual secret, and authentication endpoint
                if (responseCode == 200) {
                    // Save authn endpoint, secret, and loadbalancer cookie
                    let defaults = UserDefaults.standard
                    defaults.set(secret, forKey: self.SNS_SECRET)
                    defaults.set(authEndpoint, forKey: self.SNS_AUTHENDPOINT)
                    defaults.set(loadBalancerCookieData, forKey: self.SNS_LOADBALANCECOOKIE)
                    defaults.synchronize()
                    successHandler()
                } else {
                    failureHandler()
                }
            }
        }).resume()
    }


    // Main function to respond to an incoming authentication request
    // Requires approve/reject flag and a completion handler - note we don't handle success or failure of the response
    func responseToAuthNotification(deny:Bool, dataJWT:String, messageId:String, completionHandler:@escaping ()->Void) {
        // Retreive secrets from user's defaults database
        let defaults = UserDefaults.standard
        if let secret = defaults.string(forKey: SNS_SECRET) {
            let authEndpoint = defaults.string(forKey: SNS_AUTHENDPOINT)
            let loadBalancerCookieData = defaults.string(forKey: SNS_LOADBALANCECOOKIE)
            
            do {
                // Decode request and attempt to generate response to challenge
                let requestClaims: ClaimSet = try JWT.decode(dataJWT, algorithm: .hs256(base64UrlDecode(url: secret)!))
                let response = generateChallengeResponse(challenge: requestClaims["c"] as! String, secret: secret)
                
                var claims = ClaimSet()
                claims["response"] = response
                if (deny) { claims["deny"] = true }
                
                let jwt = JWT.encode(claims: claims, algorithm: .hs256(base64UrlDecode(url: secret)!))
                let data:JSON = [ "messageId": messageId, "jwt": jwt ]

                // POST response to AM
                let request = NSMutableURLRequest(url: URL(string: authEndpoint!)!)
                request.httpMethod = "POST"
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                request.addValue("resource=1.0, protocol=1.0", forHTTPHeaderField: "Accept-API-Version")
                request.addValue(loadBalancerCookieData!, forHTTPHeaderField: "Set-Cookie")
                request.httpBody = data.rawString()?.data(using: .utf8)
                
                URLSession.shared.dataTask(with: request as URLRequest, completionHandler: {
                    data, response, error in
                    
                    // A client-side error occured
                    if error != nil {
                        print("Failed to send authentication request: \(String(describing: error?.localizedDescription))!")
                    } else {
                    
                        let responseCode = (response as! HTTPURLResponse).statusCode
                        let responseData = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
                        
                        if (responseCode == 200) {
                            // Treat success/failure differently?
                        }
                    }
                    completionHandler()
                }).resume()
                
            } catch {
                print("Failed to decode JWT: \(error)")
                completionHandler()
            }
        }
    }
    
    
    func getPayload(dataJWT:String) -> String {
        let defaults = UserDefaults.standard
        if let secret = defaults.string(forKey: SNS_SECRET) {
            do {
                // Decode request and attempt to generate response to challenge
                let requestClaims: ClaimSet = try JWT.decode(dataJWT, algorithm: .hs256(base64UrlDecode(url: secret)!))
                if (requestClaims["payload"] != nil) { return requestClaims["payload"] as! String }
                else { return "" }
            } catch {
                print("Failed to decode JWT: \(error)")
            }
        }
        return ""
    }

}
