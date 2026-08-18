import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance =
      DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'trading_tracker.db');

    return openDatabase(
      path,
      version: 4,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  // ============================================================
  // DATABASE CREATION
  // ============================================================

  Future<void> _createDatabase(
    Database db,
    int version,
  ) async {
    await _createTables(db);
    await _seedInitialMtfData(db);
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 4) {
      await _createTables(db);
    }

    await _seedInitialMtfData(db);
  }

  Future<void> _createTables(Database db) async {
    // ==========================================================
    // ACCOUNTS
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        broker TEXT NOT NULL,
        account_name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // APP META / ONE-TIME MIGRATIONS
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // ==========================================================
    // STOCK / MTF / CRYPTO PURCHASE LOTS
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        account_id INTEGER NOT NULL,

        asset_type TEXT NOT NULL,
        funding_type TEXT NOT NULL,

        symbol TEXT NOT NULL,
        company_name TEXT,

        quantity REAL NOT NULL,
        remaining_quantity REAL NOT NULL,

        buy_price REAL NOT NULL,
        purchase_date TEXT NOT NULL,

        purchase_charges REAL NOT NULL DEFAULT 0,
        purchase_other_charges REAL NOT NULL DEFAULT 0,

        my_funds REAL NOT NULL DEFAULT 0,
        broker_funded REAL NOT NULL DEFAULT 0,

        mtf_daily_charge REAL NOT NULL DEFAULT 0,

        current_price REAL,
        current_price_updated_at TEXT,

        nifty500_at_purchase INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,

        FOREIGN KEY (account_id)
          REFERENCES accounts(id)
      )
    ''');

    // ==========================================================
    // DIVIDENDS / INCOME
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS dividends (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        lot_id INTEGER NOT NULL,

        dividend_date TEXT NOT NULL,
        received_date TEXT,

        eligible_quantity REAL NOT NULL,
        dividend_per_share REAL NOT NULL,

        total_amount REAL NOT NULL,

        notes TEXT,

        created_at TEXT NOT NULL,

        FOREIGN KEY (lot_id)
          REFERENCES lots(id)
      )
    ''');

    // ==========================================================
    // SQUARE-OFF / CLOSED POSITIONS
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS square_offs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        lot_id INTEGER NOT NULL,
        account_id INTEGER NOT NULL,

        asset_type TEXT NOT NULL,
        symbol TEXT NOT NULL,

        quantity REAL NOT NULL,

        buy_price REAL NOT NULL,
        sell_price REAL NOT NULL,

        purchase_date TEXT NOT NULL,
        sell_date TEXT NOT NULL,

        purchase_charges REAL NOT NULL DEFAULT 0,
        purchase_other_charges REAL NOT NULL DEFAULT 0,

        mtf_interest REAL NOT NULL DEFAULT 0,

        sell_charges REAL NOT NULL DEFAULT 0,
        sell_other_charges REAL NOT NULL DEFAULT 0,

        gross_profit REAL NOT NULL DEFAULT 0,
        total_charges REAL NOT NULL DEFAULT 0,
        net_profit_loss REAL NOT NULL DEFAULT 0,

        my_funds REAL NOT NULL DEFAULT 0,
        broker_funded REAL NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,

        FOREIGN KEY (lot_id)
          REFERENCES lots(id),

        FOREIGN KEY (account_id)
          REFERENCES accounts(id)
      )
    ''');

    // ==========================================================
    // MTF INTEREST
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS mtf_interest (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        lot_id INTEGER NOT NULL,

        charge_date TEXT NOT NULL,

        quantity REAL NOT NULL,

        daily_charge REAL NOT NULL,

        charge_amount REAL NOT NULL,

        created_at TEXT NOT NULL,

        FOREIGN KEY (lot_id)
          REFERENCES lots(id)
      )
    ''');

    // ==========================================================
    // OPTIONS
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS options_trades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        account_id INTEGER NOT NULL,

        underlying TEXT NOT NULL,

        option_type TEXT NOT NULL,

        strike_price REAL NOT NULL,

        expiry_date TEXT NOT NULL,

        trade_date TEXT NOT NULL,

        quantity REAL NOT NULL,

        buy_price REAL NOT NULL,
        sell_price REAL NOT NULL,

        buy_charges REAL NOT NULL DEFAULT 0,
        sell_charges REAL NOT NULL DEFAULT 0,
        other_charges REAL NOT NULL DEFAULT 0,

        gross_profit REAL NOT NULL DEFAULT 0,
        total_charges REAL NOT NULL DEFAULT 0,
        net_profit_loss REAL NOT NULL DEFAULT 0,

        my_funds REAL NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,

        FOREIGN KEY (account_id)
          REFERENCES accounts(id)
      )
    ''');

    // ==========================================================
    // MANUAL XIRR CALCULATION HISTORY
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS xirr_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        category TEXT NOT NULL,

        xirr REAL NOT NULL,

        calculated_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // PORTFOLIO CASH FLOWS
    //
    // Used later for accurate XIRR calculations.
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cash_flows (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        category TEXT NOT NULL,

        reference_type TEXT NOT NULL,

        reference_id INTEGER,

        flow_date TEXT NOT NULL,

        amount REAL NOT NULL,

        description TEXT,

        created_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // MANUAL MARKET PRICES
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS market_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        asset_type TEXT NOT NULL,

        symbol TEXT NOT NULL,

        current_price REAL NOT NULL,

        updated_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // NIFTY 500
    // ==========================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS nifty500 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,

        symbol TEXT NOT NULL UNIQUE,

        company_name TEXT NOT NULL,

        active INTEGER NOT NULL DEFAULT 1,

        updated_at TEXT NOT NULL
      )
    ''');

    // ==========================================================
    // INDEXES
    // ==========================================================

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_lots_symbol
      ON lots(symbol)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_lots_account
      ON lots(account_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_lots_asset_type
      ON lots(asset_type)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_dividends_lot
      ON dividends(lot_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_square_offs_lot
      ON square_offs(lot_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cash_flows_category
      ON cash_flows(category)
    ''');
  }

  // ============================================================
  // ACCOUNTS
  // ============================================================

  Future<int> addAccount({
    required String broker,
    required String accountName,
  }) async {
    final db = await database;

    return db.insert(
      'accounts',
      {
        'broker': broker,
        'account_name': accountName,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getAccounts() async {
    final db = await database;

    return db.query(
      'accounts',
      orderBy: 'broker ASC, account_name ASC',
    );
  }

  // ============================================================
  // LOTS
  // ============================================================

  Future<int> addLot({
    required int accountId,
    required String assetType,
    required String fundingType,
    required String symbol,
    String? companyName,
    required double quantity,
    required double buyPrice,
    required DateTime purchaseDate,
    double purchaseCharges = 0,
    double purchaseOtherCharges = 0,
    double myFunds = 0,
    double brokerFunded = 0,
    double mtfDailyCharge = 0,
    bool nifty500AtPurchase = false,
  }) async {
    final db = await database;

    return db.insert(
      'lots',
      {
        'account_id': accountId,
        'asset_type': assetType,
        'funding_type': fundingType,
        'symbol': symbol,
        'company_name': companyName,
        'quantity': quantity,
        'remaining_quantity': quantity,
        'buy_price': buyPrice,
        'purchase_date': purchaseDate.toIso8601String(),
        'purchase_charges': purchaseCharges,
        'purchase_other_charges': purchaseOtherCharges,
        'my_funds': myFunds,
        'broker_funded': brokerFunded,
        'mtf_daily_charge': mtfDailyCharge,
        'nifty500_at_purchase':
            nifty500AtPurchase ? 1 : 0,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getOpenLots({
    int? accountId,
    String? symbol,
    String? assetType,
  }) async {
    final db = await database;

    final conditions = <String>[
      'remaining_quantity > 0',
    ];

    final args = <dynamic>[];

    if (accountId != null) {
      conditions.add('account_id = ?');
      args.add(accountId);
    }

    if (symbol != null) {
      conditions.add('UPPER(symbol) = UPPER(?)');
      args.add(symbol);
    }

    if (assetType != null) {
      conditions.add('asset_type = ?');
      args.add(assetType);
    }

    return db.query(
      'lots',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'purchase_date ASC, id ASC',
    );
  }

  Future<Map<String, dynamic>?> getLot(int id) async {
    final db = await database;

    final result = await db.query(
      'lots',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  Future<int> updateLot({
    required int lotId,
    int? accountId,
    String? assetType,
    String? fundingType,
    String? symbol,
    String? companyName,
    double? quantity,
    double? buyPrice,
    DateTime? purchaseDate,
    double? purchaseCharges,
    double? purchaseOtherCharges,
    double? myFunds,
    double? brokerFunded,
    double? mtfDailyCharge,
    bool? nifty500AtPurchase,
  }) async {
    final db = await database;
    final values = <String, dynamic>{};

    void put(String key, dynamic value) {
      if (value != null) values[key] = value;
    }

    put('account_id', accountId);
    put('asset_type', assetType);
    put('funding_type', fundingType);
    put('symbol', symbol);
    put('company_name', companyName);
    put('quantity', quantity);
    put('buy_price', buyPrice);
    put('purchase_date', purchaseDate?.toIso8601String());
    put('purchase_charges', purchaseCharges);
    put('purchase_other_charges', purchaseOtherCharges);
    put('my_funds', myFunds);
    put('broker_funded', brokerFunded);
    put('mtf_daily_charge', mtfDailyCharge);

    if (nifty500AtPurchase != null) {
      values['nifty500_at_purchase'] =
          nifty500AtPurchase! ? 1 : 0;
    }

    if (quantity != null) {
      final existing = await getLot(lotId);
      if (existing != null) {
        final oldQuantity =
            (existing['quantity'] as num).toDouble();
        final oldRemaining =
            (existing['remaining_quantity'] as num).toDouble();
        final alreadyClosed = oldQuantity - oldRemaining;
        final newRemaining = quantity - alreadyClosed;

        if (newRemaining < 0) {
          throw ArgumentError(
            'Quantity cannot be lower than the quantity already squared off.',
          );
        }

        values['remaining_quantity'] = newRemaining;
      }
    }

    if (values.isEmpty) return 0;

    values['updated_at'] =
        DateTime.now().toIso8601String();

    return db.update(
      'lots',
      values,
      where: 'id = ?',
      whereArgs: [lotId],
    );
  }

  Future<int> updateRemainingQuantity({
    required int lotId,
    required double quantity,
  }) async {
    final db = await database;

    return db.update(
      'lots',
      {
        'remaining_quantity': quantity,
      },
      where: 'id = ?',
      whereArgs: [lotId],
    );
  }

  Future<int> updateCurrentPrice({
    required int lotId,
    required double price,
  }) async {
    final db = await database;

    return db.update(
      'lots',
      {
        'current_price': price,
        'current_price_updated_at':
            DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [lotId],
    );
  }

  // ============================================================
  // DIVIDENDS
  // ============================================================

  Future<int> addDividend({
    required int lotId,
    required DateTime dividendDate,
    DateTime? receivedDate,
    required double eligibleQuantity,
    required double dividendPerShare,
    String? notes,
  }) async {
    final db = await database;

    final total =
        eligibleQuantity * dividendPerShare;

    return db.insert(
      'dividends',
      {
        'lot_id': lotId,
        'dividend_date':
            dividendDate.toIso8601String(),
        'received_date':
            receivedDate?.toIso8601String(),
        'eligible_quantity': eligibleQuantity,
        'dividend_per_share': dividendPerShare,
        'total_amount': total,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getDividendsForLot(
    int lotId,
  ) async {
    final db = await database;

    return db.query(
      'dividends',
      where: 'lot_id = ?',
      whereArgs: [lotId],
      orderBy: 'dividend_date ASC',
    );
  }

  // ============================================================
  // SQUARE OFF
  // ============================================================

  Future<int> addSquareOff({
    required int lotId,
    required int accountId,
    required String assetType,
    required String symbol,
    required double quantity,
    required double buyPrice,
    required double sellPrice,
    required DateTime purchaseDate,
    required DateTime sellDate,
    double purchaseCharges = 0,
    double purchaseOtherCharges = 0,
    double mtfInterest = 0,
    double sellCharges = 0,
    double sellOtherCharges = 0,
    required double grossProfit,
    required double totalCharges,
    required double netProfitLoss,
    double myFunds = 0,
    double brokerFunded = 0,
  }) async {
    final db = await database;

    return db.transaction((txn) async {
      final id = await txn.insert(
        'square_offs',
        {
          'lot_id': lotId,
          'account_id': accountId,
          'asset_type': assetType,
          'symbol': symbol,
          'quantity': quantity,
          'buy_price': buyPrice,
          'sell_price': sellPrice,
          'purchase_date':
              purchaseDate.toIso8601String(),
          'sell_date': sellDate.toIso8601String(),
          'purchase_charges': purchaseCharges,
          'purchase_other_charges':
              purchaseOtherCharges,
          'mtf_interest': mtfInterest,
          'sell_charges': sellCharges,
          'sell_other_charges':
              sellOtherCharges,
          'gross_profit': grossProfit,
          'total_charges': totalCharges,
          'net_profit_loss': netProfitLoss,
          'my_funds': myFunds,
          'broker_funded': brokerFunded,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      // Complete lot is being squared off.
      await txn.update(
        'lots',
        {
          'remaining_quantity': 0,
        },
        where: 'id = ?',
        whereArgs: [lotId],
      );

      return id;
    });
  }

  Future<List<Map<String, dynamic>>>
      getClosedPositions({
    String? assetType,
  }) async {
    final db = await database;

    if (assetType == null) {
      return db.query(
        'square_offs',
        orderBy: 'sell_date DESC, id DESC',
      );
    }

    return db.query(
      'square_offs',
      where: 'asset_type = ?',
      whereArgs: [assetType],
      orderBy: 'sell_date DESC, id DESC',
    );
  }

  // ============================================================
  // OPTIONS
  // ============================================================

  Future<int> addOptionsTrade({
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
    required double grossProfit,
    required double totalCharges,
    required double netProfitLoss,
    double myFunds = 0,
  }) async {
    final db = await database;

    return db.insert(
      'options_trades',
      {
        'account_id': accountId,
        'underlying': underlying,
        'option_type': optionType,
        'strike_price': strikePrice,
        'expiry_date':
            expiryDate.toIso8601String(),
        'trade_date':
            tradeDate.toIso8601String(),
        'quantity': quantity,
        'buy_price': buyPrice,
        'sell_price': sellPrice,
        'buy_charges': buyCharges,
        'sell_charges': sellCharges,
        'other_charges': otherCharges,
        'gross_profit': grossProfit,
        'total_charges': totalCharges,
        'net_profit_loss': netProfitLoss,
        'my_funds': myFunds,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<List<Map<String, dynamic>>>
      getOptionsTrades() async {
    final db = await database;

    return db.query(
      'options_trades',
      orderBy: 'trade_date DESC, id DESC',
    );
  }

  // ============================================================
  // MTF INTEREST
  // ============================================================

  Future<int> addMtfInterest({
    required int lotId,
    required DateTime chargeDate,
    required double quantity,
    required double dailyCharge,
    required double chargeAmount,
  }) async {
    final db = await database;

    return db.insert(
      'mtf_interest',
      {
        'lot_id': lotId,
        'charge_date':
            chargeDate.toIso8601String(),
        'quantity': quantity,
        'daily_charge': dailyCharge,
        'charge_amount': chargeAmount,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<double> getTotalMtfInterest(
    int lotId,
  ) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(charge_amount), 0)
      AS total
      FROM mtf_interest
      WHERE lot_id = ?
      ''',
      [lotId],
    );

    return (result.first['total'] as num?)?.toDouble() ?? 0;
  }

  // ============================================================
  // CASH FLOWS
  // ============================================================

  Future<int> addCashFlow({
    required String category,
    required String referenceType,
    int? referenceId,
    required DateTime date,
    required double amount,
    String? description,
  }) async {
    final db = await database;

    return db.insert(
      'cash_flows',
      {
        'category': category,
        'reference_type': referenceType,
        'reference_id': referenceId,
        'flow_date': date.toIso8601String(),
        'amount': amount,
        'description': description,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getCashFlows(
    String category,
  ) async {
    final db = await database;

    return db.query(
      'cash_flows',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'flow_date ASC, id ASC',
    );
  }

  // ============================================================
  // XIRR SNAPSHOTS
  // ============================================================

  Future<int> saveXirrSnapshot({
    required String category,
    required double xirr,
  }) async {
    final db = await database;

    return db.insert(
      'xirr_snapshots',
      {
        'category': category,
        'xirr': xirr,
        'calculated_at':
            DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>?> getLatestXirr(
    String category,
  ) async {
    final db = await database;

    final result = await db.query(
      'xirr_snapshots',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'calculated_at DESC',
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  // ============================================================
  // MANUAL MARKET PRICE
  // ============================================================

  Future<void> saveMarketPrice({
    required String assetType,
    required String symbol,
    required double price,
  }) async {
    final db = await database;

    await db.insert(
      'market_prices',
      {
        'asset_type': assetType,
        'symbol': symbol,
        'current_price': price,
        'updated_at':
            DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getMarketPrice({
    required String assetType,
    required String symbol,
  }) async {
    final db = await database;

    final result = await db.query(
      'market_prices',
      where: '''
        asset_type = ?
        AND UPPER(symbol) = UPPER(?)
      ''',
      whereArgs: [
        assetType,
        symbol,
      ],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  // ============================================================
  // NIFTY 500
  // ============================================================

  Future<void> replaceNifty500List(
    List<Map<String, String>> stocks,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('nifty500');

      for (final stock in stocks) {
        await txn.insert(
          'nifty500',
          {
            'symbol': stock['symbol'],
            'company_name':
                stock['company_name'],
            'active': 1,
            'updated_at':
                DateTime.now().toIso8601String(),
          },
          conflictAlgorithm:
              ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>>
      searchNifty500(String search) async {
    final db = await database;

    if (search.trim().isEmpty) {
      return db.query(
        'nifty500',
        where: 'active = 1',
        orderBy: 'company_name ASC',
      );
    }

    return db.query(
      'nifty500',
      where: '''
        active = 1
        AND (
          UPPER(symbol) LIKE UPPER(?)
          OR UPPER(company_name) LIKE UPPER(?)
        )
      ''',
      whereArgs: [
        '%$search%',
        '%$search%',
      ],
      orderBy: 'company_name ASC',
    );
  }

  Future<bool> isNifty500(String symbol) async {
    final db = await database;

    final result = await db.query(
      'nifty500',
      where: '''
        active = 1
        AND UPPER(symbol) = UPPER(?)
      ''',
      whereArgs: [symbol],
      limit: 1,
    );

    return result.isNotEmpty;
  }


    // ============================================================
    // WALLET LEDGER
    // ============================================================

    await db.execute('''
      CREATE TABLE IF NOT EXISTS wallet_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        reference_type TEXT,
        reference_id INTEGER,
        transfer_account_id INTEGER,
        transaction_date TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (account_id) REFERENCES accounts(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_wallet_account
      ON wallet_transactions(account_id)
    ''');


  // ============================================================
  // WALLET
  // ============================================================

  Future<int> addWalletTransaction({
    required int accountId,
    required String type,
    required double amount,
    String? referenceType,
    int? referenceId,
    int? transferAccountId,
    DateTime? transactionDate,
    String? description,
  }) async {
    final db = await database;
    return db.insert('wallet_transactions', {
      'account_id': accountId,
      'type': type,
      'amount': amount,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'transfer_account_id': transferAccountId,
      'transaction_date':
          (transactionDate ?? DateTime.now()).toIso8601String(),
      'description': description,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<double> getWalletBalance(int accountId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS balance
      FROM wallet_transactions
      WHERE account_id = ?
    ''', [accountId]);
    return (result.first['balance'] as num).toDouble();
  }

  Future<Map<int, double>> getAllWalletBalances() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT account_id, COALESCE(SUM(amount), 0) AS balance
      FROM wallet_transactions
      GROUP BY account_id
    ''');
    return {
      for (final row in rows)
        (row['account_id'] as num).toInt():
            (row['balance'] as num).toDouble(),
    };
  }

  Future<List<Map<String, dynamic>>> getWalletTransactions(
    int accountId,
  ) async {
    final db = await database;
    return db.query(
      'wallet_transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'transaction_date DESC, id DESC',
    );
  }

  Future<void> setOpeningBalance({
    required int accountId,
    required double balance,
  }) async {
    final db = await database;
    await db.delete(
      'wallet_transactions',
      where: 'account_id = ? AND type = ?',
      whereArgs: [accountId, 'opening'],
    );
    await db.insert('wallet_transactions', {
      'account_id': accountId,
      'type': 'opening',
      'amount': balance,
      'transaction_date': DateTime.now().toIso8601String(),
      'description': 'Opening wallet balance',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> transferFunds({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
  }) async {
    if (amount <= 0) {
      throw Exception('Transfer amount must be greater than zero.');
    }

    final db = await database;
    await db.transaction((txn) async {
      final result = await txn.rawQuery('''
        SELECT COALESCE(SUM(amount), 0) AS balance
        FROM wallet_transactions
        WHERE account_id = ?
      ''', [fromAccountId]);

      final balance = (result.first['balance'] as num).toDouble();
      if (balance < amount) {
        throw Exception('Insufficient wallet balance.');
      }

      final now = DateTime.now().toIso8601String();

      await txn.insert('wallet_transactions', {
        'account_id': fromAccountId,
        'type': 'transfer_out',
        'amount': -amount,
        'transfer_account_id': toAccountId,
        'transaction_date': now,
        'description': 'Transfer to another account',
        'created_at': now,
      });

      await txn.insert('wallet_transactions', {
        'account_id': toAccountId,
        'type': 'transfer_in',
        'amount': amount,
        'transfer_account_id': fromAccountId,
        'transaction_date': now,
        'description': 'Transfer from another account',
        'created_at': now,
      });
    });
  }

  // ============================================================
  // BACKUP / RESTORE
  // ============================================================

  Future<String> backupDatabaseTo(String destinationPath) async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    final sourcePath = await getDatabasePath();
    await File(sourcePath).copy(destinationPath);
    return destinationPath;
  }

  Future<void> restoreDatabaseFrom(String backupPath) async {
    final source = File(backupPath);

    if (!await source.exists()) {
      throw Exception('Backup file not found.');
    }

    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    final destination = File(await getDatabasePath());
    await source.copy(destination.path);
  }

  // ============================================================
  // ONE-TIME INITIAL MTF DATA
  // ============================================================

  Future<void> _seedInitialMtfData(Database db) async {
    final marker = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: ['initial_mtf_seed_v1'],
      limit: 1,
    );

    if (marker.isNotEmpty) return;

    final rows = <Map<String, dynamic>>[
      {
        'tradeDate': '2026-07-08T00:00:00.000',
        'symbol': 'Adani Power Ltd',
        'quantity': 80.0,
        'buyPrice': 216.6,
        'charges': 17.33,
      },
      {
        'tradeDate': '2026-05-19T00:00:00.000',
        'symbol': 'Ashok Leyland Ltd',
        'quantity': 106.0,
        'buyPrice': 152.46,
        'charges': 16.11,
      },
      {
        'tradeDate': '2026-06-01T00:00:00.000',
        'symbol': 'HDFC Bank Ltd',
        'quantity': 24.0,
        'buyPrice': 747.5,
        'charges': 17.94,
      },
      {
        'tradeDate': '2026-04-16T00:00:00.000',
        'symbol': 'Inox Wind Ltd',
        'quantity': 200.0,
        'buyPrice': 96.13,
        'charges': 19.23,
      },
      {
        'tradeDate': '2026-06-24T00:00:00.000',
        'symbol': 'Inox Wind Ltd',
        'quantity': 192.0,
        'buyPrice': 90.52,
        'charges': 17.0,
      },
      {
        'tradeDate': '2026-05-08T00:00:00.000',
        'symbol': 'JK Tyre & Industries Ltd',
        'quantity': 44.0,
        'buyPrice': 408.6,
        'charges': 17.98,
      },
      {
        'tradeDate': '2026-06-11T00:00:00.000',
        'symbol': 'REC Ltd',
        'quantity': 57.0,
        'buyPrice': 338.15,
        'charges': 19.0,
      },
      {
        'tradeDate': '2026-06-23T00:00:00.000',
        'symbol': 'Billionbrains Garage Ventures Ltd',
        'quantity': 113.0,
        'buyPrice': 194.5672,
        'charges': 22.0,
      },
      {
        'tradeDate': '2026-06-01T00:00:00.000',
        'symbol': 'Inox Wind Ltd',
        'quantity': 236.0,
        'buyPrice': 88.24,
        'charges': 21.24,
      },
      {
        'tradeDate': '2026-04-16T00:00:00.000',
        'symbol': 'Crompton Greaves Consumer Electricals Ltd',
        'quantity': 100.0,
        'buyPrice': 255.3,
        'charges': 25.53,
      },
      {
        'tradeDate': '2026-04-16T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 105.0,
        'buyPrice': 250.36,
        'charges': 26.24,
      },
      {
        'tradeDate': '2026-07-09T00:00:00.000',
        'symbol': 'Inox Wind Ltd',
        'quantity': 290.0,
        'buyPrice': 83.9,
        'charges': 24.04,
      },
      {
        'tradeDate': '2026-07-16T00:00:00.000',
        'symbol': 'Varun Beverages Ltd',
        'quantity': 55.0,
        'buyPrice': 464.35,
        'charges': 25.54,
      },
      {
        'tradeDate': '2026-06-05T00:00:00.000',
        'symbol': 'Bharti Airtel Ltd',
        'quantity': 16.0,
        'buyPrice': 1797.3,
        'charges': 28.55,
      },
      {
        'tradeDate': '2026-04-06T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 25.0,
        'buyPrice': 1175.2,
        'charges': 29.24,
      },
      {
        'tradeDate': '2026-04-09T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 24.0,
        'buyPrice': 1255.2,
        'charges': 30.12,
      },
      {
        'tradeDate': '2026-04-10T00:00:00.000',
        'symbol': 'Sun Pharmaceutical Industries Ltd',
        'quantity': 18.0,
        'buyPrice': 1652.5833,
        'charges': 30.0,
      },
      {
        'tradeDate': '2026-05-07T00:00:00.000',
        'symbol': 'United Spirits Ltd',
        'quantity': 23.0,
        'buyPrice': 1290.8,
        'charges': 29.69,
      },
      {
        'tradeDate': '2026-07-06T00:00:00.000',
        'symbol': 'Varun Beverages Ltd',
        'quantity': 65.0,
        'buyPrice': 495.1,
        'charges': 32.0,
      },
      {
        'tradeDate': '2026-05-07T00:00:00.000',
        'symbol': 'Vedanta Ltd',
        'quantity': 102.0,
        'buyPrice': 305.95,
        'charges': 31.15,
      },
      {
        'tradeDate': '2026-07-08T00:00:00.000',
        'symbol': 'Tata Power Company Ltd',
        'quantity': 106.0,
        'buyPrice': 371.7,
        'charges': 39.67,
      },
      {
        'tradeDate': '2026-07-29T00:00:00.000',
        'symbol': 'Varun Beverages Ltd',
        'quantity': 88.0,
        'buyPrice': 439.25,
        'charges': 39.0,
      },
      {
        'tradeDate': '2026-07-23T00:00:00.000',
        'symbol': 'Inox Wind Ltd',
        'quantity': 540.0,
        'buyPrice': 77.39,
        'charges': 42.0,
      },
      {
        'tradeDate': '2026-07-01T00:00:00.000',
        'symbol': 'HCL Technologies Ltd',
        'quantity': 43.0,
        'buyPrice': 1063.9,
        'charges': 45.83,
      },
      {
        'tradeDate': '2026-05-08T00:00:00.000',
        'symbol': 'HDFC Bank Ltd',
        'quantity': 58.0,
        'buyPrice': 784.6,
        'charges': 45.02,
      },
      {
        'tradeDate': '2026-04-23T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 47.0,
        'buyPrice': 1279.6553,
        'charges': 60.14,
      },
      {
        'tradeDate': '2026-05-13T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 51.0,
        'buyPrice': 1199.9,
        'charges': 61.0,
      },
      {
        'tradeDate': '2026-06-02T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 54.0,
        'buyPrice': 1135.0,
        'charges': 61.0,
      },
      {
        'tradeDate': '2026-06-29T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 52.0,
        'buyPrice': 1168.7,
        'charges': 60.95,
      },
      {
        'tradeDate': '2026-06-19T00:00:00.000',
        'symbol': 'HCL Technologies Ltd',
        'quantity': 55.0,
        'buyPrice': 1119.9873,
        'charges': 62.0,
      },
      {
        'tradeDate': '2025-10-07T00:00:00.000',
        'symbol': 'Crompton Greaves Consumer Electricals Ltd',
        'quantity': 10.0,
        'buyPrice': 287.6,
        'charges': 3.22,
      },
      {
        'tradeDate': '2025-11-19T00:00:00.000',
        'symbol': 'RattanIndia Power Ltd',
        'quantity': 291.0,
        'buyPrice': 10.16,
        'charges': 3.0,
      },
      {
        'tradeDate': '2025-09-11T00:00:00.000',
        'symbol': 'Crompton Greaves Consumer Electricals Ltd',
        'quantity': 20.0,
        'buyPrice': 319.65,
        'charges': 6.39,
      },
      {
        'tradeDate': '2026-03-11T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 29.0,
        'buyPrice': 225.49,
        'charges': 6.54,
      },
      {
        'tradeDate': '2025-06-05T00:00:00.000',
        'symbol': 'Crompton Greaves Consumer Electricals Ltd',
        'quantity': 20.0,
        'buyPrice': 348.25,
        'charges': 6.97,
      },
      {
        'tradeDate': '2025-09-26T00:00:00.000',
        'symbol': 'Inox Wind Ltd',
        'quantity': 51.0,
        'buyPrice': 137.35,
        'charges': 7.0,
      },
      {
        'tradeDate': '2025-06-05T00:00:00.000',
        'symbol': 'Aadhar Housing Finance Ltd',
        'quantity': 20.0,
        'buyPrice': 445.4,
        'charges': 9.03,
      },
      {
        'tradeDate': '2026-01-21T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 35.0,
        'buyPrice': 273.85,
        'charges': 9.58,
      },
      {
        'tradeDate': '2026-02-26T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 38.0,
        'buyPrice': 253.45,
        'charges': 10.0,
      },
      {
        'tradeDate': '2025-11-25T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 32.0,
        'buyPrice': 302.35,
        'charges': 9.28,
      },
      {
        'tradeDate': '2026-02-16T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 34.0,
        'buyPrice': 287.35,
        'charges': 10.0,
      },
      {
        'tradeDate': '2025-09-29T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 30.0,
        'buyPrice': 326.6,
        'charges': 10.0,
      },
      {
        'tradeDate': '2026-02-24T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 38.0,
        'buyPrice': 258.35,
        'charges': 10.0,
      },
      {
        'tradeDate': '2026-03-25T00:00:00.000',
        'symbol': 'Inox Wind Ltd',
        'quantity': 128.0,
        'buyPrice': 80.893,
        'charges': 10.0,
      },
      {
        'tradeDate': '2025-12-12T00:00:00.000',
        'symbol': 'Inox Wind Ltd',
        'quantity': 85.0,
        'buyPrice': 122.15,
        'charges': 10.38,
      },
      {
        'tradeDate': '2026-01-13T00:00:00.000',
        'symbol': 'Zen Technologies Ltd',
        'quantity': 9.0,
        'buyPrice': 1234.6,
        'charges': 11.11,
      },
      {
        'tradeDate': '2025-12-30T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 8.0,
        'buyPrice': 1411.2,
        'charges': 11.29,
      },
      {
        'tradeDate': '2026-01-12T00:00:00.000',
        'symbol': 'Zen Technologies Ltd',
        'quantity': 9.0,
        'buyPrice': 1266.6,
        'charges': 11.0,
      },
      {
        'tradeDate': '2026-03-30T00:00:00.000',
        'symbol': 'Axis Bank Ltd',
        'quantity': 10.0,
        'buyPrice': 1161.1,
        'charges': 11.61,
      },
      {
        'tradeDate': '2026-03-30T00:00:00.000',
        'symbol': 'Crompton Greaves Consumer Electricals Ltd',
        'quantity': 55.0,
        'buyPrice': 222.55,
        'charges': 12.39,
      },
      {
        'tradeDate': '2026-01-20T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 47.0,
        'buyPrice': 273.2,
        'charges': 12.84,
      },
      {
        'tradeDate': '2025-09-26T00:00:00.000',
        'symbol': 'Tata Consultancy Services Ltd',
        'quantity': 5.0,
        'buyPrice': 2897.7,
        'charges': 14.36,
      },
      {
        'tradeDate': '2025-11-06T00:00:00.000',
        'symbol': 'Infosys Ltd',
        'quantity': 10.0,
        'buyPrice': 1464.7,
        'charges': 14.65,
      },
      {
        'tradeDate': '2025-08-26T00:00:00.000',
        'symbol': 'Axis Bank Ltd',
        'quantity': 14.0,
        'buyPrice': 1051.0571,
        'charges': 14.71,
      },
      {
        'tradeDate': '2025-09-25T00:00:00.000',
        'symbol': 'Tata Consultancy Services Ltd',
        'quantity': 5.0,
        'buyPrice': 2958.2,
        'charges': 14.79,
      },
      {
        'tradeDate': '2026-02-04T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 11.0,
        'buyPrice': 1346.1,
        'charges': 15.0,
      },
      {
        'tradeDate': '2025-11-21T00:00:00.000',
        'symbol': 'Crompton Greaves Consumer Electricals Ltd',
        'quantity': 56.0,
        'buyPrice': 270.35,
        'charges': 15.14,
      },
      {
        'tradeDate': '2026-03-27T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 70.0,
        'buyPrice': 234.62,
        'charges': 16.42,
      },
      {
        'tradeDate': '2026-03-04T00:00:00.000',
        'symbol': 'JK Tyre & Industries Ltd',
        'quantity': 40.0,
        'buyPrice': 442.6,
        'charges': 17.7,
      },
      {
        'tradeDate': '2026-03-27T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 3591.0,
        'charges': 17.58,
      },
      {
        'tradeDate': '2025-07-28T00:00:00.000',
        'symbol': 'Inox Wind Ltd',
        'quantity': 115.0,
        'buyPrice': 161.56,
        'charges': 18.58,
      },
      {
        'tradeDate': '2025-09-22T00:00:00.000',
        'symbol': 'Jindal Steel Ltd',
        'quantity': 18.0,
        'buyPrice': 1038.4778,
        'charges': 19.0,
      },
      {
        'tradeDate': '2026-02-01T00:00:00.000',
        'symbol': 'Zen Technologies Ltd',
        'quantity': 14.0,
        'buyPrice': 1351.5857,
        'charges': 18.92,
      },
      {
        'tradeDate': '2026-03-24T00:00:00.000',
        'symbol': 'Varun Beverages Ltd',
        'quantity': 49.0,
        'buyPrice': 392.9,
        'charges': 19.0,
      },
      {
        'tradeDate': '2025-10-23T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 59.0,
        'buyPrice': 329.25,
        'charges': 19.43,
      },
      {
        'tradeDate': '2026-03-19T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 3902.4,
        'charges': 19.51,
      },
      {
        'tradeDate': '2026-03-12T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 4024.2,
        'charges': 20.12,
      },
      {
        'tradeDate': '2026-02-06T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 4030.7,
        'charges': 20.0,
      },
      {
        'tradeDate': '2025-10-13T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 14.0,
        'buyPrice': 1474.0,
        'charges': 21.0,
      },
      {
        'tradeDate': '2026-02-12T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 4144.0,
        'charges': 21.0,
      },
      {
        'tradeDate': '2025-10-15T00:00:00.000',
        'symbol': 'Asian Paints Ltd',
        'quantity': 9.0,
        'buyPrice': 2363.1444,
        'charges': 21.0,
      },
      {
        'tradeDate': '2026-01-21T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 4299.0,
        'charges': 21.42,
      },
      {
        'tradeDate': '2026-02-01T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 4387.4,
        'charges': 22.08,
      },
      {
        'tradeDate': '2026-01-13T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 4404.0,
        'charges': 22.22,
      },
      {
        'tradeDate': '2025-07-18T00:00:00.000',
        'symbol': 'Axis Bank Ltd',
        'quantity': 20.0,
        'buyPrice': 1106.9,
        'charges': 22.0,
      },
      {
        'tradeDate': '2025-11-24T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 4448.1,
        'charges': 22.0,
      },
      {
        'tradeDate': '2026-03-12T00:00:00.000',
        'symbol': 'Varun Beverages Ltd',
        'quantity': 54.0,
        'buyPrice': 414.3,
        'charges': 21.88,
      },
      {
        'tradeDate': '2026-01-13T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 5.0,
        'buyPrice': 4490.4,
        'charges': 22.67,
      },
      {
        'tradeDate': '2025-12-16T00:00:00.000',
        'symbol': 'Zen Technologies Ltd',
        'quantity': 17.0,
        'buyPrice': 1356.2,
        'charges': 23.06,
      },
      {
        'tradeDate': '2025-12-30T00:00:00.000',
        'symbol': 'Zen Technologies Ltd',
        'quantity': 17.0,
        'buyPrice': 1356.2,
        'charges': 22.71,
      },
      {
        'tradeDate': '2025-11-06T00:00:00.000',
        'symbol': 'ICICI Bank Ltd',
        'quantity': 18.0,
        'buyPrice': 1320.4,
        'charges': 23.35,
      },
      {
        'tradeDate': '2025-08-26T00:00:00.000',
        'symbol': 'Zen Technologies Ltd',
        'quantity': 16.0,
        'buyPrice': 1488.9375,
        'charges': 24.29,
      },
      {
        'tradeDate': '2026-03-04T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 18.0,
        'buyPrice': 1323.9,
        'charges': 23.49,
      },
      {
        'tradeDate': '2025-07-14T00:00:00.000',
        'symbol': 'Amara Raja Energy & Mobility Ltd',
        'quantity': 25.0,
        'buyPrice': 985.498,
        'charges': 25.0,
      },
      {
        'tradeDate': '2026-03-11T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 19.0,
        'buyPrice': 1381.1,
        'charges': 26.46,
      },
      {
        'tradeDate': '2025-12-16T00:00:00.000',
        'symbol': 'Axis Bank Ltd',
        'quantity': 22.0,
        'buyPrice': 1235.1,
        'charges': 26.94,
      },
      {
        'tradeDate': '2025-07-28T00:00:00.000',
        'symbol': 'Bajaj Finance Ltd',
        'quantity': 31.0,
        'buyPrice': 885.25,
        'charges': 27.42,
      },
      {
        'tradeDate': '2026-01-20T00:00:00.000',
        'symbol': 'Bajaj Finance Ltd',
        'quantity': 29.0,
        'buyPrice': 947.0,
        'charges': 27.16,
      },
      {
        'tradeDate': '2025-11-21T00:00:00.000',
        'symbol': 'Bajaj Finance Ltd',
        'quantity': 28.0,
        'buyPrice': 1005.2,
        'charges': 28.15,
      },
      {
        'tradeDate': '2025-08-18T00:00:00.000',
        'symbol': 'Manappuram Finance Ltd',
        'quantity': 110.0,
        'buyPrice': 268.1,
        'charges': 29.0,
      },
      {
        'tradeDate': '2025-10-28T00:00:00.000',
        'symbol': 'ICICI Bank Ltd',
        'quantity': 22.0,
        'buyPrice': 1359.8,
        'charges': 30.0,
      },
      {
        'tradeDate': '2025-09-11T00:00:00.000',
        'symbol': 'United Spirits Ltd',
        'quantity': 25.0,
        'buyPrice': 1311.9,
        'charges': 32.61,
      },
      {
        'tradeDate': '2025-05-06T00:00:00.000',
        'symbol': 'Biocon Ltd',
        'quantity': 100.0,
        'buyPrice': 344.15,
        'charges': 34.0,
      },
      {
        'tradeDate': '2026-03-19T00:00:00.000',
        'symbol': 'Havells India Ltd',
        'quantity': 27.0,
        'buyPrice': 1308.5,
        'charges': 35.49,
      },
      {
        'tradeDate': '2026-03-23T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 10.0,
        'buyPrice': 3651.72,
        'charges': 37.0,
      },
      {
        'tradeDate': '2025-11-21T00:00:00.000',
        'symbol': 'Hindustan Aeronautics Ltd',
        'quantity': 10.0,
        'buyPrice': 4592.5,
        'charges': 45.71,
      },
      {
        'tradeDate': '2025-12-05T00:00:00.000',
        'symbol': 'Axis Bank Ltd',
        'quantity': 48.0,
        'buyPrice': 1268.0,
        'charges': 60.79,
      },
      {
        'tradeDate': '2026-06-01T00:00:00.000',
        'symbol': 'Adani Power Ltd',
        'quantity': 57.0,
        'buyPrice': 242.49,
        'charges': 13.82,
      },
      {
        'tradeDate': '2026-06-10T00:00:00.000',
        'symbol': 'Adani Power Ltd',
        'quantity': 46.0,
        'buyPrice': 223.98,
        'charges': 10.65,
      },
      {
        'tradeDate': '2026-04-09T00:00:00.000',
        'symbol': 'Crompton Greaves Consumer Electricals Ltd',
        'quantity': 63.0,
        'buyPrice': 245.4,
        'charges': 15.46,
      },
      {
        'tradeDate': '2026-06-05T00:00:00.000',
        'symbol': 'Crompton Greaves Consumer Electricals Ltd',
        'quantity': 58.0,
        'buyPrice': 266.4,
        'charges': 15.45,
      },
      {
        'tradeDate': '2026-04-02T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 43.0,
        'buyPrice': 226.4,
        'charges': 10.0,
      },
      {
        'tradeDate': '2026-06-10T00:00:00.000',
        'symbol': 'Eternal Ltd',
        'quantity': 41.0,
        'buyPrice': 239.35,
        'charges': 9.81,
      },
      {
        'tradeDate': '2026-05-07T00:00:00.000',
        'symbol': 'Greenply Industries Ltd',
        'quantity': 10.0,
        'buyPrice': 262.05,
        'charges': 2.62,
      },
      {
        'tradeDate': '2026-07-07T00:00:00.000',
        'symbol': 'Housing & Urban Development Corporation Ltd',
        'quantity': 10.0,
        'buyPrice': 209.99,
        'charges': 2.0,
      },
      {
        'tradeDate': '2026-04-06T00:00:00.000',
        'symbol': 'JK Tyre & Industries Ltd',
        'quantity': 28.0,
        'buyPrice': 384.2,
        'charges': 10.76,
      },
      {
        'tradeDate': '2026-05-19T00:00:00.000',
        'symbol': 'JK Tyre & Industries Ltd',
        'quantity': 39.0,
        'buyPrice': 365.8987,
        'charges': 14.27,
      },
      {
        'tradeDate': '2026-05-07T00:00:00.000',
        'symbol': 'Kalyan Jewellers India Ltd',
        'quantity': 9.0,
        'buyPrice': 408.5,
        'charges': 3.68,
      },
      {
        'tradeDate': '2026-05-22T00:00:00.000',
        'symbol': 'Kalyan Jewellers India Ltd',
        'quantity': 10.0,
        'buyPrice': 355.8,
        'charges': 3.91,
      },
      {
        'tradeDate': '2026-06-10T00:00:00.000',
        'symbol': 'Manappuram Finance Ltd',
        'quantity': 33.0,
        'buyPrice': 289.1,
        'charges': 9.54,
      },
      {
        'tradeDate': '2026-05-22T00:00:00.000',
        'symbol': 'Rashtriya Chemicals & Fertilizers Ltd',
        'quantity': 20.0,
        'buyPrice': 132.84,
        'charges': 2.66,
      },
      {
        'tradeDate': '2026-04-24T00:00:00.000',
        'symbol': 'RattanIndia Power Ltd',
        'quantity': 1208.0,
        'buyPrice': 9.45,
        'charges': 11.0,
      },
      {
        'tradeDate': '2026-05-07T00:00:00.000',
        'symbol': 'Sun TV Network Ltd',
        'quantity': 5.0,
        'buyPrice': 572.35,
        'charges': 2.86,
      },
      {
        'tradeDate': '2026-05-19T00:00:00.000',
        'symbol': 'Sun TV Network Ltd',
        'quantity': 5.0,
        'buyPrice': 524.65,
        'charges': 2.62,
      },
      {
        'tradeDate': '2026-05-22T00:00:00.000',
        'symbol': 'Sun TV Network Ltd',
        'quantity': 5.0,
        'buyPrice': 486.6,
        'charges': 2.43,
      },
      {
        'tradeDate': '2026-07-03T00:00:00.000',
        'symbol': 'Sun TV Network Ltd',
        'quantity': 5.0,
        'buyPrice': 517.35,
        'charges': 3.0,
      },
    ];

    await db.transaction((txn) async {
      final accountRows = await txn.query(
        'accounts',
        where: 'broker = ? AND account_name = ?',
        whereArgs: ['Kotak Neo', 'Kotak Neo'],
        limit: 1,
      );

      final accountId = accountRows.isNotEmpty
          ? accountRows.first['id'] as int
          : await txn.insert(
              'accounts',
              {
                'broker': 'Kotak Neo',
                'account_name': 'Kotak Neo',
                'created_at':
                    DateTime.now().toIso8601String(),
              },
            );

      for (final row in rows) {
        final existing = await txn.query(
          'lots',
          where: '''
            account_id = ?
            AND UPPER(symbol) = UPPER(?)
            AND quantity = ?
            AND buy_price = ?
            AND purchase_date = ?
          ''',
          whereArgs: [
            accountId,
            row['symbol'],
            row['quantity'],
            row['buyPrice'],
            row['tradeDate'],
          ],
          limit: 1,
        );

        if (existing.isNotEmpty) continue;

        await txn.insert(
          'lots',
          {
            'account_id': accountId,
            'asset_type': 'Stock',
            'funding_type': 'MTF',
            'symbol': row['symbol'],
            'company_name': row['symbol'],
            'quantity': row['quantity'],
            'remaining_quantity': row['quantity'],
            'buy_price': row['buyPrice'],
            'purchase_date': row['tradeDate'],
            'purchase_charges': row['charges'],
            'purchase_other_charges': 0,
            'my_funds': 0,
            'broker_funded': 0,
            'mtf_daily_charge': 0,
            'nifty500_at_purchase': 0,
            'created_at':
                DateTime.now().toIso8601String(),
          },
        );
      }

      await txn.insert(
        'app_meta',
        {
          'key': 'initial_mtf_seed_v1',
          'value': '116 MTF lots seeded',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  // ============================================================
  // DATABASE PATH
  // ============================================================

  Future<String> getDatabasePath() async {
    final databasesPath = await getDatabasesPath();

    return join(
      databasesPath,
      'trading_tracker.db',
    );
  }
}