/// ============================================================================
/// 新建合集 — 独立可复用组件
/// ============================================================================
///
/// 包含：
///   1. VoiceInputSheet        — 带语音识别的输入弹窗（全屏透明页面）
///   2. AIGlowBorder           — AI 彩色动态光效边框
///   3. _ExpandGlowWidget      — 彩色光晕从底部扩散到全屏的一次性动画
///   4. _SoundWaveBars         — 麦克风声波动画条
///   5. _SoftBounceCurve       — 柔和回弹曲线
///
/// 依赖：
///   - flutter sdk
///   - speech_to_text (pubspec.yaml: speech_to_text: ^7.0.0)
///
/// 使用方式：
///   VoiceInputSheet.show(
///     context,
///     onSubmit: (text) {
///       // 用户提交的文字（语音识别或手动输入）
///       print('用户输入: $text');
///     },
///   );
/// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// =============================================================================
// 一、主入口 — VoiceInputSheet
// =============================================================================

/// 带语音识别 + 手动输入的底部弹窗。
/// 弹出后自动开始语音识别，识别到文字后自动提交。
/// 也可手动输入文字后点击发送。
class VoiceInputSheet extends StatefulWidget {
  /// 用户提交文字后的回调
  final ValueChanged<String> onSubmit;

  /// 输入框占位文字（语音监听中）
  final String listeningHint;

  /// 输入框占位文字（非监听状态）
  final String typingHint;

  /// 语音识别语言，默认中文
  final String localeId;

  const VoiceInputSheet({
    super.key,
    required this.onSubmit,
    this.listeningHint = '说点什么...',
    this.typingHint = '输入你想说的内容',
    this.localeId = 'zh_CN',
  });

  /// 弹出语音输入面板
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onSubmit,
    String listeningHint = '说点什么...',
    String typingHint = '输入你想说的内容',
    String localeId = 'zh_CN',
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _VoiceInputPage(
            onSubmit: onSubmit,
            listeningHint: listeningHint,
            typingHint: typingHint,
            localeId: localeId,
            animation: animation,
          );
        },
        transitionDuration: const Duration(milliseconds: 700),
        reverseTransitionDuration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  State<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

/// 全屏页面：遮罩(底) → 光晕(中) → 输入框(顶)
class _VoiceInputPage extends StatelessWidget {
  final ValueChanged<String> onSubmit;
  final String listeningHint;
  final String typingHint;
  final String localeId;
  final Animation<double> animation;

  const _VoiceInputPage({
    required this.onSubmit,
    required this.listeningHint,
    required this.typingHint,
    required this.localeId,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: Stack(
          children: [
            // 1. 黑色遮罩（淡入淡出）
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
            // 2. 扫描光效
            Positioned.fill(
              child: IgnorePointer(
                child: _ExpandGlowWidget(screenSize: screenSize),
              ),
            ),
            // 3. 输入框（从底部滑入，柔和回弹）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: const _SoftBounceCurve(),
                        reverseCurve: Curves.easeIn,
                      ),
                    ),
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: VoiceInputSheet(
                    onSubmit: onSubmit,
                    listeningHint: listeningHint,
                    typingHint: typingHint,
                    localeId: localeId,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 二、输入框状态管理 + 语音识别
// =============================================================================

class _VoiceInputSheetState extends State<VoiceInputSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _speechAvailable = false;
  bool _isProcessing = false;
  bool _hasText = false;
  bool _micPressed = false;
  bool _gotWords = false;
  Timer? _silenceTimer;
  DateTime? _listenStartTime;
  bool _manualStop = false;
  double _soundLevel = 0.0;
  bool _ignoreStatus = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _initSpeech();
  }

  // ---------------------------------------------------------------------------
  // 语音初始化
  // ---------------------------------------------------------------------------

  Future<bool> _initSpeech() async {
    _ignoreStatus = true;
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          debugPrint('[VoiceInput] onStatus: $status');
          if (_ignoreStatus || !mounted || _manualStop) return;
          if (status == 'done' || status == 'notListening') {
            final hadWords = _gotWords;
            // 还在 5s 窗口内且没识别到文字 → 自动重新监听
            if (!hadWords && _listenStartTime != null) {
              final elapsed = DateTime.now().difference(_listenStartTime!);
              if (elapsed.inSeconds < 5) {
                _doListen();
                return;
              }
            }
            _silenceTimer?.cancel();
            setState(() {
              _isListening = false;
              _soundLevel = 0.0;
            });
            // 识别到文字后语音结束 → 自动提交
            if (hadWords && _controller.text.trim().isNotEmpty) {
              _submit();
            }
          }
        },
        onError: (error) {
          debugPrint('[VoiceInput] onError: ${error.errorMsg}');
          if (_ignoreStatus || !mounted || _manualStop) return;
          _silenceTimer?.cancel();
          setState(() {
            _isListening = false;
            _soundLevel = 0.0;
          });
        },
      );
      debugPrint('[VoiceInput] initialize result: $_speechAvailable');
    } catch (e) {
      debugPrint('[VoiceInput] initialize exception: $e');
      _speechAvailable = false;
    }

    // 首次权限弹窗后可能返回 false，最多重试 3 次
    if (!_speechAvailable && mounted) {
      for (int i = 0; i < 3; i++) {
        await Future.delayed(Duration(milliseconds: 600 + i * 400));
        if (!mounted) return false;
        try {
          _speechAvailable = await _speech.initialize();
          debugPrint('[VoiceInput] retry #${i + 1} result: $_speechAvailable');
        } catch (e) {
          debugPrint('[VoiceInput] retry #${i + 1} exception: $e');
        }
        if (_speechAvailable) break;
      }
    }

    // 引擎就绪后自动开始监听
    if (_speechAvailable && mounted) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        _ignoreStatus = false;
        _startListening();
      }
    }
    return _speechAvailable;
  }

  // ---------------------------------------------------------------------------
  // 开始 / 停止 / 切换 监听
  // ---------------------------------------------------------------------------

  void _startListening() {
    if (!_speechAvailable || _isListening) return;
    HapticFeedback.mediumImpact();
    _focusNode.unfocus();
    _gotWords = false;
    _manualStop = false;
    _listenStartTime = DateTime.now();
    setState(() => _isListening = true);

    // 5s 初始静默超时
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isListening && !_gotWords) {
        _stopListening();
      }
    });

    _ignoreStatus = true;
    _doListen();
    // 1.2s 保护期后开启回调
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _ignoreStatus = false;
      if (_isListening && !_manualStop && !_speech.isListening) {
        _doListen();
        _ignoreStatus = true;
        Future.delayed(const Duration(milliseconds: 1000), () {
          _ignoreStatus = false;
        });
      }
    });
  }

  void _doListen() {
    _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        final words = result.recognizedWords;
        if (words.isNotEmpty && !_gotWords) {
          _gotWords = true;
          _silenceTimer?.cancel();
        }
        setState(() {
          _controller.text = words;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        // dB 值通常 -2 ~ 10，归一化到 0~1
        final normalized = ((level + 2) / 12).clamp(0.0, 1.0);
        setState(() => _soundLevel = normalized);
      },
      localeId: widget.localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
      ),
    );
  }

  void _stopListening() {
    _manualStop = true;
    _ignoreStatus = true;
    _silenceTimer?.cancel();
    _speech.stop();
    setState(() {
      _isListening = false;
      _soundLevel = 0.0;
    });
  }

  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      // 如果之前初始化失败，重新尝试
      if (!_speechAvailable) {
        _initSpeech();
      } else {
        _startListening();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 提交
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    _stopListening();
    _focusNode.unfocus();
    setState(() => _isProcessing = true);

    // 回调给外部处理
    widget.onSubmit(input);

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _speech.stop();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintText = _isListening ? widget.listeningHint : widget.typingHint;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _isProcessing
            ? _buildProcessingIndicator(isDark)
            : AIGlowBorder(
                borderRadius: BorderRadius.circular(100),
                intensity: _isListening ? 0.4 + _soundLevel * 0.6 : 0.25,
                child: _buildInputBar(isDark, hintText),
              ),
      ),
    );
  }

  Widget _buildProcessingIndicator(bool isDark) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isDark ? const Color(0xFF6366F1) : const Color(0xFF6366F1),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '处理中...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isDark, String hintText) {
    final surfaceColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFF2F2F7);
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final primaryColor = const Color(0xFF6366F1);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        children: [
          // 文本输入区域
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: hintColor,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.only(left: 20),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          // 发送按钮（有文字时）/ 麦克风按钮（无文字时）
          if (_hasText)
            GestureDetector(
              onTap: _submit,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            )
          else
            GestureDetector(
              onTapDown: (_) => setState(() => _micPressed = true),
              onTapUp: (_) => setState(() => _micPressed = false),
              onTapCancel: () => setState(() => _micPressed = false),
              onTap: _toggleListening,
              behavior: HitTestBehavior.opaque,
              child: AnimatedScale(
                scale: _micPressed ? 0.85 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _isListening ? primaryColor : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: _isListening
                          ? _SoundWaveBars(
                              key: const ValueKey('wave'),
                              soundLevel: _soundLevel,
                              color: Colors.white,
                            )
                          : Icon(
                              Icons.mic_none_rounded,
                              key: const ValueKey('mic'),
                              size: 22,
                              color: hintColor,
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// 三、AI 彩色动态光效边框 — AIGlowBorder
// =============================================================================

/// 弥散 AI 彩色动态光效边框
/// [intensity] 0.0 = 微弱光效, 1.0 = 最强光效（语音说话时）
class AIGlowBorder extends StatefulWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final double intensity; // 0.0 ~ 1.0

  const AIGlowBorder({
    super.key,
    required this.child,
    this.borderRadius,
    this.intensity = 0.3,
  });

  @override
  State<AIGlowBorder> createState() => _AIGlowBorderState();
}

class _AIGlowBorderState extends State<AIGlowBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.borderRadius ?? BorderRadius.circular(20);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _GlowBorderPainter(
              animationValue: _controller.value,
              borderRadius: borderRadius,
              intensity: widget.intensity,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _GlowBorderPainter extends CustomPainter {
  final double animationValue;
  final BorderRadius borderRadius;
  final double intensity;

  _GlowBorderPainter({
    required this.animationValue,
    required this.borderRadius,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    final colors = <Color>[
      const Color(0xFF6366F1), // indigo
      const Color(0xFF8B5CF6), // violet
      const Color(0xFFEC4899), // pink
      const Color(0xFFF59E0B), // amber
      const Color(0xFF06B6D4), // cyan
      const Color(0xFF6366F1), // loop back
    ];

    final startAngle = animationValue * 2 * math.pi;
    final clampedIntensity = intensity.clamp(0.0, 1.0);

    final blurRadius = 12.0 + clampedIntensity * 20.0;
    final outerOpacity = 0.45 + clampedIntensity * 0.55;
    final strokeWidth = 1.5 + clampedIntensity * 1.5;
    final outerStroke = 4.0 + clampedIntensity * 8.0;
    final innerOpacity = 0.7 + clampedIntensity * 0.3;

    // 第一层：大范围弥散光晕
    final diffusePaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: colors
            .map((c) => c.withValues(alpha: outerOpacity * 0.6))
            .toList(),
        stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        transform: GradientRotation(startAngle),
      ).createShader(rect)
      ..strokeWidth = outerStroke + 8.0
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius * 1.5);
    canvas.drawRRect(rrect, diffusePaint);

    // 第二层：中等弥散
    final outerPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: colors.map((c) => c.withValues(alpha: outerOpacity)).toList(),
        stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        transform: GradientRotation(startAngle),
      ).createShader(rect)
      ..strokeWidth = outerStroke
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.outer, blurRadius);
    canvas.drawRRect(rrect, outerPaint);

    // 第三层：清晰边框线（轻微弥散）
    final innerPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: colors.map((c) => c.withValues(alpha: innerOpacity)).toList(),
        stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        transform: GradientRotation(startAngle),
      ).createShader(rect)
      ..strokeWidth = strokeWidth + 1.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawRRect(rrect, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _GlowBorderPainter oldDelegate) {
    return animationValue != oldDelegate.animationValue ||
        intensity != oldDelegate.intensity;
  }
}

// =============================================================================
// 四、彩色光晕扩散动画 — _ExpandGlowWidget
// =============================================================================

/// 从屏幕底部中心向全屏径向扩散的彩色光晕，一次性播放后淡出。
class _ExpandGlowWidget extends StatefulWidget {
  final Size screenSize;

  const _ExpandGlowWidget({required this.screenSize});

  @override
  State<_ExpandGlowWidget> createState() => _ExpandGlowWidgetState();
}

class _ExpandGlowWidgetState extends State<_ExpandGlowWidget>
    with TickerProviderStateMixin {
  late AnimationController _expandController;
  late Animation<double> _expandCurved;
  late AnimationController _fadeController;
  late Animation<double> _fadeCurved;

  @override
  void initState() {
    super.initState();
    // 扩散：600ms，easeOut
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _expandCurved = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOut,
    );
    // 淡出：900ms，结尾极慢
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: 0.0,
    );
    _fadeCurved = CurvedAnimation(
      parent: _fadeController,
      curve: const Cubic(0.25, 0.1, 0.25, 0.6),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _expandController.forward().then((_) {
        if (mounted) _fadeController.forward();
      });
    });
  }

  @override
  void dispose() {
    _expandController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_expandCurved, _fadeCurved]),
      builder: (context, _) {
        final fade = 1.0 - _fadeCurved.value;
        return RepaintBoundary(
          child: CustomPaint(
            size: widget.screenSize,
            painter: _ExpandGlowPainter(
              progress: _expandCurved.value,
              fade: fade,
            ),
            isComplex: true,
            willChange: true,
          ),
        );
      },
    );
  }
}

class _ExpandGlowPainter extends CustomPainter {
  final double progress;
  final double fade;

  _ExpandGlowPainter({required this.progress, required this.fade});

  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0.01) return;

    final origin = Offset(size.width / 2, size.height);
    final maxRadius =
        math.sqrt(math.pow(size.width / 2, 2) + math.pow(size.height, 2)) * 2.0;
    final currentRadius = maxRadius * progress;
    if (currentRadius < 1) return;

    final baseAlpha = (0.6 * fade * fade).clamp(0.0, 0.6);

    // 5 个彩色光斑
    final spots = <_GlowSpot>[
      _GlowSpot(
        dx: 0,
        dy: -0.4,
        color: const Color(0xFF8B5CF6),
        scale: 0.9,
        alpha: 1.0,
      ),
      _GlowSpot(
        dx: -0.45,
        dy: -0.5,
        color: const Color(0xFF6366F1),
        scale: 0.7,
        alpha: 0.8,
      ),
      _GlowSpot(
        dx: 0.45,
        dy: -0.45,
        color: const Color(0xFFEC4899),
        scale: 0.7,
        alpha: 0.75,
      ),
      _GlowSpot(
        dx: -0.3,
        dy: -0.7,
        color: const Color(0xFF06B6D4),
        scale: 0.6,
        alpha: 0.6,
      ),
      _GlowSpot(
        dx: 0.3,
        dy: -0.65,
        color: const Color(0xFFF59E0B),
        scale: 0.55,
        alpha: 0.5,
      ),
    ];

    for (final spot in spots) {
      final spotRadius = currentRadius * spot.scale;
      final center = Offset(
        origin.dx + currentRadius * spot.dx,
        origin.dy + currentRadius * spot.dy,
      );
      final alpha = baseAlpha * spot.alpha;
      final spotRect = Rect.fromCircle(center: center, radius: spotRadius);

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            spot.color.withValues(alpha: alpha),
            spot.color.withValues(alpha: alpha * 0.65),
            spot.color.withValues(alpha: alpha * 0.25),
            spot.color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.3, 0.65, 1.0],
        ).createShader(spotRect);
      canvas.drawCircle(center, spotRadius, paint);
    }

    // 左右白色高亮边扫描
    if (progress > 0.05) {
      final edgeAlpha = (0.95 * fade * fade).clamp(0.0, 0.95);
      final sweepY = size.height * (1.3 - progress * 2.0);
      final edgeH = size.height * 0.6;
      final edgeW = size.width * 0.06;

      // 左侧
      final leftRect = Rect.fromLTWH(
        -edgeW * 0.5,
        sweepY - edgeH / 2,
        edgeW,
        edgeH,
      );
      final leftPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color.fromRGBO(255, 255, 255, edgeAlpha),
            Color.fromRGBO(255, 255, 255, edgeAlpha * 0.5),
            const Color(0x00FFFFFF),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(leftRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRect(leftRect, leftPaint);

      // 右侧
      final rightRect = Rect.fromLTWH(
        size.width - edgeW * 0.5,
        sweepY - edgeH / 2,
        edgeW,
        edgeH,
      );
      final rightPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            Color.fromRGBO(255, 255, 255, edgeAlpha),
            Color.fromRGBO(255, 255, 255, edgeAlpha * 0.5),
            const Color(0x00FFFFFF),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(rightRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRect(rightRect, rightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ExpandGlowPainter old) {
    return progress != old.progress || fade != old.fade;
  }
}

class _GlowSpot {
  final double dx;
  final double dy;
  final Color color;
  final double scale;
  final double alpha;

  const _GlowSpot({
    required this.dx,
    required this.dy,
    required this.color,
    required this.scale,
    required this.alpha,
  });
}

// =============================================================================
// 五、声波动画条 — _SoundWaveBars
// =============================================================================

class _SoundWaveBars extends StatefulWidget {
  final double soundLevel;
  final Color color;

  const _SoundWaveBars({
    super.key,
    required this.soundLevel,
    required this.color,
  });

  @override
  State<_SoundWaveBars> createState() => _SoundWaveBarsState();
}

class _SoundWaveBarsState extends State<_SoundWaveBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(20, 20),
          painter: _WaveBarsPainter(
            pulseValue: _pulseController.value,
            soundLevel: widget.soundLevel,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _WaveBarsPainter extends CustomPainter {
  final double pulseValue;
  final double soundLevel;
  final Color color;

  _WaveBarsPainter({
    required this.pulseValue,
    required this.soundLevel,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const barCount = 5;
    const barWidth = 2.4;
    const gap = 1.6;
    const totalWidth = barCount * barWidth + (barCount - 1) * gap;
    final startX = cx - totalWidth / 2 + barWidth / 2;

    const baseHeights = [0.3, 0.6, 1.0, 0.6, 0.3];
    const phaseOffsets = [0.0, 0.2, 0.4, 0.6, 0.8];

    final maxBarH = size.height * 0.7;
    const minBarH = 3.0;

    for (int i = 0; i < barCount; i++) {
      final x = startX + i * (barWidth + gap);
      final phase = (pulseValue + phaseOffsets[i]) % 1.0;
      final pulse = 0.5 + 0.5 * math.sin(phase * math.pi * 2);
      final level = soundLevel * 0.7 + pulse * 0.3;
      final h = (minBarH + (maxBarH - minBarH) * baseHeights[i] * level).clamp(
        minBarH,
        maxBarH,
      );

      final barRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, cy), width: barWidth, height: h),
        const Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(barRect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveBarsPainter old) => true;
}

// =============================================================================
// 六、柔和回弹曲线 — _SoftBounceCurve
// =============================================================================

/// 轻微超出后平滑回到终点，有漂浮感的弹簧曲线。
class _SoftBounceCurve extends Curve {
  const _SoftBounceCurve();

  @override
  double transformInternal(double t) {
    if (t >= 1.0) return 1.0;
    if (t <= 0.0) return 0.0;
    final decay = math.exp(-6.0 * t);
    final raw = 1.0 - decay * math.cos(t * math.pi * 1.6);
    if (t > 0.9) {
      final blend = (t - 0.9) / 0.1;
      return raw * (1.0 - blend) + blend;
    }
    return raw;
  }
}
