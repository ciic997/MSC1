import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'splash_gate.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A0F),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const SimApp());
}

class SimApp extends StatelessWidget {
  const SimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MSC',
      debugShowCheckedModeBanner: false,
      theme: KingTheme.dark,
      builder: (c, w) => Directionality(
        textDirection: TextDirection.rtl,
        child: w!,
      ),
      home: const SplashGate(),
    );
  }
}
