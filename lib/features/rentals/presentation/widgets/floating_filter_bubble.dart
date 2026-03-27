import 'package:flutter/material.dart';

/// A WhatsApp-style floating info bubble that appears at the top
/// Shows a hint message and can be dismissed
class FloatingFilterBubble extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final bool isVisible;

  const FloatingFilterBubble({
    super.key,
    required this.onTap,
    this.onDismiss,
    this.isVisible = true,
  });

  @override
  State<FloatingFilterBubble> createState() => _FloatingFilterBubbleState();
}

class _FloatingFilterBubbleState extends State<FloatingFilterBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (widget.isVisible) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(FloatingFilterBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_fadeAnimation.value == 0) {
          return const SizedBox.shrink();
        }

        return SlideTransition(
          position: _slideAnimation,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            ),
          ),
        );
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            // WhatsApp-style subtle background
            color: isDark 
                ? const Color(0xFF1F2C34) // WhatsApp dark bubble
                : const Color(0xFFE7F8F3), // WhatsApp light green tint
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lock/Filter icon like WhatsApp encryption icon
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF00A884).withOpacity(0.2)
                      : const Color(0xFF00A884).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.filter_list_rounded,
                  size: 14,
                  color: isDark 
                      ? const Color(0xFF00A884)
                      : const Color(0xFF008069),
                ),
              ),
              const SizedBox(width: 8),
              // Message text
              Flexible(
                child: Text(
                  'Tap to filter by location, price & type',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark 
                        ? Colors.white.withOpacity(0.85)
                        : const Color(0xFF1B4332),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Dismiss X button
              if (widget.onDismiss != null)
                GestureDetector(
                  onTap: widget.onDismiss,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: isDark 
                          ? Colors.white.withOpacity(0.5)
                          : const Color(0xFF1B4332).withOpacity(0.5),
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

/// A scroll-aware wrapper that shows/hides the filter bubble based on scroll direction
class ScrollAwareFilterBubble extends StatefulWidget {
  final ScrollController scrollController;
  final VoidCallback onFilterTap;
  final bool initiallyVisible;
  final bool filterApplied;

  const ScrollAwareFilterBubble({
    super.key,
    required this.scrollController,
    required this.onFilterTap,
    this.initiallyVisible = true,
    this.filterApplied = false,
  });

  @override
  State<ScrollAwareFilterBubble> createState() => _ScrollAwareFilterBubbleState();
}

class _ScrollAwareFilterBubbleState extends State<ScrollAwareFilterBubble> {
  bool _isVisible = true;
  double _lastScrollPosition = 0;
  bool _userDismissed = false;

  @override
  void initState() {
    super.initState();
    _isVisible = widget.initiallyVisible;
    // Add listener after frame to ensure scroll controller is attached
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.scrollController.hasClients) {
        widget.scrollController.addListener(_onScroll);
      } else {
        // Try again when the controller gets clients
        _addListenerWhenReady();
      }
    });
  }
  
  void _addListenerWhenReady() {
    // Check periodically until scroll controller has clients
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      if (widget.scrollController.hasClients) {
        widget.scrollController.addListener(_onScroll);
      } else {
        _addListenerWhenReady();
      }
    });
  }

  @override
  void didUpdateWidget(ScrollAwareFilterBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If filter is applied, hide the bubble
    if (widget.filterApplied && !oldWidget.filterApplied) {
      setState(() => _isVisible = false);
    }
    
    // If scroll controller changed, update listener
    if (widget.scrollController != oldWidget.scrollController) {
      if (oldWidget.scrollController.hasClients) {
        oldWidget.scrollController.removeListener(_onScroll);
      }
      if (widget.scrollController.hasClients) {
        widget.scrollController.addListener(_onScroll);
      }
    }
  }

  void _onScroll() {
    if (_userDismissed || widget.filterApplied) return;
    if (!widget.scrollController.hasClients) return;

    final currentPosition = widget.scrollController.position.pixels;
    
    // Threshold for detecting scroll direction (to avoid jitter)
    const threshold = 10.0;
    
    if (currentPosition <= 0) {
      // At top, show bubble
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
    } else if (currentPosition - _lastScrollPosition > threshold) {
      // Scrolling down - hide bubble
      if (_isVisible) {
        setState(() => _isVisible = false);
      }
    } else if (_lastScrollPosition - currentPosition > threshold) {
      // Scrolling up - show bubble
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
    }
    
    _lastScrollPosition = currentPosition;
  }

  void _onDismiss() {
    setState(() {
      _userDismissed = true;
      _isVisible = false;
    });
  }

  @override
  void dispose() {
    if (widget.scrollController.hasClients) {
      widget.scrollController.removeListener(_onScroll);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_userDismissed || widget.filterApplied) {
      return const SizedBox.shrink();
    }

    return FloatingFilterBubble(
      isVisible: _isVisible,
      onTap: widget.onFilterTap,
      onDismiss: _onDismiss,
    );
  }
}
