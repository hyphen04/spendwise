import 'package:flutter/material.dart';
import '../app/themes/app_fonts.dart';

class SwipeActionButton extends StatefulWidget {
  const SwipeActionButton({
    super.key,
    required this.onAction,
    required this.label,
    required this.color,
    required this.enabled,
  });

  final VoidCallback onAction;
  final String label;
  final Color color;
  final bool enabled;

  @override
  State<SwipeActionButton> createState() => _SwipeActionButtonState();
}

class _SwipeActionButtonState extends State<SwipeActionButton> {
  double _position = 0;
  bool _isSettled = false;

  @override
  void didUpdateWidget(SwipeActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _position > 0) {
      _position = 0;
      _isSettled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        const thumbWidth = 56.0;
        final maxPosition = trackWidth - thumbWidth - 8;

        return Opacity(
          opacity: widget.enabled ? 1.0 : 0.5,
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 48),
                    child: Text(
                      widget.label,
                      style: plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: widget.color,
                      ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: _position == 0 || _isSettled ? const Duration(milliseconds: 250) : Duration.zero,
                  curve: Curves.easeOutBack,
                  left: _position,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      if (!widget.enabled || _isSettled) return;
                      setState(() {
                        _position += details.delta.dx;
                        if (_position < 0) _position = 0;
                        if (_position > maxPosition) _position = maxPosition;
                      });
                    },
                    onPanEnd: (details) {
                      if (!widget.enabled || _isSettled) return;
                      if (_position > maxPosition * 0.75) {
                        setState(() {
                          _position = maxPosition;
                          _isSettled = true;
                        });
                        widget.onAction();
                      } else {
                        setState(() => _position = 0);
                      }
                    },
                    child: Container(
                      width: thumbWidth,
                      height: 56,
                      decoration: BoxDecoration(
                        color: widget.color,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.double_arrow_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
