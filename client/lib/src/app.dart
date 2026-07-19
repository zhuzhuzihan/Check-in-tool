import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/attendance_controller.dart';
import 'screens/home/attendance_home_screen.dart';
import 'theme/app_theme.dart';

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({
    super.key,
    required this.controller,
    this.disposeController = true,
  });

  final AttendanceController controller;
  final bool disposeController;

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.controller.isSubmitting) {
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.disposeController) widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智能打卡',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: AttendanceHomeScreen(controller: widget.controller),
    );
  }
}
