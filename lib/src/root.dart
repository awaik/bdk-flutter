import 'package:bdk_flutter/bdk_flutter.dart';
import 'package:bdk_flutter/src/utils/custom_objects.dart';
import 'package:bdk_flutter/src/utils/exceptions/broadcast_exceptions.dart';
import 'package:bdk_flutter/src/utils/exceptions/key_exceptions.dart';
import 'package:bdk_flutter/src/utils/exceptions/wallet_exceptions.dart';
import 'package:bdk_flutter/src/utils/validators.dart';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'utils/loader.dart';

class BdkWallet {
  Future<ResponseWallet> createWallet(
      {String? mnemonic,
        String? password,
        String? descriptor,
        String? changeDescriptor,
        required Network network,
        required String blockChainConfigUrl,
        String? socks5OrProxy,
        required Blockchain blockchain,
        String? retry,
        String? timeOut}) async {
    try {
      if ((mnemonic == null || mnemonic.isEmpty ) && (descriptor == null || descriptor.isEmpty)) {
        throw const WalletException.insufficientCoreArguments("Requires a mnemonic or a descriptor");
      }
      if((mnemonic != null )&& (descriptor != null ))
      {
        throw const WalletException.repetitiousArguments("Provided both mnemonic and descriptor.");
      }
      if (blockChainConfigUrl.isEmpty||blockChainConfigUrl == null ) {
        throw const WalletException.invalidBlockchainUrl();
      }
      if (descriptor != null || changeDescriptor!=null) {
        await loaderApi.walletInit(
            descriptor: descriptor.toString(),
            changeDescriptor: changeDescriptor.toString(),
            network: network.name.toString(),
            blockchain: blockchain.name.toString(),
            socks5OrProxy: socks5OrProxy.toString(),
            url: blockChainConfigUrl);
      } else {
        var key = await createDescriptorsFromMnemonic(
            network: network,
            mnemonic: mnemonic.toString(),
            password: password,
            type: Descriptor.P2PK,
            descriptorPath: 'm/0',
            changeDescriptorPath: "m/1"
        );
        await loaderApi.walletInit(
            descriptor: key.descriptor,
            changeDescriptor: key.changeDescriptor,
            network: network.name.toString(),
            blockchain: blockchain.name.toString(),
            url: blockChainConfigUrl,
            socks5OrProxy: socks5OrProxy.toString());
      }
      final res = await loaderApi.getWallet();
      return res;
    } on FfiException catch (e) {
      throw WalletException.unexpected( e.message);
    }
  }

  Future<ResponseWallet> getWallet() async {
    try {
      return await loaderApi.getWallet();
    } on FfiException catch (e) {
      throw WalletException.unexpected(e.message);
    }
  }

  Future<String> getNewAddress() async {
    try {
      var res = await loaderApi.getNewAddress();
      return res.toString();
    } on FfiException catch (e) {
      throw WalletException.unexpected( e.message);
    }
  }

  Future<String> getBalance() async {
    try {
      var res = await loaderApi.getBalance();
      return res.total.toString();
    } on FfiException catch (e) {
      throw WalletException.unexpected(e.message);
    }
  }

  Future<String> getLastUnusedAddress() async {
    try {
      var res = await loaderApi.getLastUnusedAddress();
      return res.toString();
    } on FfiException catch (e) {
      throw WalletException.unexpected(e.message);
    }
  }

  syncWallet() async {
    try {
      print("Syncing Wallet");
      await loaderApi.syncWallet();
    } on FfiException catch (e) {
      throw WalletException.unexpected(e.message);
    }
  }

  Future<List<Transaction>> getTransactions() async {
    try {
      final res = await loaderApi.getTransactions();
      return res;
    } on FfiException catch (e) {
      throw WalletException.unexpected(e.message);
    }

  }

  Future<List<Transaction>> getPendingTransactions() async {
    try {
      List<Transaction> unConfirmed = [];
      final res = await getTransactions();
      for (var e in res) {
        e.maybeMap(
            orElse: () {},
            unconfirmed: (e) {
              unConfirmed.add(e);
            });
      }
      return unConfirmed;
    } on WalletException catch (e) {
      rethrow;
    }
  }

  Future<List<Transaction>> getConfirmedTransactions() async {
    try {
      List<Transaction> confirmed = [];
      final res = await getTransactions();
      for (var e in res) {
        e.maybeMap(
            orElse: () {},
            confirmed: (e) {
              confirmed.add(e);
            });
      }
      return confirmed;
    } on WalletException catch (e) {
      rethrow;
    }
  }

  Future<String> createTransaction(
      {required String recipient,
        required int amount,
        required double feeRate}) async {
    try {
      if(amount<100) throw const BroadcastException.insufficientBroadcastAmount( "The minimum amount should be greater 100");
      final res = await loaderApi.createTransaction(
          recipient: recipient, amount: amount, feeRate: feeRate);
      return res;
    } on FfiException catch (e) {
      if(e.message.contains("InsufficientFunds")){
        final message = e.message.split("InsufficientFunds").last;
        throw  BroadcastException.insufficientFunds(message);
      }
      throw BroadcastException.unexpected(e.message);
    }
  }



  Future<void> signTransaction({required String psbt}) async {
    try {
      await loaderApi.sign(psbtStr: psbt);
    } on FfiException catch (e) {
      throw BroadcastException.unexpected( e.message);
    }
  }

  Future<String> broadcastTransaction({required String psbt}) async {
    try {
      final txid = await loaderApi.broadcast(psbtStr: psbt);
      return txid;
    } on FfiException catch (e) {
      throw BroadcastException.unexpected(e.message);
    }
  }

  Future<String> quickSend({required String recipient,
    required int amount,
    required double feeRate}) async {
    try {
      if(amount<100) throw const BroadcastException.insufficientBroadcastAmount( "The minimum amount should be greater 100");
      final psbt = await createTransaction(recipient: recipient, amount: amount, feeRate: feeRate);
      await signTransaction(psbt: psbt);
      final txid = await broadcastTransaction(psbt: psbt);
      return txid;
    } on FfiException catch (e) {
      if(e.message.contains("InsufficientFunds")){
        final message = e.message.split("InsufficientFunds").last;
        throw  BroadcastException.insufficientFunds(message);
      }
      throw BroadcastException.unexpected(e.message);
    }
  }
}

Future<String> generateMnemonic(
    {WordCount ? wordCount ,
      Entropy? entropy }) async {
  try {
    if((wordCount != null  ) && (entropy != null ))
    {
      var res = await loaderApi.generateSeedFromEntropy(entropy: entropy.name.toString());
      return res;
    } else if( wordCount != null ) {
      var res = await loaderApi.generateSeedFromWordCount(wordCount: wordCount.name.toString());
      return res;
    } else if(entropy != null )
    {
      var res = await loaderApi.generateSeedFromEntropy(entropy: entropy.name.toString());
      return res;
    } else{
      var res = await loaderApi.generateSeedFromEntropy(entropy: Entropy.Entropy128.name.toString());
      return res;
    }
  } on FfiException catch (e) {
    throw KeyException.unexpected(e.message);
  }
}

Future<String> createXprv(
    {required Network network,
      required String mnemonic,
      String? password = ''}) async {
  try {
    var res = await createExtendedKey(network: network, mnemonic: mnemonic, password: password.toString());
    return res.xprv.toString();
  } on KeyException  {
    rethrow;
  }
}
Future<String> createXpub(
    {required Network network,
      required String mnemonic,
      String? password = ''}) async {
  try {
    var res = await createExtendedKey(network: network, mnemonic: mnemonic, password: password.toString());
    return res.xpub.toString();
  } on KeyException  {
    rethrow;
  }
}

Future<ExtendedKeyInfo> createExtendedKey(
    {required Network network,
      required String mnemonic,
      String? password = ''}) async {
  try {
    if(!isValidMnemonic(mnemonic.toString())) throw const KeyException.badWordCount("The mnemonic length must be a multiple of 6 greater than or equal to 12 and less than 24");
    var res = await loaderApi.createKey(
      nodeNetwork: network.name.toString(),
      mnemonic: mnemonic,
      password: password,
    );
    return res;
  } on FfiException catch (e) {
    if(e.message.contains("UnknownWord")){
      final message = e.message.split("value:").last;
      throw  KeyException.invalidMnemonic(message);
    }
    throw KeyException.unexpected(e.message);
  }
}
Future<DescriptorExtendedKey> createDescriptorExtendedKey(
    {required Network network,
      required String mnemonic,
      String? path,
      String? password = ''}) async {
  try {
    if(!isValidMnemonic(mnemonic.toString())) throw const KeyException.badWordCount("The mnemonic length must be a multiple of 6 greater than or equal to 12 and less than 24");
    var res = await loaderApi.createDescriptorSecretKeys(nodeNetwork: network.name.toString(), mnemonic: mnemonic, path: path ?? "m");
    return res;
  } on FfiException catch (e) {
    if(e.message.contains("UnknownWord")){
      final message = e.message.split("value:").last;
      throw  KeyException.invalidMnemonic(message);
    }
    throw KeyException.unexpected(e.message);
  }
}

PathDescriptors createDescriptorsFromKeys(
    {required Descriptor type,
      required String derivedKey,
      String? changeDerivedKey,
      List<String>? publicKeys,
      int? threshold = 4}){
  switch (type) {
    case Descriptor.P2PKH:
      return PathDescriptors(descriptor:"pkh($derivedKey)", changeDescriptor: (changeDerivedKey==null||changeDerivedKey=="")? "":"pkh($changeDerivedKey)");
    case Descriptor.P2WPKH:
      return PathDescriptors(descriptor:"wpkh($derivedKey)", changeDescriptor: (changeDerivedKey==null||changeDerivedKey=="")? "":"wpkh($changeDerivedKey)");
    case Descriptor.P2SHP2WPKH:
      return  PathDescriptors(descriptor:"sh(wpkh($derivedKey))", changeDescriptor: (changeDerivedKey==null||changeDerivedKey=="")? "":"sh(wpkh($changeDerivedKey))");
    case Descriptor.P2SHP2WSHP2PKH:
      return  PathDescriptors(descriptor:"sh(wsh(pkh($derivedKey)))", changeDescriptor: (changeDerivedKey==null||changeDerivedKey=="")? "":"sh(wsh(pkh($changeDerivedKey)))");
    case Descriptor.MULTI:
      return _createMultiSigDescriptor(publicKeys: publicKeys, threshold: threshold!.toInt(), descriptorKey: derivedKey, changeDescriptorKey: changeDerivedKey);
    default:
      return PathDescriptors(descriptor:"wpkh($derivedKey)", changeDescriptor: (changeDerivedKey==null||changeDerivedKey=="")? "":"wpkh($changeDerivedKey)");
  }
}


Future<PathDescriptors> createDescriptorsFromMnemonic({
  required String descriptorPath,
  String? changeDescriptorPath,
  required Descriptor type,
  required String mnemonic,
  required Network network,
  String? password,
  List<String>? publicKeys,
  int? threshold = 4
}) async {

  var descriptorKey =await loaderApi.createDescriptorSecretKeys(nodeNetwork: network.name.toString(), password: password, mnemonic: mnemonic, path: descriptorPath);
  var changeDescriptorKey = (changeDescriptorPath==null||changeDescriptorPath==""||changeDescriptorPath.isEmpty)?
  DescriptorExtendedKey(xprv: "", xpub: ""):
  await loaderApi.createDescriptorSecretKeys(
      nodeNetwork: network.name.toString(),
      password: password,
      mnemonic: mnemonic,
      path: changeDescriptorPath.toString()) ;

  switch (type) {
    case Descriptor.P2PKH:
      return PathDescriptors(descriptor:"pkh(${descriptorKey.xprv})", changeDescriptor: "pkh(${changeDescriptorKey.xprv})");
    case Descriptor.P2WPKH:
      return PathDescriptors(descriptor:"wpkh(${descriptorKey.xprv})", changeDescriptor: "wpkh(${changeDescriptorKey.xprv})");
    case Descriptor.P2SHP2WPKH:
      return  PathDescriptors(descriptor:"sh(wpkh(${descriptorKey.xprv}))", changeDescriptor: "sh(wpkh(${changeDescriptorKey.xprv}))");
    case Descriptor.P2SHP2WSHP2PKH:
      return  PathDescriptors(descriptor:"sh(wsh(pkh(${descriptorKey.xprv})))", changeDescriptor: "sh(wsh(pkh(${changeDescriptorKey.xprv})))");
    case Descriptor.MULTI:
      return _createMultiSigDescriptor(publicKeys: publicKeys, threshold: threshold!.toInt(), descriptorKey:  descriptorKey.xprv, changeDescriptorKey:  changeDescriptorKey.xprv);
    default:
      return PathDescriptors(descriptor:"wpkh(${descriptorKey.xprv})", changeDescriptor: "wpkh(${changeDescriptorKey.xprv})");
  }
}

PathDescriptors _createMultiSigDescriptor({required List<String>? publicKeys, int threshold = 2, required String descriptorKey, String? changeDescriptorKey}){
  if( publicKeys == null ) {
    throw const KeyException.invalidPublicKey("Public key must not be null");
  }
  if (threshold == 0 || threshold > publicKeys.length + 1) throw const KeyException.invalidThresholdValue();
  return  PathDescriptors(
      descriptor:"wsh(multi($threshold,$descriptorKey,${publicKeys.reduce((value, element) => '$value,$element')}))",
      changeDescriptor: (changeDescriptorKey==null||changeDescriptorKey=="") ? "":
      "wsh(multi($threshold,$changeDescriptorKey,${publicKeys.reduce((value, element) => '$value,$element')}))");
}


