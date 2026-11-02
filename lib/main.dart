import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
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
    Color(0xFF17803F), Color(0xFF0B6FD0), Color(0xFF7B3FBF), Color(0xFFC2410C), Color(0xFFB0124F),
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
  late Person root;
  SharedPreferences? _prefs;

  AppState() {
    _seed();
  }

  Color get primary => accents[accent % accents.length];

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

  void reset() {
    people.clear();
    events.clear();
    _n = 0;
    _e = 0;
    _seed();
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
        'textScale': textScale, 'userName': userName, 'n': _n, 'e': _e,
      };

  bool applyMap(Map<String, dynamic> j) {
    final ps = [for (final x in (j['people'] as List? ?? [])) Person.fromJson(x as Map<String, dynamic>)];
    if (ps.isEmpty || !ps.any((p) => p.parentId == null)) return false;
    people..clear()..addAll(ps);
    root = people.firstWhere((p) => p.parentId == null);
    events
      ..clear()
      ..addAll([for (final x in (j['events'] as List? ?? [])) Event.fromJson(x as Map<String, dynamic>)]);
    started = j['started'] as bool? ?? started;
    themeMode = j['themeMode'] as int? ?? 0;
    accent = j['accent'] as int? ?? 0;
    textScale = (j['textScale'] as num?)?.toDouble() ?? 1.0;
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
      scaffoldBackgroundColor: light ? const Color(0xFFF3F5F1) : const Color(0xFF0C1110),
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

class Surface extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return Material(
      color: color ?? (light ? Colors.white : cs.surfaceContainerLow),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: cs.outlineVariant.withAlpha(light ? 70 : 90)),
      ),
      child: onTap == null && onLongPress == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap!();
                    },
              onLongPress: onLongPress,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
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
        home: app.started ? const Shell() : const StartScreen(),
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
    app.update(() => app.started = true);
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
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(children: [
              Expanded(
                flex: 5,
                child: RepaintBoundary(
                  child: CustomPaint(size: Size.infinite, painter: _HeroPainter(ctl, app.primary, cs.surface)),
                ),
              ),
              const Text('شجرة العائلة', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                'اجمع أفراد عائلتك وفروعها في مكان واحد، وتعرّف على صلة القرابة بينهم.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.7, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _go, child: const Text('تسجيل الدخول'))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _go, child: const Text('إنشاء شجرة جديدة'))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HeroPainter extends CustomPainter {
  final Animation<double> t;
  final Color primary, surface;
  _HeroPainter(this.t, this.primary, this.surface) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final m = math.min(s.width, s.height);
    final time = t.value * 2 * math.pi;
    canvas.drawCircle(c, m * .34, Paint()..color = primary.withAlpha(55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 42));
    for (var i = 0; i < 6; i++) {
      final col = AppState.branchColors[i];
      final a = i * 2 * math.pi / 6 + time * .5;
      final r = m * .25 + math.sin(time * 2 + i) * 5;
      final pos = c + Offset(math.cos(a) * r, math.sin(a) * r);
      final a2 = a + .32 * math.sin(time + i);
      final r2 = m * .44 + math.sin(time * 3 + i) * 5;
      final pos2 = c + Offset(math.cos(a2) * r2, math.sin(a2) * r2);
      final line = Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 3.5..strokeCap = StrokeCap.round;
      canvas.drawLine(c, pos, line);
      canvas.drawLine(pos, pos2, line..strokeWidth = 2.5);
      canvas.drawCircle(pos2, 11, Paint()..color = col);
      canvas.drawCircle(pos, 22, Paint()..color = surface);
      canvas.drawCircle(pos, 22, Paint()..color = col..style = PaintingStyle.stroke..strokeWidth = 4.5);
    }
    canvas.drawCircle(c, 40, Paint()..color = primary);
    canvas.drawCircle(c, 40, Paint()..color = Colors.white.withAlpha(90)..style = PaintingStyle.stroke..strokeWidth = 6);
    canvas.drawCircle(c, 12, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _HeroPainter old) => old.primary != primary || old.surface != surface;
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
                color: light ? Colors.white : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: cs.outlineVariant.withAlpha(110)),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(light ? 28 : 90), blurRadius: 26, offset: const Offset(0, 8))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
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
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(DateTime.now().hour < 12 ? 'صباح الخير' : 'مساء الخير', style: TextStyle(color: cs.onSurfaceVariant)),
                  Text(app.userName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                ]),
              ),
              GestureDetector(onTap: () => app.update(() => app.tab = 3), child: Avatar(app.root, size: 50)),
            ]),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [app.primary, dark], begin: Alignment.topRight, end: Alignment.bottomLeft),
                borderRadius: BorderRadius.circular(32),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Stack(children: [
                  Positioned(top: -50, left: -30, child: _Blob(170, 26)),
                  Positioned(bottom: -60, right: -20, child: _Blob(150, 18)),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('شجرتك', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const Text('شجرة عائلة حمد', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 18),
                      Row(children: [
                        _Stat(ar(app.people.length), 'فرد'),
                        const SizedBox(width: 10),
                        _Stat(ar(branches), 'فرع'),
                        const SizedBox(width: 10),
                        _Stat(ar(gens), 'أجيال'),
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
            ),
            const SizedBox(height: 16),
            Row(children: [
              _Quick(Icons.person_add_alt_1_rounded, 'إضافة فرد', () => openAdd(context)),
              const SizedBox(width: 10),
              _Quick(Icons.search_rounded, 'بحث', () => app.update(() => app.tab = 2)),
              const SizedBox(width: 10),
              _Quick(Icons.hub_outlined, 'الشجرة الكاملة', () => openFullTree(context)),
              const SizedBox(width: 10),
              _Quick(Icons.diversity_3_rounded, 'صلة القرابة', () => openKinship(context)),
            ]),
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

class _Blob extends StatelessWidget {
  final double size;
  final int alpha;
  const _Blob(this.size, this.alpha);
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(alpha)));
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(18)),
          child: Column(children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
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
            final dark = Color.lerp(app.primary, Colors.black, .38)!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, kNavPad + 40),
              children: [
                PageHeader('الشجرة', subtitle: '${ar(app.people.length)} فرداً · ${ar(kids.length)} فروع', actions: [
                  IconButton.filledTonal(tooltip: 'الشجرة الكاملة', icon: const Icon(Icons.hub_outlined), onPressed: () => openFullTree(context)),
                ]),
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
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 34),
                  child: Column(children: [
                    for (var i = 0; i < kids.length; i++) NodeTile(key: ValueKey(kids[i].id), p: kids[i], last: i == kids.length - 1),
                  ]),
                ),
              ],
            );
          },
        ),
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

class TreeLayout {
  static const double rowH = 42, colW = 150, pillW = 120, pillH = 34, margin = 28, rootW = 150, rootH = 46;
  final Map<String, Offset> pos = {}; // x = عمق الفرع، y = أعلى الصف
  final Map<String, int> side = {}; // +1 يمين، -1 يسار
  double _next = 0;
  int maxDepth = 1;
  double bodyH = rowH;

  TreeLayout() {
    final kids = app.children(app.root.id);
    int leaves(Person p) {
      final k = app.children(p.id);
      return k.isEmpty ? 1 : k.fold<int>(0, (a, c) => a + leaves(c));
    }

    final total = kids.fold<int>(0, (a, k) => a + leaves(k));
    var acc = 0, split = kids.length, best = 1 << 30;
    for (var i = 0; i <= kids.length; i++) {
      final d = (total - 2 * acc).abs();
      if (d < best) {
        best = d;
        split = i;
      }
      if (i < kids.length) acc += leaves(kids[i]);
    }
    final right = kids.sublist(0, split), left = kids.sublist(split);
    final hr = _layoutSide(right, 1), hl = _layoutSide(left, -1);
    bodyH = math.max(math.max(hr, hl), rowH);
    _shift(1, (bodyH - hr) / 2);
    _shift(-1, (bodyH - hl) / 2);
    pos[app.root.id] = Offset(0, (bodyH - rowH) / 2);
    side[app.root.id] = 0;
  }

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
    final kids = app.children(p.id);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _reset());
  }

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  void _reset() {
    if (!mounted) return;
    final s = MediaQuery.of(context).size;
    final sc = math.max(.55, math.min(1.0, s.width / layout.size.width));
    final tx = s.width / 2 - layout.halfW * sc;
    final ty = math.max(90.0, (s.height - layout.size.height * sc) / 2);
    tc.value = Matrix4.identity()
      ..translate(tx, ty)
      ..scale(sc, sc, 1.0);
  }

  void _zoom(double f) {
    final s = MediaQuery.of(context).size;
    final cx = s.width / 2, cy = s.height / 2;
    final m = Matrix4.identity()
      ..translate(cx, cy)
      ..scale(f, f, 1.0)
      ..translate(-cx, -cy);
    final next = m.multiplied(tc.value);
    final sc = next.getMaxScaleOnAxis();
    if (sc < .25 || sc > 3) return;
    tc.value = next;
  }

  void _tap(Offset o) {
    for (final p in app.people) {
      if (layout.rect(p).inflate(4).contains(o)) {
        HapticFeedback.selectionClick();
        openPerson(context, p);
        return;
      }
    }
  }

  Future<Uint8List> _buildPdf() async {
    final L = layout;
    const titleH = 96.0;
    final W = L.size.width, H = L.size.height + titleH;
    final pr = (4096 / math.max(W, H)).clamp(1.0, 3.0).toDouble();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(pr);
    c.drawRect(Rect.fromLTWH(0, 0, W, H), Paint()..color = Colors.white);
    final t1 = TextPainter(
      text: const TextSpan(text: 'شجرة عائلة حمد', style: TextStyle(color: Color(0xFF14181A), fontSize: 32, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.rtl,
    )..layout();
    t1.paint(c, Offset((W - t1.width) / 2, 18));
    final t2 = TextPainter(
      text: TextSpan(text: '${ar(app.people.length)} فرداً · ${fmtDate(DateTime.now())}', style: const TextStyle(color: Color(0xFF5B6168), fontSize: 15)),
      textDirection: TextDirection.rtl,
    )..layout();
    t2.paint(c, Offset((W - t2.width) / 2, 62));
    c.save();
    c.translate(0, titleH);
    _TreePainter(L, Colors.white, const Color(0xFF14181A), const Color(0xFFD5D9D2), dots: false).paint(c, L.size);
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
    toast(context, 'جارٍ تجهيز ملف PDF…');
    try {
      final bytes = await _buildPdf();
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: 'family-tree.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'family-tree.pdf');
      }
    } catch (e) {
      if (mounted) toast(context, 'تعذر إنشاء ملف PDF');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('الشجرة الكاملة'),
        actions: [
          PopupMenuButton<bool>(
            tooltip: 'حفظ PDF',
            icon: const Icon(Icons.picture_as_pdf_rounded),
            onSelected: _pdf,
            itemBuilder: (_) => const [
              PopupMenuItem(value: false, child: Text('حفظ / طباعة كـ PDF')),
              PopupMenuItem(value: true, child: Text('مشاركة ملف PDF')),
            ],
          ),
        ],
      ),
      body: InteractiveViewer(
        transformationController: tc,
        constrained: false,
        minScale: .25,
        maxScale: 3,
        boundaryMargin: const EdgeInsets.all(500),
        child: GestureDetector(
          onTapUp: (d) => _tap(d.localPosition),
          child: CustomPaint(size: layout.size, painter: _TreePainter(layout, cs.surface, cs.onSurface, cs.outlineVariant)),
        ),
      ),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(heroTag: 'z+', tooltip: 'تكبير', onPressed: () => _zoom(1.25), child: const Icon(Icons.add_rounded)),
        const SizedBox(height: 8),
        FloatingActionButton.small(heroTag: 'z-', tooltip: 'تصغير', onPressed: () => _zoom(.8), child: const Icon(Icons.remove_rounded)),
        const SizedBox(height: 8),
        FloatingActionButton.small(heroTag: 'z0', tooltip: 'إعادة الضبط', onPressed: _reset, child: const Icon(Icons.center_focus_strong_rounded)),
      ]),
    );
  }
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
      for (double x = 16; x < s.width; x += 32) {
        for (double y = 16; y < s.height; y += 32) {
          canvas.drawCircle(Offset(x, y), 1.2, dp);
        }
      }
    }
    for (final p in app.people) {
      if (p.parentId == null) continue;
      final a = L.rect(app.byId(p.parentId!)!);
      final b = L.rect(p);
      final right = L.side[p.id]! > 0;
      final from = right ? Offset(a.right, a.center.dy) : Offset(a.left, a.center.dy);
      final to = right ? Offset(b.left, b.center.dy) : Offset(b.right, b.center.dy);
      final mx = (from.dx + to.dx) / 2;
      canvas.drawPath(
        Path()..moveTo(from.dx, from.dy)..cubicTo(mx, from.dy, mx, to.dy, to.dx, to.dy),
        Paint()..color = app.colorOf(p)..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round,
      );
    }
    for (final p in app.people) {
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
        text: TextSpan(text: p.name.substring(0, 1), style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w900)),
        textDirection: TextDirection.rtl,
      )..layout();
      ini.paint(canvas, cc - Offset(ini.width / 2, ini.height / 2));
      final tp = TextPainter(
        text: TextSpan(text: p.name, style: TextStyle(color: fg, fontSize: isRoot ? 15 : 13, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: r.width - r.height - 6);
      tp.paint(canvas, Offset(r.right - r.height - tp.width, r.center.dy - tp.height / 2));
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
                  SectionTitle('الأبناء'),
                  if (kids.isEmpty)
                    Surface(child: Text('لا يوجد أبناء مسجلون بعد', style: TextStyle(color: cs.onSurfaceVariant))),
                  for (final k in kids)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Surface(
                        radius: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        onTap: () => openPerson(context, k),
                        child: Row(children: [
                          Avatar(k, size: 42),
                          const SizedBox(width: 12),
                          Expanded(child: Text(k.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                          Text(k.female ? 'ابنة' : 'ابن', style: TextStyle(color: cs.onSurfaceVariant)),
                          Icon(Icons.chevron_left_rounded, color: cs.onSurfaceVariant),
                        ]),
                      ),
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
                const SizedBox(height: 18),
                const Text('حجم الخط', style: TextStyle(fontWeight: FontWeight.w800)),
                Row(children: [
                  const Text('أ', style: TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider(
                      min: .85,
                      max: 1.3,
                      divisions: 9,
                      value: app.textScale.clamp(.85, 1.3).toDouble(),
                      label: '${(app.textScale * 100).round()}٪',
                      onChanged: (v) => app.update(() => app.textScale = v),
                    ),
                  ),
                  const Text('أ', style: TextStyle(fontSize: 22)),
                ]),
              ]),
            ),
            const SectionTitle('الشجرة والبيانات'),
            _group(context, [
              _Tile(Icons.group_add_outlined, 'دعوة أفراد العائلة', 'نسخ نص الدعوة', () {
                Clipboard.setData(const ClipboardData(text: 'انضم إلى شجرة عائلة حمد'));
                toast(context, 'تم نسخ نص الدعوة');
              }),
              _Tile(Icons.ios_share_rounded, 'تصدير الشجرة', 'نسخ الشجرة كنص مرتب', () {
                Clipboard.setData(ClipboardData(text: app.exportText()));
                toast(context, 'تم نسخ الشجرة كنص');
              }),
              _Tile(Icons.cloud_upload_outlined, 'نسخة احتياطية', 'نسخ كل بياناتك إلى الحافظة', () {
                Clipboard.setData(ClipboardData(text: app.exportJson()));
                toast(context, 'تم نسخ النسخة الاحتياطية. احفظها في مكان آمن');
              }),
              _Tile(Icons.cloud_download_outlined, 'استعادة نسخة', 'من الحافظة', () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                final ok = d?.text != null && app.restore(d!.text!);
                if (context.mounted) toast(context, ok ? 'تمت استعادة البيانات' : 'لا توجد نسخة احتياطية صالحة في الحافظة');
              }),
              _Tile(Icons.restart_alt_rounded, 'إعادة تعيين البيانات', 'العودة إلى البيانات الأولية', () async {
                if (await _confirm(context, 'إعادة التعيين؟', 'ستُحذف تعديلاتك وتعود البيانات الأولية.')) app.reset();
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
