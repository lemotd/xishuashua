import 'package:flutter/material.dart';
import '../color/app_colors.dart';
import '../services/interaction_service.dart';
import 'spring_bottom_sheet.dart';

const _c = AppColors.dark;

class CommentSheet extends StatefulWidget {
  final String assetId;

  const CommentSheet({super.key, required this.assetId});

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  late List<CommentItem> _comments;
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  static const double _inputBarHeight = 56.0;

  @override
  void initState() {
    super.initState();
    _comments = InteractionService.getComments(widget.assetId);
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    InteractionService.addComment(widget.assetId, text);
    _textController.clear();
    setState(() {
      _comments = InteractionService.getComments(widget.assetId);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Real keyboard height passed through KeyboardInset (MediaQuery
    // viewInsets are stripped by the route so the sheet body stays put).
    final keyboardHeight = KeyboardInset.of(context);
    final sheetHeight = MediaQuery.of(context).size.height * 0.6;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    // Input bar offset from the bottom of the sheet.
    // Keyboard open  → float above keyboard (relative to sheet bottom).
    // Keyboard closed → sit at sheet bottom respecting safe area.
    final inputBottom = keyboardHeight > 0 ? keyboardHeight : safeBottom;

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: sheetHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Sheet body (never moves) ──
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: _c.cardBackground,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Column(
                  children: [
                    _buildHeader(),
                    Divider(color: _c.divider, height: 1),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _focusNode.unfocus(),
                        behavior: HitTestBehavior.opaque,
                        child: _buildCommentList(safeBottom),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Input bar (only this lifts with keyboard) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: inputBottom,
              child: Container(
                decoration: BoxDecoration(
                  color: _c.cardBackground,
                  border: Border(top: BorderSide(color: _c.divider)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        style: TextStyle(color: _c.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '写评论...',
                          hintStyle: TextStyle(color: _c.textHint),
                          filled: true,
                          fillColor: _c.inputFill,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _send,
                      icon: Icon(Icons.send_rounded, color: _c.primary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: _c.textHint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '评论 (${_comments.length})',
            style: TextStyle(
              color: _c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentList(double safeBottom) {
    if (_comments.isEmpty) {
      return Center(
        child: Text('还没有评论，来说点什么吧~', style: TextStyle(color: _c.textHint)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 8, 16, _inputBarHeight + safeBottom + 8),
      itemCount: _comments.length,
      itemBuilder: (context, index) {
        final comment = _comments[_comments.length - 1 - index];
        return _CommentTile(comment: comment);
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentItem comment;

  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(comment.time);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _c.avatarBg,
            child: Icon(Icons.person, size: 18, color: _c.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '我',
                      style: TextStyle(
                        color: _c.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeStr,
                      style: TextStyle(color: _c.textHint, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.text,
                  style: TextStyle(color: _c.textPrimary, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${t.month}/${t.day}';
  }
}
