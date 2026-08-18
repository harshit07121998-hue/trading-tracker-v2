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
    required