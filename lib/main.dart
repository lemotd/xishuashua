import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'color/app_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Replace the ugly red error screen with a dark-themed one
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Container(
      color: AppColors.dark.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Text(
        '加载出错了\n${details.exceptionAsString()}',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.dark.textSecondary, fontSize: 14),
      ),
    );
  };

  runApp(const XiShuaShuaApp());
}
