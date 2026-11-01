import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kGreen = Color(0xFF17803F);

// ───────────────────────── النموذج والحالة ─────────────────────────

class Person {
  final String id;
  String name;
  final String? parentId;
  final bool female;
  String birth, city, spouse;
  Person(this.id, this.name, this.parentId,
      {this.female = false, this.birth = '', this.city = '', this.spouse = ''});

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'parentId': parentId, 'female': female,
        'birth': birth, 'city': city, 'spouse': spouse,
      };

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        j['id'] as String, j['name'] as String, j['parentId'] as String?,
        female: j['female'] as bool? ?? false,
        birth: j['birth'] as String? ?? '',
        city: j['city'] as String? ?? '',
        spouse: j['spouse'] as String? ?? '',
      );
}

class Event {
  final String id;
  String title, date; // date بصيغة yyyy/mm/dd
  Event(this.id, this.title, this.date);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'date': date};
  factory Event.fromJson(Map<String, dynamic> j) =>
      Event(j['id'] as String, j['title'] as String, j['date'] as String);
}

String fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

Future<String?> pickDate(BuildContext context) async {
  final d = await showDatePicker(
    context: context,
    initialDate: DateTime(2000),
    firstDate: DateTime(1800),
    lastDate: DateTime(2100),
  );
  return d == null ? null : fmtDate(d);
}

String ar(int n) => n
    .toString()
    .split('')
    .map((d) => d == '-' ? '-' : '٠١٢٣٤٥٦٧٨٩'[int.parse(d)])
    .join();

String kidsText(int n) {
  if (n == 0) return 'لا يوجد أبناء';
  if (n == 1) return 'ابن واحد';
  if (n == 2) return 'ابنان';
  if (n <= 10) return '${ar(n)} أبناء';
  return '${ar(n)} ابناً';
}

class AppState extends ChangeNotifier {
  static const branchColors = [
    Color(0xFFF47A14), Color(0xFFD9A400), Color(0xFF6BB82E), Color(0xFF1F9A4D),
    Color(0xFF0B8FD0), Color(0xFF2B2FA0), Color(0xFF6A3D99), Color(0xFFC0158C),
  ];
  final List<Person> people = [];
  bool started = false;
  bool dark = false;
  int tab = 0;
  int _n = 0;
  late Person root;
  final List<Event> events = [];
  int _e = 0;
  SharedPreferences? _prefs;

  AppState() {
    _seed();
  }

  Person _add(String name, String? parentId, {bool female = false}) {
    final p = Person('p${_n++}', name, parentId, female: female);
    people.add(p);
    return p;
  }

  void _seed() {
    const fem = {
      'التومه', 'ليلى', 'شامه', 'بتول', 'هويدا', 'هبه', 'هناء', 'ريم', 'رحاب',
      'هبيات', 'هدى', 'هنادي', 'نعمات', 'نوال', 'عاطفه', 'احلام', 'الهام',
      'بدريه', 'سلوى', 'غاده', 'هاله', 'نجلاء', 'لمياء',
    };
    root = _add('محمد حمد', null);
    const data = {
      'يوسف': ['نعمان', 'هويدا', 'نزار', 'نقيب', 'هبه', 'هناء', 'ريم', 'رحاب'],
      'حمد': ['وضاح', 'فواز'],
      'صلاح': ['سامر'],
      'حسن': ['حاتم', 'حافظ', 'زاهر', 'ياسر', 'نجلاء', 'لمياء', 'محمد'],
      'التومه': ['هبيات', 'خالد', 'هدى', 'طارق', 'بكري', 'هنادي'],
      'ليلى': ['نعمات', 'عادل', 'نوال', 'عاطفه', 'احلام', 'الهام', 'احمد', 'محمد', 'موهيد'],
      'شامه': ['فيصل', 'بدريه', 'سلوى', 'سيف', 'عصام', 'مجدى', 'عماد', 'عباس', 'ضياء الدين', 'غاده', 'هاله'],
      'بتول': <String>[],
    };
    data.forEach((b, kids) {
      final bp = _add(b, root.id, female: fem.contains(b));
      for (final k in kids) {
        _add(k, bp.id, female: fem.contains(k));
      }
    });
  }

  Person? byId(String id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Person> children(String id) => people.where((p) => p.parentId == id).toList();

  Person branchOf(Person p) {
    var c = p;
    while (c.parentId != null && c.parentId != root.id) {
      c = byId(c.parentId!)!;
    }
    return c;
  }

  Color colorOf(Person p) {
    if (p == root) return kGreen;
    final i = children(root.id).indexOf(branchOf(p));
    return branchColors[(i < 0 ? 0 : i) % branchColors.length];
  }

  int descendants(String id) {
    var n = 0;
    for (final c in children(id)) {
      n += 1 + descendants(c.id);
    }
    return n;
  }

  Person add(String name, String parentId,
      {bool female = false, String birth = '', String city = ''}) {
    final p = _add(name, parentId, female: female);
    p.birth = birth;
    p.city = city;
    notifyListeners();
    return p;
  }

  void edit(Person p, String name, String birth, String city, String spouse) {
    p.name = name;
    p.birth = birth;
    p.city = city;
    p.spouse = spouse;
    notifyListeners();
  }

  void addEvent(String title, String date) {
    events.add(Event('e${_e++}', title, date));
    notifyListeners();
  }

  void removeEvent(String id) {
    events.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void reset() {
    people.clear();
    events.clear();
    _n = 0;
    _e = 0;
    _seed();
    notifyListeners();
  }

  // ───── الحفظ على الجهاز ─────
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString('data');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final ps = [for (final x in j['people'] as List) Person.fromJson(x as Map<String, dynamic>)];
      if (ps.isEmpty) return;
      people..clear()..addAll(ps);
      root = people.firstWhere((p) => p.parentId == null);
      events
        ..clear()
        ..addAll([for (final x in (j['events'] as List? ?? [])) Event.fromJson(x as Map<String, dynamic>)]);
      dark = j['dark'] as bool? ?? false;
      started = j['started'] as bool? ?? false;
      _n = (j['n'] as int?) ?? people.length;
      _e = (j['e'] as int?) ?? events.length;
    } catch (_) {
      // بيانات تالفة: نبقى على البيانات الأولية
    }
  }

  void _save() {
    final pr = _prefs;
    if (pr == null) return;
    pr.setString('data', jsonEncode({
      'people': [for (final p in people) p.toJson()],
      'events': [for (final e in events) e.toJson()],
      'dark': dark, 'started': started, 'n': _n, 'e': _e,
    }));
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _save();
  }

  // ───── صلة القرابة ─────
  List<Person> pathUp(Person p) {
    final r = <Person>[];
    Person? c = p;
    while (c != null) {
      r.add(c);
      c = c.parentId == null ? null : byId(c.parentId!);
    }
    return r;
  }

  int depth(Person p) => pathUp(p).length - 1;

  String kinship(Person a, Person b) {
    if (a == b) return 'اختر شخصين مختلفين';
    final pa = pathUp(a), pb = pathUp(b);
    var da = -1, db = -1;
    for (var i = 0; i < pa.length; i++) {
      final j = pb.indexOf(pa[i]);
      if (j >= 0) {
        da = i;
        db = j;
        break;
      }
    }
    if (da < 0) return 'لا توجد صلة قرابة مسجلة';
    final bf = b.female;
    String rel;
    if (da == 0) {
      rel = db == 1 ? (bf ? 'ابنة' : 'ابن') : db == 2 ? (bf ? 'حفيدة' : 'حفيد') : 'من أحفاد الجيل ${ar(db)}';
    } else if (db == 0) {
      rel = da == 1 ? (bf ? 'أم' : 'أب') : da == 2 ? (bf ? 'جدة' : 'جد') : 'من أجداد الجيل ${ar(da)}';
    } else if (da == 1 && db == 1) {
      rel = bf ? 'أخت' : 'أخ';
    } else if (da == 1 && db == 2) {
      rel = bf ? 'ابنة أخ أو أخت' : 'ابن أخ أو أخت';
    } else if (da == 2 && db == 1) {
      rel = bf ? 'عمة أو خالة' : 'عم أو خال';
    } else if (da == 2 && db == 2) {
      rel = bf ? 'ابنة عم أو خال' : 'ابن عم أو خال';
    } else {
      rel = 'قريب من الدرجة ${ar(da + db)}';
    }
    return '${b.name} ${bf ? 'هي' : 'هو'} $rel ${a.name}';
  }

  void remove(String id) {
    for (final c in children(id)) {
      remove(c.id);
    }
    people.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void update(void Function() f) {
    f();
    notifyListeners();
  }

  String exportText([Person? p, int depth = 0]) {
    p ??= root;
    final b = StringBuffer('${'  ' * depth}- ${p.name}\n');
    for (final c in children(p.id)) {
      b.write(exportText(c, depth + 1));
    }
    return b.toString();
  }
}

final app = AppState();

void openPerson(BuildContext c, Person p) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => PersonScreen(p.id)));
void openAdd(BuildContext c, {String? parentId}) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => AddScreen(parentId: parentId)));
void openFullTree(BuildContext c) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => const FullTreeScreen()));

// ───────────────────────── التطبيق ─────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.load();
  runApp(const FamilyApp());
}

class FamilyApp extends StatelessWidget {
  const FamilyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'شجرة العائلة',
        debugShowCheckedModeBanner: false,
        themeMode: app.dark ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.light),
        darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: kGreen, brightness: Brightness.dark),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: app.started ? const Shell() : const StartScreen(),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  final Person p;
  final double size;
  const Avatar(this.p, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final c = app.colorOf(p);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.withAlpha(45),
        border: Border.all(color: c, width: 2.5),
      ),
      child: Text(p.name.substring(0, 1),
          style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.bold)),
    );
  }
}

// ───────────────────────── شاشة البداية ─────────────────────────

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              const SizedBox(height: 260, width: 350, child: CustomPaint(painter: _HeroPainter())),
              const SizedBox(height: 8),
              const Text('شجرة العائلة', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(
                'اجمع أفراد عائلتك وفروعها في مكان واحد، وتعرّف على صلة القرابة بينهم.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.6, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => app.update(() => app.started = true),
                  child: const Text('تسجيل الدخول', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: () => app.update(() => app.started = true),
                  child: const Text('إنشاء شجرة جديدة', style: TextStyle(fontSize: 17)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPainter extends CustomPainter {
  const _HeroPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final pts = [
      Offset(size.width * .18, size.height * .2), Offset(size.width * .84, size.height * .17),
      Offset(size.width * .13, size.height * .58), Offset(size.width * .88, size.height * .55),
      Offset(size.width * .3, size.height * .85), Offset(size.width * .72, size.height * .86),
    ];
    final cols = [0xFFF47A14, 0xFFD9A400, 0xFF6BB82E, 0xFF0B8FD0, 0xFF6A3D99, 0xFFC0158C];
    for (var i = 0; i < pts.length; i++) {
      final col = Color(cols[i]);
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..cubicTo(c.dx + (pts[i].dx - c.dx) * .3, c.dy, pts[i].dx, pts[i].dy + (c.dy - pts[i].dy) * .4, pts[i].dx, pts[i].dy);
      canvas.drawPath(path, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round);
      canvas.drawCircle(pts[i], 22, Paint()..color = Colors.white);
      canvas.drawCircle(pts[i], 22, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 4);
    }
    canvas.drawCircle(c, 44, Paint()..color = const Color(0xFFDFF3E6));
    canvas.drawCircle(c, 44, Paint()..color = kGreen..style = PaintingStyle.stroke..strokeWidth = 5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ───────────────────────── الهيكل والتنقل ─────────────────────────

class Shell extends StatelessWidget {
  const Shell({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        body: IndexedStack(index: app.tab, children: const [
          HomeScreen(), TreeScreen(), SearchScreen(), SettingsScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: app.tab,
          onDestinationSelected: (i) => app.update(() => app.tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
            NavigationDestination(icon: Icon(Icons.account_tree_outlined), selectedIcon: Icon(Icons.account_tree), label: 'الشجرة'),
            NavigationDestination(icon: Icon(Icons.search), label: 'الأفراد'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── الرئيسية ─────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final recent = app.people.where((p) => p != app.root).toList().reversed.take(3).toList();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('مرحباً بك', style: TextStyle(color: cs.onSurfaceVariant)),
                  const Text('الرئيسية', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                ]),
              ),
              Avatar(app.root, size: 48),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('شجرتك', style: TextStyle(color: Colors.white)),
                const SizedBox(height: 6),
                const Text('شجرة عائلة حمد', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                Row(children: [
                  for (final b in app.children(app.root.id))
                    Container(
                      width: 14, height: 14, margin: const EdgeInsetsDirectional.only(end: 6),
                      decoration: BoxDecoration(color: app.colorOf(b), shape: BoxShape.circle),
                    ),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                    onPressed: () => app.update(() => app.tab = 1),
                    child: const Text('فتح الشجرة', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              _Action(Icons.person_add_alt_1, 'إضافة فرد', () => openAdd(context)),
              const SizedBox(width: 8),
              _Action(Icons.search, 'بحث', () => app.update(() => app.tab = 2)),
              const SizedBox(width: 8),
              _Action(Icons.account_tree, 'الشجرة الكاملة', () => openFullTree(context)),
              const SizedBox(width: 8),
              _Action(Icons.people_alt_outlined, 'صلة القرابة', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KinshipScreen()))),
            ]),
            const SizedBox(height: 20),
            const Text('آخر المضافين', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final p in recent)
              Card(
                child: ListTile(
                  leading: Avatar(p, size: 40),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${p.female ? 'ابنة' : 'ابن'} ${app.byId(p.parentId!)!.name}'),
                  onTap: () => openPerson(context, p),
                ),
              ),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('مناسبات قريبة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              TextButton.icon(onPressed: () => addEventDialog(context), icon: const Icon(Icons.add), label: const Text('إضافة')),
            ]),
            if (app.events.isEmpty)
              Card(child: ListTile(title: const Text('لا توجد مناسبات مضافة بعد'), trailing: Icon(Icons.event, color: cs.onSurfaceVariant))),
            for (final e in ([...app.events]..sort((x, y) => x.date.compareTo(y.date))))
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(e.date),
                  trailing: IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline), onPressed: () => app.removeEvent(e.id)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> addEventDialog(BuildContext context) async {
  final title = TextEditingController();
  final date = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('إضافة مناسبة'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'اسم المناسبة', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(
          controller: date,
          readOnly: true,
          decoration: const InputDecoration(labelText: 'التاريخ', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_month)),
          onTap: () async => date.text = await pickDate(c) ?? date.text,
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
      ],
    ),
  );
  if (ok == true && title.text.trim().isNotEmpty && date.text.isNotEmpty) {
    app.addEvent(title.text.trim(), date.text);
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 76),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ───────────────────────── الشجرة ─────────────────────────

class TreeScreen extends StatelessWidget {
  const TreeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('شجرة عائلة حمد', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(tooltip: 'الشجرة الكاملة', icon: const Icon(Icons.account_tree), onPressed: () => openFullTree(context)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'إضافة فرد',
        backgroundColor: kGreen,
        foregroundColor: Colors.white,
        onPressed: () => openAdd(context),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final kids = app.children(app.root.id);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              Card(
                elevation: 2,
                child: SizedBox(
                  height: 76,
                  child: Row(children: [
                    const SizedBox(width: 12),
                    Avatar(app.root, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(app.root.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                        Text('${ar(kids.length)} فروع', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ]),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 26),
                child: Column(children: [
                  for (var i = 0; i < kids.length; i++)
                    NodeTile(key: ValueKey(kids[i].id), p: kids[i], last: i == kids.length - 1),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class NodeTile extends StatefulWidget {
  final Person p;
  final bool last;
  const NodeTile({super.key, required this.p, required this.last});
  @override
  State<NodeTile> createState() => _NodeTileState();
}

class _NodeTileState extends State<NodeTile> {
  bool open = false;
  static const double cardH = 64;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final kids = app.children(p.id);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final cs = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 28,
          child: CustomPaint(painter: _ElbowPainter(last: widget.last, rtl: rtl, color: cs.outlineVariant, midY: cardH / 2 + 12)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(children: [
              Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => kids.isEmpty ? openPerson(context, p) : setState(() => open = !open),
                  child: SizedBox(
                    height: cardH,
                    child: Row(children: [
                      const SizedBox(width: 12),
                      Avatar(p, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                          Text(kidsText(kids.length), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                        ]),
                      ),
                      if (kids.isNotEmpty) Icon(open ? Icons.expand_less : Icons.expand_more, color: cs.onSurfaceVariant),
                      IconButton(tooltip: 'بطاقة الفرد', icon: const Icon(Icons.info_outline), onPressed: () => openPerson(context, p)),
                    ]),
                  ),
                ),
              ),
              if (open && kids.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 20),
                  child: Column(children: [
                    for (var i = 0; i < kids.length; i++)
                      NodeTile(key: ValueKey(kids[i].id), p: kids[i], last: i == kids.length - 1),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ElbowPainter extends CustomPainter {
  final bool last, rtl;
  final Color color;
  final double midY;
  _ElbowPainter({required this.last, required this.rtl, required this.color, required this.midY});
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round;
    final x = rtl ? s.width - 14 : 14.0;
    final dir = rtl ? -1.0 : 1.0;
    final edge = rtl ? 0.0 : s.width;
    const r = 14.0;
    if (last) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x, midY - r)
          ..quadraticBezierTo(x, midY, x + dir * r, midY)
          ..lineTo(edge, midY),
        paint,
      );
    } else {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), paint);
      canvas.drawLine(Offset(x, midY), Offset(edge, midY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ElbowPainter o) => o.last != last || o.color != color || o.rtl != rtl;
}

// ───────────────────────── الشجرة الكاملة ─────────────────────────

class TreeLayout {
  static const double rowH = 40, colW = 140, pillW = 104, pillH = 30, margin = 24;
  final Map<String, Offset> pos = {};
  double nextY = 0;
  int maxDepth = 0;

  TreeLayout() {
    _place(app.root, 0);
  }

  double _place(Person p, int depth) {
    maxDepth = math.max(maxDepth, depth);
    final kids = app.children(p.id);
    double y;
    if (kids.isEmpty) {
      y = nextY;
      nextY += rowH;
    } else {
      final ys = [for (final k in kids) _place(k, depth + 1)];
      y = (ys.first + ys.last) / 2;
    }
    pos[p.id] = Offset(depth.toDouble(), y);
    return y;
  }

  Size get size => Size(margin * 2 + pillW + maxDepth * colW, margin * 2 + nextY);
}

class FullTreeScreen extends StatefulWidget {
  const FullTreeScreen({super.key});
  @override
  State<FullTreeScreen> createState() => _FullTreeScreenState();
}

class _FullTreeScreenState extends State<FullTreeScreen> {
  final tc = TransformationController();
  late final TreeLayout layout = TreeLayout();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final w = MediaQuery.of(context).size.width;
      tc.value = Matrix4.translationValues(math.min(0.0, w - layout.size.width), 0, 0);
    });
  }

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  void _zoom(double f) {
    tc.value = tc.value.clone()..scale(f, f, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الشجرة الكاملة', style: TextStyle(fontWeight: FontWeight.bold))),
      body: InteractiveViewer(
        transformationController: tc,
        constrained: false,
        minScale: 0.3,
        maxScale: 3,
        boundaryMargin: const EdgeInsets.all(300),
        child: CustomPaint(
          size: layout.size,
          painter: _TreePainter(layout, cs.surface, cs.onSurface, cs.outlineVariant),
        ),
      ),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(heroTag: 'z+', tooltip: 'تكبير', onPressed: () => _zoom(1.25), child: const Icon(Icons.add)),
        const SizedBox(height: 8),
        FloatingActionButton.small(heroTag: 'z-', tooltip: 'تصغير', onPressed: () => _zoom(0.8), child: const Icon(Icons.remove)),
      ]),
    );
  }
}

class _TreePainter extends CustomPainter {
  final TreeLayout L;
  final Color fill, text, line;
  _TreePainter(this.L, this.fill, this.text, this.line);

  Rect _rect(Size s, Offset p) => Rect.fromLTWH(
        s.width - TreeLayout.margin - TreeLayout.pillW - p.dx * TreeLayout.colW,
        TreeLayout.margin + p.dy + (TreeLayout.rowH - TreeLayout.pillH) / 2,
        TreeLayout.pillW,
        TreeLayout.pillH,
      );

  @override
  void paint(Canvas canvas, Size s) {
    for (final p in app.people) {
      if (p.parentId == null) continue;
      final a = _rect(s, L.pos[p.parentId!]!);
      final b = _rect(s, L.pos[p.id]!);
      final c = app.colorOf(p);
      final from = Offset(a.left, a.center.dy), to = Offset(b.right, b.center.dy);
      final mx = (from.dx + to.dx) / 2;
      canvas.drawPath(
        Path()..moveTo(from.dx, from.dy)..cubicTo(mx, from.dy, mx, to.dy, to.dx, to.dy),
        Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 2.5,
      );
    }
    for (final p in app.people) {
      final r = RRect.fromRectAndRadius(_rect(s, L.pos[p.id]!), const Radius.circular(15));
      final c = app.colorOf(p);
      canvas.drawRRect(r, Paint()..color = fill);
      canvas.drawRRect(r, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 2.5);
      final tp = TextPainter(
        text: TextSpan(text: p.name, style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: r.width - 12);
      tp.paint(canvas, Offset(r.left + (r.width - tp.width) / 2, r.top + (r.height - tp.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ───────────────────────── بطاقة الفرد ─────────────────────────

class PersonScreen extends StatelessWidget {
  final String id;
  const PersonScreen(this.id, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.byId(id);
        if (p == null) return const Scaffold();
        final parent = p.parentId == null ? null : app.byId(p.parentId!);
        final kids = app.children(p.id);
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, p)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(child: Avatar(p, size: 88)),
              const SizedBox(height: 10),
              Center(child: Text(p.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
              Center(
                child: Text(
                  parent == null ? 'جذر الشجرة' : '${p.female ? 'ابنة' : 'ابن'} ${parent.name}',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 16),
              Card(child: ListTile(title: const Text('الفرع'), trailing: Text(app.branchOf(p).name))),
              Card(child: ListTile(title: const Text('عدد الأحفاد والأبناء'), trailing: Text(ar(app.descendants(p.id))))),
              if (p.birth.isNotEmpty) Card(child: ListTile(title: const Text('تاريخ الميلاد'), trailing: Text(p.birth))),
              if (p.city.isNotEmpty) Card(child: ListTile(title: const Text('مكان الإقامة'), trailing: Text(p.city))),
              if (p.spouse.isNotEmpty) Card(child: ListTile(title: const Text('الزوج / الزوجة'), trailing: Text(p.spouse))),
              const SizedBox(height: 12),
              const Text('الأبناء', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (kids.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('لا يوجد أبناء', style: TextStyle(color: cs.onSurfaceVariant))),
              for (final k in kids)
                Card(
                  child: ListTile(
                    leading: Avatar(k, size: 40),
                    title: Text(k.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Text(k.female ? 'ابنة' : 'ابن', style: TextStyle(color: app.colorOf(k))),
                    onTap: () => openPerson(context, k),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: kGreen),
                onPressed: () => openAdd(context, parentId: p.id),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('إضافة ابن / ابنة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (parent != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: const Color(0xFFB3261E)),
                  onPressed: () => _delete(context, p),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, Person p) async {
    final name = TextEditingController(text: p.name);
    final birth = TextEditingController(text: p.birth);
    final city = TextEditingController(text: p.city);
    final spouse = TextEditingController(text: p.spouse);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تعديل البيانات'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
              controller: birth,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'تاريخ الميلاد', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_month)),
              onTap: () async => birth.text = await pickDate(c) ?? birth.text,
            ),
            const SizedBox(height: 12),
            TextField(controller: city, decoration: const InputDecoration(labelText: 'مكان الإقامة', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: spouse, decoration: const InputDecoration(labelText: 'الزوج / الزوجة', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      app.edit(p, name.text.trim(), birth.text, city.text.trim(), spouse.text.trim());
    }
  }

  Future<void> _delete(BuildContext context, Person p) async {
    final n = app.descendants(p.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('حذف ${p.name}؟'),
        content: Text(n == 0 ? 'سيتم حذف هذا الفرد من الشجرة.' : 'سيتم حذف هذا الفرد مع ${ar(n)} من أبنائه وأحفاده.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.pop(context);
      app.remove(p.id);
    }
  }
}

// ───────────────────────── إضافة فرد ─────────────────────────

class AddScreen extends StatefulWidget {
  final String? parentId;
  const AddScreen({super.key, this.parentId});
  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  static const rels = ['ابن', 'ابنة', 'أخ', 'أخت', 'زوج/ة'];
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final birth = TextEditingController();
  final city = TextEditingController();
  late String relatedId = widget.parentId ?? app.root.id;
  int rel = 0;

  @override
  void dispose() {
    name.dispose();
    birth.dispose();
    city.dispose();
    super.dispose();
  }

  void _save() {
    if (!form.currentState!.validate()) return;
    final other = app.byId(relatedId)!;
    final n = name.text.trim();
    final msg = ScaffoldMessenger.of(context);
    if (rel == 4) {
      app.update(() => other.spouse = n);
      Navigator.pop(context);
      msg.showSnackBar(SnackBar(content: Text('تم تسجيل $n كزوج/ة ${other.name}')));
      return;
    }
    String parent = relatedId;
    if (rel == 2 || rel == 3) {
      if (other.parentId == null) {
        msg.showSnackBar(const SnackBar(content: Text('لا يمكن إضافة أخ أو أخت لجذر الشجرة')));
        return;
      }
      parent = other.parentId!;
    }
    app.add(n, parent, female: rel == 1 || rel == 3, birth: birth.text, city: city.text.trim());
    Navigator.pop(context);
    msg.showSnackBar(SnackBar(content: Text('تمت إضافة $n')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة فرد', style: TextStyle(fontWeight: FontWeight.bold))),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(
              child: CircleAvatar(radius: 44, backgroundColor: Color(0xFFDFF3E6), child: Icon(Icons.person, size: 40, color: kGreen)),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل الاسم' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: birth,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'تاريخ الميلاد (اختياري)', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_month)),
              onTap: () async {
                final d = await pickDate(context);
                if (d != null) birth.text = d;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: city,
              decoration: const InputDecoration(labelText: 'مكان الإقامة (اختياري)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text('صلته بـ', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (var i = 0; i < rels.length; i++)
                ChoiceChip(label: Text(rels[i]), selected: rel == i, onSelected: (_) => setState(() => rel = i)),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: relatedId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشخص المرتبط', border: OutlineInputBorder()),
              items: [for (final p in app.people) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => relatedId = v!),
            ),
            const SizedBox(height: 28),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: kGreen),
              onPressed: _save,
              child: const Text('حفظ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── البحث ─────────────────────────

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String q = '';
  String? branch;
  int? gen; // 1 = الأبناء، 2 = الأحفاد، ...

  Widget _chips(List<Widget> items) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          children: [for (final w in items) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: w)],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بحث', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final branches = app.children(app.root.id);
          final maxGen = app.people.map(app.depth).fold<int>(1, math.max);
          final t = q.trim();
          final res = app.people.where((p) {
            if (p == app.root) return false;
            if (t.isNotEmpty && !p.name.contains(t) && !p.city.contains(t)) return false;
            if (branch != null && app.branchOf(p).id != branch) return false;
            if (gen != null && app.depth(p) != gen) return false;
            return true;
          }).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: TextField(
                onChanged: (v) => setState(() => q = v),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'الاسم أو المدينة', border: OutlineInputBorder()),
              ),
            ),
            _chips([
              ChoiceChip(label: const Text('كل الفروع'), selected: branch == null, onSelected: (_) => setState(() => branch = null)),
              for (final b in branches)
                ChoiceChip(
                  label: Text(b.name),
                  selected: branch == b.id,
                  onSelected: (_) => setState(() => branch = branch == b.id ? null : b.id),
                ),
            ]),
            _chips([
              ChoiceChip(label: const Text('كل الأجيال'), selected: gen == null, onSelected: (_) => setState(() => gen = null)),
              for (var g = 1; g <= maxGen; g++)
                ChoiceChip(
                  label: Text('الجيل ${ar(g)}'),
                  selected: gen == g,
                  onSelected: (_) => setState(() => gen = gen == g ? null : g),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('النتائج (${ar(res.length)})', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            ),
            Expanded(
              child: res.isEmpty
                  ? const Center(child: Text('لا توجد نتائج'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: res.length,
                      itemBuilder: (_, i) {
                        final p = res[i];
                        return Card(
                          child: ListTile(
                            leading: Avatar(p, size: 40),
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${p.female ? 'ابنة' : 'ابن'} ${app.byId(p.parentId!)!.name} · فرع ${app.branchOf(p).name}'),
                            onTap: () => openPerson(context, p),
                          ),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

// ───────────────────────── صلة القرابة ─────────────────────────

class KinshipScreen extends StatefulWidget {
  const KinshipScreen({super.key});
  @override
  State<KinshipScreen> createState() => _KinshipScreenState();
}

class _KinshipScreenState extends State<KinshipScreen> {
  String? a, b;

  Widget _pick(String label, String? v, ValueChanged<String?> f) => DropdownButtonFormField<String>(
        value: v,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [for (final p in app.people) DropdownMenuItem(value: p.id, child: Text(p.name))],
        onChanged: f,
      );

  @override
  Widget build(BuildContext context) {
    final pa = a == null ? null : app.byId(a!);
    final pb = b == null ? null : app.byId(b!);
    return Scaffold(
      appBar: AppBar(title: const Text('صلة القرابة', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _pick('الشخص الأول', a, (v) => setState(() => a = v)),
          const SizedBox(height: 16),
          _pick('الشخص الثاني', b, (v) => setState(() => b = v)),
          const SizedBox(height: 24),
          if (pa != null && pb != null)
            Card(
              color: kGreen,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(app.kinship(pa, pb),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.5)),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── الإعدادات ─────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _msg(BuildContext c, String t) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: Avatar(app.root, size: 52),
              title: const Text('المستخدم', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('إدارة الحساب'),
              trailing: const Icon(Icons.chevron_left),
            ),
          ),
          const SizedBox(height: 12),
          Text('عام', style: TextStyle(color: cs.onSurfaceVariant)),
          Card(
            child: Column(children: [
              const ListTile(title: Text('اللغة'), trailing: Text('العربية')),
              SwitchListTile(
                title: const Text('الوضع الداكن'),
                value: app.dark,
                onChanged: (v) => app.update(() => app.dark = v),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text('الشجرة', style: TextStyle(color: cs.onSurfaceVariant)),
          Card(
            child: Column(children: [
              ListTile(
                title: const Text('الخصوصية'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => showDialog(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('الخصوصية'),
                    content: const Text('بيانات الشجرة محفوظة على جهازك فقط ولا تُرسل إلى أي خادم.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
                  ),
                ),
              ),
              ListTile(
                title: const Text('دعوة أفراد العائلة'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: 'انضم إلى شجرة عائلة حمد'));
                  _msg(context, 'تم نسخ نص الدعوة');
                },
              ),
              ListTile(
                title: const Text('تصدير الشجرة'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: app.exportText()));
                  _msg(context, 'تم نسخ الشجرة كنص');
                },
              ),
              ListTile(
                title: const Text('النسخ الاحتياطي'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _msg(context, 'بياناتك تُحفظ تلقائياً على هذا الجهاز'),
              ),
              ListTile(
                title: const Text('إعادة تعيين البيانات'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('إعادة التعيين؟'),
                      content: const Text('ستُحذف تعديلاتك وتعود البيانات الأولية.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
                      ],
                    ),
                  );
                  if (ok == true) app.reset();
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('تسجيل الخروج', style: TextStyle(color: Color(0xFFB3261E))),
              onTap: () => app.update(() {
                app.started = false;
                app.tab = 0;
              }),
            ),
          ),
        ],
      ),
    );
  }
}
