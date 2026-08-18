import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'lot.dart';
import 'lot_manager.dart';

final lotManager = LotManager();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TradingTrackerApp());
}

class TradingTrackerApp extends StatelessWidget {
  const TradingTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Trading Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Lot> lots = [];
  List<Map<String, dynamic>> accounts = [];
  Map<int, double> walletBalances = {};
  final Map<String, double?> xirr = {};

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final newLots = await lotManager.getAllOpenLots();
    final newAccounts = await lotManager.getAccounts();
    final newWallet = await lotManager.getAllWalletBalances();

    if (!mounted) return;
    setState(() {
      lots = newLots;
      accounts = newAccounts;
      walletBalances = newWallet;
    });
  }

  double get totalInvested =>
      lots.fold(0, (sum, lot) => sum + lot.investedValue);

  double get stockValue => lots
      .where((lot) => lot.assetType == 'Stock')
      .fold(0, (sum, lot) => sum + lot.marketValue);

  double get mtfFunds => lots
      .where((lot) => lot.assetType == 'MTF')
      .fold(0, (sum, lot) => sum + lot.myFunds);

  double get mtfGain => lots
      .where((lot) => lot.assetType == 'MTF')
      .fold(0, (sum, lot) => sum + lot.unrealisedPnL);

  double get cryptoValue => lots
      .where((lot) => lot.assetType == 'Crypto')
      .fold(0, (sum, lot) => sum + lot.marketValue);

  double get portfolioValue =>
      stockValue + mtfFunds + mtfGain + cryptoValue;

  double get walletBalance =>
      walletBalances.values.fold(0, (a, b) => a + b);

  Future<double> realizedGain() async {
    final closed = await lotManager.getClosedPositions();
    final options = await lotManager.getOptionsTrades();

    final a = closed.fold<double>(
      0,
      (sum, row) =>
          sum + (row['net_profit_loss'] as num).toDouble(),
    );
    final b = options.fold<double>(
      0,
      (sum, row) =>
          sum + (row['net_profit_loss'] as num).toDouble(),
    );
    return a + b;
  }

  Future<void> backup() async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Backup Trading Tracker',
        fileName: 'trading_tracker.db',
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (path == null) return;
      await lotManager.backupToFile(path);
      _message('Backup saved successfully.');
    } catch (e) {
      _message('Backup failed: $e');
    }
  }

  Future<void> restore() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        withData: true,
      );
      if (result == null) return;

      final bytes = result.files.single.bytes;
      if (bytes == null) {
        _message('Unable to read backup file.');
        return;
      }

      await lotManager.restoreFromBytes(bytes);
      await refresh();
      _message('Backup restored successfully.');
    } catch (e) {
      _message('Restore failed: $e');
    }
  }

  Future<void> open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    await refresh();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trading Tracker',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Wallet',
            onPressed: () => open(WalletScreen(accounts: accounts)),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'backup') backup();
              if (value == 'restore') restore();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'backup',
                child: Text('Backup Data'),
              ),
              PopupMenuItem(
                value: 'restore',
                child: Text('Restore Data'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _summaryCard(),
            const SizedBox(height: 12),
            _xirrCard(),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Open Positions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => open(const AddPurchaseScreen()),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._positionGroups(),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: () => open(const OptionsScreen()),
              icon: const Icon(Icons.show_chart),
              label: const Text('Add Options Trade'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => open(const ClosedScreen()),
              icon: const Icon(Icons.history),
              label: const Text('Closed Positions / Options'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _metric('Total Invested Value', totalInvested),
            _metric('Wallet Balance', walletBalance),
            _metric('Portfolio Value', portfolioValue),
            _metric(
              'Unrealized Gain/Loss',
              portfolioValue - totalInvested,
              signed: true,
            ),
            FutureBuilder<double>(
              future: realizedGain(),
              builder: (_, snapshot) => _metric(
                'Realized Gain/Loss',
                snapshot.data ?? 0,
                signed: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
    String title,
    double value, {
    bool signed = false,
  }) {
    return ListTile(
      dense: true,
      title: Text(title),
      trailing: Text(
        '${signed && value >= 0 ? '+' : ''}₹${value.toStringAsFixed(2)}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: signed
              ? (value >= 0 ? Colors.green[700] : Colors.red[700])
              : null,
        ),
      ),
    );
  }

  Widget _xirrCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'XIRR',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: () async {
                    for (final category in [
                      'Stock',
                      'MTF',
                      'Crypto',
                      'Option',
                    ]) {
                      xirr[category] =
                          await lotManager.getLatestXirr(category);
                    }
                    if (mounted) setState(() {});
                  },
                  child: const Text('Update XIRR'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _xirrChip('Stock'),
                _xirrChip('MTF'),
                _xirrChip('Crypto'),
                _xirrChip('Option'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _xirrChip(String category) {
    final value = xirr[category];
    return Chip(
      label: Text(
        '$category: ${value == null ? '--' : '${(value * 100).toStringAsFixed(2)}%'}',
      ),
    );
  }

  List<Widget> _positionGroups() {
    final groups = <String, List<Lot>>{};

    for (final lot in lots) {
      groups.putIfAbsent(
        '${lot.assetType}|${lot.symbol}',
        () => [],
      ).add(lot);
    }

    return groups.values.map((group) {
      final first = group.first;
      final quantity = group.fold<double>(
        0,
        (sum, lot) => sum + lot.remainingQuantity,
      );

      return Card(
        elevation: 0,
        child: ExpansionTile(
          title: Text(
            first.symbol,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${first.assetType} • $quantity units • ${group.length} lot(s)',
          ),
          children: group.map((lot) {
            return ListTile(
              title: Text(
                '${lot.remainingQuantity} @ ₹${lot.buyPrice.toStringAsFixed(2)}',
              ),
              subtitle: Text(
                '${lot.account} • '
                '${lot.purchaseDate.day}/${lot.purchaseDate.month}/${lot.purchaseDate.year}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    await open(EditLotScreen(lot: lot));
                  } else if (value == 'price') {
                    await open(CurrentPriceScreen(lot: lot));
                  } else if (value == 'dividend') {
                    await open(DividendScreen(lot: lot));
                  } else if (value == 'square') {
                    await open(SquareOffScreen(lot: lot));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit Position'),
                  ),
                  PopupMenuItem(
                    value: 'price',
                    child: Text('Update Current Price'),
                  ),
                  PopupMenuItem(
                    value: 'dividend',
                    child: Text('Add Dividend'),
                  ),
                  PopupMenuItem(
                    value: 'square',
                    child: Text('Square Off Full Lot'),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );
    }).toList();
  }
}

class AddPurchaseScreen extends StatefulWidget {
  const AddPurchaseScreen({super.key});

  @override
  State<AddPurchaseScreen> createState() => _AddPurchaseScreenState();
}

class _AddPurchaseScreenState extends State<AddPurchaseScreen> {
  String assetType = 'Stock';
  int? accountId;
  DateTime purchaseDate = DateTime.now();

  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> nifty500 = [];
  bool loadingNifty500 = true;

  final symbol = TextEditingController();
  final companyName = TextEditingController();
  final quantity = TextEditingController();
  final price = TextEditingController();
  final charges = TextEditingController(text: '0');
  final myFunds = TextEditingController();
  final brokerFunded = TextEditingController();
  final mtfDaily = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    loadAccounts();
    loadNifty500();
  }

  Future<void> loadNifty500() async {
    try {
      final rows = await lotManager.searchNifty500('');
      if (!mounted) return;
      setState(() {
        nifty500 = rows;
        loadingNifty500 = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingNifty500 = false);
    }
  }

  Future<void> loadAccounts() async {
    accounts = await lotManager.getAccounts();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      symbol,
      companyName,
      quantity,
      price,
      charges,
      myFunds,
      brokerFunded,
      mtfDaily,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (accountId == null) {
      _error('Select an account first.');
      return;
    }

    final q = double.tryParse(quantity.text) ?? 0;
    final p = double.tryParse(price.text) ?? 0;

    if (symbol.text.trim().isEmpty || q <= 0 || p <= 0) {
      _error('Enter a symbol, quantity and valid buy price.');
      return;
    }

    final account = accounts.firstWhere(
      (a) => (a['id'] as num).toInt() == accountId,
    );

    final funded = double.tryParse(brokerFunded.text) ?? 0;
    final own = double.tryParse(myFunds.text) ??
        (assetType == 'MTF' ? q * p - funded : q * p);

    try {
      await lotManager.addPurchase(
        accountId: accountId!,
        symbol: symbol.text.trim().toUpperCase(),
        quantity: q,
        buyPrice: p,
        purchaseDate: purchaseDate,
        assetType: assetType,
        fundingType: assetType == 'MTF' ? 'MTF' : 'Regular',
        purchaseCharges: double.tryParse(charges.text) ?? 0,
        myFunds: own,
        brokerFunded: funded,
        mtfDailyCharge: assetType == 'MTF'
            ? double.tryParse(mtfDaily.text) ?? 0
            : 0,
        nifty500AtPurchase:
            (assetType == 'Stock' || assetType == 'MTF') &&
            companyName.text.trim().isNotEmpty,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      _error('$e');
    }

    debugPrint('Purchase account: ${account['account_name']}');
  }

  void _error(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _nifty500Selector() {
    if (assetType != 'Stock' && assetType != 'MTF') {
      return TextField(
        controller: symbol,
        decoration: const InputDecoration(
          labelText: 'Symbol / Security',
        ),
      );
    }

    if (loadingNifty500) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    }

    return Autocomplete<Map<String, dynamic>>(
      displayStringForOption: (stock) {
        final stockSymbol = '${stock['symbol'] ?? ''}'.trim();
        final company = '${stock['company_name'] ?? ''}'.trim();
        return company.isEmpty ? stockSymbol : '$stockSymbol • $company';
      },
      optionsBuilder: (TextEditingValue value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) {
          return const Iterable<Map<String, dynamic>>.empty();
        }
        return nifty500.where((stock) {
          final stockSymbol =
              '${stock['symbol'] ?? ''}'.toLowerCase();
          final company =
              '${stock['company_name'] ?? ''}'.toLowerCase();
          return stockSymbol.contains(query) || company.contains(query);
        }).take(30);
      },
      onSelected: (stock) {
        symbol.text =
            '${stock['symbol'] ?? ''}'.trim().toUpperCase();
        companyName.text =
            '${stock['company_name'] ?? ''}'.trim();
        setState(() {});
      },
      fieldViewBuilder: (
        context,
        textController,
        focusNode,
        onFieldSubmitted,
      ) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Nifty 500 Stock',
            hintText: 'Search symbol or company',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => symbol.text = value.toUpperCase(),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 320,
                maxWidth: 600,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final stock = options.elementAt(index);
                  final stockSymbol =
                      '${stock['symbol'] ?? ''}'.trim();
                  final company =
                      '${stock['company_name'] ?? ''}'.trim();
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.business, size: 20),
                    title: Text(
                      stockSymbol,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(company),
                    onTap: () => onSelected(stock),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Purchase')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: assetType,
            decoration:
                const InputDecoration(labelText: 'Asset Type'),
            items: const [
              DropdownMenuItem(value: 'Stock', child: Text('Stock')),
              DropdownMenuItem(value: 'MTF', child: Text('MTF')),
              DropdownMenuItem(value: 'Crypto', child: Text('Crypto')),
            ],
            onChanged: (value) =>
                setState(() => assetType = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: accountId,
            decoration: const InputDecoration(
              labelText: 'Account',
              hintText: 'Select account',
            ),
            items: accounts.map((account) {
              final id = (account['id'] as num).toInt();
              return DropdownMenuItem(
                value: id,
                child: Text(
                  '${account['broker']} • ${account['account_name']}',
                ),
              );
            }).toList(),
            onChanged: (value) =>
                setState(() => accountId = value),
          ),
          TextButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AccountScreen(),
                ),
              );
              await loadAccounts();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add another account'),
          ),
          _nifty500Selector(),
          const SizedBox(height: 12),
          _numberField(quantity, 'Quantity'),
          _numberField(price, 'Buy Price'),
          _numberField(charges, 'Purchase Charges'),
          if (assetType == 'MTF') ...[
            _numberField(myFunds, 'My Funds'),
            _numberField(brokerFunded, 'Broker Funded'),
            _numberField(mtfDaily, 'MTF Daily Charge / Day'),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Purchase Date'),
            subtitle: Text(
              '${purchaseDate.day}/${purchaseDate.month}/${purchaseDate.year}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: purchaseDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (selected != null) {
                  setState(() => purchaseDate = selected);
                }
              },
            ),
          ),
          FilledButton(
            onPressed: save,
            child: const Text('Confirm Purchase'),
          ),
        ],
      ),
    );
  }
}
