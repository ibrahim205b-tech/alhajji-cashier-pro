
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

const gold = Color(0xFFD4AF37);
const black = Color(0xFF101010);
final money = NumberFormat('#,##0', 'en_US');

Future<Database> openCashierDB() async {
  final path = p.join(await getDatabasesPath(), 'alhajji_pro.db');
  return openDatabase(path, version: 1, onCreate: (db, version) async {
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, price REAL NOT NULL, category TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total REAL NOT NULL, items TEXT NOT NULL, created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE shifts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total REAL NOT NULL, closed_at TEXT NOT NULL
      )
    ''');
    final batch = db.batch();
    final samples = [
      ['برغر لحم', 5000.0, 'وجبات'],
      ['برغر دجاج', 4000.0, 'وجبات'],
      ['شاورما دجاج', 3000.0, 'شرقي'],
      ['كباب', 6000.0, 'مشويات'],
      ['فلافل', 1000.0, 'فلافل'],
      ['بطاطا', 2000.0, 'مقبلات'],
      ['بيبسي', 500.0, 'مشروبات'],
      ['ماء', 250.0, 'مشروبات'],
    ];
    for (final item in samples) {
      batch.insert('products', {
        'name': item[0], 'price': item[1], 'category': item[2]
      });
    }
    await batch.commit(noResult: true);
  });
}

void main() => runApp(const CashierApp());

class CashierApp extends StatelessWidget {
  const CashierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'كاشير الحجي Pro',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold, brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: black, foregroundColor: gold,
          centerTitle: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF202020),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        useMaterial3: true,
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: CashierHome(),
      ),
    );
  }
}

class CashierHome extends StatefulWidget {
  const CashierHome({super.key});
  @override
  State<CashierHome> createState() => _CashierHomeState();
}

class _CashierHomeState extends State<CashierHome> {
  Database? db;
  List<Map<String, Object?>> products = [];
  List<Map<String, dynamic>> cart = [];
  List<Map<String, Object?>> sales = [];
  int tab = 0;
  bool loading = true;
  double shiftTotal = 0;
  String status = 'جاهز للعمل';

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    db = await openCashierDB();
    await refresh();
  }

  Future<void> refresh() async {
    if (db == null) return;
    final ps = await db!.query('products', orderBy: 'category, name');
    final ss = await db!.query('sales', orderBy: 'id DESC');
    final last = await db!.query('shifts', orderBy: 'id DESC', limit: 1);
    final lastClose = last.isEmpty ? '' : last.first['closed_at'] as String;
    final current = await db!.query(
      'sales', where: 'created_at > ?', whereArgs: [lastClose]);
    final total = current.fold<double>(
      0, (sum, row) => sum + (row['total'] as num).toDouble());
    if (!mounted) return;
    setState(() {
      products = ps;
      sales = ss;
      shiftTotal = total;
      loading = false;
    });
  }

  void addToCart(Map<String, Object?> product) {
    setState(() {
      final id = product['id'];
      final i = cart.indexWhere((e) => e['id'] == id);
      if (i >= 0) {
        cart[i]['qty']++;
      } else {
        cart.add({
          'id': id, 'name': product['name'],
          'price': (product['price'] as num).toDouble(),
          'qty': 1,
        });
      }
    });
  }

  double get cartTotal => cart.fold<double>(
    0, (s, e) => s + e['price'] * e['qty']);

  Future<void> checkout() async {
    if (cart.isEmpty || db == null) return;
    final items = cart.map((e) => {
      'name': e['name'], 'price': e['price'], 'qty': e['qty'],
    }).toList();
    await db!.insert('sales', {
      'total': cartTotal,
      'items': jsonEncode(items),
      'created_at': DateTime.now().toIso8601String(),
    });
    setState(() {
      cart.clear();
      status = 'تم حفظ الطلب بنجاح';
    });
    await refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل البيع وحفظه في الجهاز')),
      );
    }
  }

  Future<void> addProduct() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final category = TextEditingController(text: 'وجبات');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة منتج'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration:
              const InputDecoration(labelText: 'اسم المنتج')),
            const SizedBox(height: 10),
            TextField(controller: price, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'السعر بالدينار')),
            const SizedBox(height: 10),
            TextField(controller: category, decoration:
              const InputDecoration(labelText: 'القسم')),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty ||
        double.tryParse(price.text) == null) return;
    await db!.insert('products', {
      'name': name.text.trim(),
      'price': double.parse(price.text),
      'category': category.text.trim().isEmpty ? 'عام' : category.text.trim(),
    });
    await refresh();
  }

  Future<void> editProduct(Map<String, Object?> product) async {
    final name = TextEditingController(text: product['name'].toString());
    final price = TextEditingController(text: product['price'].toString());
    final category = TextEditingController(text: product['category'].toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل المنتج'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name,
            decoration: const InputDecoration(labelText: 'اسم المنتج')),
          const SizedBox(height: 8),
          TextField(controller: price, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'السعر')),
          const SizedBox(height: 8),
          TextField(controller: category,
            decoration: const InputDecoration(labelText: 'القسم')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty ||
        double.tryParse(price.text) == null) return;
    await db!.update('products', {
      'name': name.text.trim(), 'price': double.parse(price.text),
      'category': category.text.trim(),
    }, where: 'id = ?', whereArgs: [product['id']]);
    await refresh();
  }

  Future<void> closeShift() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إغلاق الوردية'),
        content: Text(
          'إجمالي المبيعات منذ آخر إغلاق:\n${money.format(shiftTotal)} د.ع\n\nهل تريد تسجيل الإغلاق؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإغلاق')),
        ],
      ),
    );
    if (ok != true) return;
    await db!.insert('shifts', {
      'total': shiftTotal, 'closed_at': DateTime.now().toIso8601String(),
    });
    await refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل إغلاق الوردية')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(
        child: CircularProgressIndicator(color: gold)));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('مطعم الحجي  •  PRO',
          style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(tooltip: 'تحديث', onPressed: refresh,
            icon: const Icon(Icons.refresh, color: gold)),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity, margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xFF302710), Color(0xFF171717)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold.withValues(alpha: 0.45)),
          ),
          child: Row(children: [
            const Icon(Icons.point_of_sale, color: gold, size: 32),
            const SizedBox(width: 12),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('كاشير الحجي Pro',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('نظام مبيعات محلي يعمل دون إنترنت',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            )),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('مبيعات الوردية', style: TextStyle(color: gold)),
              Text('${money.format(shiftTotal)} د.ع',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ]),
        ),
        Expanded(child: IndexedStack(index: tab, children: [
          buildPOS(), buildSales(), buildProducts(),
        ])),
      ]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF1B1B1B),
        indicatorColor: gold.withValues(alpha: 0.2),
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart, color: gold), label: 'الكاشير'),
          NavigationDestination(icon: Icon(Icons.receipt_long),
            selectedIcon: Icon(Icons.receipt, color: gold), label: 'المبيعات'),
          NavigationDestination(icon: Icon(Icons.restaurant_menu),
            selectedIcon: Icon(Icons.restaurant, color: gold), label: 'المنتجات'),
        ],
      ),
    );
  }

  Widget buildPOS() {
    return Column(children: [
      Expanded(child: products.isEmpty
        ? const Center(child: Text('أضف المنتجات من تبويب المنتجات'))
        : GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 190, mainAxisExtent: 112,
            crossAxisSpacing: 8, mainAxisSpacing: 8),
          itemCount: products.length,
          itemBuilder: (ctx, i) {
            final product = products[i];
            return InkWell(
              onTap: () => addToCart(product),
              onLongPress: () => editProduct(product),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF202020),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: gold.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text('${product['name']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold))),
                    Text('${money.format(product['price'])} د.ع',
                      style: const TextStyle(color: gold,
                        fontWeight: FontWeight.bold)),
                    Text('${product['category']}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            );
          },
        )),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          border: Border(top: BorderSide(color: gold, width: 0.5)),
        ),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.shopping_basket, color: gold),
            const SizedBox(width: 8),
            Expanded(child: Text('السلة (${cart.length} أصناف)',
              style: const TextStyle(fontWeight: FontWeight.bold))),
            Text('${money.format(cartTotal)} د.ع',
              style: const TextStyle(color: gold, fontSize: 18,
                fontWeight: FontWeight.bold)),
          ]),
          if (cart.isNotEmpty)
            SizedBox(height: 76, child: ListView(
              scrollDirection: Axis.horizontal,
              children: cart.map((e) => Container(
                width: 145, margin: const EdgeInsets.only(left: 8, top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: black,
                  borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e['name']}', maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                    Row(children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          e['qty']--;
                          if (e['qty'] <= 0) cart.remove(e);
                        }),
                        icon: const Icon(Icons.remove_circle_outline, size: 18)),
                      Text('${e['qty']}'),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => e['qty']++),
                        icon: const Icon(Icons.add_circle_outline,
                          color: gold, size: 18)),
                    ]),
                  ],
                ),
              )).toList(),
            )),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: cart.isEmpty ? null : () => setState(() => cart.clear()),
              child: const Text('مسح السلة'))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: gold, foregroundColor: black,
                padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: cart.isEmpty ? null : checkout,
              icon: const Icon(Icons.check_circle),
              label: const Text('تثبيت البيع',
                style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ]),
      ),
    ]);
  }

  Widget buildSales() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(14), child: Row(children: [
        const Expanded(child: Text('سجل المبيعات',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
        Text('${sales.length} عملية', style: const TextStyle(color: gold)),
      ])),
      Expanded(child: sales.isEmpty
        ? const Center(child: Text('لا توجد مبيعات مسجلة بعد'))
        : ListView.builder(
          itemCount: sales.length,
          itemBuilder: (ctx, i) {
            final s = sales[i];
            final date = DateTime.tryParse('${s['created_at']}');
            final items = jsonDecode('${s['items']}') as List;
            return Card(
              color: const Color(0xFF202020),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: ExpansionTile(
                leading: const Icon(Icons.receipt_long, color: gold),
                title: Text('فاتورة #${s['id']}'),
                subtitle: Text(date == null ? '' :
                  DateFormat('yyyy/MM/dd  HH:mm').format(date)),
                trailing: Text('${money.format(s['total'])} د.ع',
                  style: const TextStyle(color: gold,
                    fontWeight: FontWeight.bold)),
                children: items.map((e) => ListTile(
                  dense: true,
                  title: Text('${e['name']} × ${e['qty']}'),
                  trailing: Text('${money.format(
                    (e['price'] as num) * (e['qty'] as num))} د.ع'),
                )).toList(),
              ),
            );
          },
        )),
      Padding(padding: const EdgeInsets.all(12), child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: closeShift,
          icon: const Icon(Icons.lock_clock, color: gold),
          label: const Text('إغلاق الوردية'),
        ),
      )),
    ]);
  }

  Widget buildProducts() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        const Expanded(child: Text('إدارة قائمة الطعام',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: gold, foregroundColor: black),
          onPressed: addProduct,
          icon: const Icon(Icons.add),
          label: const Text('إضافة'),
        ),
      ])),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('اضغط مطولاً على أي منتج لتعديل اسمه أو سعره أو قسمه',
          style: TextStyle(color: Colors.white54)),
      ),
      Expanded(child: ListView.builder(
        itemCount: products.length,
        itemBuilder: (ctx, i) {
          final product = products[i];
          return ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF302710),
              child: Icon(Icons.fastfood, color: gold)),
            title: Text('${product['name']}'),
            subtitle: Text('${product['category']}'),
            trailing: Text('${money.format(product['price'])} د.ع',
              style: const TextStyle(color: gold,
                fontWeight: FontWeight.bold)),
            onTap: () => editProduct(product),
          );
        },
      )),
    ]);
  }
}
