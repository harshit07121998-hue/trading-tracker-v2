import 'dart:io';
import 'dart:typed_data';

import 'Database/database_helper.dart';
import 'lot.dart';

class LotManager {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<Map<String, dynamic>>> getAccounts() =>
      _db.getAccounts();

  Future<int> addAccount({
    required String broker,
    required String accountName,
  }) =>
      _db.addAccount(
        broker: broker,
        accountName: accountName,
      );

  Future<Lot> addPurchase({
    required int accountId,
    required String symbol,
    required double quantity,
    required double buyPrice,
    required DateTime purchaseDate,
    required String assetType,
    required String fundingType,
    double purchaseCharges = 0,
    double purchaseOtherCharges = 0,
    double myFunds = 0,
    double brokerFunded = 0,
    double mtfDailyCharge = 0,
    bool nifty500AtPurchase = false,
  }) async {
    final ownFunds = assetType == 'MTF'
        ? (myFunds > 0 ? myFunds : quantity * buyPrice - brokerFunded)
        : (myFunds > 0 ? myFunds : quantity * buyPrice);

    final walletDeduction =
        ownFunds + purchaseCharges + purchaseOtherCharges;

    final wallet = await _db.getWalletBalance(accountId);
    if (wallet < walletDeduction) {
      throw Exception(
        'Insufficient wallet balance. Available: ₹${wallet.toStringAsFixed(2)}',
      );
    }

    final id = await _db.addLot(
      accountId: accountId,
      assetType: assetType,
      fundingType: fundingType,
      symbol: symbol,
      quantity: quantity,
      buyPrice: buyPrice,
      purchaseDate: purchaseDate,
      purchaseCharges: purchaseCharges,
      purchaseOtherCharges: purchaseOtherCharges,
      myFunds: ownFunds,
      brokerFunded: brokerFunded,
      mtfDailyCharge: mtfDailyCharge,
      nifty500AtPurchase: nifty500AtPurchase,
    );

    await _db.addWalletTransaction(
      accountId: accountId,
      type: 'buy',
      amount: -walletDeduction,
      referenceType: 'lot',
      referenceId: id,
      description: 'Purchase $symbol',
    );

    return Lot.fromMap((await _db.getLot(id))!);
  }

  Future<List<Lot>> getAllOpenLots() async {
    final rows = await _db.getOpenLots();
    return rows.map(Lot.fromMap).toList();
  }

  Future<Lot?> getLotById(int id) async {
    final row = await _db.getLot(id);
    return row == null ? null : Lot.fromMap(row);
  }

  Future<void> updateLot({
    required int lotId,
    required int accountId,
    required String assetType,
    required String fundingType,
    required String symbol,
    required double quantity,
    required double buyPrice,
    required DateTime purchaseDate,
    required double purchaseCharges,
    required double purchaseOtherCharges,
    required double myFunds,
    required double brokerFunded,
    required double mtfDailyCharge,
    bool nifty500AtPurchase = false,
  }) async {
    final old = await getLotById(lotId);
    if (old == null) throw Exception('Position not found.');

    if (quantity < old.remainingQuantity) {
      throw Exception(
        'Quantity cannot be lower than the current open quantity. '
        'Square off the lot instead.',
      );
    }

    final oldCost =
        old.myFunds + old.purchaseCharges + old.purchaseOtherCharges;
    final newCost =
        myFunds + purchaseCharges + purchaseOtherCharges;

    if (accountId != old.accountId) {
      throw Exception(
        'Changing the broker account during edit is disabled. '
        'Use a transfer if the cash is moving between brokers.',
      );
    }

    final delta = newCost - oldCost;
    if (delta > 0) {
      final balance = await _db.getWalletBalance(accountId);
      if (balance < delta) {
        throw Exception('Insufficient wallet balance for this edit.');
      }
    }

    await _db.updateLot(
      lotId: lotId,
      accountId: accountId,
      assetType: assetType,
      fundingType: fundingType,
      symbol: symbol,
      quantity: quantity,
      buyPrice: buyPrice,
      purchaseDate: purchaseDate,
      purchaseCharges: purchaseCharges,
      purchaseOtherCharges: purchaseOtherCharges,
      myFunds: myFunds,
      brokerFunded: brokerFunded,
      mtfDailyCharge: mtfDailyCharge,
      nifty500AtPurchase: nifty500AtPurchase,
    );

    if (delta != 0) {
      await _db.addWalletTransaction(
        accountId: accountId,
        type: 'edit_adjustment',
        amount: -delta,
        referenceType: 'lot',
        referenceId: lotId,
        description: 'Open position edit adjustment',
      );
    }
  }

  Future<void> updateCurrentPrice({
    required int lotId,
    required double price,
  }) =>
      _db.updateCurrentPrice(lotId: lotId, price: price);

  double calculateMtfInterest(
    Lot lot, {
    DateTime? tillDate,
  }) =>
      lot.mtfInterest(tillDate: tillDate);

  Future<Map<String, double>> previewSquareOff({
    required Lot lot,
    required double sellPrice,
    required DateTime sellDate,
    double sellCharges = 0,
    double sellOtherCharges = 0,
  }) async {
    final gross =
        (sellPrice - lot.buyPrice) * lot.remainingQuantity;
    final interest = calculateMtfInterest(
      lot,
      tillDate: sellDate,
    );

    final purchaseCharges = lot.allocatedPurchaseCharges;
    final totalCharges =
        (lot.isMtf ? purchaseCharges : purchaseCharges) +
        interest +
        sellCharges +
        sellOtherCharges;

    return {
      'grossProfit': gross,
      'purchaseCharges': purchaseCharges,
      'mtfInterest': lot.isMtf ? interest : 0,
      'sellCharges': sellCharges,
      'sellOtherCharges': sellOtherCharges,
      'totalCharges': totalCharges,
      'netProfitLoss': gross - totalCharges,
    };
  }

  Future<void> squareOffLot({
    required Lot lot,
    required double sellPrice,
    required DateTime sellDate,
    double sellCharges = 0,
    double sellOtherCharges = 0,
  }) async {
    final preview = await previewSquareOff(
      lot: lot,
      sellPrice: sellPrice,
      sellDate: sellDate,
      sellCharges: sellCharges,
      sellOtherCharges: sellOtherCharges,
    );

    await _db.addSquareOff(
      lotId: lot.id,
      accountId: lot.accountId,
      assetType: lot.assetType,
      symbol: lot.symbol,
      quantity: lot.remainingQuantity,
      buyPrice: lot.buyPrice,
      sellPrice: sellPrice,
      purchaseDate: lot.purchaseDate,
      sellDate: sellDate,
      purchaseCharges: preview['purchaseCharges']!,
      purchaseOtherCharges: 0,
      mtfInterest: preview['mtfInterest']!,
      sellCharges: sellCharges,
      sellOtherCharges: sellOtherCharges,
      grossProfit: preview['grossProfit']!,
      totalCharges: preview['totalCharges']!,
      netProfitLoss: preview['netProfitLoss']!,
      myFunds: lot.allocatedMyFunds,
      brokerFunded: lot.brokerFunded * lot.remainingRatio,
    );

    // Wallet is intentionally separate from MTF interest.
    // MTF financing cost is recorded in the square-off calculation only;
    // it is never debited from Wallet.
    final walletCredit =
        lot.remainingQuantity * sellPrice -
        sellCharges -
        sellOtherCharges;

    await _db.addWalletTransaction(
      accountId: lot.accountId,
      type: 'sell',
      amount: walletCredit,
      referenceType: 'square_off',
      referenceId: lot.id,
      description: 'Square off ${lot.symbol}',
    );
  }

  Future<void> addDividend({
    required int lotId,
    required DateTime dividendDate,
    DateTime? receivedDate,
    required double eligibleQuantity,
    required double dividendPerShare,
    String? notes,
  }) async {
    final lot = await getLotById(lotId);
    if (lot == null) throw Exception('Position not found.');
    if (eligibleQuantity <= 0 || eligibleQuantity > lot.quantity) {
      throw Exception('Invalid dividend quantity.');
    }

    final id = await _db.addDividend(
      lotId: lotId,
      dividendDate: dividendDate,
      receivedDate: receivedDate,
      eligibleQuantity: eligibleQuantity,
      dividendPerShare: dividendPerShare,
      notes: notes,
    );

    if (receivedDate != null) {
      await _db.addWalletTransaction(
        accountId: lot.accountId,
        type: 'dividend',
        amount: eligibleQuantity * dividendPerShare,
        referenceType: 'dividend',
        referenceId: id,
        description: 'Dividend ${lot.symbol}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getClosedPositions() =>
      _db.getClosedPositions();

  Future<List<Map<String, dynamic>>> getOptionsTrades() =>
      _db.getOptionsTrades();

  Future<void> addOptionsTrade({
    required int accountId,
    required String underlying,
    required String optionType,
    required double strikePrice,
    required DateTime expiryDate,
    required DateTime tradeDate,
    required double quantity,
    required double buyPrice,
    required double sellPrice,
    double buyCharges = 0,
    double sellCharges = 0,
    double otherCharges = 0,
  }) async {
    final gross = (sellPrice - buyPrice) * quantity;
    final charges = buyCharges + sellCharges + otherCharges;
    final net = gross - charges;

    final buyCash = buyPrice * quantity + buyCharges;
    final sellCash = sellPrice * quantity - sellCharges - otherCharges;

    final wallet = await _db.getWalletBalance(accountId);
    if (wallet < buyCash) {
      throw Exception('Insufficient wallet balance.');
    }

    final id = await _db.addOptionsTrade(
      accountId: accountId,
      underlying: underlying,
      optionType: optionType,
      strikePrice: strikePrice,
      expiryDate: expiryDate,
      tradeDate: tradeDate,
      quantity: quantity,
      buyPrice: buyPrice,
      sellPrice: sellPrice,
      buyCharges: buyCharges,
      sellCharges: sellCharges,
      otherCharges: otherCharges,
      grossProfit: gross,
      totalCharges: charges,
      netProfitLoss: net,
      myFunds: buyCash,
    );

    await _db.addWalletTransaction(
      accountId: accountId,
      type: 'option',
      amount: sellCash - buyCash,
      referenceType: 'option',
      referenceId: id,
      description: 'Completed option trade',
    );
  }

  Future<Map<int, double>> getAllWalletBalances() =>
      _db.getAllWalletBalances();

  Future<void> setOpeningBalance({
    required int accountId,
    required double balance,
  }) =>
      _db.setOpeningBalance(
        accountId: accountId,
        balance: balance,
      );

  Future<void> addWalletTransaction({
    required int accountId,
    required String type,
    required double amount,
  }) =>
      _db.addWalletTransaction(
        accountId: accountId,
        type: type,
        amount: amount,
      );

  Future<void> transferFunds({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
  }) =>
      _db.transferFunds(
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        amount: amount,
      );

  Future<void> backupToFile(String path) async {
    final bytes = await _db.readDatabaseBytes();
    await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<void> restoreFromBytes(Uint8List bytes) =>
      _db.restoreDatabaseBytes(bytes);

  Future<double?> getLatestXirr(String category) async {
    final row = await _db.getLatestXirr(category);
    if (row == null) return null;
    return (row['xirr'] as num).toDouble();
  }

  Future<void> saveXirr(
    String category,
    double value,
  ) =>
      _db.saveXirrSnapshot(
        category: category,
        xirr: value,
      );

  Future<List<Map<String, dynamic>>> searchNifty500(
    String search,
  ) =>
      _db.searchNifty500(search);
}
