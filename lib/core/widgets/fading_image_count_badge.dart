import 'dart:async';
import 'package:flutter/material.dart';

class FadingImageCountText extends StatefulWidget {
  final int currentIndex;
  final int totalCount;
  final Duration autoHideDuration;
  final TextStyle? style;

  const FadingImageCountText({
    super.key,
    required this.currentIndex,
    required this.totalCount,
    this.autoHideDuration = const Duration(milliseconds: 2500),
    this.style,
  });

  @override
  State<FadingImageCountText> createState() => FadingImageCountTextState();
}

class FadingImageCountTextState extends State<FadingImageCountText> {
  bool _isVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant FadingImageCountText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.totalCount != widget.totalCount) {
      showAndResetTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.autoHideDuration, () {
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
      }
    });
  }

  void showAndResetTimer() {
    if (!_isVisible && mounted) {
      setState(() {
        _isVisible = true;
      });
    }
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalCount <= 1) {
      return const SizedBox.shrink();
    }

    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      child: Text(
        '${widget.currentIndex + 1}/${widget.totalCount}',
        style: widget.style ??
            const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              shadows: [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 6,
                  offset: Offset(0, 1),
                ),
              ],
            ),
      ),
    );
  }
}

class FadingImageCountBadge extends StatefulWidget {
  final int currentIndex;
  final int totalCount;
  final Widget child;
  final Duration autoHideDuration;
  final Alignment alignment;

  const FadingImageCountBadge({
    super.key,
    required this.currentIndex,
    required this.totalCount,
    required this.child,
    this.autoHideDuration = const Duration(milliseconds: 2500),
    this.alignment = Alignment.topRight,
  });

  @override
  State<FadingImageCountBadge> createState() => _FadingImageCountBadgeState();
}

class _FadingImageCountBadgeState extends State<FadingImageCountBadge> {
  bool _isVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant FadingImageCountBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.totalCount != widget.totalCount) {
      _showAndResetTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.autoHideDuration, () {
      if (mounted) {
        setState(() {
          _isVisible = false;
        });
      }
    });
  }

  void _showAndResetTimer() {
    if (!_isVisible && mounted) {
      setState(() {
        _isVisible = true;
      });
    }
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalCount <= 1) {
      return widget.child;
    }

    final isTop = widget.alignment == Alignment.topRight ||
        widget.alignment == Alignment.topLeft;
    final isRight = widget.alignment == Alignment.topRight ||
        widget.alignment == Alignment.bottomRight;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => _showAndResetTimer(),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned(
            top: isTop ? 16 : null,
            bottom: !isTop ? 16 : null,
            right: isRight ? 16 : null,
            left: !isRight ? 16 : null,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _isVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                child: Text(
                  '${widget.currentIndex + 1}/${widget.totalCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
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
