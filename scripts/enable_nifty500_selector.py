from pathlib import Path

path = Path('lib/main.dart')
s = path.read_text(encoding='utf-8')

old = """  List<Map<String, dynamic>> accounts = [];\n\n  final symbol = TextEditingController();"""
new = """  List<Map<String, dynamic>> accounts = [];\n  List<Map<String, dynamic>> nifty500 = [];\n  bool loadingNifty500 = true;\n  bool selectedNifty500 = false;\n\n  final symbol = TextEditingController();"""
assert old in s, 'AddPurchaseScreen state insertion point not found'
s = s.replace(old, new, 1)

old = """    super.initState();\n    loadAccounts();\n  }\n\n  Future<void> loadAccounts() async {"""
new = """    super.initState();\n    loadAccounts();\n    loadNifty500();\n  }\n\n  Future<void> loadNifty500() async {\n    try {\n      final rows = await lotManager.searchNifty500('');\n      if (!mounted) return;\n      setState(() {\n        nifty500 = rows;\n        loadingNifty500 = false;\n      });\n    } catch (_) {\n      if (!mounted) return;\n      setState(() => loadingNifty500 = false);\n    }\n  }\n\n  Future<void> loadAccounts() async {"""
assert old in s, 'initState insertion point not found'
s = s.replace(old, new, 1)

old = """  Widget _numberField(\n    TextEditingController controller,\n    String label,\n  ) {"""
new = """  Widget _nifty500Selector() {\n    if (assetType != 'Stock' && assetType != 'MTF') {\n      return TextField(\n        controller: symbol,\n        decoration: const InputDecoration(\n          labelText: 'Symbol / Security',\n        ),\n      );\n    }\n\n    if (loadingNifty500) {\n      return const Padding(\n        padding: EdgeInsets.symmetric(vertical: 12),\n        child: LinearProgressIndicator(),\n      );\n    }\n\n    return Autocomplete<Map<String, dynamic>>(\n      displayStringForOption: (option) =>\n          '${option['symbol']} • ${option['company_name'] ?? ''}',\n      optionsBuilder: (textEditingValue) {\n        final query = textEditingValue.text.trim().toLowerCase();\n        if (query.isEmpty) return nifty500.take(30);\n        return nifty500.where((stock) {\n          final stockSymbol = '${stock['symbol'] ?? ''}'.toLowerCase();\n          final company = '${stock['company_name'] ?? ''}'.toLowerCase();\n          return stockSymbol.contains(query) || company.contains(query);\n        }).take(30);\n      },\n      onSelected: (stock) {\n        symbol.text = '${stock['symbol'] ?? ''}'.trim().toUpperCase();\n        selectedNifty500 = true;\n        setState(() {});\n      },\n      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {\n        if (symbol.text.isNotEmpty && controller.text != symbol.text) {\n          controller.text = symbol.text;\n          controller.selection = TextSelection.fromPosition(\n            TextPosition(offset: controller.text.length),\n          );\n        }\n        return TextField(\n          controller: controller,\n          focusNode: focusNode,\n          decoration: const InputDecoration(\n            labelText: 'Nifty 500 Stock',\n            hintText: 'Search symbol or company',\n            prefixIcon: Icon(Icons.search),\n          ),\n          onChanged: (value) {\n            symbol.text = value.toUpperCase();\n            selectedNifty500 = false;\n          },\n          onSubmitted: (_) => onFieldSubmitted(),\n        );\n      },\n    );\n  }\n\n  Widget _numberField(\n    TextEditingController controller,\n    String label,\n  ) {"""
assert old in s, 'numberField insertion point not found'
s = s.replace(old, new, 1)

old = """        mtfDailyCharge: assetType == 'MTF'\n            ? double.tryParse(mtfDaily.text) ?? 0\n            : 0,\n      );"""
new = """        mtfDailyCharge: assetType == 'MTF'\n            ? double.tryParse(mtfDaily.text) ?? 0\n            : 0,\n        nifty500AtPurchase: selectedNifty500,\n      );"""
assert old in s, 'addPurchase argument insertion point not found'
s = s.replace(old, new, 1)

old = """          TextField(\n            controller: symbol,\n            decoration:\n                const InputDecoration(labelText: 'Symbol / Security'),\n          ),"""
new = """          _nifty500Selector(),"""
assert old in s, 'symbol field replacement point not found'
s = s.replace(old, new, 1)

path.write_text(s, encoding='utf-8')
print('Nifty 500 selector enabled in lib/main.dart')
