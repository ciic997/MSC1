import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'sim_channel.dart';
import 'theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<Map> sims = [];
  Map cfg = {
    'blocked': -1,
    'mode': 'reject',
    'enabled': true,
    'allowContacts': false,
    'notify': false,
    'total': 0,
    'allowed': [],
    'log': [],
  };
  bool role = false;
  bool loading = true;
  bool permanentlyDenied = false;
  String? error;
  bool _busy = false;
  bool _again = false;

  String _explain(Object e) {
    if (e is MissingPluginException) {
      return 'قناة النظام غير موجودة (sim_channel). تأكد أن AndroidManifest يستخدم '
          'com.example.simdata.MainActivity ثم أعد التثبيت.';
    }
    if (e is PlatformException) {
      if (e.code == 'PERMISSION') return 'يلزم منح صلاحية الهاتف لقراءة الشرائح.';
      return 'خطأ من النظام: ${e.message ?? e.code}';
    }
    return 'حدث خطأ أثناء تحميل البيانات.';
  }

  int get blocked => cfg['blocked'] as int;
  String get mode => cfg['mode'] as String;
  bool get enabled => cfg['enabled'] as bool;
  bool get allowContacts => cfg['allowContacts'] as bool;
  bool get notify => cfg['notify'] as bool;
  int get total => (cfg['total'] as num).toInt();
  List get allowed => cfg['allowed'] as List;
  List get log => cfg['log'] as List;

  Map? get blockedSim {
    for (final s in sims) {
      if (s['subId'] == blocked) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load(askPermission: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // عند العودة للتطبيق نحدّث بصمت دون إعادة طلب الصلاحيات (لتفادي الحلقات)
    if (s == AppLifecycleState.resumed) load(silent: true);
  }

  // ── Data ────────────────────────────────────────────────────────────────────
  Future<void> load({bool askPermission = false, bool silent = false}) async {
    if (_busy) {
      _again = true; // نعيد التحميل بعد انتهاء الحالي بدل تجاهل الطلب
      return;
    }
    _busy = true;
    if (!silent && mounted) setState(() => loading = true);
    try {
      var st = await Permission.phone.status;
      if (!st.isGranted && askPermission) st = await Permission.phone.request();
      if (!st.isGranted) {
        if (!mounted) return;
        setState(() {
          permanentlyDenied = st.isPermanentlyDenied;
          error = 'يلزم منح صلاحية الهاتف لقراءة الشرائح.';
          loading = false;
        });
        return;
      }
      final s = await SimChannel.getSims();
      final c = await SimChannel.getConfig();
      final r = await SimChannel.hasRole();
      if (!mounted) return;
      setState(() {
        sims = s;
        cfg = c;
        role = r;
        error = null;
        permanentlyDenied = false;
        loading = false;
      });
    } catch (e) {
      debugPrint('load failed: $e');
      if (!mounted) return;
      setState(() {
        error = _explain(e);
        loading = false;
      });
    } finally {
      _busy = false;
      if (_again && mounted) {
        _again = false;
        load(silent: true);
      }
    }
  }

  Future<void> save(Map<String, dynamic> m) async {
    try {
      await SimChannel.setConfig(m);
    } catch (e) {
      debugPrint('setConfig failed: $e');
      toast('تعذّر حفظ الإعداد.');
    }
    await load(silent: true);
  }

  Future<void> assign(Map s) async {
    await save({'blocked': s['subId']});
    if (!role) await SimChannel.requestRole();
  }

  void toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: KingTheme.cardElevated,
      ));
  }

  Future<void> toggleContacts(bool v) async {
    if (v) {
      final st = await Permission.contacts.request();
      if (!st.isGranted) {
        toast('لم تُمنح صلاحية جهات الاتصال.');
        return;
      }
    }
    await save({'allowContacts': v});
  }

  Future<void> toggleNotify(bool v) async {
    if (v) {
      final st = await Permission.notification.request();
      if (!st.isGranted) {
        toast('لم تُمنح صلاحية الإشعارات.');
        return;
      }
    }
    await save({'notify': v});
  }

  Future<void> addAllowed(String raw) async {
    final d = Num.digits(raw);
    if (d.length < 6) {
      toast('الرقم قصير جداً.');
      return;
    }
    if (allowed.any((x) => Num.same(x as String, raw))) {
      toast('الرقم موجود مسبقاً.');
      return;
    }
    await save({'allowed': [...allowed, d]});
    toast('تمت إضافة الرقم للمسموحة.');
  }

  Future<void> addNumber() async {
    final ctl = TextEditingController();
    final n = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KingTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('رقم مسموح',
            style: TextStyle(color: KingTheme.textPrimary)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          style: const TextStyle(color: KingTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'مثال: 21612345678',
            prefixIcon: Icon(Icons.phone, color: KingTheme.accent),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
                style: TextStyle(color: KingTheme.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (n != null && n.isNotEmpty) await addAllowed(n);
  }

  Future<void> confirmClearLog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KingTheme.card,
        title: const Text('مسح السجل؟',
            style: TextStyle(color: KingTheme.textPrimary)),
        content: const Text('سيتم حذف سجل المكالمات المحجوبة والعدّاد.',
            style: TextStyle(color: KingTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء',
                style: TextStyle(color: KingTheme.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('مسح'),
          ),
        ],
      ),
    );
    if (ok == true) await save({'clearLog': true});
  }

  String fmt(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}/${p(d.month)}/${p(d.day)}  ${p(d.hour)}:${p(d.minute)}';
  }

  // ── Small building blocks ───────────────────────────────────────────────────
  Widget _box({required Widget child, EdgeInsets? padding, double radius = 14}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KingTheme.card,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }

  Widget _smallAction(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: KingTheme.accent,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget sectionTitle(String t, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: KingTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t,
              style: const TextStyle(
                color: KingTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _switchTile(
      IconData icon, String title, String sub, bool value, ValueChanged<bool> on) {
    return SwitchListTile(
      value: value,
      onChanged: on,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      secondary: Icon(icon, color: KingTheme.textSecondary),
      title: Text(title,
          style: const TextStyle(color: KingTheme.textPrimary, fontSize: 14)),
      subtitle: Text(sub,
          style: const TextStyle(color: KingTheme.textSecondary, fontSize: 11.5)),
    );
  }

  // ── Status Card ─────────────────────────────────────────────────────────────
  Widget statusCard() {
    String title;
    String sub;
    IconData icon;
    Color c;
    Widget? action;

    if (blocked == -1) {
      title = 'لا توجد شريحة مخصصة';
      sub = 'اختر شريحة من القائمة بالأسفل لجعلها للإنترنت فقط.';
      icon = Icons.info_outline_rounded;
      c = KingTheme.cyan;
    } else if (blockedSim == null) {
      title = 'الشريحة المخصصة غير موجودة';
      sub = 'تمت إزالتها أو تعطيلها.';
      icon = Icons.sim_card_alert_rounded;
      c = KingTheme.danger;
      action = _smallAction('إلغاء', () => save({'blocked': -1}));
    } else if (!role) {
      title = 'الحظر غير مفعّل';
      sub = 'امنح التطبيق دور "تصفية المكالمات" لتفعيل الحظر.';
      icon = Icons.warning_amber_rounded;
      c = KingTheme.warning;
      action = _smallAction('تفعيل', SimChannel.requestRole);
    } else if (!enabled) {
      title = 'الحظر متوقف مؤقتاً';
      sub = 'المكالمات على SIM ${blockedSim!['slot'] + 1} تصل بشكل طبيعي.';
      icon = Icons.pause_circle_outline_rounded;
      c = KingTheme.warning;
      action = _smallAction('تشغيل', () => save({'enabled': true}));
    } else if (blockedSim!['isData'] != true) {
      title = 'الحظر يعمل، لكن البيانات على شريحة أخرى';
      sub = 'اجعل SIM ${blockedSim!['slot'] + 1} شريحة البيانات من الإعدادات.';
      icon = Icons.swap_horiz_rounded;
      c = KingTheme.warning;
      action = _smallAction('الإعدادات', SimChannel.openDataSettings);
    } else if (blockedSim!['dataEnabled'] != true) {
      title = 'الحظر يعمل، لكن بيانات الجوال مطفأة';
      sub = 'فعّل "بيانات الجوال" لتستخدم الشريحة للإنترنت.';
      icon = Icons.signal_cellular_connected_no_internet_0_bar_rounded;
      c = KingTheme.warning;
      action = _smallAction('الإعدادات', SimChannel.openDataSettings);
    } else {
      title = 'كل شيء يعمل بنجاح';
      sub = 'SIM ${blockedSim!['slot'] + 1} مخصصة للإنترنت فقط.';
      icon = Icons.check_circle_outline_rounded;
      c = KingTheme.success;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: KingTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: c.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: c, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: KingTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(sub,
                      style: const TextStyle(
                          color: KingTheme.textSecondary,
                          fontSize: 12.5,
                          height: 1.35)),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action],
          ],
        ),
      ),
    );
  }

  Widget statsRow() {
    Widget stat(IconData i, String v, String l, Color c) => Expanded(
          child: _box(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(i, color: c, size: 20),
                const SizedBox(height: 6),
                Text(v,
                    style: const TextStyle(
                        color: KingTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                Text(l,
                    style: const TextStyle(
                        color: KingTheme.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        stat(Icons.block_rounded, '$total', 'محجوبة', KingTheme.accent),
        const SizedBox(width: 10),
        stat(Icons.verified_user_rounded, '${allowed.length}', 'أرقام مسموحة',
            KingTheme.cyan),
        const SizedBox(width: 10),
        stat(
            enabled ? Icons.shield_rounded : Icons.shield_outlined,
            enabled ? 'يعمل' : 'متوقف',
            'الحماية',
            enabled ? KingTheme.success : KingTheme.warning),
      ],
    );
  }

  // ── SIM Card ────────────────────────────────────────────────────────────────
  Widget simCard(Map s) {
    final isBlocked = s['subId'] == blocked;
    final num = (s['number'] as String).isEmpty ? 'غير متاح' : s['number'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: KingTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: isBlocked
            ? Border.all(color: KingTheme.accent, width: 1.6)
            : Border.all(color: Colors.white.withValues(alpha: 0.04)),
        boxShadow: isBlocked
            ? [
                BoxShadow(
                  color: KingTheme.accent.withValues(alpha: 0.15),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isBlocked
                        ? KingTheme.accent.withValues(alpha: 0.18)
                        : KingTheme.cardElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.sim_card_rounded,
                      color: isBlocked
                          ? KingTheme.accent
                          : KingTheme.textSecondary,
                      size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SIM ${s['slot'] + 1} — ${s['carrier']}',
                          style: const TextStyle(
                              color: KingTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        'الرقم: $num',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                            color: KingTheme.textSecondary, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (s['isData'] == true)
                  _chip(Icons.wifi_rounded, 'شريحة البيانات', KingTheme.cyan),
                _chip(
                  s['dataEnabled'] == true
                      ? Icons.signal_cellular_alt_rounded
                      : Icons.signal_cellular_nodata_rounded,
                  s['dataEnabled'] == true ? 'البيانات مفعّلة' : 'البيانات مطفأة',
                  s['dataEnabled'] == true
                      ? KingTheme.success
                      : KingTheme.textSecondary,
                ),
                if (s['roaming'] == true)
                  _chip(Icons.public_rounded, 'تجوال', KingTheme.warning),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: KingTheme.cardElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isBlocked
                    ? (!enabled
                        ? 'المكالمات الواردة: مسموحة (الحظر متوقف)'
                        : mode == 'silence'
                            ? 'المكالمات الواردة: مكتومة'
                            : 'المكالمات الواردة: مرفوضة')
                    : 'المكالمات الواردة: مسموحة',
                style: TextStyle(
                  color: isBlocked && enabled
                      ? KingTheme.accent
                      : KingTheme.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isBlocked
                  ? OutlinedButton(
                      onPressed: () => save({'blocked': -1}),
                      child: const Text('إلغاء التخصيص'),
                    )
                  : FilledButton(
                      onPressed: () => assign(s),
                      child: const Text('خصّصها للإنترنت فقط'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Log item ────────────────────────────────────────────────────────────────
  Widget logItem(Map e) {
    final number = (e['number'] as String);
    final isAllowed = number.isNotEmpty && allowed.any((x) => Num.same(x as String, number));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: KingTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            e['action'] == 'silence'
                ? Icons.volume_off_rounded
                : Icons.call_end_rounded,
            size: 20,
            color: KingTheme.accent.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number.isEmpty ? 'رقم مخفي' : number,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      color: KingTheme.textPrimary, fontSize: 14),
                ),
                Text(fmt(e['time']),
                    style: const TextStyle(
                        color: KingTheme.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
          if (number.isNotEmpty && !isAllowed)
            IconButton(
              tooltip: 'إضافة للمسموحة',
              onPressed: () => addAllowed(number),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
              color: KingTheme.cyan,
            ),
        ],
      ),
    );
  }

  Widget errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: KingTheme.danger.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: KingTheme.textSecondary, fontSize: 15)),
            const SizedBox(height: 20),
            if (permanentlyDenied)
              FilledButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('فتح إعدادات التطبيق'),
              )
            else
              FilledButton.icon(
                onPressed: () => load(askPermission: true),
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
          ],
        ),
      ),
    );
  }

  Widget content() {
    return RefreshIndicator(
      onRefresh: () => load(silent: true),
      color: KingTheme.accent,
      backgroundColor: KingTheme.card,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          statusCard(),
          if (blocked != -1) ...[statsRow(), const SizedBox(height: 16)],
          if (sims.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('لم يتم العثور على شرائح نشطة.',
                    style: TextStyle(color: KingTheme.textSecondary)),
              ),
            ),
          ...sims.map(simCard),
          sectionTitle('عند ورود مكالمة على الشريحة المخصصة'),
          _box(
            padding: const EdgeInsets.all(6),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'reject',
                  label: Text('رفض'),
                  icon: Icon(Icons.call_end_rounded, size: 18),
                ),
                ButtonSegment(
                  value: 'silence',
                  label: Text('كتم الرنين'),
                  icon: Icon(Icons.volume_off_rounded, size: 18),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (v) => save({'mode': v.first}),
              style: ButtonStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
          sectionTitle('خيارات'),
          _box(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _switchTile(Icons.power_settings_new_rounded, 'تشغيل الحظر',
                    'إيقاف مؤقت دون إلغاء تخصيص الشريحة', enabled,
                    (v) => save({'enabled': v})),
                _switchTile(Icons.contacts_rounded, 'السماح لجهات الاتصال',
                    'مكالمات الأرقام المحفوظة عندك لا تُحظر', allowContacts,
                    toggleContacts),
                _switchTile(Icons.notifications_active_rounded,
                    'إشعار عند الحظر', 'إشعار صامت بكل مكالمة محجوبة', notify,
                    toggleNotify),
              ],
            ),
          ),
          sectionTitle('أرقام مسموحة (تستثنى من الحظر)'),
          _box(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...allowed.map(
                  (n) => InputChip(
                    label: Text('$n', textDirection: TextDirection.ltr),
                    onDeleted: () => save({
                      'allowed': allowed.where((x) => x != n).toList(),
                    }),
                    deleteIconColor: KingTheme.textSecondary,
                    backgroundColor: KingTheme.cardElevated,
                    side: BorderSide.none,
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded,
                      size: 18, color: KingTheme.accent),
                  label: const Text('إضافة',
                      style: TextStyle(color: KingTheme.accent)),
                  onPressed: addNumber,
                  backgroundColor: KingTheme.accentSoft,
                  side: BorderSide.none,
                ),
              ],
            ),
          ),
          sectionTitle(
            'سجل المكالمات المحجوبة',
            trailing: log.isNotEmpty
                ? TextButton(
                    onPressed: confirmClearLog,
                    style: TextButton.styleFrom(
                      foregroundColor: KingTheme.textSecondary,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('مسح', style: TextStyle(fontSize: 13)),
                  )
                : null,
          ),
          if (log.isEmpty)
            _box(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: const Center(
                child: Text('لا يوجد سجل بعد',
                    style: TextStyle(
                        color: KingTheme.textSecondary, fontSize: 13)),
              ),
            )
          else
            ...log.map((e) => logItem(e as Map)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: SimChannel.openDataSettings,
              icon: const Icon(Icons.settings_cell_rounded),
              label: const Text('فتح إعدادات شريحة البيانات'),
              style: FilledButton.styleFrom(
                backgroundColor: KingTheme.cardElevated,
                foregroundColor: KingTheme.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'أندرويد لا يسمح للتطبيقات بتبديل شريحة البيانات تلقائياً، لذلك يتم الاختيار من الإعدادات.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: KingTheme.textSecondary.withValues(alpha: 0.7),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // الخلفية معزولة بـ RepaintBoundary حتى لا تُعاد رسمها أثناء التمرير
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset('assets/splash.jpg',
                      fit: BoxFit.cover, alignment: Alignment.centerRight),
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Container(
                      color: const Color(0xFF0A0A0F).withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: KingTheme.accent.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.asset('assets/splash.jpg',
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('MSC',
                                style: TextStyle(
                                    color: KingTheme.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                            Text('KING STYLE',
                                style: TextStyle(
                                    color: KingTheme.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.5)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => load(),
                        icon: const Icon(Icons.refresh_rounded),
                        color: KingTheme.textSecondary,
                        tooltip: 'تحديث',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: error != null
                      ? errorView()
                      : loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: KingTheme.accent, strokeWidth: 2.5))
                          : content(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
