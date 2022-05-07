//
//  Utils.swift
//  AutoFlowUI
//
//  Created by Felipe Campos on 4/30/22.
//

import Foundation

// TODO: Utils for server address, endpoints, common helper functions, etc.

// NOTE: this constitutes an initial refactor

class ServerUtils {
    static let JSON_ATTACHMENT = "application/json"
    static let PROTOBUF_ATTACHMENT = "attachment/x-protobuf"
    
    static func getServerDomain() -> String {
        return "https://autoflow.ngrok.io"
    }
    
    static func getRequest(domain: String, endpoint: String, args: [String : String] = [:], timeout: Double = 10.0) -> MutableURLRequest {
        var argString = ""
        for (name, val) in args {
            argString += "\(name)=\(val)&"
        }
        if (!argString.isEmpty) {
            argString.remove(at: argString.index(before: argString.endIndex)) // remove last &
        }
        
        let url: URL = URL(string: "\(domain)/\(endpoint)?\(argString)")!
                
        let cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        let request = MutableURLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeout) // TODO: change to URLRequest
        request.httpMethod = "GET"
        
        return request
    }
    
    static func postRequest(domain: String, endpoint: String, args: [String : String] = [:], bodyData: Data? = nil, dataType: String = "", timeout: Double = 10.0) -> MutableURLRequest {
        var argString = ""
        for (name, val) in args {
            argString += "\(name)=\(val)&"
        }
        if (!argString.isEmpty) {
            argString.remove(at: argString.index(before: argString.endIndex)) // remove last &
        }
        
        let url: URL = URL(string: "\(domain)/\(endpoint)?\(argString)")!
        let cachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        
        let request = MutableURLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 10.0)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue(dataType, forHTTPHeaderField: "Content-Type")
        request.setValue(dataType, forHTTPHeaderField: "Accept")
        
        return request
    }
    
    enum Status: Int, CaseIterable {
        case OK = 200
        case CREATED = 201
        case MULTIPLE_OPTIONS = 300
        case BAD_REQUEST = 400
        case UNAUTHORIZED = 401
        case FORBIDDEN = 403
        case NOT_FOUND = 404
        case NOT_ALLOWED = 405
        case CONFLICT = 409
        case IM_A_TEAPOT = 418
        case INTERNAL_SERVER_ERROR = 500
        case NOT_IMPLEMENTED = 501
        case BAD_GATEWAY = 502
        case SERVICE_UNAVAILABLE = 503
        
        case UNKNOWN_STATUS = 0
    }
    
    static func getStatus(code: Int) -> ServerUtils.Status {
        for status in Status.allCases {
            if (code == status.rawValue) {
                return status
            }
        }
        
        return .UNKNOWN_STATUS
    }
    
    static func getStatus(httpResponse: HTTPURLResponse) -> ServerUtils.Status {
        return getStatus(code: httpResponse.statusCode)
    }
    
    static func checkStatus(httpResponse: HTTPURLResponse, status: ServerUtils.Status) -> Bool {
        return httpResponse.statusCode == status.rawValue
    }
}
