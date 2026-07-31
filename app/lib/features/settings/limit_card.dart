import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/config_models.dart';
import 'config_controller.dart';

/// One limit key: a slider + numeric field with instant apply, a dirty dot
/// while the field diverges from the last-committed value, and an Undo
/// action on the confirmation snackbar.
class LimitCard extends ConsumerStatefulWidget {
  const LimitCard({super.key, required this.schema, required this.committedValue});

  final ConfigKeySchema schema;
  final int committedValue;

  @override
  ConsumerState<LimitCard> createState() => _LimitCardState();
}

class _LimitCardState extends ConsumerState<LimitCard> {
  late double _sliderValue;
  late final TextEditingController _textController;
  bool _dirty = false;
  bool _applying = false;

  int get _min => widget.schema.min ?? 0;

  @override
  void initState() {
    super.initState();
    _sliderValue = widget.committedValue.toDouble();
    _textController = TextEditingController(text: widget.committedValue.toString());
  }

  @override
  void didUpdateWidget(covariant LimitCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only follow external updates while the user isn't mid-edit, so a
    // config.changed echo doesn't yank the field out from under them.
    if (!_dirty && !_applying && widget.committedValue != oldWidget.committedValue) {
      _sliderValue = widget.committedValue.toDouble();
      _textController.text = widget.committedValue.toString();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  double get _sliderMax {
    final defaultValue = widget.schema.defaultValue;
    final defaultInt = defaultValue is int ? defaultValue : 100;
    final candidates = [_sliderValue, widget.committedValue.toDouble(), (defaultInt * 3).toDouble(), 10.0];
    return candidates.reduce((a, b) => a > b ? a : b);
  }

  Future<void> _apply(int value) async {
    if (value < _min) {
      _revert('${widget.schema.name} must be >= $_min');
      return;
    }
    final previous = widget.committedValue;
    if (value == previous) {
      setState(() => _dirty = false);
      return;
    }

    setState(() => _applying = true);
    try {
      await ref.read(configControllerProvider.notifier).applyLimit(widget.schema.name, value);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _applying = false;
      });
      AppSnackBar.show(
        context,
        '${widget.schema.name} set to $value',
        action: SnackBarAction(label: 'Undo', onPressed: () => _apply(previous)),
      );
    } on DioException catch (e) {
      _revert(_errorMessage(e));
    }
  }

  void _revert(String message) {
    if (!mounted) return;
    setState(() {
      _sliderValue = widget.committedValue.toDouble();
      _textController.text = widget.committedValue.toString();
      _dirty = false;
      _applying = false;
    });
    AppSnackBar.show(context, message, isError: true);
  }

  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is Map && data['detail']['errors'] is List) {
      return (data['detail']['errors'] as List).join(', ');
    }
    return 'Failed to update ${widget.schema.name}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sliderMax = _sliderMax;
    final range = (sliderMax - _min).round();

    return SizedBox(
      width: 340,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(widget.schema.name, style: theme.textTheme.titleMedium),
                  if (_dirty || _applying) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                  const Spacer(),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: _textController,
                      textAlign: TextAlign.end,
                      keyboardType: TextInputType.number,
                      enabled: !_applying,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                      onChanged: (_) => setState(() => _dirty = true),
                      onSubmitted: (text) {
                        final parsed = int.tryParse(text.trim());
                        if (parsed == null) {
                          _revert('Enter a whole number');
                          return;
                        }
                        setState(() => _sliderValue = parsed.toDouble());
                        _apply(parsed);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.schema.help,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Slider(
                value: _sliderValue.clamp(_min.toDouble(), sliderMax),
                min: _min.toDouble(),
                max: sliderMax,
                divisions: range > 0 ? (range > 200 ? 200 : range) : null,
                label: _sliderValue.round().toString(),
                onChanged: _applying
                    ? null
                    : (v) => setState(() {
                        _sliderValue = v;
                        _textController.text = v.round().toString();
                        _dirty = true;
                      }),
                onChangeEnd: (v) => _apply(v.round()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
