import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Calls [onSize] with the size of [child] after each layout that changes it (after the frame, so that the callback
/// may set state)
class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({super.key, required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderSizeReporter).onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _reported) {
      final reported = _reported = size;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (attached) {
          onSize(reported);
        }
      });
    }
  }
}
