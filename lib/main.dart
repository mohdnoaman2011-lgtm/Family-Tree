import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double kNavPad = 112;

// ═════════════════════════ النموذج ═════════════════════════

class Person {
  final String id;
  String name;
  final String? parentId;
  final bool female;
  String birth, city, spouse, photo;
  Person(this.id, this.name, this.parentId,
      {this.female = false, this.birth = '', this.city = '', this.spouse = '', this.photo = ''});

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'parentId': parentId, 'female': female,
        'birth': birth, 'city': city, 'spouse': spouse, 'photo': photo,
      };

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        j['id'] as String, j['name'] as String, j['parentId'] as String?,
        female: j['female'] as bool? ?? false,
        birth: j['birth'] as String? ?? '',
        city: j['city'] as String? ?? '',
        spouse: j['spouse'] as String? ?? '',
        photo: j['photo'] as String? ?? '',
      );
}

class Event {
  final String id;
  String title, date;
  Event(this.id, this.title, this.date);
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'date': date};
  factory Event.fromJson(Map<String, dynamic> j) =>
      Event(j['id'] as String, j['title'] as String, j['date'] as String);
}

class Upcoming {
  final String title, date;
  final int days;
  final String? eventId;
  final Person? person;
  Upcoming(this.title, this.date, this.days, {this.eventId, this.person});
}

String ar(int n) => n.toString().split('').map((d) => d == '-' ? '-' : '٠١٢٣٤٥٦٧٨٩'[int.parse(d)]).join();

String kidsText(int n) {
  if (n == 0) return 'لا يوجد أبناء';
  if (n == 1) return 'ابن واحد';
  if (n == 2) return 'ابنان';
  if (n <= 10) return '${ar(n)} أبناء';
  return '${ar(n)} ابناً';
}

String daysLabel(int d) => d < 0 ? 'مضت' : d == 0 ? 'اليوم' : d == 1 ? 'غداً' : 'بعد ${ar(d)} يوماً';

String fmtDate(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

DateTime? parseDate(String s) {
  final p = s.split('/');
  if (p.length != 3) return null;
  try {
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  } catch (_) {
    return null;
  }
}

Future<String?> pickDate(BuildContext context) async {
  final d = await showDatePicker(
    context: context,
    initialDate: DateTime(2000),
    firstDate: DateTime(1800),
    lastDate: DateTime(2100),
  );
  return d == null ? null : fmtDate(d);
}

Future<String?> pickPhoto() async {
  try {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 400, maxHeight: 400, imageQuality: 70);
    if (x == null) return null;
    return base64Encode(await x.readAsBytes());
  } catch (_) {
    return null;
  }
}

// ═════════════════════════ الحالة ═════════════════════════

class AppState extends ChangeNotifier {
  static const branchColors = [
    Color(0xFFF47A14), Color(0xFFD9A400), Color(0xFF6BB82E), Color(0xFF1F9A4D),
    Color(0xFF0B8FD0), Color(0xFF2B2FA0), Color(0xFF6A3D99), Color(0xFFC0158C),
  ];
  static const accents = [
    Color(0xFFB4570E), Color(0xFF17803F), Color(0xFF0B6FD0), Color(0xFF7B3FBF), Color(0xFFB0124F),
  ];

  final List<Person> people = [];
  final List<Event> events = [];
  final Map<String, Uint8List> _img = {};
  final Map<String, int> _imgLen = {};
  bool started = false;
  int themeMode = 0; // 0 تلقائي، 1 فاتح، 2 داكن
  int accent = 0;
  double textScale = 1.0;
  String userName = 'المستخدم';
  int tab = 0;
  int _n = 0, _e = 0;
  Person? _root;
  String familyName = '';
  Person get root => _root!;
  bool get hasTree => _root != null;
  String get treeTitle => familyName.isEmpty ? 'شجرة العائلة' : 'شجرة عائلة $familyName';
  SharedPreferences? _prefs;

  Color get primary => accents[accent % accents.length];

  Person _add(String name, String? parentId, {bool female = false}) {
    final p = Person('p${_n++}', name, parentId, female: female);
    people.add(p);
    return p;
  }

  void createTree(String rootName, String family) {
    people.clear();
    events.clear();
    _img.clear();
    _imgLen.clear();
    _n = 0;
    _e = 0;
    _root = _add(rootName, null);
    familyName = family;
    started = true;
    tab = 0;
    notifyListeners();
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
    if (p == root) return primary;
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

  Uint8List? imageOf(Person p) {
    if (p.photo.isEmpty) return null;
    final c = _img[p.id];
    if (c != null && _imgLen[p.id] == p.photo.length) return c;
    try {
      final b = base64Decode(p.photo);
      _img[p.id] = b;
      _imgLen[p.id] = p.photo.length;
      return b;
    } catch (_) {
      return null;
    }
  }

  void setPhoto(Person p, String b64) {
    p.photo = b64;
    notifyListeners();
  }

  Person add(String name, String parentId,
      {bool female = false, String birth = '', String city = '', String photo = ''}) {
    final p = _add(name, parentId, female: female);
    p.birth = birth;
    p.city = city;
    p.photo = photo;
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

  void remove(String id) {
    for (final c in children(id)) {
      remove(c.id);
    }
    people.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void _applyOrder(String parentId, List<Person> ordered) {
    final slots = <int>[for (var i = 0; i < people.length; i++) if (people[i].parentId == parentId) i];
    for (var i = 0; i < slots.length; i++) {
      people[slots[i]] = ordered[i];
    }
    notifyListeners();
  }

  void reorderChildren(String parentId, int oldIndex, int newIndex) {
    final kids = children(parentId);
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    kids.insert(newIndex, kids.removeAt(oldIndex));
    _applyOrder(parentId, kids);
  }

  /// mode 0: الاسم، mode 1: الأكبر سناً (تاريخ الميلاد)
  void sortChildren(String parentId, int mode) {
    final kids = children(parentId);
    kids.sort((a, b) {
      if (mode == 1) {
        final da = parseDate(a.birth), db = parseDate(b.birth);
        if (da != null && db != null) return da.compareTo(db);
        if (da != null) return -1;
        if (db != null) return 1;
      }
      return a.name.compareTo(b.name);
    });
    _applyOrder(parentId, kids);
  }

  void reset() {
    people.clear();
    events.clear();
    _img.clear();
    _imgLen.clear();
    _root = null;
    familyName = '';
    started = false;
    tab = 0;
    _n = 0;
    _e = 0;
    notifyListeners();
  }

  void update(void Function() f) {
    f();
    notifyListeners();
  }

  List<Upcoming> upcoming({int horizon = 90}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <Upcoming>[];
    for (final e in events) {
      final d = parseDate(e.date);
      if (d != null) out.add(Upcoming(e.title, e.date, d.difference(today).inDays, eventId: e.id));
    }
    for (final p in people) {
      final b = parseDate(p.birth);
      if (b == null) continue;
      var n = DateTime(today.year, b.month, b.day);
      if (n.isBefore(today)) n = DateTime(today.year + 1, b.month, b.day);
      final diff = n.difference(today).inDays;
      if (diff <= horizon) out.add(Upcoming('عيد ميلاد ${p.name}', fmtDate(n), diff, person: p));
    }
    int key(Upcoming u) => u.days < 0 ? 100000 - u.days : u.days;
    out.sort((a, b) => key(a).compareTo(key(b)));
    return out;
  }

  // ───── الحفظ والاستعادة ─────
  Map<String, dynamic> toMap() => {
        'people': [for (final p in people) p.toJson()],
        'events': [for (final e in events) e.toJson()],
        'started': started, 'themeMode': themeMode, 'accent': accent,
        'textScale': textScale, 'userName': userName, 'familyName': familyName, 'n': _n, 'e': _e,
      };

  bool applyMap(Map<String, dynamic> j) {
    final ps = [for (final x in (j['people'] as List? ?? [])) Person.fromJson(x as Map<String, dynamic>)];
    themeMode = j['themeMode'] as int? ?? themeMode;
    accent = j['accent'] as int? ?? accent;
    textScale = 1.0;
    userName = j['userName'] as String? ?? userName;
    if (ps.isEmpty || !ps.any((p) => p.parentId == null)) return false;
    people..clear()..addAll(ps);
    _root = people.firstWhere((p) => p.parentId == null);
    familyName = j['familyName'] as String? ?? '';
    events
      ..clear()
      ..addAll([for (final x in (j['events'] as List? ?? [])) Event.fromJson(x as Map<String, dynamic>)]);
    started = j['started'] as bool? ?? started;
    themeMode = j['themeMode'] as int? ?? 0;
    accent = j['accent'] as int? ?? 0;
    textScale = 1.0;
    userName = j['userName'] as String? ?? 'المستخدم';
    _n = (j['n'] as int?) ?? people.length + 1;
    _e = (j['e'] as int?) ?? events.length + 1;
    _img.clear();
    _imgLen.clear();
    return true;
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString('data');
    if (raw == null) return;
    try {
      applyMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  String exportJson() => jsonEncode(toMap()..['started'] = true);

  // ───── تصدير / استيراد (CSV يفتح في Excel) ─────
  static const csvHeader = ['المعرف', 'معرف الأب', 'الاسم', 'الجنس', 'تاريخ الميلاد', 'المدينة', 'الزوج/ة'];

  String exportCsv() {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    final b = StringBuffer('\uFEFF');
    b.writeln(csvHeader.map(q).join(','));
    for (final p in people) {
      b.writeln([p.id, p.parentId ?? '', p.name, p.female ? 'أنثى' : 'ذكر', p.birth, p.city, p.spouse].map(q).join(','));
    }
    return b.toString();
  }

  static List<List<String>> parseCsv(String t) {
    if (t.startsWith('\uFEFF')) t = t.substring(1);
    final rows = <List<String>>[];
    var row = <String>[];
    final f = StringBuffer();
    var inQ = false;
    void endRow() {
      row.add(f.toString());
      f.clear();
      if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (inQ) {
        if (ch == '"') {
          if (i + 1 < t.length && t[i + 1] == '"') {
            f.write('"');
            i++;
          } else {
            inQ = false;
          }
        } else {
          f.write(ch);
        }
      } else if (ch == '"') {
        inQ = true;
      } else if (ch == ',' || ch == ';') {
        row.add(f.toString());
        f.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < t.length && t[i + 1] == '\n') i++;
        endRow();
      } else {
        f.write(ch);
      }
    }
    if (f.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  /// يستبدل الشجرة بمحتوى الملف. يعيد عدد الأفراد، أو -1 إذا كان الملف غير صالح.
  int importCsv(String text) {
    try {
      final rows = parseCsv(text);
      if (rows.length < 2) return -1;
      String cell(List<String> r, int i) => i < r.length ? r[i].trim() : '';
      final list = <Person>[];
      final ids = <String>{};
      for (final r in rows.skip(1)) {
        final id = cell(r, 0), parent = cell(r, 1), name = cell(r, 2);
        if (id.isEmpty || name.isEmpty || !ids.add(id)) return -1;
        final g = cell(r, 3);
        list.add(Person(id, name, parent.isEmpty ? null : parent,
            female: g.startsWith('أ') || g.toLowerCase().startsWith('f'), birth: cell(r, 4), city: cell(r, 5), spouse: cell(r, 6)));
      }
      final roots = list.where((p) => p.parentId == null).toList();
      if (roots.length != 1 || list.any((p) => p.parentId != null && !ids.contains(p.parentId))) return -1;
      people
        ..clear()
        ..addAll(list);
      events.clear();
      _img.clear();
      _imgLen.clear();
      _root = roots.first;
      var mx = 0;
      for (final p in list) {
        final m = RegExp(r'^p(\d+)$').firstMatch(p.id);
        if (m != null) mx = math.max(mx, int.parse(m.group(1)!));
      }
      _n = math.max(mx + 1, list.length + 1);
      started = true;
      notifyListeners();
      return list.length;
    } catch (_) {
      return -1;
    }
  }

  bool restore(String raw) {
    try {
      final ok = applyMap(jsonDecode(raw) as Map<String, dynamic>);
      if (ok) notifyListeners();
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _prefs?.setString('data', jsonEncode(toMap()));
  }

  String exportText([Person? p, int depth = 0]) {
    p ??= root;
    final b = StringBuffer('${'  ' * depth}- ${p.name}\n');
    for (final c in children(p.id)) {
      b.write(exportText(c, depth + 1));
    }
    return b.toString();
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
}

final app = AppState();

// ═════════════════════════ الثيم ═════════════════════════

Color onColor(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : const Color(0xFF14181A);

final Map<String, ThemeData> _themes = {};

ThemeData buildTheme(Brightness b) {
  final key = '${app.accent}-${b.name}';
  return _themes.putIfAbsent(key, () {
    final scheme = ColorScheme.fromSeed(seedColor: app.primary, brightness: b);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = GoogleFonts.tajawalTextTheme(base.textTheme);
    final light = b == Brightness.light;
    return base.copyWith(
      scaffoldBackgroundColor: light ? const Color(0xFFF8F4EC) : const Color(0xFF14100C),
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 22, color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium?.copyWith(fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  });
}

void toast(BuildContext c, String msg) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), margin: const EdgeInsets.fromLTRB(16, 0, 16, 96)));
}

InputDecoration deco(BuildContext c, String label, {Widget? suffix, String? hint}) {
  final cs = Theme.of(c).colorScheme;
  OutlineInputBorder b(Color col, double w) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col, width: w));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffix,
    filled: true,
    fillColor: cs.surfaceContainerHighest.withAlpha(110),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: b(Colors.transparent, 0),
    enabledBorder: b(Colors.transparent, 0),
    focusedBorder: b(cs.primary, 2),
    errorBorder: b(cs.error, 1.5),
    focusedErrorBorder: b(cs.error, 2),
  );
}

// ═════════════════════════ عناصر مشتركة ═════════════════════════

class Surface extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final double radius;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.color,
    this.radius = 24,
  });

  @override
  State<Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<Surface> {
  bool down = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final w = widget;
    final interactive = w.onTap != null || w.onLongPress != null;
    final card = Material(
      color: w.color ?? (light ? Colors.white : cs.surfaceContainerLow),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(w.radius),
        side: BorderSide(color: cs.outlineVariant.withAlpha(light ? 70 : 90)),
      ),
      child: !interactive
          ? Padding(padding: w.padding, child: w.child)
          : InkWell(
              onHighlightChanged: (v) => setState(() => down = v),
              onTap: w.onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      w.onTap!();
                    },
              onLongPress: w.onLongPress,
              child: Padding(padding: w.padding, child: w.child),
            ),
    );
    if (!interactive) return card;
    return AnimatedScale(scale: down ? .97 : 1, duration: const Duration(milliseconds: 130), curve: Curves.easeOut, child: card);
  }
}

/// ظهور متدرّج: يتلاشى العنصر ويرتفع قليلاً عند فتح الشاشة (i = ترتيبه).
class Reveal extends StatelessWidget {
  final int i;
  final Widget child;
  const Reveal({super.key, required this.i, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 420 + i * 140),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, (1 - v) * 22), child: c)),
        child: child,
      );
}

class _AppScroll extends MaterialScrollBehavior {
  const _AppScroll();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class Avatar extends StatelessWidget {
  final Person p;
  final double size;
  final Color? ring;
  const Avatar(this.p, {super.key, this.size = 44, this.ring});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = app.colorOf(p);
    final img = app.imageOf(p);
    final rc = ring ?? c;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size > 70 ? 3.5 : 2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [rc, rc.withAlpha(120)], begin: Alignment.topRight, end: Alignment.bottomLeft),
      ),
      child: ClipOval(
        child: img != null
            ? Image.memory(img, fit: BoxFit.cover, gaplessPlayback: true)
            : Container(
                color: Color.alphaBlend(c.withAlpha(46), cs.surface),
                alignment: Alignment.center,
                child: Text(p.name.substring(0, 1),
                    style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: cs.onSurface)),
              ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageHeader(this.title, {super.key, this.subtitle, this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.2)),
            if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ]),
      );
}

void openPerson(BuildContext c, Person p) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => PersonScreen(p.id)));
void openAdd(BuildContext c, {String? parentId}) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => AddScreen(parentId: parentId)));
void openFullTree(BuildContext c) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => const FullTreeScreen()));
void openKinship(BuildContext c) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => const KinshipScreen()));

Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(c).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: builder(c)),
      ),
    );

Future<void> addEventSheet(BuildContext context) async {
  final title = TextEditingController();
  final date = TextEditingController();
  await showSheet<void>(
    context,
    (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('إضافة مناسبة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 16),
      TextField(controller: title, decoration: deco(c, 'اسم المناسبة')),
      const SizedBox(height: 12),
      TextField(
        controller: date,
        readOnly: true,
        decoration: deco(c, 'التاريخ', suffix: const Icon(Icons.calendar_month)),
        onTap: () async => date.text = await pickDate(c) ?? date.text,
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () {
          if (title.text.trim().isEmpty || date.text.isEmpty) return;
          app.addEvent(title.text.trim(), date.text);
          Navigator.pop(c);
        },
        child: const Text('حفظ'),
      ),
    ]),
  );
}

Future<void> editPersonSheet(BuildContext context, Person p) async {
  final name = TextEditingController(text: p.name);
  final birth = TextEditingController(text: p.birth);
  final city = TextEditingController(text: p.city);
  final spouse = TextEditingController(text: p.spouse);
  await showSheet<void>(
    context,
    (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('تعديل البيانات', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 16),
      TextField(controller: name, decoration: deco(c, 'الاسم')),
      const SizedBox(height: 12),
      TextField(
        controller: birth,
        readOnly: true,
        decoration: deco(c, 'تاريخ الميلاد', suffix: const Icon(Icons.calendar_month)),
        onTap: () async => birth.text = await pickDate(c) ?? birth.text,
      ),
      const SizedBox(height: 12),
      TextField(controller: city, decoration: deco(c, 'مكان الإقامة')),
      const SizedBox(height: 12),
      TextField(controller: spouse, decoration: deco(c, 'الزوج / الزوجة')),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () {
          if (name.text.trim().isEmpty) return;
          app.edit(p, name.text.trim(), birth.text, city.text.trim(), spouse.text.trim());
          Navigator.pop(c);
        },
        child: const Text('حفظ'),
      ),
    ]),
  );
}

// ═════════════════════════ التطبيق ═════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
        scrollBehavior: const _AppScroll(),
        themeMode: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark][app.themeMode],
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(app.textScale)),
              child: Directionality(textDirection: TextDirection.rtl, child: child!),
            ),
          );
        },
        home: (app.started && app.hasTree) ? const Shell() : const StartScreen(),
      ),
    );
  }
}

// ═════════════════════════ شاشة البداية ═════════════════════════

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});
  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _go() {
    HapticFeedback.mediumImpact();
    if (app.hasTree) {
      app.update(() => app.started = true);
    } else {
      _create();
    }
  }

  Future<void> _create() async {
    if (app.hasTree) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('إنشاء شجرة جديدة؟'),
          content: const Text('ستُستبدل الشجرة الحالية وتُحذف بياناتها.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(88, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('متابعة')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final name = TextEditingController();
    final fam = TextEditingController();
    await showSheet<void>(
      context,
      (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('إنشاء شجرة جديدة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('ابدأ بجذر الشجرة، ثم أضف بقية الأفراد.', style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextField(controller: name, autofocus: true, decoration: deco(c, 'اسم جذر الشجرة (مثال: محمد أحمد)')),
        const SizedBox(height: 12),
        TextField(controller: fam, decoration: deco(c, 'اسم العائلة (مثال: أحمد)')),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty) return;
            final n = name.text.trim(), f = fam.text.trim();
            Navigator.pop(c);
            app.createTree(n, f);
          },
          child: const Text('إنشاء الشجرة'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primaryContainer.withAlpha(170), Theme.of(context).scaffoldBackgroundColor],
            stops: const [0, .65],
          ),
        ),
        child: Stack(children: [
          Positioned(top: -90, right: -70, child: _glow(280, app.primary.withAlpha(46))),
          Positioned(bottom: 100, left: -120, child: _glow(320, cs.tertiary.withAlpha(34))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(children: [
                Expanded(
                  flex: 5,
                  child: Center(
                    child: Reveal(
                      i: 0,
                      child: AnimatedBuilder(
                        animation: ctl,
                        builder: (_, child) => Transform.translate(offset: Offset(0, math.sin(ctl.value * 2 * math.pi) * 5), child: child),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(44),
                            boxShadow: [BoxShadow(color: Colors.black.withAlpha(34), blurRadius: 34, offset: const Offset(0, 14))],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(44),
                            child: Image.asset('assets/logo.jpg', fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Reveal(i: 1, child: const Text('شجرة العائلة', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900))),
                const SizedBox(height: 10),
                Reveal(
                  i: 2,
                  child: Text(
                    'اجمع أفراد عائلتك وفروعها في مكان واحد، وتعرّف على صلة القرابة بينهم.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, height: 1.7, color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 20),
                Reveal(
                  i: 3,
                  child: const Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                    _FeatureChip(Icons.account_tree_rounded, 'شجرة تفاعلية'),
                    _FeatureChip(Icons.diversity_3_rounded, 'صلة القرابة'),
                    _FeatureChip(Icons.lock_outline_rounded, 'بياناتك على جهازك'),
                  ]),
                ),
                const SizedBox(height: 26),
                Reveal(
                  i: 4,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _go,
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(app.hasTree ? 'متابعة' : 'ابدأ'),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _glow(double d, Color c) => IgnorePointer(
        child: Container(width: d, height: d, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, Colors.transparent]))),
      );
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip(this.icon, this.label);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: light ? Colors.white.withAlpha(200) : cs.surfaceContainerHigh.withAlpha(200),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withAlpha(110)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ═════════════════════════ الهيكل ═════════════════════════

class Shell extends StatelessWidget {
  const Shell({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        extendBody: true,
        body: IndexedStack(index: app.tab, children: const [HomeScreen(), TreeScreen(), SearchScreen(), SettingsScreen()]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(34),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(light ? 28 : 90), blurRadius: 26, offset: const Offset(0, 8))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: light ? Colors.white.withAlpha(185) : cs.surfaceContainerHigh.withAlpha(200),
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(color: cs.outlineVariant.withAlpha(110)),
                    ),
                    child: NavigationBar(
                  selectedIndex: app.tab,
                  onDestinationSelected: (i) {
                    HapticFeedback.selectionClick();
                    app.update(() => app.tab = i);
                  },
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
                    NavigationDestination(icon: Icon(Icons.account_tree_outlined), selectedIcon: Icon(Icons.account_tree_rounded), label: 'الشجرة'),
                    NavigationDestination(icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.manage_search_rounded), label: 'الأفراد'),
                    NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'الإعدادات'),
                  ],
                ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ الرئيسية ═════════════════════════

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final others = app.people.where((p) => p != app.root).toList();
    final recent = others.reversed.take(10).toList();
    final branches = app.children(app.root.id).length;
    final gens = app.people.map(app.depth).fold<int>(0, math.max) + 1;
    final ups = app.upcoming();
    final dark = Color.lerp(app.primary, Colors.black, .38)!;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, kNavPad),
          children: [
            Reveal(i: 0, child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(DateTime.now().hour < 12 ? 'صباح الخير' : 'مساء الخير', style: TextStyle(color: cs.onSurfaceVariant)),
                  Text(app.userName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                ]),
              ),
              GestureDetector(onTap: () => app.update(() => app.tab = 3), child: Avatar(app.root, size: 50)),
            ])),
            const SizedBox(height: 18),
            Reveal(i: 1, child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [app.primary, dark], begin: Alignment.topRight, end: Alignment.bottomLeft),
                borderRadius: BorderRadius.circular(32),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Stack(children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(center: const Alignment(-.9, -1), radius: 1.2, colors: [Colors.white.withAlpha(52), Colors.transparent]),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(center: const Alignment(1, 1.1), radius: 1.0, colors: [Color.lerp(app.primary, Colors.white, .35)!.withAlpha(120), Colors.transparent]),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('شجرتك', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      Text(app.treeTitle, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 18),
                      Row(children: [
                        _Stat(app.people.length, 'فرد'),
                        const SizedBox(width: 10),
                        _Stat(branches, 'فرع'),
                        const SizedBox(width: 10),
                        _Stat(gens, 'أجيال'),
                      ]),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF14181A)),
                          onPressed: () => app.update(() => app.tab = 1),
                          child: const Text('فتح الشجرة'),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            )),
            const SizedBox(height: 16),
            Reveal(i: 2, child: Row(children: [
              _Quick(Icons.person_add_alt_1_rounded, 'إضافة فرد', () => openAdd(context)),
              const SizedBox(width: 10),
              _Quick(Icons.search_rounded, 'بحث', () => app.update(() => app.tab = 2)),
              const SizedBox(width: 10),
              _Quick(Icons.hub_outlined, 'الشجرة الكاملة', () => openFullTree(context)),
              const SizedBox(width: 10),
              _Quick(Icons.diversity_3_rounded, 'صلة القرابة', () => openKinship(context)),
            ])),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Surface(
                  onTap: () => openAdd(context),
                  child: Row(children: [
                    Icon(Icons.person_add_alt_1_rounded, color: cs.primary),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('شجرتك فارغة. ابدأ بإضافة أول فرد من العائلة.', style: TextStyle(fontWeight: FontWeight.w800, height: 1.5))),
                  ]),
                ),
              )
            else ...[
            const SectionTitle('أحدث الأفراد'),
            SizedBox(
              height: 98,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) {
                  final p = recent[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => openPerson(context, p),
                    child: SizedBox(
                      width: 72,
                      child: Column(children: [
                        Avatar(p, size: 58),
                        const SizedBox(height: 6),
                        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            ],
            SectionTitle('مناسبات قريبة',
                trailing: TextButton.icon(onPressed: () => addEventSheet(context), icon: const Icon(Icons.add_rounded), label: const Text('إضافة'))),
            if (ups.isEmpty)
              Surface(
                child: Row(children: [
                  Icon(Icons.event_available_rounded, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(child: Text('لا توجد مناسبات قريبة. أضف تاريخ ميلاد لأي فرد ليظهر هنا تلقائياً.', style: TextStyle(color: cs.onSurfaceVariant, height: 1.5))),
                ]),
              ),
            for (final u in ups.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Surface(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  onTap: u.person != null ? () => openPerson(context, u.person!) : null,
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                      child: Icon(u.person != null ? Icons.cake_rounded : Icons.event_rounded, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(u.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        Text('${u.date} · ${daysLabel(u.days)}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ]),
                    ),
                    if (u.eventId != null)
                      IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => app.removeEvent(u.eventId!)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final int value;
  final String label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(34),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withAlpha(40)),
          ),
          child: Column(children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value.toDouble()),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Text(ar(v.round()), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            ),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
      );
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Quick(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Surface(
        radius: 22,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.25)),
        ]),
      ),
    );
  }
}

// ═════════════════════════ الشجرة ═════════════════════════

class TreeScreen extends StatelessWidget {
  const TreeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: FloatingActionButton.extended(
          onPressed: () => openAdd(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة فرد', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final kids = app.children(app.root.id);
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: PageHeader('الشجرة', subtitle: '${ar(app.people.length)} فرداً · ${ar(kids.length)} فروع', actions: [
                  IconButton.filledTonal(tooltip: 'الشجرة الكاملة', icon: const Icon(Icons.hub_outlined), onPressed: () => openFullTree(context)),
                ]),
              ),
              const Expanded(child: _TreeList()),
            ]);
          },
        ),
      ),
    );
  }
}

class _TreeList extends StatelessWidget {
  const _TreeList();
  @override
  Widget build(BuildContext context) {
    final kids = app.children(app.root.id);
    final dark = Color.lerp(app.primary, Colors.black, .38)!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, kNavPad + 40),
      children: [
        Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [app.primary, dark], begin: Alignment.topRight, end: Alignment.bottomLeft),
            borderRadius: BorderRadius.circular(28),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => openPerson(context, app.root),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Avatar(app.root, size: 64, ring: Colors.white),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.root.name, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                    Text('جذر الشجرة · ${ar(kids.length)} فروع', style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
                const Icon(Icons.chevron_left_rounded, color: Colors.white),
              ]),
            ),
          ),
        ),
        if (kids.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 28),
            child: Text('لم تُضف أفراداً بعد.\nاضغط "إضافة فرد" للبدء.',
                textAlign: TextAlign.center, style: TextStyle(height: 1.7, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 34),
          child: Column(children: [
            for (var i = 0; i < kids.length; i++) NodeTile(key: ValueKey(kids[i].id), p: kids[i], last: i == kids.length - 1),
          ]),
        ),
      ],
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
  static const double cardH = 68;

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final kids = app.children(p.id);
    final c = app.colorOf(p);
    final cs = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
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
              Surface(
                radius: 22,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onTap: () => kids.isEmpty ? openPerson(context, p) : setState(() => open = !open),
                onLongPress: () => openPerson(context, p),
                child: SizedBox(
                  height: cardH,
                  child: Row(children: [
                    Avatar(p, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text(kidsText(kids.length), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                      ]),
                    ),
                    if (kids.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: c.withAlpha(36), borderRadius: BorderRadius.circular(12)),
                        child: Text(ar(kids.length), style: const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    if (kids.isNotEmpty)
                      AnimatedRotation(
                        turns: open ? .5 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
                      ),
                    IconButton(
                      tooltip: 'بطاقة الفرد',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.north_west_rounded, size: 20, color: cs.onSurfaceVariant),
                      onPressed: () => openPerson(context, p),
                    ),
                  ]),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: open && kids.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsetsDirectional.only(start: 20),
                        child: Column(children: [
                          for (var i = 0; i < kids.length; i++) NodeTile(key: ValueKey(kids[i].id), p: kids[i], last: i == kids.length - 1),
                        ]),
                      )
                    : const SizedBox(width: double.infinity, height: 0),
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
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round;
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

// ═════════════════════════ الشجرة الكاملة ═════════════════════════

abstract class TreeGeometry {
  Size get size;
  Offset get rootCenter;
  bool visible(Person p);
  Person? hit(Offset o);
  bool toggleHit(Offset o, Person p);
  CustomPainter painter(Color fill, Color text, Color dot, {bool dots = true});
}

Offset polar(double a, double r) => Offset(math.cos(a) * r, math.sin(a) * r);

/// تخطيط دائري: الجذر في الوسط، والأجيال حلقات، وكل فرع له قطاع بلونه.
class RadialLayout implements TreeGeometry {
  static const double pillW = 124, pillH = 30, margin = 44, rootR = 52, ringGap = 40;
  final Set<String> expanded;
  final bool all;
  final Map<String, double> ang = {};
  final Map<String, double> rin = {};
  final Map<String, int> dep = {};
  double outer = rootR;

  RadialLayout(this.expanded, {this.all = false}) {
    final kids = app.children(app.root.id);
    final total = kids.fold<int>(0, (a, k) => a + fullLeaves(k));
    if (total > 0) {
      var a0 = -math.pi / 2;
      for (final k in kids) {
        final span = 2 * math.pi * fullLeaves(k) / total;
        _place(k, 1, a0, span);
        a0 += span;
      }
    }
    final byDepth = <int, List<double>>{};
    ang.forEach((id, a) => byDepth.putIfAbsent(dep[id]!, () => []).add(a));
    final maxD = byDepth.keys.fold<int>(0, math.max);
    final rByDepth = <int, double>{};
    var prevOuter = rootR;
    for (var d = 1; d <= maxD; d++) {
      final list = byDepth[d]!..sort();
      var minGap = 2 * math.pi;
      for (var i = 0; i < list.length; i++) {
        final next = i == list.length - 1 ? list[0] + 2 * math.pi : list[i + 1];
        final g = next - list[i];
        if (g > 1e-6 && g < minGap) minGap = g;
      }
      final need = list.length > 1 ? (pillH + 10) / minGap : 0.0;
      final r = math.max(prevOuter + (d == 1 ? 44 : ringGap), need);
      rByDepth[d] = r;
      prevOuter = r + pillW;
    }
    outer = prevOuter;
    for (final id in ang.keys) {
      rin[id] = rByDepth[dep[id]!]!;
    }
  }

  bool isOpen(Person p) => all || expanded.contains(p.id);

  int _vis(Person p) {
    final k = isOpen(p) ? app.children(p.id) : <Person>[];
    return k.isEmpty ? 1 : k.fold<int>(0, (a, c) => a + _vis(c));
  }

  void _place(Person p, int depth, double start, double span) {
    ang[p.id] = start + span / 2;
    dep[p.id] = depth;
    final kids = isOpen(p) ? app.children(p.id) : <Person>[];
    if (kids.isEmpty) return;
    final total = kids.fold<int>(0, (a, k) => a + _vis(k));
    var a0 = start;
    for (final k in kids) {
      final sp = span * _vis(k) / total;
      _place(k, depth + 1, a0, sp);
      a0 += sp;
    }
  }

  Offset get center => Offset(outer + margin, outer + margin);
  @override
  Size get size => Size((outer + margin) * 2, (outer + margin) * 2);
  @override
  Offset get rootCenter => center;
  @override
  bool visible(Person p) => p.parentId == null || ang.containsKey(p.id);

  @override
  Person? hit(Offset o) {
    final d = o - center;
    if (d.distance <= rootR + 6) return app.root;
    for (final e in ang.entries) {
      final a = e.value, ri = rin[e.key]!;
      final x = d.dx * math.cos(a) + d.dy * math.sin(a);
      final y = -d.dx * math.sin(a) + d.dy * math.cos(a);
      if (x >= ri - 4 && x <= ri + pillW + 14 && y.abs() <= pillH / 2 + 4) return app.byId(e.key);
    }
    return null;
  }

  @override
  bool toggleHit(Offset o, Person p) => p.parentId != null && app.children(p.id).isNotEmpty;

  @override
  CustomPainter painter(Color fill, Color text, Color dot, {bool dots = true}) => _RadialPainter(this, fill, text, dot, dots: dots);
}

class _RadialPainter extends CustomPainter {
  final RadialLayout L;
  final Color fill, text, dot;
  final bool dots;
  _RadialPainter(this.L, this.fill, this.text, this.dot, {this.dots = true});

  @override
  void paint(Canvas canvas, Size s) {
    if (dots) {
      final dp = Paint()..color = dot.withAlpha(110);
      for (double x = 20; x < s.width; x += 40) {
        for (double y = 20; y < s.height; y += 40) {
          canvas.drawCircle(Offset(x, y), 1.3, dp);
        }
      }
    }
    final c = L.center;
    const pw = RadialLayout.pillW, ph = RadialLayout.pillH, rr = RadialLayout.rootR;
    // حلقات إرشادية خفيفة
    final guide = Paint()..color = dot.withAlpha(70)..style = PaintingStyle.stroke..strokeWidth = 1;
    final seen = <double>{};
    for (final r in L.rin.values) {
      if (seen.add(r)) canvas.drawCircle(c, r, guide);
    }
    final vis = [for (final p in app.people) if (L.ang.containsKey(p.id)) p];
    for (final p in vis) {
      final a = L.ang[p.id]!;
      final inner = c + polar(a, L.rin[p.id]!);
      Offset start;
      Offset startDir;
      if (p.parentId == app.root.id) {
        start = c + polar(a, rr);
        startDir = polar(a, 1);
      } else {
        final pa = L.ang[p.parentId!]!;
        start = c + polar(pa, L.rin[p.parentId!]! + pw);
        startDir = polar(pa, 1);
      }
      final k = (inner - start).distance * .4;
      canvas.drawPath(
        Path()..moveTo(start.dx, start.dy)..cubicTo(start.dx + startDir.dx * k, start.dy + startDir.dy * k, inner.dx - math.cos(a) * k, inner.dy - math.sin(a) * k, inner.dx, inner.dy),
        Paint()..color = app.colorOf(p)..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.round,
      );
    }
    for (final p in vis) {
      final a = L.ang[p.id]!, ri = L.rin[p.id]!;
      final col = app.colorOf(p);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      final rr2 = RRect.fromRectAndRadius(Rect.fromLTWH(ri, -ph / 2, pw, ph), const Radius.circular(ph / 2));
      canvas.drawShadow(Path()..addRRect(rr2), Colors.black, 2.5, false);
      canvas.drawRRect(rr2, Paint()..color = fill);
      canvas.drawRRect(rr2, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 2.2);
      final tp = TextPainter(
        text: TextSpan(text: p.name, style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: pw - 16);
      canvas.save();
      canvas.translate(ri + pw / 2, 0);
      if (math.cos(a) < 0) canvas.rotate(math.pi);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      canvas.restore();

      final n = app.children(p.id).length;
      if (n > 0 && !L.all) {
        final open = L.isOpen(p);
        final bc = c + polar(a, ri + pw + 3);
        canvas.drawCircle(bc, 12, Paint()..color = open ? Colors.white : col);
        canvas.drawCircle(bc, 12, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 2);
        final bt = TextPainter(
          text: TextSpan(text: open ? '−' : '+${ar(n)}', style: TextStyle(color: open ? col : onColor(col), fontSize: open ? 16 : 10, fontWeight: FontWeight.w900)),
          textDirection: TextDirection.rtl,
        )..layout();
        bt.paint(canvas, bc - Offset(bt.width / 2, bt.height / 2));
      }
    }
    // الجذر
    final root = app.root;
    canvas.drawShadow(Path()..addOval(Rect.fromCircle(center: c, radius: rr)), Colors.black, 4, false);
    canvas.drawCircle(c, rr, Paint()..color = app.primary);
    canvas.drawCircle(c, rr - 4, Paint()..color = Colors.white.withAlpha(70)..style = PaintingStyle.stroke..strokeWidth = 2);
    final rt = TextPainter(
      text: TextSpan(text: root.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, height: 1.2)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: rr * 1.7);
    rt.paint(canvas, c - Offset(rt.width / 2, rt.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ═════════════════════ صور الأفراد للرسم على اللوحة ═════════════════════

final Map<String, ui.Image> photoImages = {};
String photoKey(Person p) => '${p.id}:${p.photo.length}';

Future<bool> loadPhotos() async {
  var changed = false;
  for (final p in app.people.toList()) {
    if (p.photo.isEmpty || photoImages.containsKey(photoKey(p))) continue;
    final b = app.imageOf(p);
    if (b == null) continue;
    try {
      final codec = await ui.instantiateImageCodec(b, targetWidth: 160);
      final f = await codec.getNextFrame();
      photoImages[photoKey(p)] = f.image;
      changed = true;
    } catch (_) {}
  }
  return changed;
}

/// تخطيط البطاقات العمودي: الجذر في الأعلى والأبناء تحته بخطوط متعامدة.
/// تصميم الكبسولات: كل فرد كبسولة (صورة/حرف + اسم)، والزوج/ة بجانبه يصلهما خط،
/// ومن منتصف هذا الخط تنزل خطوط منحنية إلى الأبناء.
void drawCapsule(Canvas canvas, Rect r, String name, bool female, ui.Image? img,
    {required Color fill, required Color ink, required Color dark, bool shadow = true}) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
  if (shadow) {
    canvas.drawRRect(rr.shift(const Offset(0, 3)), Paint()..color = Colors.black.withAlpha(30)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
  }
  canvas.drawRRect(rr, Paint()..color = female ? dark : fill);
  if (!female) canvas.drawRRect(rr, Paint()..color = ink.withAlpha(24)..style = PaintingStyle.stroke..strokeWidth = 1);
  final d = r.height - 10;
  final ac = Offset(r.right - 5 - d / 2, r.center.dy);
  if (img != null) {
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: ac, radius: d / 2)));
    paintImage(canvas: canvas, rect: Rect.fromCircle(center: ac, radius: d / 2), image: img, fit: BoxFit.cover);
    canvas.restore();
  } else {
    canvas.drawCircle(ac, d / 2, Paint()..color = female ? Colors.white : Color.alphaBlend(dark.withAlpha(46), fill));
    final ini = TextPainter(
      text: TextSpan(text: name.isEmpty ? '' : name.substring(0, 1), style: TextStyle(color: dark, fontSize: d * .44, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.rtl,
    )..layout();
    ini.paint(canvas, ac - Offset(ini.width / 2, ini.height / 2));
  }
  final tp = TextPainter(
    text: TextSpan(text: name, style: TextStyle(color: female ? Colors.white : ink, fontSize: r.height >= 48 ? 15.5 : 13, fontWeight: FontWeight.w800)),
    textDirection: TextDirection.rtl,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: math.max(10.0, r.width - d - 24));
  tp.paint(canvas, Offset(ac.dx - d / 2 - 10 - tp.width, r.center.dy - tp.height / 2));
}

class CardLayout implements TreeGeometry {
  static const double pillW = 150, pillH = 52, coupleGap = 36, gapX = 28, gapY = 108, margin = 56;
  final Set<String> expanded;
  final bool all;
  final Map<String, double> ux = {}; // يسار الوحدة (منطقياً)
  final Map<String, int> dep = {};
  final Map<String, double> sub = {};
  int maxDepth = 0;
  double rootW = 0;

  CardLayout(this.expanded, {this.all = false}) {
    rootW = _measure(app.root);
    _place(app.root, 0, 0);
  }

  bool isOpen(Person p) => all || p.parentId == null || expanded.contains(p.id);
  List<Person> _kids(Person p) => isOpen(p) ? app.children(p.id) : <Person>[];
  double unitW(Person p) => p.spouse.isNotEmpty ? 2 * pillW + coupleGap : pillW;

  double _kidsW(Person p) {
    final ks = _kids(p);
    var t = 0.0;
    for (var i = 0; i < ks.length; i++) {
      t += sub[ks[i].id]! + (i > 0 ? gapX : 0);
    }
    return t;
  }

  double _measure(Person p) {
    for (final k in _kids(p)) {
      _measure(k);
    }
    final w = math.max(unitW(p), _kidsW(p));
    sub[p.id] = w;
    return w;
  }

  void _place(Person p, double x0, int d) {
    maxDepth = math.max(maxDepth, d);
    dep[p.id] = d;
    final w = sub[p.id]!;
    ux[p.id] = x0 + (w - unitW(p)) / 2;
    var kx = x0 + (w - _kidsW(p)) / 2;
    for (final k in _kids(p)) {
      _place(k, kx, d + 1);
      kx += sub[k.id]! + gapX;
    }
  }

  @override
  Size get size => Size(margin * 2 + rootW, margin * 2 + (maxDepth + 1) * pillH + maxDepth * gapY);

  double _top(Person p) => margin + dep[p.id]! * (pillH + gapY);

  // الفرد على اليمين والزوج/ة على يساره (اتجاه عربي)
  Rect rect(Person p) => Rect.fromLTWH(margin + rootW - (ux[p.id]! + pillW), _top(p), pillW, pillH);

  Rect? spouseRect(Person p) {
    if (p.spouse.isEmpty) return null;
    final x = ux[p.id]! + pillW + coupleGap;
    return Rect.fromLTWH(margin + rootW - (x + pillW), _top(p), pillW, pillH);
  }

  Offset junction(Person p) {
    final r = rect(p), s = spouseRect(p);
    if (s == null) return Offset(r.center.dx, r.bottom);
    return Offset((r.left + s.right) / 2, r.center.dy);
  }

  Rect badgeRect(Person p) {
    final r = rect(p);
    return Rect.fromCenter(center: Offset(r.center.dx, r.bottom), width: 34, height: 34);
  }

  @override
  Offset get rootCenter => rect(app.root).center;
  @override
  bool visible(Person p) => ux.containsKey(p.id);

  @override
  Person? hit(Offset o) {
    for (final p in app.people) {
      if (!visible(p)) continue;
      final s = spouseRect(p);
      if (rect(p).inflate(2).contains(o) || (s != null && s.inflate(2).contains(o)) || (p.parentId != null && app.children(p.id).isNotEmpty && badgeRect(p).contains(o))) return p;
    }
    return null;
  }

  @override
  bool toggleHit(Offset o, Person p) => p.parentId != null && app.children(p.id).isNotEmpty && badgeRect(p).contains(o);

  @override
  CustomPainter painter(Color fill, Color text, Color dot, {bool dots = true}) => _CardPainter(this, fill, text, dot, dots: dots);
}

class _CardPainter extends CustomPainter {
  final CardLayout L;
  final Color fill, text, line;
  final bool dots;
  _CardPainter(this.L, this.fill, this.text, this.line, {this.dots = true});

  @override
  void paint(Canvas canvas, Size s) {
    final night = fill.computeLuminance() < .5;
    final dk = Color.lerp(app.primary, Colors.black, night ? .12 : .38)!;
    if (dots) {
      final pts = <Offset>[];
      for (double x = -1200; x < s.width + 1200; x += 30) {
        for (double y = -1200; y < s.height + 1200; y += 30) {
          pts.add(Offset(x, y));
        }
      }
      canvas.drawPoints(ui.PointMode.points, pts, Paint()..color = line.withAlpha(120)..strokeWidth = 3..strokeCap = StrokeCap.round);
    }
    final lp = Paint()
      ..color = Color.alphaBlend(app.primary.withAlpha(120), line)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final vis = [for (final p in app.people) if (L.visible(p)) p];
    for (final p in vis) {
      final r = L.rect(p), sr = L.spouseRect(p);
      if (sr != null) canvas.drawLine(Offset(r.left, r.center.dy), Offset(sr.right, r.center.dy), lp);
      final j = L.junction(p);
      for (final k in app.children(p.id)) {
        if (!L.visible(k)) continue;
        final kr = L.rect(k);
        final ex = kr.center.dx, ey = kr.top;
        final my = j.dy + (ey - j.dy) * .5;
        final path = Path()..moveTo(j.dx, j.dy);
        if ((ex - j.dx).abs() < 1) {
          path.lineTo(ex, ey);
        } else {
          path.cubicTo(j.dx, my, ex, my, ex, ey);
        }
        canvas.drawPath(path, lp);
      }
    }
    for (final p in vis) {
      final r = L.rect(p);
      drawCapsule(canvas, r, p.name, p.female, photoImages[photoKey(p)], fill: fill, ink: text, dark: dk);
      final sr = L.spouseRect(p);
      if (sr != null) drawCapsule(canvas, sr, p.spouse, !p.female, null, fill: fill, ink: text, dark: dk);
      final n = app.children(p.id).length;
      if (p.parentId != null && n > 0 && !L.all) {
        final open = L.isOpen(p);
        final bc = Offset(r.center.dx, r.bottom);
        canvas.drawCircle(bc, 12, Paint()..color = open ? fill : dk);
        canvas.drawCircle(bc, 12, Paint()..color = dk..style = PaintingStyle.stroke..strokeWidth = 2);
        final bt = TextPainter(
          text: TextSpan(text: open ? '−' : '+${ar(n)}', style: TextStyle(color: open ? dk : Colors.white, fontSize: open ? 16 : 10, fontWeight: FontWeight.w900)),
          textDirection: TextDirection.rtl,
        )..layout();
        bt.paint(canvas, bc - Offset(bt.width / 2, bt.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ═════════════════════════ PDF هرمي مرتب ═════════════════════════
// صفحة للنظرة العامة (الجذر + الفروع + أبناؤهم) ثم صفحة لكل فرع له أحفاد.
// كل صفحة تُملأ بالشجرة بحجم مناسب (A4 ثم A3 ثم A2 حسب الحاجة).

class _PBox {
  final Person p;
  final List<_PBox> kids = [];
  bool hang = false; // الأبناء الأخيرون يُعرضون معلّقين تحت أبيهم
  double w = 0, h = 0, cx = 0, cy = 0; // cx: يسار الوحدة (منطقياً)
  _PBox(this.p);
}

class _PdfTree {
  static const double cardW = 150, cardH = 52, gapX = 26, gapY = 76, coupleGap = 36;
  static const double pillW = 128, pillH = 38, pillGap = 8, hangGap = 24, hangIndent = 22, trunkX = 12;
  static const Color ink = Color(0xFF14181A);
  late final _PBox root;
  double bw = 0, bh = 0;

  _PdfTree(Person top, {int? limit}) {
    root = _build(top, 0, limit);
    _measure(root);
    _place(root, 0, 0);
    bw = root.w;
    bh = root.h;
  }

  _PBox _build(Person p, int d, int? limit) {
    final b = _PBox(p);
    if (limit == null || d < limit) {
      for (final k in app.children(p.id)) {
        b.kids.add(_build(k, d + 1, limit));
      }
    }
    b.hang = d > 0 && b.kids.isNotEmpty && b.kids.every((k) => k.kids.isEmpty);
    return b;
  }

  double _unit(_PBox b) => b.p.spouse.isNotEmpty ? 2 * cardW + coupleGap : cardW;
  double _kw(_PBox b) => b.kids.fold<double>(0, (a, k) => a + k.w) + gapX * math.max(0, b.kids.length - 1);

  void _measure(_PBox b) {
    for (final k in b.kids) {
      _measure(k);
    }
    if (b.kids.isEmpty) {
      b.w = _unit(b);
      b.h = cardH;
    } else if (b.hang) {
      b.w = math.max(_unit(b), hangIndent + pillW);
      b.h = cardH + hangGap + b.kids.length * (pillH + pillGap) - pillGap;
    } else {
      var mh = 0.0;
      for (final k in b.kids) {
        mh = math.max(mh, k.h);
      }
      b.w = math.max(_unit(b), _kw(b));
      b.h = cardH + gapY + mh;
    }
  }

  void _place(_PBox b, double x, double y) {
    b.cy = y;
    if (b.kids.isEmpty || b.hang) {
      b.cx = x;
      return;
    }
    var kx = x + (b.w - _kw(b)) / 2;
    for (final k in b.kids) {
      _place(k, kx, y + cardH + gapY);
      kx += k.w + gapX;
    }
    b.cx = x + (b.w - _unit(b)) / 2;
  }

  // العرض من اليمين لليسار: نعكس المواضع أفقياً مع إبقاء النصوص سليمة
  Rect _mr(double x, double y, double w, double h) => Rect.fromLTWH(bw - (x + w), y, w, h);
  double _mx(double x) => bw - x;

  void draw(Canvas c) {
    final line = Paint()
      ..color = Color.alphaBlend(app.primary.withAlpha(120), const Color(0xFFD5D9D2))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    _lines(root, c, line);
    _cards(root, c);
  }

  void _lines(_PBox b, Canvas c, Paint line) {
    final hasS = b.p.spouse.isNotEmpty;
    final midY = b.cy + cardH / 2;
    if (hasS) c.drawLine(Offset(_mx(b.cx + cardW), midY), Offset(_mx(b.cx + cardW + coupleGap), midY), line);
    final bottom = b.cy + cardH;
    if (b.hang) {
      final tx = _mx(b.cx + trunkX);
      final firstY = bottom + hangGap + pillH / 2;
      final lastY = bottom + hangGap + (b.kids.length - 1) * (pillH + pillGap) + pillH / 2;
      c.drawLine(Offset(tx, bottom), Offset(tx, lastY), line);
      for (var i = 0; i < b.kids.length; i++) {
        final py = firstY + i * (pillH + pillGap);
        c.drawLine(Offset(tx, py), Offset(_mx(b.cx + hangIndent), py), line);
      }
      return;
    }
    final jx = hasS ? _mx(b.cx + cardW + coupleGap / 2) : _mx(b.cx + cardW / 2);
    final jy = hasS ? midY : bottom;
    for (final k in b.kids) {
      final ex = _mx(k.cx + cardW / 2), ey = k.cy;
      final my = jy + (ey - jy) * .5;
      final path = Path()..moveTo(jx, jy);
      if ((ex - jx).abs() < 1) {
        path.lineTo(ex, ey);
      } else {
        path.cubicTo(jx, my, ex, my, ex, ey);
      }
      c.drawPath(path, line);
      _lines(k, c, line);
    }
  }

  void _cards(_PBox b, Canvas c) {
    final dk = Color.lerp(app.primary, Colors.black, .38)!;
    drawCapsule(c, _mr(b.cx, b.cy, cardW, cardH), b.p.name, b.p.female, photoImages[photoKey(b.p)], fill: Colors.white, ink: ink, dark: dk);
    if (b.p.spouse.isNotEmpty) {
      drawCapsule(c, _mr(b.cx + cardW + coupleGap, b.cy, cardW, cardH), b.p.spouse, !b.p.female, null, fill: Colors.white, ink: ink, dark: dk);
    }
    if (b.hang) {
      for (var i = 0; i < b.kids.length; i++) {
        final k = b.kids[i].p;
        drawCapsule(c, _mr(b.cx + hangIndent, b.cy + cardH + hangGap + i * (pillH + pillGap), pillW, pillH), k.name, k.female, photoImages[photoKey(k)],
            fill: Colors.white, ink: ink, dark: dk);
      }
    } else {
      for (final k in b.kids) {
        _cards(k, c);
      }
    }
  }
}

Future<Uint8List> buildFamilyPdf() async {
  final specs = <(String, String, _PdfTree)>[];
  final top = app.children(app.root.id);
  final deep = [for (final b in top) if (app.children(b.id).any((k) => app.children(k.id).isNotEmpty)) b];
  final hasDeep = deep.isNotEmpty;
  specs.add((
    app.treeTitle,
    '${ar(app.people.length)} فرداً · ${fmtDate(DateTime.now())}${hasDeep ? ' · تفاصيل الأحفاد في الصفحات التالية' : ''}',
    _PdfTree(app.root, limit: hasDeep ? 2 : null),
  ));
  for (final b in deep) {
    specs.add(('فرع ${b.name}', '${ar(app.descendants(b.id) + 1)} فرداً', _PdfTree(b)));
  }
  final doc = pw.Document();
  const papers = [PdfPageFormat.a4, PdfPageFormat.a3, PdfPageFormat(1190.55, 1683.78)]; // A4 ثم A3 ثم A2
  for (var i = 0; i < specs.length; i++) {
    final (title, sub, t) = specs[i];
    final land = t.bw >= t.bh * .85;
    late double W, H, sc;
    for (final f in papers) {
      W = land ? f.height : f.width;
      H = land ? f.width : f.height;
      sc = math.min((W - 56) / t.bw, (H - 56 - 84) / t.bh);
      if (sc >= .6) break;
    }
    sc = sc.clamp(.15, 1.6).toDouble();
    final pr = math.min(3.0, 3600 / math.max(W, H));
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(pr);
    c.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..color = Colors.white);
    TextPainter tp(String s, double size, FontWeight w, Color col) => TextPainter(
          text: TextSpan(text: s, style: TextStyle(color: col, fontSize: size, fontWeight: w)),
          textDirection: TextDirection.rtl,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: W - 80);
    final t1 = tp(title, 26, FontWeight.w900, const Color(0xFF14181A));
    t1.paint(c, Offset((W - t1.width) / 2, 18));
    final t2 = tp(sub, 12, FontWeight.w400, const Color(0xFF5B6168));
    t2.paint(c, Offset((W - t2.width) / 2, 52));
    c.drawLine(Offset(40, 76), Offset(W - 40, 76), Paint()..color = const Color(0xFFE3DED5)..strokeWidth = 1);
    final t3 = tp('صفحة ${ar(i + 1)} من ${ar(specs.length)}', 10, FontWeight.w400, const Color(0xFF8A8F96));
    t3.paint(c, Offset((W - t3.width) / 2, H - 22));
    final availH = H - 84 - 28;
    c.save();
    c.translate((W - t.bw * sc) / 2, 84 + (availH - t.bh * sc) / 2);
    c.scale(sc);
    t.draw(c);
    c.restore();
    final img = await rec.endRecording().toImage((W * pr).round(), (H * pr).round());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    final image = pw.MemoryImage(bd!.buffer.asUint8List());
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(W, H),
      build: (_) => pw.Image(image, width: W, height: H, fit: pw.BoxFit.fill),
    ));
  }
  return doc.save();
}

int fullLeaves(Person p) {
  final k = app.children(p.id);
  return k.isEmpty ? 1 : k.fold<int>(0, (a, c) => a + fullLeaves(c));
}

class TreeLayout implements TreeGeometry {
  static const double rowH = 50, colW = 175, pillW = 130, pillH = 36, margin = 36, rootW = 160, rootH = 50;
  final Set<String> expanded;
  final bool all;
  final Map<String, Offset> pos = {}; // x = عمق الفرع، y = أعلى الصف
  final Map<String, int> side = {}; // +1 يمين، -1 يسار
  double _next = 0;
  int maxDepth = 1;
  double bodyH = rowH;

  TreeLayout(this.expanded, {this.all = false}) {
    final kids = app.children(app.root.id);
    // التقسيم يعتمد على العدد الكامل للأفراد ليبقى ثابتاً عند الطي والتوسيع
    final total = kids.fold<int>(0, (a, k) => a + fullLeaves(k));
    var acc = 0, split = kids.length, best = 1 << 30;
    for (var i = 0; i <= kids.length; i++) {
      final d = (total - 2 * acc).abs();
      if (d < best) {
        best = d;
        split = i;
      }
      if (i < kids.length) acc += fullLeaves(kids[i]);
    }
    final right = kids.sublist(0, split), left = kids.sublist(split);
    final hr = _layoutSide(right, 1), hl = _layoutSide(left, -1);
    bodyH = math.max(math.max(hr, hl), rowH);
    _shift(1, (bodyH - hr) / 2);
    _shift(-1, (bodyH - hl) / 2);
    pos[app.root.id] = Offset(0, (bodyH - rowH) / 2);
    side[app.root.id] = 0;
  }

  bool isOpen(Person p) => all || p.parentId == null || expanded.contains(p.id);
  @override
  bool visible(Person p) => pos.containsKey(p.id);

  @override
  Offset get rootCenter => rect(app.root).center;

  @override
  Person? hit(Offset o) {
    for (final p in app.people) {
      if (visible(p) && rect(p).inflate(4).contains(o)) return p;
    }
    return null;
  }

  @override
  bool toggleHit(Offset o, Person p) => p.parentId != null && app.children(p.id).isNotEmpty;

  @override
  CustomPainter painter(Color fill, Color text, Color dot, {bool dots = true}) => _TreePainter(this, fill, text, dot, dots: dots);

  double _layoutSide(List<Person> list, int sign) {
    _next = 0;
    for (final k in list) {
      _place(k, 1, sign);
    }
    return _next;
  }

  void _shift(int sign, double dy) {
    for (final e in side.entries) {
      if (e.value == sign) pos[e.key] = pos[e.key]! + Offset(0, dy);
    }
  }

  double _place(Person p, int depth, int sign) {
    maxDepth = math.max(maxDepth, depth);
    side[p.id] = sign;
    final kids = isOpen(p) ? app.children(p.id) : <Person>[];
    double y;
    if (kids.isEmpty) {
      y = _next;
      _next += rowH;
    } else {
      final ys = [for (final k in kids) _place(k, depth + 1, sign)];
      y = (ys.first + ys.last) / 2;
    }
    pos[p.id] = Offset(depth * sign.toDouble(), y);
    return y;
  }

  double get halfW => maxDepth * colW + pillW / 2 + margin;
  Size get size => Size(halfW * 2, margin * 2 + bodyH);

  Rect rect(Person p) {
    final o = pos[p.id]!;
    final cy = margin + o.dy + rowH / 2;
    if (p.parentId == null) return Rect.fromCenter(center: Offset(halfW, cy), width: rootW, height: rootH);
    return Rect.fromCenter(center: Offset(halfW + o.dx * colW, cy), width: pillW, height: pillH);
  }
}

/// لوحة الشجرة: بطاقات عمودية / دائري / جانبين
class TreeCanvas extends StatefulWidget {
  const TreeCanvas({super.key});
  @override
  State<TreeCanvas> createState() => _TreeCanvasState();
}

class _TreeCanvasState extends State<TreeCanvas> {
  final tc = TransformationController();
  int mode = 0; // 0 بطاقات، 1 دائري، 2 جانبين
  Size _vp = Size.zero;
  int _lastSig = 0;
  late Set<String> expanded = _defaultExpanded();
  late TreeGeometry geo = _make();

  Set<String> _defaultExpanded() => mode == 0 ? <String>{} : {for (final b in app.children(app.root.id)) b.id};

  TreeGeometry _make({bool all = false}) =>
      mode == 0 ? CardLayout(expanded, all: all) : mode == 1 ? RadialLayout(expanded, all: all) : TreeLayout(expanded, all: all);

  bool get _allOpen => app.people.where((p) => p.parentId != null && app.children(p.id).isNotEmpty).every((p) => expanded.contains(p.id));

  int _sig() => Object.hashAll([for (final p in app.people) Object.hash(p.id, p.name, p.parentId, p.photo.length, p.female, p.spouse)]);

  @override
  void initState() {
    super.initState();
    _lastSig = _sig();
    app.addListener(_onApp);
    _loadPhotos();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reset());
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    tc.dispose();
    super.dispose();
  }

  void _loadPhotos() => loadPhotos().then((c) {
        if (c && mounted) setState(() {});
      });

  void _onApp() {
    if (!mounted || !app.hasTree) return;
    final s = _sig();
    if (s == _lastSig) return;
    _lastSig = s;
    _relayout(() {});
    _loadPhotos();
  }

  void _reset() {
    if (!mounted || _vp.isEmpty) return;
    final rc = geo.rootCenter;
    if (mode == 0) {
      const sc = .75;
      tc.value = Matrix4.identity()
        ..translate(_vp.width / 2 - rc.dx * sc, 90 - rc.dy * sc)
        ..scale(sc, sc, 1.0);
      return;
    }
    final sc = math.min(1.0, math.max(.5, _vp.width / geo.size.width * 1.5));
    tc.value = Matrix4.identity()
      ..translate(_vp.width / 2 - rc.dx * sc, _vp.height / 2 - rc.dy * sc)
      ..scale(sc, sc, 1.0);
  }

  // يغيّر الطي/التوسيع مع إبقاء الجذر في نفس مكانه على الشاشة
  void _relayout(void Function() change) {
    final m = tc.value;
    final p0 = MatrixUtils.transformPoint(m, geo.rootCenter);
    setState(() {
      change();
      geo = _make();
    });
    final p1 = MatrixUtils.transformPoint(m, geo.rootCenter);
    tc.value = Matrix4.translationValues(p0.dx - p1.dx, p0.dy - p1.dy, 0).multiplied(m);
  }

  void _setMode(int m) {
    if (m == mode) return;
    setState(() {
      mode = m;
      expanded = _defaultExpanded();
      geo = _make();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reset());
  }

  void _toggle(Person p) => _relayout(() {
        if (!expanded.remove(p.id)) expanded.add(p.id);
      });

  void _zoom(double f) {
    final cx = _vp.width / 2, cy = _vp.height / 2;
    final m = Matrix4.identity()
      ..translate(cx, cy)
      ..scale(f, f, 1.0)
      ..translate(-cx, -cy);
    final next = m.multiplied(tc.value);
    final sc = next.getMaxScaleOnAxis();
    if (sc < .2 || sc > 3) return;
    tc.value = next;
  }

  void _tap(Offset o) {
    final p = geo.hit(o);
    if (p == null) return;
    HapticFeedback.selectionClick();
    if (geo.toggleHit(o, p)) {
      _toggle(p);
    } else {
      openPerson(context, p);
    }
  }

  Future<Uint8List> _buildPdf() async {
    final TreeGeometry L = mode == 0
        ? CardLayout(const {}, all: true)
        : mode == 1
            ? RadialLayout(const {}, all: true)
            : TreeLayout(const {}, all: true);
    const titleH = 96.0;
    final W = math.max(L.size.width, 420.0), H = L.size.height + titleH;
    final pr = (4096 / math.max(W, H)).clamp(.4, 3.0).toDouble();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(pr);
    c.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..color = Colors.white);
    final t1 = TextPainter(
      text: TextSpan(text: app.treeTitle, style: const TextStyle(color: Color(0xFF14181A), fontSize: 32, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.rtl,
    )..layout();
    t1.paint(c, Offset((W - t1.width) / 2, 18));
    final t2 = TextPainter(
      text: TextSpan(text: '${ar(app.people.length)} فرداً · ${fmtDate(DateTime.now())}', style: const TextStyle(color: Color(0xFF5B6168), fontSize: 15)),
      textDirection: TextDirection.rtl,
    )..layout();
    t2.paint(c, Offset((W - t2.width) / 2, 62));
    c.save();
    c.translate((W - L.size.width) / 2, titleH);
    L.painter(Colors.white, const Color(0xFF14181A), const Color(0xFFD5D9D2), dots: false).paint(c, L.size);
    c.restore();
    final img = await rec.endRecording().toImage((W * pr).round(), (H * pr).round());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    final image = pw.MemoryImage(bd!.buffer.asUint8List());
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(W, H),
      build: (_) => pw.Image(image, width: W, height: H, fit: pw.BoxFit.fill),
    ));
    return doc.save();
  }

  Future<void> _pdf(bool share) async {
    toast(context, 'جارٍ تجهيز ملف PDF (قد يستغرق لحظات)…');
    try {
      final bytes = await buildFamilyPdf();
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: 'family-tree.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'family-tree.pdf');
      }
    } catch (e) {
      if (mounted) toast(context, 'تعذر إنشاء ملف PDF');
    }
  }

  Widget _roundBtn(BuildContext context, IconData icon, String tip, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return Tooltip(
      message: tip,
      child: Material(
        color: light ? Colors.white : cs.surfaceContainerHigh,
        elevation: 2,
        shadowColor: Colors.black45,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: SizedBox(width: 52, height: 52, child: Icon(icon, size: 26)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allOpen = _allOpen;
    return LayoutBuilder(builder: (context, box) {
      final first = _vp.isEmpty;
      _vp = Size(box.maxWidth, box.maxHeight);
      if (first) WidgetsBinding.instance.addPostFrameCallback((_) => _reset());
      return Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: tc,
            constrained: false,
            minScale: .2,
            maxScale: 3,
            boundaryMargin: const EdgeInsets.all(600),
            child: GestureDetector(
              onTapUp: (d) => _tap(d.localPosition),
              onLongPressStart: (d) {
                final p = geo.hit(d.localPosition);
                if (p != null) {
                  HapticFeedback.mediumImpact();
                  openPerson(context, p);
                }
              },
              child: CustomPaint(size: geo.size, painter: geo.painter(cs.surface, cs.onSurface, cs.outlineVariant)),
            ),
          ),
        ),
        // أدوات التكبير (كبسولة أسفل اليسار)
        Positioned(
          left: 12,
          bottom: 12,
          child: Material(
            color: Theme.of(context).brightness == Brightness.light ? Colors.white : cs.surfaceContainerHigh,
            elevation: 3,
            shadowColor: Colors.black54,
            shape: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'إعادة الضبط', icon: const Icon(Icons.my_location_rounded), onPressed: () { HapticFeedback.selectionClick(); _reset(); }),
                IconButton(tooltip: 'تكبير', icon: const Icon(Icons.add_rounded, size: 28), onPressed: () { HapticFeedback.selectionClick(); _zoom(1.25); }),
                IconButton(tooltip: 'تصغير', icon: const Icon(Icons.remove_rounded, size: 28), onPressed: () { HapticFeedback.selectionClick(); _zoom(.8); }),
                AnimatedBuilder(
                  animation: tc,
                  builder: (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${ar((tc.value.getMaxScaleOnAxis() * 100).round())}٪', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ),
        ),
        // أدوات الشكل و PDF
        Positioned(
          right: 12,
          top: 12,
          child: Row(children: [
            PopupMenuButton<int>(
              tooltip: 'شكل العرض',
              onSelected: _setMode,
              itemBuilder: (_) => [
                for (final e in const [(0, 'بطاقات عمودية'), (1, 'دائري'), (2, 'على الجانبين')])
                  CheckedPopupMenuItem(value: e.$1, checked: mode == e.$1, child: Text(e.$2)),
              ],
              child: IgnorePointer(child: _roundBtn(context, Icons.view_quilt_rounded, 'شكل العرض', null)),
            ),
            const SizedBox(width: 8),
            _roundBtn(
              context,
              allOpen ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
              allOpen ? 'طي الفروع' : 'توسيع الكل',
              () => _relayout(() => expanded = allOpen ? _defaultExpanded() : {for (final p in app.people) if (app.children(p.id).isNotEmpty) p.id}),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<bool>(
              tooltip: 'حفظ PDF',
              onSelected: _pdf,
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('حفظ / طباعة كـ PDF')),
                PopupMenuItem(value: true, child: Text('مشاركة ملف PDF')),
              ],
              child: IgnorePointer(child: _roundBtn(context, Icons.picture_as_pdf_rounded, 'حفظ PDF', null)),
            ),
          ]),
        ),
        Positioned(
          bottom: 76,
          left: 12,
          right: 12,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: cs.surfaceContainerHigh.withAlpha(230), borderRadius: BorderRadius.circular(20)),
                child: Text(
                  mode == 0 ? 'اضغط الاسم لفتح البطاقة · الدائرة أسفله تفتح الفرع أو تطويه' : 'اضغط الفرع لفتحه أو طيّه · اضغط مطولاً لفتح البطاقة',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

class FullTreeScreen extends StatelessWidget {
  const FullTreeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الشجرة الكاملة')),
        body: const SafeArea(top: false, child: TreeCanvas()),
      );
}

class _TreePainter extends CustomPainter {
  final TreeLayout L;
  final Color fill, text, dot;
  final bool dots;
  _TreePainter(this.L, this.fill, this.text, this.dot, {this.dots = true});

  @override
  void paint(Canvas canvas, Size s) {
    if (dots) {
      final dp = Paint()..color = dot.withAlpha(110);
      for (double x = 20; x < s.width; x += 40) {
        for (double y = 20; y < s.height; y += 40) {
          canvas.drawCircle(Offset(x, y), 1.3, dp);
        }
      }
    }
    final vis = [for (final p in app.people) if (L.visible(p)) p];
    for (final p in vis) {
      if (p.parentId == null) continue;
      final a = L.rect(app.byId(p.parentId!)!);
      final b = L.rect(p);
      final right = L.side[p.id]! > 0;
      final from = right ? Offset(a.right, a.center.dy) : Offset(a.left, a.center.dy);
      final to = right ? Offset(b.left, b.center.dy) : Offset(b.right, b.center.dy);
      final mx = (from.dx + to.dx) / 2;
      canvas.drawPath(
        Path()..moveTo(from.dx, from.dy)..cubicTo(mx, from.dy, mx, to.dy, to.dx, to.dy),
        Paint()..color = app.colorOf(p)..style = PaintingStyle.stroke..strokeWidth = 2.6..strokeCap = StrokeCap.round,
      );
    }
    for (final p in vis) {
      final r = L.rect(p);
      final isRoot = p.parentId == null;
      final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height / 2));
      final c = app.colorOf(p);
      canvas.drawShadow(Path()..addRRect(rr), Colors.black, 3, false);
      canvas.drawRRect(rr, Paint()..color = isRoot ? c : fill);
      canvas.drawRRect(rr, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 2.2);
      final fg = isRoot ? Colors.white : text;
      final cc = Offset(r.right - r.height / 2, r.center.dy);
      canvas.drawCircle(cc, r.height / 2 - 5, Paint()..color = isRoot ? Colors.white.withAlpha(60) : Color.alphaBlend(c.withAlpha(70), fill));
      final ini = TextPainter(
        text: TextSpan(text: p.name.substring(0, 1), style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w900)),
        textDirection: TextDirection.rtl,
      )..layout();
      ini.paint(canvas, cc - Offset(ini.width / 2, ini.height / 2));
      final tp = TextPainter(
        text: TextSpan(text: p.name, style: TextStyle(color: fg, fontSize: isRoot ? 16 : 14, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: r.width - r.height - 6);
      tp.paint(canvas, Offset(r.right - r.height - tp.width, r.center.dy - tp.height / 2));

      // شارة الطي/التوسيع على الحافة الخارجية للفرع
      final n = app.children(p.id).length;
      if (!isRoot && n > 0 && !L.all) {
        final open = L.isOpen(p);
        final bc = Offset(L.side[p.id]! > 0 ? r.right + 2 : r.left - 2, r.center.dy);
        canvas.drawCircle(bc, 12, Paint()..color = open ? Colors.white : c);
        canvas.drawCircle(bc, 12, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 2);
        final bt = TextPainter(
          text: TextSpan(text: open ? '−' : '+${ar(n)}', style: TextStyle(color: open ? c : onColor(c), fontSize: open ? 16 : 10, fontWeight: FontWeight.w900)),
          textDirection: TextDirection.rtl,
        )..layout();
        bt.paint(canvas, bc - Offset(bt.width / 2, bt.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ═════════════════════════ بطاقة الفرد ═════════════════════════

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
        final c = app.colorOf(p);
        final dark = Color.lerp(c, Colors.black, .32)!;
        final fg = onColor(Color.lerp(c, dark, .5)!);
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            foregroundColor: fg,
            actions: [IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined), onPressed: () => editPersonSheet(context, p))],
          ),
          body: ListView(
            padding: EdgeInsets.only(bottom: 32 + MediaQuery.of(context).padding.bottom),
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + kToolbarHeight, 20, 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c, dark], begin: Alignment.topRight, end: Alignment.bottomLeft),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
                ),
                child: Column(children: [
                  GestureDetector(
                    onTap: () async {
                      final b = await pickPhoto();
                      if (b != null) app.setPhoto(p, b);
                    },
                    child: Stack(children: [
                      Avatar(p, size: 112, ring: fg.withAlpha(230)),
                      PositionedDirectional(
                        bottom: 0,
                        end: 0,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withAlpha(50), blurRadius: 8)]),
                          child: const Icon(Icons.photo_camera_rounded, size: 19, color: Color(0xFF14181A)),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Text(p.name, style: TextStyle(color: fg, fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: fg.withAlpha(34), borderRadius: BorderRadius.circular(20)),
                    child: Text(parent == null ? 'جذر الشجرة' : '${p.female ? 'ابنة' : 'ابن'} ${parent.name}',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    _MiniStat(ar(kids.length), 'الأبناء'),
                    const SizedBox(width: 10),
                    _MiniStat(ar(app.descendants(p.id)), 'الذرية'),
                    const SizedBox(width: 10),
                    _MiniStat(ar(app.depth(p) + 1), 'الجيل'),
                  ]),
                  const SizedBox(height: 14),
                  Surface(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      _InfoRow(Icons.account_tree_outlined, 'الفرع', app.branchOf(p).name, null),
                      const Divider(height: 1, indent: 64),
                      _InfoRow(Icons.cake_outlined, 'تاريخ الميلاد', p.birth, () => editPersonSheet(context, p)),
                      const Divider(height: 1, indent: 64),
                      _InfoRow(Icons.location_on_outlined, 'مكان الإقامة', p.city, () => editPersonSheet(context, p)),
                      const Divider(height: 1, indent: 64),
                      _InfoRow(Icons.favorite_border_rounded, 'الزوج / الزوجة', p.spouse, () => editPersonSheet(context, p)),
                    ]),
                  ),
                  SectionTitle(
                    'الأبناء',
                    trailing: kids.length > 1
                        ? PopupMenuButton<int>(
                            tooltip: 'ترتيب تلقائي',
                            icon: const Icon(Icons.sort_rounded),
                            onSelected: (m) => app.sortChildren(p.id, m),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 0, child: Text('ترتيب حسب الاسم')),
                              PopupMenuItem(value: 1, child: Text('الأكبر سناً أولاً (تاريخ الميلاد)')),
                            ],
                          )
                        : null,
                  ),
                  if (kids.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10, right: 4),
                      child: Text('اسحب المقبض لتغيير ترتيب الأبناء', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                    ),
                  if (kids.isEmpty)
                    Surface(child: Text('لا يوجد أبناء مسجلون بعد', style: TextStyle(color: cs.onSurfaceVariant))),
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: kids.length,
                    onReorderStart: (_) => HapticFeedback.mediumImpact(),
                    onReorder: (o, n) => app.reorderChildren(p.id, o, n),
                    proxyDecorator: (child, i, anim) => AnimatedBuilder(
                      animation: anim,
                      builder: (c, w) => Transform.scale(
                        scale: 1 + .03 * Curves.easeOut.transform(anim.value),
                        child: Material(color: Colors.transparent, child: w),
                      ),
                      child: child,
                    ),
                    itemBuilder: (context, i) {
                      final k = kids[i];
                      return Padding(
                        key: ValueKey(k.id),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Surface(
                          radius: 20,
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                          onTap: () => openPerson(context, k),
                          child: Row(children: [
                            Avatar(k, size: 42),
                            const SizedBox(width: 12),
                            Expanded(child: Text(k.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                            Text(k.female ? 'ابنة' : 'ابن', style: TextStyle(color: cs.onSurfaceVariant)),
                            ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Icon(Icons.drag_indicator_rounded, color: cs.onSurfaceVariant),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => openAdd(context, parentId: p.id),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('إضافة ابن / ابنة'),
                      ),
                    ),
                    if (parent != null) ...[
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        tooltip: 'حذف',
                        style: IconButton.styleFrom(minimumSize: const Size(56, 56), foregroundColor: cs.error),
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(context, p),
                      ),
                    ],
                  ]),
                ]),
              ),
            ],
          ),
        );
      },
    );
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
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error, minimumSize: const Size(88, 44)),
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

class _MiniStat extends StatelessWidget {
  final String value, label;
  const _MiniStat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Surface(
          radius: 20,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final VoidCallback? onTap;
  const _InfoRow(this.icon, this.label, this.value, this.onTap);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(value.isEmpty ? 'إضافة' : value,
              style: TextStyle(color: value.isEmpty ? cs.primary : cs.onSurfaceVariant, fontWeight: value.isEmpty ? FontWeight.w800 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ═════════════════════════ إضافة فرد ═════════════════════════

class AddScreen extends StatefulWidget {
  final String? parentId;
  const AddScreen({super.key, this.parentId});
  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  static const rels = ['ابن', 'ابنة', 'أخ', 'أخت', 'زوج/ة'];
  static const relIcons = [Icons.boy_rounded, Icons.girl_rounded, Icons.boy_rounded, Icons.girl_rounded, Icons.favorite_rounded];
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final birth = TextEditingController();
  final city = TextEditingController();
  late String relatedId = widget.parentId ?? app.root.id;
  int rel = 0;
  String photo = '';

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
    final nav = Navigator.of(context);
    final root = Navigator.of(context, rootNavigator: true).context;
    if (rel == 4) {
      app.update(() => other.spouse = n);
      nav.pop();
      toast(root, 'تم تسجيل $n كزوج/ة ${other.name}');
      return;
    }
    var parent = relatedId;
    if (rel == 2 || rel == 3) {
      if (other.parentId == null) {
        toast(context, 'لا يمكن إضافة أخ أو أخت لجذر الشجرة');
        return;
      }
      parent = other.parentId!;
    }
    app.add(n, parent, female: rel == 1 || rel == 3, birth: birth.text, city: city.text.trim(), photo: photo);
    nav.pop();
    toast(root, 'تمت إضافة $n');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bytes = photo.isEmpty ? null : base64Decode(photo);
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة فرد')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('حفظ'))),
        ),
      ),
      body: Form(
        key: form,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final b = await pickPhoto();
                  if (b != null) setState(() => photo = b);
                },
                child: Stack(children: [
                  Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primaryContainer,
                      border: Border.all(color: cs.primary, width: 3),
                      image: bytes == null ? null : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
                    ),
                    child: bytes == null ? Icon(Icons.person_rounded, size: 52, color: cs.onPrimaryContainer) : null,
                  ),
                  PositionedDirectional(
                    bottom: 0,
                    end: 0,
                    child: CircleAvatar(radius: 18, backgroundColor: cs.primary, child: Icon(Icons.photo_camera_rounded, size: 18, color: cs.onPrimary)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 22),
            TextFormField(
              controller: name,
              textInputAction: TextInputAction.next,
              decoration: deco(context, 'الاسم'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل الاسم' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: birth,
              readOnly: true,
              decoration: deco(context, 'تاريخ الميلاد (اختياري)', suffix: const Icon(Icons.calendar_month)),
              onTap: () async {
                final d = await pickDate(context);
                if (d != null) birth.text = d;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(controller: city, decoration: deco(context, 'مكان الإقامة (اختياري)')),
            const SectionTitle('صلته بـ'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < rels.length; i++)
                ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(relIcons[i], size: 20),
                  label: Text(rels[i]),
                  selected: rel == i,
                  onSelected: (_) => setState(() => rel = i),
                ),
            ]),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: relatedId,
              isExpanded: true,
              decoration: deco(context, 'الشخص المرتبط'),
              items: [for (final p in app.people) DropdownMenuItem(value: p.id, child: Text(p.name))],
              onChanged: (v) => setState(() => relatedId = v!),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════ البحث ═════════════════════════

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String q = '';
  String? branch;
  int? gen;

  Widget _chips(List<Widget> items) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          children: [for (final w in items) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: w)],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(children: [
                  PageHeader('الأفراد', subtitle: '${ar(app.people.length - 1)} فرداً في الشجرة'),
                  TextField(
                    onChanged: (v) => setState(() => q = v),
                    decoration: deco(context, 'ابحث بالاسم أو المدينة').copyWith(prefixIcon: const Icon(Icons.search_rounded)),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
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
              Expanded(
                child: res.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.search_off_rounded, size: 56, color: cs.onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text('لا توجد نتائج', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
                        ]),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, kNavPad),
                        itemCount: res.length,
                        itemBuilder: (_, i) {
                          final p = res[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Surface(
                              radius: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              onTap: () => openPerson(context, p),
                              child: Row(children: [
                                Avatar(p, size: 46),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                    Text('${p.female ? 'ابنة' : 'ابن'} ${app.byId(p.parentId!)!.name} · فرع ${app.branchOf(p).name}',
                                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                                  ]),
                                ),
                                Icon(Icons.chevron_left_rounded, color: cs.onSurfaceVariant),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ═════════════════════════ صلة القرابة ═════════════════════════

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
        decoration: deco(context, label),
        items: [for (final p in app.people) DropdownMenuItem(value: p.id, child: Text(p.name))],
        onChanged: f,
      );

  @override
  Widget build(BuildContext context) {
    final pa = a == null ? null : app.byId(a!);
    final pb = b == null ? null : app.byId(b!);
    final dark = Color.lerp(app.primary, Colors.black, .38)!;
    return Scaffold(
      appBar: AppBar(title: const Text('صلة القرابة')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _pick('الشخص الأول', a, (v) => setState(() => a = v)),
          Center(
            child: IconButton(
              tooltip: 'تبديل',
              icon: const Icon(Icons.swap_vert_rounded),
              onPressed: () => setState(() {
                final t = a;
                a = b;
                b = t;
              }),
            ),
          ),
          _pick('الشخص الثاني', b, (v) => setState(() => b = v)),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: (pa != null && pb != null)
                ? Container(
                    key: ValueKey('${pa.id}-${pb.id}'),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [app.primary, dark], begin: Alignment.topRight, end: Alignment.bottomLeft),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(children: [
                      const Icon(Icons.diversity_3_rounded, color: Colors.white70, size: 34),
                      const SizedBox(height: 10),
                      Text(app.kinship(pa, pb),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.55)),
                    ]),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════ الإعدادات ═════════════════════════

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _group(BuildContext c, List<Widget> tiles) {
    final cs = Theme.of(c).colorScheme;
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 68, color: cs.outlineVariant.withAlpha(120)),
          tiles[i],
        ],
      ]),
    );
  }

  Future<void> _editName(BuildContext context) async {
    final ctl = TextEditingController(text: app.userName);
    await showSheet<void>(
      context,
      (c) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('اسم المستخدم', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        TextField(controller: ctl, autofocus: true, decoration: deco(c, 'الاسم')),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            if (ctl.text.trim().isNotEmpty) app.update(() => app.userName = ctl.text.trim());
            Navigator.pop(c);
          },
          child: const Text('حفظ'),
        ),
      ]),
    );
  }

  Future<void> _backup(BuildContext context) async {
    try {
      final d = DateTime.now();
      final name = 'family-tree-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.json';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ النسخة الاحتياطية',
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(app.exportJson())),
      );
      if (context.mounted) toast(context, path == null ? 'لم يتم حفظ الملف' : 'تم حفظ النسخة الاحتياطية في هاتفك');
    } catch (_) {
      if (context.mounted) toast(context, 'تعذر حفظ الملف');
    }
  }

  Future<void> _restore(BuildContext context) async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      if (!context.mounted) return;
      if (!await _confirm(context, 'استعادة النسخة؟', 'ستُستبدل بيانات التطبيق الحالية ببيانات الملف.')) return;
      final ok = app.restore(utf8.decode(bytes));
      if (context.mounted) toast(context, ok ? 'تمت استعادة البيانات' : 'الملف غير صالح كنسخة احتياطية');
    } catch (_) {
      if (context.mounted) toast(context, 'تعذر قراءة الملف');
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(88, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, kNavPad),
          children: [
            const PageHeader('الإعدادات'),
            Surface(
              onTap: () => _editName(context),
              child: Row(children: [
                Avatar(app.root, size: 60),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    Text('اضغط لتعديل الاسم', style: TextStyle(color: cs.onSurfaceVariant)),
                  ]),
                ),
                Icon(Icons.edit_outlined, color: cs.onSurfaceVariant),
              ]),
            ),
            const SectionTitle('المظهر'),
            Surface(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('تلقائي'), icon: Icon(Icons.brightness_auto_rounded)),
                    ButtonSegment(value: 1, label: Text('فاتح'), icon: Icon(Icons.light_mode_rounded)),
                    ButtonSegment(value: 2, label: Text('داكن'), icon: Icon(Icons.dark_mode_rounded)),
                  ],
                  selected: {app.themeMode},
                  onSelectionChanged: (s) => app.update(() => app.themeMode = s.first),
                ),
                const SizedBox(height: 18),
                const Text('لون التطبيق', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Row(children: [
                  for (var i = 0; i < AppState.accents.length; i++)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 12),
                      child: InkResponse(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          app.update(() => app.accent = i);
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppState.accents[i],
                            shape: BoxShape.circle,
                            border: Border.all(color: app.accent == i ? cs.onSurface : Colors.transparent, width: 3),
                          ),
                          child: app.accent == i ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
            const SectionTitle('الشجرة والبيانات'),
            _group(context, [
              _Tile(Icons.cloud_upload_outlined, 'نسخة احتياطية', 'حفظ ملف النسخة في هاتفك', () => _backup(context)),
              _Tile(Icons.cloud_download_outlined, 'استعادة نسخة', 'اختيار ملف النسخة من هاتفك', () => _restore(context)),
              _Tile(Icons.restart_alt_rounded, 'حذف كل البيانات', 'حذف الشجرة والبدء من جديد', () async {
                if (await _confirm(context, 'حذف كل البيانات؟', 'ستُحذف الشجرة وكل الأفراد والمناسبات نهائياً.')) app.reset();
              }),
            ]),
            const SectionTitle('عام'),
            _group(context, [
              _Tile(Icons.lock_outline_rounded, 'الخصوصية', 'بياناتك على جهازك فقط', () {
                showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('الخصوصية'),
                    content: const Text('بيانات الشجرة محفوظة على جهازك فقط ولا تُرسل إلى أي خادم.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
                  ),
                );
              }),
              _Tile(Icons.info_outline_rounded, 'عن التطبيق', 'الإصدار ٢٫٠', () {
                showAboutDialog(context: context, applicationName: 'شجرة العائلة', applicationVersion: '2.0.0', applicationLegalese: 'بياناتك محفوظة على جهازك');
              }),
              _Tile(Icons.logout_rounded, 'تسجيل الخروج', null, () => app.update(() {
                    app.started = false;
                    app.tab = 0;
                  }), danger: true),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
  const _Tile(this.icon, this.title, this.subtitle, this.onTap, {this.danger = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = danger ? cs.error : cs.onSurface;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: danger ? cs.errorContainer : cs.primaryContainer, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, size: 21, color: danger ? cs.onErrorContainer : cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: col)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ]),
          ),
          Icon(Icons.chevron_left_rounded, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}
