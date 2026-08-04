// COMPONENTS.md §6 — fields.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/tokens.dart';

/// The one text field. `inputDecorationTheme` (`build_theme.dart`) already
/// carries the fill/border/focus treatment, so this only ever needs to
/// choose which affordances (label, hint, icons) a given field wants.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
  });

  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        labelText: label,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: tokens.space.iconSm),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

/// Replaces three near-identical inline `TextField`s (`library_rail.dart:87`,
/// `insights_page.dart:270`, the queue tab) — adds what all three lack: a
/// clear button, a debounce so every keystroke doesn't refilter, and `Esc`
/// to clear.
class SearchField extends StatefulWidget {
  const SearchField({super.key, this.hint = 'Search', required this.onChanged, this.autofocus = false, this.debounce = const Duration(milliseconds: 250)});

  final String hint;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final Duration debounce;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () => widget.onChanged(value));
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    widget.onChanged('');
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clear},
      child: AppTextField(
        controller: _controller,
        hint: widget.hint,
        autofocus: widget.autofocus,
        onChanged: (value) {
          _onChanged(value);
          setState(() {});
        },
        prefixIcon: Icons.search,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, size: tokens.space.iconSm),
                onPressed: _clear,
                visualDensity: VisualDensity.compact,
              ),
      ),
    );
  }
}

class AppOption<T> {
  const AppOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// A themed dropdown — `menuTheme`/`dropdownMenuTheme` already carry the
/// overlay's surface, so this only ever picks the option list.
class AppSelect<T> extends StatelessWidget {
  const AppSelect({super.key, required this.value, required this.options, required this.onChanged, this.label});

  final T value;
  final List<AppOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return DropdownMenu<T>(
      initialSelection: value,
      label: label == null ? null : Text(label!),
      textStyle: Theme.of(context).textTheme.bodyMedium,
      onSelected: (selected) {
        if (selected != null) onChanged(selected);
      },
      dropdownMenuEntries: [
        for (final option in options)
          DropdownMenuEntry<T>(
            value: option.value,
            label: option.label,
            leadingIcon: option.icon == null ? null : Icon(option.icon, size: tokens.space.iconSm),
          ),
      ],
    );
  }
}

/// Folds in `core/flow_switch_confirm.dart`'s existing confirm-before-toggle
/// rule so it can't be forgotten on a new switch — only prompts when turning
/// **off**, matching that file's own rule (turning something on needs no
/// confirmation).
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, this.onChanged, this.confirmMessage});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? confirmMessage;

  Future<void> _handle(BuildContext context, bool next) async {
    if (!next && confirmMessage != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Turn this off?'),
          content: Text(confirmMessage!),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Turn off')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) => Switch(value: value, onChanged: onChanged == null ? null : (next) => _handle(context, next));
}
