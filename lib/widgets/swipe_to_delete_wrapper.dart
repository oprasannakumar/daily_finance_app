import 'package:flutter/material.dart';

/// A rounded swipe-to-delete wrapper matching the partial-reveal + full-swipe
/// delete interaction. Clips the crimson `DELETE` background to [borderRadius].
class SwipeToDeleteWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onDelete;
  final Future<bool> Function()? confirmDelete;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry margin;
  final bool enabled;
  final BoxBorder? border;

  const SwipeToDeleteWrapper({
    super.key,
    required this.child,
    required this.onDelete,
    this.confirmDelete,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.margin = EdgeInsets.zero,
    this.enabled = true,
    this.border,
  });

  @override
  State<SwipeToDeleteWrapper> createState() => _SwipeToDeleteWrapperState();
}

class _SwipeToDeleteWrapperState extends State<SwipeToDeleteWrapper>
    with SingleTickerProviderStateMixin {
  static const double _revealWidth = 104.0;

  late final AnimationController _controller;
  double _dragOffset = 0.0;
  double _animStart = 0.0;
  double _animEnd = 0.0;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
        setState(() {
          _dragOffset = _animStart +
              (_animEnd - _animStart) *
                  Curves.easeOutCubic.transform(_controller.value);
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _animStart = _dragOffset;
    _animEnd = target;
    _controller.forward(from: 0.0);
  }

  Future<void> _triggerDelete() async {
    if (_isDeleting) return;
    if (widget.confirmDelete != null) {
      final ok = await widget.confirmDelete!();
      if (!mounted) return;
      if (!ok) {
        _animateTo(0.0);
        return;
      }
    }
    _isDeleting = true;
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Padding(
        padding: widget.margin,
        child: widget.child,
      );
    }

    return Padding(
      padding: widget.margin,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;

          return ClipRRect(
            borderRadius: widget.borderRadius,
            child: Stack(
              children: [
                if (_dragOffset < -0.5)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _dragOffset < -20 ? _triggerDelete : null,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'DELETE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 0.7,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _dragOffset < -10 ? () => _animateTo(0.0) : null,
                  onHorizontalDragStart: (_) => _controller.stop(),
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragOffset =
                          (_dragOffset + details.delta.dx).clamp(-maxWidth, 0.0);
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    final vx = details.primaryVelocity ?? 0.0;
                    if (_dragOffset <= -maxWidth * 0.55 || vx < -900) {
                      _animateTo(-maxWidth);
                      _triggerDelete();
                    } else if (_dragOffset <= -42 || vx < -250) {
                      _animateTo(-_revealWidth);
                    } else {
                      _animateTo(0.0);
                    }
                  },
                  child: Transform.translate(
                    offset: Offset(_dragOffset, 0),
                    child: widget.child,
                  ),
                ),
                if (widget.border != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: widget.borderRadius,
                          border: widget.border,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
