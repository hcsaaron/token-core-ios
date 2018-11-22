//
//  WalletManager.swift
//  token
//
//  Created by Kai Chen on 05/09/2017.
//  Copyright © 2017 imToken PTE. LTD. All rights reserved.
//

import Foundation
import CoreBitcoin

public struct WalletManager {
  public static func importFromMnemonic(_ mnemonic: String, metadata: WalletMeta, encryptBy password: String, at path: String) throws -> BasicWallet {
    let identity = try IdentityValidator().validate()
    return try identity.importFromMnemonic(mnemonic, metadata: metadata, encryptBy: password, at: path)
  }

  /**
   Import ETH keystore json to generate wallet

   - parameter keystore: JSON text
   - parameter password: Password of keystore
   - parameter metadata: Wallet metadata
   */
  public static func importFromKeystore(_ keystore: JSONObject, encryptedBy password: String, metadata: WalletMeta) throws -> BasicWallet {
    let identity = try IdentityValidator().validate()
    _ = try V3KeystoreValidator(keystore).validate()
    return try identity.importFromKeystore(keystore, encryptedBy: password, metadata: metadata)
  }

  /**
   Import private key to generate wallet
   */
  public static func importFromPrivateKey(_ privateKey: String, encryptedBy password: String, metadata: WalletMeta, accountName: String? = nil) throws -> BasicWallet {
    let identity = try IdentityValidator().validate()
    return try identity.importFromPrivateKey(privateKey, encryptedBy: password, metadata: metadata, accountName: accountName)
  }

  public static func findWalletByPrivateKey(_ privateKey: String, on chainType: ChainType, network: Network? = nil, segWit: SegWit = .none) throws -> BasicWallet? {
    let identity = try IdentityValidator().validate()
    return try identity.findWalletByPrivateKey(privateKey, on: chainType, network: network, segWit: segWit)
  }

  public static func findWalletByMnemonic(_ mnemonic: String, on chainType: ChainType, path: String, network: Network? = nil, segWit: SegWit = .none) throws -> BasicWallet? {
    let identity = try IdentityValidator().validate()
    return try identity.findWalletByMnemonic(mnemonic, on: chainType, path: path, network: network, segWit: segWit)
  }

  public static func findWalletByKeystore(_ keystore: [String: Any], on chainType: ChainType, password: String) throws -> BasicWallet? {
    let identity = try IdentityValidator().validate()
    return try identity.findWalletByKeystore(keystore, on: chainType, password: password)
  }

  public static func findWalletByWalletID(_ walletID: String) throws -> BasicWallet {
    let identity = try IdentityValidator().validate()
    guard let wallet = identity.findWalletByWalletID(walletID) else {
      throw GenericError.walletNotFound
    }

    return wallet
  }

  public static func findWalletByAddress(_ address: String, on chainType: ChainType) throws -> BasicWallet {
    let identity = try IdentityValidator().validate()
    guard let wallet = identity.findWalletByAddress(address, on: chainType) else {
      throw GenericError.walletNotFound
    }

    return wallet
  }

  public static func exportPrivateKey(walletID: String, password: String) throws -> String {
    guard let wallet = Identity.currentIdentity?.findWalletByWalletID(walletID) else {
      throw GenericError.walletNotFound
    }

    return try wallet.privateKey(password: password)
  }

  public static func exportMnemonic(walletID: String, password: String) throws -> String {
    guard let wallet = Identity.currentIdentity?.findWalletByWalletID(walletID) else {
      throw GenericError.walletNotFound
    }
    return try wallet.exportMnemonic(password: password)
  }

  public static func exportKeystore(walletID: String, password: String) throws -> String {
    guard let wallet = Identity.currentIdentity?.findWalletByWalletID(walletID) else {
      throw GenericError.walletNotFound
    }

    guard wallet.verifyPassword(password) else {
      throw PasswordError.incorrect
    }

    return wallet.export()
  }

  /**
   Sign transaction with given parameters

   - returns signed data
   */
  public static func ethSignTransaction(
    walletID: String,
    nonce: String,
    gasPrice: String,
    gasLimit: String,
    to: String,
    value: String,
    data: String,
    password: String,
    chainID: Int
  ) throws -> TransactionSignedResult {
    guard let wallet = Identity.currentIdentity?.findWalletByWalletID(walletID) else {
      throw GenericError.walletNotFound
    }

    let privateKey = try wallet.privateKey(password: password)

    let raw: [String: String] = [
      "nonce": nonce,
      "gasPrice": gasPrice,
      "gasLimit": gasLimit,
      "to": to,
      "value": value,
      "data": data
    ]
    let tx = ETHTransaction(raw: raw, chainID: chainID)
    _ = tx.sign(with: privateKey)

    return tx.signedResult
  }

  public static func btcSignTransaction(
    walletID: String,
    to: String,
    amount: Int64,
    fee: Int64,
    password: String,
    outputs: [[String: Any]],
    changeIdx: Int,
    isTestnet: Bool,
    segWit: SegWit
  ) throws -> TransactionSignedResult {
    guard let wallet = Identity.currentIdentity?.findWalletByWalletID(walletID) else {
      throw GenericError.walletNotFound
    }

    guard let toAddress = BTCAddress(string: to) else {
      throw AddressError.invalid
    }

    let utxos: [UTXO] = try outputs.map { output in
      guard let utxo = UTXO(raw: output) else {
        throw GenericError.paramError
      }
      return utxo
    }

    let changeKey: BTCKey
    let privateKeys: [BTCKey]

    if wallet.imTokenMeta.source == .wif {
      let wif = try wallet.privateKey(password: password)
      changeKey = BTCKey(wif: wif)
      privateKeys = Array(repeating: changeKey, count: outputs.count)
    } else {
      let extendedKey = try wallet.privateKey(password: password)
      guard let keychain = BTCKeychain(extendedKey: extendedKey), let key = keychain.changeKey(at: UInt32(changeIdx)) else {
          throw GenericError.unknownError
      }
      changeKey = key
      privateKeys = utxos.map { output in
        let pathWithSlash = "/\(output.derivedPath ?? "")"
        let key = keychain.key(withPath: pathWithSlash)!
        key.isPublicKeyCompressed = true
        return key
      }
    }
    // 由于源码中的changeAddress似乎不是wallet本身，导致找零的钱不知道去哪了，因此将找零地址改为钱包地址（知道原理的朋友望告知）
//    let changeAddress = changeKey.address(on: isTestnet ? .testnet : .mainnet, segWit: segWit)
    let changeAddress: BTCAddress! = BTCAddress(string: wallet.address)
    let signer = try BTCTransactionSigner(utxos: utxos, keys: privateKeys, amount: amount, fee: fee, toAddress: toAddress, changeAddress: changeAddress)

    if segWit.isSegWit {
      return try signer.signSegWit()
    } else {
      return try signer.sign()
    }
  }

  /// Allow BTC wallet to switch between legacy/SegWit.
  public static func switchBTCWalletMode(walletID: String, password: String, segWit: SegWit) throws -> BasicWallet {
     let wallet = try findWalletByWalletID(walletID)

    if wallet.imTokenMeta.chain != .btc {
      throw GenericError.operationUnsupported
    }

    if wallet.imTokenMeta.segWit == segWit {
      return wallet
    }

    let newKeystore: Keystore
    var metadata = wallet.imTokenMeta
    metadata.segWit = segWit
    let path = BIP44.path(for: metadata.network, segWit: segWit)

    if let mnemonicKeystore = wallet.keystore as? EncMnemonicKeystore {
      guard wallet.keystore.verify(password: password) else {
        throw PasswordError.incorrect
      }
      let mnemonic = mnemonicKeystore.decryptMnemonic(password)

      newKeystore = try BTCMnemonicKeystore(
        password: password,
        mnemonic: mnemonic,
        path: path,
        metadata: metadata,
        id: walletID
      )
    } else {
      // private key export already verifies password
      let privateKey = try wallet.privateKey(password: password)
      newKeystore = try BTCKeystore(
        password: password,
        wif: privateKey,
        metadata: metadata,
        id: walletID
      )
    }
    // check if the new walle will override the wallet derived by identity
    if Identity.currentIdentity?.findWalletByAddress(newKeystore.address, on: .btc) != nil {
      throw AddressError.alreadyExist
    }

    wallet.keystore = newKeystore
    if !Identity.storage.flushWallet(newKeystore) {
      throw GenericError.storeWalletFailed
    }

    return wallet
  }
  

}
