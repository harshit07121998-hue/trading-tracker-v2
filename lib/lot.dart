class Lot {
  final int id;
  final int accountId;
  final String account;
  final String assetType;
  final String fundingType;
  final String symbol;
  final String? companyName;
  final double quantity;
  final double remainingQuantity;
  final double buyPrice;
  final DateTime purchaseDate;
  final double purchaseCharges;
  final double purchaseOtherCharges;
  final double myFunds;
  final double brokerFunded;
  final double mtfDailyCharge;
  final double? currentPrice;
  final DateTime? currentPriceUpdatedAt;
  final bool nifty500AtPurchase;

  const Lot({
    required this.id,
    required this.accountId,
    required this.account,
    required this.assetType,
    required this.fundingType,
    required this.symbol,
    this.companyName,
    required this.quantity,
    required this.remainingQuantity,
    required this.buyPrice,
    required this.purchaseDate,
    required this.purchaseCharges,
    required this.purchaseOtherCharges,
    required this.myFunds,
    required this.brokerFunded,
    required this.mtfDailyCharge,
    this.currentPrice,
    this.currentPriceUpdatedAt,
    required this.nifty500AtPurchase,
  });

  bool get isMtf => assetType.toUpperCase() == 'MTF';

  double get currentOrBuyPrice => currentPrice ?? buyPrice;

  double get marketValue =>
      remainingQuantity * currentOrBuyPrice;

  double get remainingRatio {
    if (quantity <= 0) return 0;
    return (remainingQuantity / quantity).clamp(0.0, 1.0);
  }

  // Only the portion belonging to the currently open quantity.
  double get allocatedMyFunds =>
      isMtf ? myFunds * remainingRatio : 0;

  double get allocatedPurchaseCharges =>
      (purchaseCharges + purchaseOtherCharges) * remainingRatio;

  // Invested capital for the currently open quantity.
  // MTF uses only the user's own funds; broker funding is excluded.
  double get investedValue {
    if (isMtf) {
      return allocatedMyFunds + allocatedPurchaseCharges;
    }
    return marketCost;
  }

  double get marketCost =>
      remainingQuantity * buyPrice + allocatedPurchaseCharges;

  // Gross mark-to-market P&L before MTF financing cost.
  double get grossUnrealisedPnL =>
      (currentOrBuyPrice - buyPrice) * remainingQuantity -
      (isMtf ? 0 : allocatedPurchaseCharges);

  // Accrued MTF interest is calculated from the purchase date to the
  // current calendar date. It is a calculation only and never changes Wallet.
  double mtfInterest({DateTime? tillDate}) {
    if (!isMtf || mtfDailyCharge <= 0 || remainingQuantity <= 0) {
      return 0;
    }

    final end = tillDate ?? DateTime.now();
    final startDate = DateTime(
      purchaseDate.year,
      purchaseDate.month,
      purchaseDate.day,
    );
    final endDate = DateTime(
      end.year,
      end.month,
      end.day,
    );

    final days = endDate.difference(startDate).inDays;
    return (days <= 0 ? 0 : days) * mtfDailyCharge;
  }

  double get netUnrealisedPnL {
    final gross = grossUnrealisedPnL;
    return isMtf ? gross - mtfInterest() : gross;
  }

  double get grossUnrealisedPnLPercent {
    final invested = investedValue;
    if (invested == 0) return 0;
    return grossUnrealisedPnL / invested * 100;
  }

  double get netUnrealisedPnLPercent {
    final invested = investedValue;
    if (invested == 0) return 0;
    return netUnrealisedPnL / invested * 100;
  }

  // Backwards-compatible getter used by existing screens.
  double get unrealisedPnL => netUnrealisedPnL;

  factory Lot.fromMap(Map<String, dynamic> map) {
    return Lot(
      id: (map['id'] as num).toInt(),
      accountId: (map['account_id'] as num).toInt(),
      account: (map['account'] ?? map['account_name'] ?? '') as String,
      assetType: (map['asset_type'] ?? 'Stock') as String,
      fundingType: (map['funding_type'] ?? 'Regular') as String,
      symbol: (map['symbol'] ?? '') as String,
      companyName: map['company_name'] as String?,
      quantity: _d(map['quantity']),
      remainingQuantity: _d(
        map['remaining_quantity'] ?? map['quantity'],
      ),
      buyPrice: _d(map['buy_price']),
      purchaseDate: DateTime.parse(map['purchase_date'] as String),
      purchaseCharges: _d(map['purchase_charges']),
      purchaseOtherCharges: _d(map['purchase_other_charges']),
      myFunds: _d(map['my_funds']),
      brokerFunded: _d(map['broker_funded']),
      mtfDailyCharge: _d(map['mtf_daily_charge']),
      currentPrice: map['current_price'] == null
          ? null
          : _d(map['current_price']),
      currentPriceUpdatedAt:
          map['current_price_updated_at'] == null
              ? null
              : DateTime.tryParse(
                  map['current_price_updated_at'] as String,
                ),
      nifty500AtPurchase:
          (map['nifty500_at_purchase'] ?? 0) == 1,
    );
  }

  static double _d(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
