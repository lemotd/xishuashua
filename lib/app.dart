import 'package:flutter/material.dart';
import 'color/app_colors.dart';
import 'pages/feed_page.dart';

const _c = AppColors.dark;

class XiShuaShuaApp extends StatelessWidget {
  const XiShuaShuaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '喜刷刷',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _c.background,
        colorScheme: ColorScheme.dark(
          primary: _c.primary,
          secondary: _c.primary,
          surface: _c.surface,
        ),
      ),
      home: const FeedPage(),
    );
  }
}
