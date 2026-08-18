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
  bool nifty500Selected = false;

  final symbol = TextEditingController();
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
        nifty500AtPurchase: nifty500Selected,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      _error('$e');
    }

    // Keep the account lookup in the UI so the selection is visibly tied
    // to the chosen broker/account.
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
        onChanged: (_) {
          nifty500Selected = false;
        },
      );
    }

    if (loadingNifty500) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    }

    return Autocomplete<Map<String, dynamic>>(
      displayStringForOption: (stock) =>
          '${stock['symbol']} • ${stock['company_name'] ?? ''}',
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();

        if (query.isEmpty) {
          return nifty500.take(30);
        }

        return nifty500.where((stock) {
          final stockSymbol =
              '${stock['symbol'] ?? ''}'.toLowerCase();
          final company =
              '${stock['company_name'] ?? ''}'.toLowerCase();

          return stockSymbol.contains(query) ||
              company.contains(query);
        }).take(30);
      },
      onSelected: (stock) {
        symbol.text =
            '${stock['symbol'] ?? ''}'.trim().toUpperCase();

        nifty500Selected = true;
        setState(() {});
      },
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        if (symbol.text.isNotEmpty &&
            controller.text != symbol.text) {
          controller.text = symbol.text;
          controller.selection =
              TextSelection.fromPosition(
            TextPosition(offset: controller.text.length),
          );
        }

        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Nifty 500 Stock',
            hintText: 'Search symbol or company',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            symbol.text = value.toUpperCase();
            nifty500Selected = false;
          },
          onSubmitted: (_) => onFieldSubmitted(),
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
              DropdownMenuItem(
                value: 'Stock',
                child: Text('Stock'),
              ),
              DropdownMenuItem(
                value: 'MTF',
                child: Text('MTF'),
              ),
              DropdownMenuItem(
                value: 'Crypto',
                child: Text('Crypto'),
              ),
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

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final broker = TextEditingController();
  final name = TextEditingController();
  final balance = TextEditingController(text: '0');

  @override
  void dispose() {
    broker.dispose();
    name.dispose();
    balance.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (broker.text.trim().isEmpty) return;

    final id = await lotManager.addAccount(
      broker: broker.text.trim(),
      accountName: name.text.trim().isEmpty
          ? broker.text.trim()
          : name.text.trim(),
    );

    final opening = double.tryParse(balance.text) ?? 0;
    if (opening != 0) {
      await lotManager.setOpeningBalance(
        accountId: id,
        balance: opening,
      );
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: broker,
            decoration: const InputDecoration(
              labelText: 'Broker / Platform',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Account Name (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: balance,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Opening Wallet Balance',
              prefixText: '₹ ',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: save,
            child: const Text('Create Account'),
          ),
        ],
      ),
    );
  }
}

class EditLotScreen extends StatefulWidget {
  final Lot lot;

  const EditLotScreen({
    super.key,
    required this.lot,
  });

  @override
  State<EditLotScreen> createState() => _EditLotScreenState();
}

class _EditLotScreenState extends State<EditLotScreen> {
  late final TextEditingController symbol;
  late final TextEditingController quantity;
  late final TextEditingController price;
  late final TextEditingController charges;
  late final TextEditingController myFunds;
  late final TextEditingController brokerFunded;
  late final TextEditingController mtfDaily;

  late DateTime purchaseDate;

  @override
  void initState() {
    super.initState();
    final lot = widget.lot;

    symbol = TextEditingController(text: lot.symbol);
    quantity = TextEditingController(text: '${lot.quantity}');
    price = TextEditingController(text: '${lot.buyPrice}');
    charges = TextEditingController(
      text: '${lot.purchaseCharges}',
    );
    myFunds = TextEditingController(text: '${lot.myFunds}');
    brokerFunded = TextEditingController(
      text: '${lot.brokerFunded}',
    );
    mtfDaily = TextEditingController(
      text: '${lot.mtfDailyCharge}',
    );
    purchaseDate = lot.purchaseDate;
  }

  @override
  void dispose() {
    for (final controller in [
      symbol,
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
    try {
      await lotManager.updateLot(
        lotId: widget.lot.id,
        accountId: widget.lot.accountId,
        assetType: widget.lot.assetType,
        fundingType: widget.lot.fundingType,
        symbol: symbol.text.trim().toUpperCase(),
        quantity: double.parse(quantity.text),
        buyPrice: double.parse(price.text),
        purchaseDate: purchaseDate,
        purchaseCharges:
            double.tryParse(charges.text) ?? 0,
        purchaseOtherCharges:
            widget.lot.purchaseOtherCharges,
        myFunds: double.tryParse(myFunds.text) ?? 0,
        brokerFunded:
            double.tryParse(brokerFunded.text) ?? 0,
        mtfDailyCharge:
            double.tryParse(mtfDaily.text) ?? 0,
        nifty500AtPurchase:
            widget.lot.nifty500AtPurchase,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Open Position')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: symbol,
            decoration:
                const InputDecoration(labelText: 'Symbol'),
          ),
          TextField(
            controller: quantity,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Quantity'),
          ),
          TextField(
            controller: price,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Buy Price'),
          ),
          TextField(
            controller: charges,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Purchase Charges'),
          ),
          if (widget.lot.assetType == 'MTF') ...[
            TextField(
              controller: myFunds,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'My Funds'),
            ),
            TextField(
              controller: brokerFunded,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Broker Funded'),
            ),
            TextField(
              controller: mtfDaily,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'MTF Daily Charge / Day',
              ),
            ),
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
          const SizedBox(height: 12),
          FilledButton(
            onPressed: save,
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

class CurrentPriceScreen extends StatefulWidget {
  final Lot lot;

  const CurrentPriceScreen({
    super.key,
    required this.lot,
  });

  @override
  State<CurrentPriceScreen> createState() =>
      _CurrentPriceScreenState();
}

class _CurrentPriceScreenState
    extends State<CurrentPriceScreen> {
  late final TextEditingController price;

  @override
  void initState() {
    super.initState();
    price = TextEditingController(
      text: widget.lot.currentPrice?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Current Price • ${widget.lot.symbol}',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Current Price',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final value = double.tryParse(price.text) ?? 0;
                if (value <= 0) return;

                await lotManager.updateCurrentPrice(
                  lotId: widget.lot.id,
                  price: value,
                );

                if (mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class SquareOffScreen extends StatefulWidget {
  final Lot lot;

  const SquareOffScreen({
    super.key,
    required this.lot,
  });

  @override
  State<SquareOffScreen> createState() =>
      _SquareOffScreenState();
}

class _SquareOffScreenState
    extends State<SquareOffScreen> {
  final sellPrice = TextEditingController();
  final sellCharges = TextEditingController(text: '0');
  final otherCharges = TextEditingController(text: '0');

  DateTime sellDate = DateTime.now();
  Map<String, double>? preview;

  @override
  void dispose() {
    sellPrice.dispose();
    sellCharges.dispose();
    otherCharges.dispose();
    super.dispose();
  }

  Future<void> calculate() async {
    final price = double.tryParse(sellPrice.text) ?? 0;
    if (price <= 0) return;

    final result = await lotManager.previewSquareOff(
      lot: widget.lot,
      sellPrice: price,
      sellDate: sellDate,
      sellCharges:
          double.tryParse(sellCharges.text) ?? 0,
      sellOtherCharges:
          double.tryParse(otherCharges.text) ?? 0,
    );

    if (mounted) setState(() => preview = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = preview;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Square Off • ${widget.lot.symbol}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Full lot: ${widget.lot.remainingQuantity} shares/units',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          TextField(
            controller: sellPrice,
            onChanged: (_) => calculate(),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Sell Price'),
          ),
          TextField(
            controller: sellCharges,
            onChanged: (_) => calculate(),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Selling Charges'),
          ),
          TextField(
            controller: otherCharges,
            onChanged: (_) => calculate(),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Other Selling Charges',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sell Date'),
            subtitle: Text(
              '${sellDate.day}/${sellDate.month}/${sellDate.year}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: sellDate,
                  firstDate: widget.lot.purchaseDate,
                  lastDate: DateTime(2100),
                );
                if (selected != null) {
                  setState(() => sellDate = selected);
                  await calculate();
                }
              },
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  _row('Gross Profit', result['grossProfit']!),
                  _row(
                    'Purchase Charges',
                    result['purchaseCharges']!,
                  ),
                  _row(
                    'MTF Interest',
                    result['mtfInterest']!,
                  ),
                  _row(
                    'Selling Charges',
                    result['sellCharges']!,
                  ),
                  _row(
                    'Total Charges',
                    result['totalCharges']!,
                  ),
                  const Divider(),
                  _row(
                    'Net Profit/Loss',
                    result['netProfitLoss']!,
                    bold: true,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await calculate();
              if (preview == null) return;

              await lotManager.squareOffLot(
                lot: widget.lot,
                sellPrice: double.parse(sellPrice.text),
                sellDate: sellDate,
                sellCharges:
                    double.tryParse(sellCharges.text) ?? 0,
                sellOtherCharges:
                    double.tryParse(otherCharges.text) ?? 0,
              );

              if (mounted) Navigator.pop(context);
            },
            child: const Text('Confirm Square Off'),
          ),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    double value, {
    bool bold = false,
  }) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        '₹${value.toStringAsFixed(2)}',
        style: TextStyle(
          fontWeight: bold ? FontWeight.bold : null,
        ),
      ),
    );
  }
}

class DividendScreen extends StatefulWidget {
  final Lot lot;

  const DividendScreen({
    super.key,
    required this.lot,
  });

  @override
  State<DividendScreen> createState() => _DividendScreenState();
}

class _DividendScreenState
    extends State<DividendScreen> {
  final eligibleShares = TextEditingController();
  final dividendPerShare = TextEditingController();
  final notes = TextEditingController();
  bool received = false;

  @override
  void dispose() {
    eligibleShares.dispose();
    dividendPerShare.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Dividend • ${widget.lot.symbol}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: eligibleShares,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Eligible Shares'),
          ),
          TextField(
            controller: dividendPerShare,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Dividend / Share',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dividend received'),
            value: received,
            onChanged: (value) =>
                setState(() => received = value),
          ),
          TextField(
            controller: notes,
            decoration:
                const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final shares =
                  double.tryParse(eligibleShares.text) ?? 0;
              final rate =
                  double.tryParse(dividendPerShare.text) ?? 0;

              if (shares <= 0 ||
                  rate <= 0 ||
                  shares > widget.lot.quantity) {
                return;
              }

              await lotManager.addDividend(
                lotId: widget.lot.id,
                dividendDate: DateTime.now(),
                receivedDate:
                    received ? DateTime.now() : null,
                eligibleQuantity: shares,
                dividendPerShare: rate,
                notes: notes.text.trim(),
              );

              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save Dividend'),
          ),
        ],
      ),
    );
  }
}

class OptionsScreen extends StatefulWidget {
  const OptionsScreen({super.key});

  @override
  State<OptionsScreen> createState() =>
      _OptionsScreenState();
}

class _OptionsScreenState
    extends State<OptionsScreen> {
  List<Map<String, dynamic>> accounts = [];
  int? accountId;
  String optionType = 'CE';

  final underlying = TextEditingController();
  final strike = TextEditingController();
  final quantity = TextEditingController();
  final buyPrice = TextEditingController();
  final sellPrice = TextEditingController();
  final buyCharges = TextEditingController(text: '0');
  final sellCharges = TextEditingController(text: '0');
  final otherCharges = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    loadAccounts();
  }

  Future<void> loadAccounts() async {
    accounts = await lotManager.getAccounts();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      underlying,
      strike,
      quantity,
      buyPrice,
      sellPrice,
      buyCharges,
      sellCharges,
      otherCharges,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Options — Buy + Sell'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            initialValue: accountId,
            decoration:
                const InputDecoration(labelText: 'Account'),
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
          TextField(
            controller: underlying,
            decoration:
                const InputDecoration(labelText: 'Underlying'),
          ),
          DropdownButtonFormField<String>(
            initialValue: optionType,
            decoration:
                const InputDecoration(labelText: 'Option Type'),
            items: const [
              DropdownMenuItem(
                value: 'CE',
                child: Text('CE'),
              ),
              DropdownMenuItem(
                value: 'PE',
                child: Text('PE'),
              ),
            ],
            onChanged: (value) =>
                setState(() => optionType = value!),
          ),
          _numberField(strike, 'Strike Price'),
          _numberField(quantity, 'Quantity'),
          _numberField(buyPrice, 'Buy Price'),
          _numberField(sellPrice, 'Sell Price'),
          _numberField(buyCharges, 'Buy Charges'),
          _numberField(sellCharges, 'Sell Charges'),
          _numberField(otherCharges, 'Other Charges'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              if (accountId == null) return;

              await lotManager.addOptionsTrade(
                accountId: accountId!,
                underlying: underlying.text.trim(),
                optionType: optionType,
                strikePrice:
                    double.tryParse(strike.text) ?? 0,
                expiryDate: DateTime.now(),
                tradeDate: DateTime.now(),
                quantity:
                    double.tryParse(quantity.text) ?? 0,
                buyPrice:
                    double.tryParse(buyPrice.text) ?? 0,
                sellPrice:
                    double.tryParse(sellPrice.text) ?? 0,
                buyCharges:
                    double.tryParse(buyCharges.text) ?? 0,
                sellCharges:
                    double.tryParse(sellCharges.text) ?? 0,
                otherCharges:
                    double.tryParse(otherCharges.text) ?? 0,
              );

              if (mounted) Navigator.pop(context);
            },
            child: const Text('Confirm Option Trade'),
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
  ) {
    return TextField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class WalletScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;

  const WalletScreen({
    super.key,
    required this.accounts,
  });

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Map<int, double> balances = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    balances = await lotManager.getAllWalletBalances();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final total =
        balances.values.fold<double>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Total Wallet Balance'),
              trailing: Text(
                '₹${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          ...widget.accounts.map((account) {
            final id = (account['id'] as num).toInt();
            return Card(
              child: ListTile(
                title: Text(
                  '${account['broker']} • ${account['account_name']}',
                ),
                trailing: Text(
                  '₹${(balances[id] ?? 0).toStringAsFixed(2)}',
                ),
                onTap: () => actions(id),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AccountScreen(),
                ),
              );
              await load();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Account'),
          ),
        ],
      ),
    );
  }

  Future<void> actions(int accountId) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Add Funds'),
              onTap: () =>
                  Navigator.pop(context, 'add'),
            ),
            ListTile(
              title: const Text('Withdraw'),
              onTap: () =>
                  Navigator.pop(context, 'withdraw'),
            ),
            ListTile(
              title: const Text('Transfer'),
              onTap: () =>
                  Navigator.pop(context, 'transfer'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;

    if (action == 'transfer') {
      await transfer(accountId);
      return;
    }

    final controller = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          action == 'add'
              ? 'Add Funds'
              : 'Withdraw Funds',
        ),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixText: '₹ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(
                  context,
                  double.tryParse(controller.text),
                ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value == null || value <= 0) return;

    await lotManager.addWalletTransaction(
      accountId: accountId,
      type: action == 'add'
          ? 'deposit'
          : 'withdrawal',
      amount: action == 'add' ? value : -value,
    );

    await load();
  }

  Future<void> transfer(int fromAccountId) async {
    final otherAccounts = widget.accounts
        .where(
          (account) =>
              (account['id'] as num).toInt() != fromAccountId,
        )
        .toList();

    if (otherAccounts.isEmpty) return;

    int toAccountId =
        (otherAccounts.first['id'] as num).toInt();
    final controller = TextEditingController();

    final amount = await showDialog<double>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Transfer Funds'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: toAccountId,
                  decoration: const InputDecoration(
                    labelText: 'To Account',
                  ),
                  items: otherAccounts.map((account) {
                    return DropdownMenuItem(
                      value:
                          (account['id'] as num).toInt(),
                      child: Text(
                        account['account_name'] as String,
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(
                      () => toAccountId = value!,
                    );
                  },
                ),
                TextField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(
                      context,
                      double.tryParse(controller.text),
                    ),
                child: const Text('Transfer'),
              ),
            ],
          );
        },
      ),
    );

    controller.dispose();

    if (amount == null || amount <= 0) return;

    await lotManager.transferFunds(
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amount: amount,
    );

    await load();
  }
}

class ClosedScreen extends StatelessWidget {
  const ClosedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Closed / Completed Trades'),
      ),
      body: FutureBuilder(
        future: Future.wait([
          lotManager.getClosedPositions(),
          lotManager.getOptionsTrades(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final closed =
              snapshot.data![0] as List<Map<String, dynamic>>;
          final options =
              snapshot.data![1] as List<Map<String, dynamic>>;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Closed Positions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...closed.map(
                (row) => ListTile(
                  title: Text(
                    '${row['symbol']} • ${row['asset_type']}',
                  ),
                  trailing: Text(
                    '₹${(row['net_profit_loss'] as num).toStringAsFixed(2)}',
                  ),
                ),
              ),
              const Divider(height: 30),
              const Text(
                'Options',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...options.map(
                (row) => ListTile(
                  title: Text(
                    '${row['underlying']} '
                    '${row['strike_price']} '
                    '${row['option_type']}',
                  ),
                  subtitle: Text(
                    'Buy ₹${row['buy_price']} → '
                    'Sell ₹${row['sell_price']}',
                  ),
                  trailing: Text(
                    '₹${(row['net_profit_loss'] as num).toStringAsFixed(2)}',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
