/// ============================================================================
/// 输入框跟随键盘抬高 — 最小可运行示例
/// ============================================================================
///
/// 核心要点：
///   1. PageRouteBuilder 设 opaque: false，页面背景透明
///   2. 在路由页面最外层读取 viewInsets.bottom（键盘高度）
///   3. 用 MediaQuery.copyWith(viewInsets: EdgeInsets.zero) 清零传给子树
///      → 杜绝子组件（Scaffold/Material 等）重复响应键盘
///   4. 输入框用 Positioned(bottom: 0) 贴底
///   5. 用 AnimatedPadding(bottom: keyboardHeight) 平滑跟随键盘
///      → 不要用普通 Padding，否则会硬跳
///   6. 键盘弹出时机必须在路由动画结束之后
///      → 避免 SlideTransition 和键盘 padding 两个动画叠加导致闪跳
///
/// 运行方式：
///   在任意页面调用 BottomInputSheet.show(context)
/// ============================================================================

import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('键盘跟随示例')),
        body: Center(
          child: ElevatedButton(
            onPressed: () => BottomInputSheet.show(context),
            child: const Text('弹出输入框'),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 对外入口
// =============================================================================

class BottomInputSheet {
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false, // ← 关键：透明背景
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, _) {
          return _SheetPage(animation: animation);
        },
      ),
    );
  }
}

// =============================================================================
// 全屏透明页面（路由级别）
// =============================================================================

class _SheetPage extends StatelessWidget {
  final Animation<double> animation;
  const _SheetPage({required this.animation});

  @override
  Widget build(BuildContext context) {
    // ★ 第一步：在最外层读取真实的键盘高度
    final mq = MediaQuery.of(context);
    final keyboardHeight = mq.viewInsets.bottom;

    // ★ 第二步：清零 viewInsets 传给子树，防止任何子组件重复避让
    return MediaQuery(
      data: mq.copyWith(viewInsets: EdgeInsets.zero),
      child: Material(
        color: Colors.transparent,
        child: SizedBox.expand(
          child: Stack(
            children: [
              // 半透明遮罩
              Positioned.fill(
                child: FadeTransition(
                  opacity: animation,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: const ColoredBox(color: Colors.black26),
                  ),
                ),
              ),

              // 输入框 — 贴底 + 跟随键盘
              Positioned(
                left: 0,
                right: 0,
                bottom: 0, // ← 贴着屏幕底部
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0, 1), // 从屏幕下方滑入
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeIn,
                        ),
                      ),
                  // ★ 第三步：用 AnimatedPadding 平滑过渡键盘高度
                  //    不要用普通 Padding — 普通 Padding 在 viewInsets
                  //    变化时是瞬间跳变的，会导致闪跳
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(bottom: keyboardHeight),
                    child: const _InputBar(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 输入框组件
// =============================================================================

class _InputBar extends StatefulWidget {
  const _InputBar();

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    // ★ 第四步：延迟弹出键盘，等路由动画播完
    //    路由 transitionDuration 是 500ms，这里等 600ms 再 requestFocus
    //    如果在 initState 里直接 requestFocus，键盘弹出会和
    //    SlideTransition 动画叠加，导致输入框位置闪跳
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _focusNode.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入内容...',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.only(left: 20),
                  ),
                  onSubmitted: (text) {
                    if (text.trim().isNotEmpty) {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
              GestureDetector(
                onTap: () {
                  final text = _controller.text.trim();
                  if (text.isNotEmpty) Navigator.pop(context);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
