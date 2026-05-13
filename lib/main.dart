import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/rig_state.dart';
import 'screens/dashboard_screen.dart';
import 'theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => RigState(),
      child: const RigApp(),
    ),
  );
}

class RigApp extends StatelessWidget {
  const RigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rig Dashboard',
      debugShowCheckedModeBanner: false,
      theme: RigTheme.theme,
      home: const DashboardScreen(),
    );
  }
}