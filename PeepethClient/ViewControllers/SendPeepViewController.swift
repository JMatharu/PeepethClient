//
//  SendPeepViewController.swift
//  PeepethClient
//
//  Created by Антон Григорьев on 07.07.2018.
//  Copyright © 2018 BaldyAsh. All rights reserved.
//

import UIKit
import BigInt
import web3swift

class SendPeepViewController: UIViewController {
    
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var postTheMessageLabel: UILabel!
    @IBOutlet weak var lockNowButton: UIButton!
    
    var textViewEdited = false
    
    var firstTimeEditing: Bool = true
    let service = Web3swiftService()
    let keysService = KeysService()
    let ipfsService = IPFSService()
    
    var shareHash: String? = nil
    var parentHash: String? = nil
    
    var sendingToBlockchain: Bool = false
    
    let animation = AnimationController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if shareHash != nil {
            postTheMessageLabel.text = "Share the message!"
        } else if parentHash != nil {
            postTheMessageLabel.text = "Parent the message!"
        } else {
            postTheMessageLabel.text = "Post the message!"
        }
        
        
        self.hideKeyboardWhenTappedAround()
        service.getETHbalance() { (result, error) in
            DispatchQueue.main.async {
                let ethUnits = Web3Utils.formatToEthereumUnits(result!,
                                                               toUnits: .eth,
                                                               decimals: 6,
                                                               decimalSeparator: ".")
                self.balanceLabel.text = "ETH Balance: " + ethUnits!
            }
            
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        lockNowButton.setImage(UIImage(named: "checkbox_unchecked"), for: .normal)
        sendingToBlockchain = false
        lockNowButton.setTitleColor(UIColor.black, for: .normal)
        textView.textColor = UIColor.lightGray
        textView.layer.borderWidth = 1.0
        textView.layer.borderColor = UIColor.lightGray.cgColor
        
    }
    
    @IBAction func lockNowAction(_ sender: UIButton) {
        sendingToBlockchain = !sendingToBlockchain
        lockNowButton.setTitleColor(sendingToBlockchain ? UIColor.blue : UIColor.black, for: .normal)
        lockNowButton.setImage(sendingToBlockchain ?
            UIImage(named: "checkbox_checked") :
            UIImage(named: "checkbox_unchecked"), for: .normal)
    }
    
    @IBAction func postPeep(_ sender: UIButton) {
        
        let alert = UIAlertController(title: "Send peep", message: nil, preferredStyle: UIAlertControllerStyle.alert)
        
        alert.addTextField { (textField) in
            textField.isSecureTextEntry = true
            textField.placeholder = "Enter your password"
        }
        
        //get private key
        let enterPasswordAction = UIAlertAction(title: "Enter", style: .default) { (alertAction) in
            self.animation.waitAnimation(isEnabled: true,
                                         notificationText: "Preparing transaction",
                                         selfView: self.view)
            let passwordText = alert.textFields![0].text!
            if let privateKey = self.keysService.getWalletPrivateKey(password: passwordText) {
                
                let content = self.textViewEdited ? self.textView.text : ""
                let shareHash = self.shareHash != nil ? self.shareHash! : ""
                let parentHash = self.parentHash != nil ? self.parentHash! : ""
                
                DispatchQueue.global().async {
                    self.prepareTransaction(privateKey: privateKey,
                                            password: passwordText,
                                            content: content!,
                                            shareHash: shareHash,
                                            parentHash: parentHash)
                }
                
                
            } else {
                self.showErrorAlert(error: "Wrong password")
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (cancel) in
            
        }
        
        alert.addAction(enterPasswordAction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func postPeepToServer(peep createdPeep: CreateServerPeep, withPassword: String) {

        DispatchQueue.global().async {
            let peepethService = PeepethAuthService(with: withPassword)
            peepethService.createPeep(data: createdPeep, completion: { (result) in
                switch result {
                case .Success(let resp) :
                    print(resp)
                    DispatchQueue.main.async {
                        self.animation.waitAnimation(isEnabled: false,
                                                     notificationText: nil,
                                                     selfView: self.view)
                        self.showAlertSuccessSendingPeep(peep: createdPeep, password: withPassword)
                    }
                    
                case .Error(let error) :
                    print(error.localizedDescription)
                }
                
            })
        }

    }
    
    func showErrorAlert(error: String?) {
        animation.waitAnimation(isEnabled: false,
                                notificationText: nil,
                                selfView: self.view)
        let alert = UIAlertController(title: "Error",
                                      message: error!,
                                      preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel",
                                         style: .cancel,
                                         handler: nil)
        alert.addAction(cancelAction)
        self.present(alert, animated: true, completion: nil)
    }
    
    func prepareTransaction(privateKey: String,
                            password: String,
                            content: String,
                            shareHash: String,
                            parentHash: String) {
        
        //get your adress
        service.getUntrustedAddress(completion: { (address) in
            if address != nil {
                // send to ipfs, get hash, intermediate transaction - show gas price
                let peep = Peep(type: "peep",
                                content: content,
                                pic: "",
                                untrustedAddress: address!,
                                untrustedTimestamp: Int(Date().timeIntervalSince1970),
                                shareID: shareHash,
                                parentID: parentHash)
                
                let createdServerPeep = CreateServerPeep(ipfs: "xxx",
                                                  author: address!,
                                                  content: content,
                                                  parentID: parentHash,
                                                  shareID: shareHash,
                                                  twitterShare: false,
                                                  picIpfs: "",
                                                  origContents: peep,
                                                  shareNow: true)
                self.postPeepToServer(peep: createdServerPeep, withPassword: password)
            } else {
                return
            }
        })
        
    }
    
    func postToIPFS(peep: Peep, password: String) {
        self.animation.waitAnimation(isEnabled: true,
                                     notificationText: "Transaction to blockchain",
                                     selfView: self.view)
        DispatchQueue.global().async {
            self.ipfsService.postToIPFS(data: peep, completion: { (result) in
                
                switch result {
                case .Success(let peepHash):
                    if self.shareHash != "" {
                        self.service.prepareSharePeepTransaction(peepDataHash: peepHash, completion: { (result) in
                            switch result {
                            case .Success(let transaction):
                                self.confirmTransactionAlert(password: password, transaction: transaction)
                            case .Error(let error):
                                self.showErrorAlert(error: error.localizedDescription)
                            }
                        })
                    } else if self.parentHash != "" {
                        self.service.prepareReplyPeepTransaction(peepDataHash: peepHash, completion: { (result) in
                            switch result {
                            case .Success(let transaction):
                                self.confirmTransactionAlert(password: password, transaction: transaction)
                            case .Error(let error):
                                self.showErrorAlert(error: error.localizedDescription)
                            }
                        })
                    } else {
                        self.service.preparePostPeepTransaction(peepDataHash: peepHash, completion: { (result) in
                            switch result {
                            case .Success(let transaction):
                                self.confirmTransactionAlert(password: password, transaction: transaction)
                            case .Error(let error):
                                self.showErrorAlert(error: error.localizedDescription)
                            }
                        })
                    }
                case .Error(let error):
                    self.showErrorAlert(error: error.localizedDescription)
                }
                
            })
        }
        
    }
    
    func confirmTransactionAlert(password: String, transaction: (TransactionIntermediate)) {
        
        animation.waitAnimation(isEnabled: false,
                                notificationText: nil,
                                selfView: self.view)
        
        let alert = UIAlertController(title: "Confirm transaction", message: nil, preferredStyle: UIAlertControllerStyle.alert)
        
        alert.addTextField { (textField) in
            //gas price
            let gasPrice = Web3Utils.formatToEthereumUnits(transaction.transaction.gasPrice,
                                                           toUnits: .eth,
                                                           decimals: 16,
                                                           decimalSeparator: ".")!
            let intGasPrice = Float(gasPrice)
            let formattedGasPrice = String(intGasPrice!*pow(10, 9))
            textField.text = "Estimated gas price: " + formattedGasPrice + " Gwei"
            textField.textAlignment = .center
            textField.font = UIFont.systemFont(ofSize: 10)
            textField.isUserInteractionEnabled = false
        }
        alert.addTextField { (textField) in
            //gas limit
            let gasLimit = Web3Utils.formatToEthereumUnits(transaction.transaction.gasLimit,
                                                           toUnits: .eth,
                                                           decimals: 16,
                                                           decimalSeparator: ".")!
            let intGasLimit = Float(gasLimit)
            let formattedGasLimit = String(intGasLimit!*pow(10, 18))
            textField.text = "Estimated gas limit: " + formattedGasLimit
            textField.textAlignment = .center
            textField.font = UIFont.systemFont(ofSize: 10)
            textField.isUserInteractionEnabled = false
        }
        
        let confirmTransaction = UIAlertAction(title: "OK", style: .default) { (alertAction) in
            self.animation.waitAnimation(isEnabled: true,
                                         notificationText: "Sending transaction",
                                         selfView: self.view)
            self.sendTransaction(password: password, transaction: transaction)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { (cancel) in
            
        }
        
        alert.addAction(confirmTransaction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func sendTransaction(password: String, transaction: (TransactionIntermediate)){
        
        self.service.sendTransaction(transaction: transaction,
                                     password: password,
                                     completion: { (result) in
            switch result {
            case .Success( _):
                self.showAlertSuccessTransaction()
            case .Error(let error):
                self.showErrorAlert(error: error.localizedDescription)
            }
        })
        
        
    }
    
    func showAlertSuccessTransaction() {
        animation.waitAnimation(isEnabled: false,
                                notificationText: nil,
                                selfView: self.view)
        let alert = UIAlertController(title: "Success transaction",
                                      message: "Thank you, now just wait while your transaction is providing in the blockchain. It may take some time :)",
                                      preferredStyle: UIAlertControllerStyle.alert)
        let okAction = UIAlertAction(title: "OK", style: .default) { (action) in
            self.dismiss(animated: true, completion: nil)
        }
        alert.addAction(okAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func showAlertSuccessSendingPeep(peep: CreateServerPeep, password: String) {
        animation.waitAnimation(isEnabled: false,
                                notificationText: nil,
                                selfView: self.view)
        let alert = UIAlertController(title: "Success posting peep",
                                      message: sendingToBlockchain ?
                                        "Thank you, now just confirm transaction to blockchain :)" :
            "Thank you for posting peep. Attention: it won't be posted to blockchain until you post it yourself",
                                      preferredStyle: UIAlertControllerStyle.alert)
        let okAction = UIAlertAction(title: "OK", style: .default) { (action) in
            if self.sendingToBlockchain {
                self.postToIPFS(peep: peep.origContents, password: password)
            } else {
                self.dismiss(animated: true, completion: nil)
            }
            
        }
        alert.addAction(okAction)
        if sendingToBlockchain {
            let cancelAction = UIAlertAction(title: "Cancel transaction",
                                             style: .cancel,
                                             handler: { (action) in
                self.dismiss(animated: true, completion: nil)
            })
            alert.addAction(cancelAction)
        }
        self.present(alert, animated: true, completion: nil)
    }
    
}

extension SendPeepViewController: UITextViewDelegate {
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        textViewEdited = true
        textView.layer.borderColor = UIColor.blue.cgColor
        if firstTimeEditing {
            textView.text = ""
            firstTimeEditing = false
        }
        
        textView.textColor = UIColor.black
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        textView.layer.borderColor = UIColor.lightGray.cgColor
    }
    
    
}