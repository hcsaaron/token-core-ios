//
//  ETHKeystore.swift
//  token
//
//  Created by xyz on 2018/1/3.
//  Copyright © 2018 ConsenLabs. All rights reserved.
//

import Foundation

public struct ETHKeystore: ExportableKeystore, PrivateKeyCrypto {
  public let id: String
  public let version = 3
  public var address: String
  public let crypto: Crypto
  public var meta: WalletMeta

  // Import from private key
  public init(password: String, privateKey: String, metadata: WalletMeta, id: String? = nil) throws {
    address = ETHKey(privateKey: privateKey).address
    crypto = Crypto(password: password, privateKey: privateKey)
    self.id = id ?? ETHKeystore.generateKeystoreId()
    meta = metadata
  }

  // MARK: - JSON
  public init(json: JSONObject) throws {
    guard
      let cryptoJson = (json["crypto"] as? JSONObject) ?? (json["Crypto"] as? JSONObject),
      json["version"] as? Int == version
      else {
        throw KeystoreError.invalid
    }

    id = (json["id"] as? String) ?? ETHKeystore.generateKeystoreId()
    address = json["address"] as? String ?? ""
    crypto = try Crypto(json: cryptoJson)

    if let metaJSON = json[WalletMeta.key] as? JSONObject {
      meta = try WalletMeta(json: metaJSON)
    } else {
      meta = WalletMeta(chain: .eth, source: .keystore)
    }
  }

  public func serializeToMap() -> [String: Any] {
    return [
      "id": id,
      "address": address,
      "createdAt": (Int)(meta.timestamp),
      "source": meta.source.rawValue,
      "chainType": meta.chain!.rawValue
    ]
  }
}
