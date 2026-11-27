import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme_colors.dart';

/// A frosted glass popup-based selector that matches TextFormField height (46px),
/// opening an elevated glassmorphic dialog popup instead of a native menu.
class PopupSelectField extends FormField<String> {
  final String label;
  final String? selectedValue;
  final List<String> items;
  final ValueChanged<String> onSelected;
  final String placeholder;
  final bool enableSearch;

  PopupSelectField({
    super.key,
    required this.label,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    this.placeholder = 'Select',
    this.enableSearch = false,
    super.validator,
  }) : super(
          initialValue: selectedValue,
          builder: (FormFieldState<String> state) {
            final context = state.context;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final colors = AppThemeColors.of(context);
            final hasValue = selectedValue != null && selectedValue.isNotEmpty;
            final displayValue = hasValue ? selectedValue : placeholder;

            final Color textColor = hasValue
                ? colors.textPrimary
                : (isDark ? const Color(0xFF8E9AC2) : const Color(0xFF94A3B8));

            return InkWell(
              onTap: () async {
                final chosen = await showDialog<String>(
                  context: context,
                  builder: (ctx) => _SelectPopupDialog(
                    title: label,
                    items: items,
                    selectedItem: selectedValue,
                    enableSearch: enableSearch || items.length > 5,
                  ),
                );

                if (chosen != null) {
                  state.didChange(chosen);
                  onSelected(chosen);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colors.inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: state.hasError
                        ? const Color(0xFFEF4444)
                        : (hasValue
                            ? colors.purpleAccent.withValues(alpha: isDark ? 0.55 : 0.38)
                            : colors.inputBorder),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 20,
                      color: isDark ? colors.purpleAccent : const Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            );
          },
        );

  @override
  FormFieldState<String> createState() => _PopupSelectFieldState();
}

class _PopupSelectFieldState extends FormFieldState<String> {
  @override
  PopupSelectField get widget => super.widget as PopupSelectField;

  @override
  void didUpdateWidget(PopupSelectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue) {
      setValue(widget.selectedValue);
    }
  }
}

class _SelectPopupDialog extends StatefulWidget {
  final String title;
  final List<String> items;
  final String? selectedItem;
  final bool enableSearch;

  const _SelectPopupDialog({
    required this.title,
    required this.items,
    required this.selectedItem,
    required this.enableSearch,
  });

  @override
  State<_SelectPopupDialog> createState() => _SelectPopupDialogState();
}

class _SelectPopupDialogState extends State<_SelectPopupDialog> {
  final TextEditingController _searchController = TextEditingController();
  late List<String> _filteredItems;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items.where((item) => item.toLowerCase().contains(query)).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppThemeColors.of(context);
    final primaryAccent = colors.primaryGradStart;
    final dividerColor = isDark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFE2E8F0);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : const Color(0xFF6366F1)).withValues(alpha: isDark ? 0.5 : 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xEB1D254D), const Color(0xE0111634)]
                      : [const Color(0xF5FFFFFF), const Color(0xEBFAF5FF)],
                ),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.white,
                  width: 1.3,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            gradient: colors.primaryGradient,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: primaryAccent.withValues(alpha: 0.30),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.list_alt_rounded, size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Select ${widget.title}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, size: 20, color: colors.textSecondary),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  if (widget.enableSearch)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(fontSize: 13, color: colors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Search options...',
                            hintStyle: TextStyle(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF8E9AC2) : const Color(0xFF94A3B8),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: isDark ? const Color(0xFF8E9AC2) : const Color(0xFF94A3B8),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            fillColor: colors.inputBg,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: colors.inputBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: colors.inputBorder),
                            ),
                          ),
                        ),
                      ),
                    ),

                  Divider(height: 12, thickness: 1, color: dividerColor),

                  Flexible(
                    child: _filteredItems.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Center(
                              child: Text(
                                'No matching options',
                                style: TextStyle(color: colors.textSecondary, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            itemCount: _filteredItems.length,
                            itemBuilder: (ctx, index) {
                              final item = _filteredItems[index];
                              final isSelected = item == widget.selectedItem;

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: isSelected
                                      ? LinearGradient(
                                          colors: [
                                            colors.primaryGradStart.withValues(alpha: 0.16),
                                            colors.primaryGradEnd.withValues(alpha: 0.12),
                                          ],
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isSelected
                                      ? Border.all(
                                          color: colors.primaryGradStart.withValues(alpha: 0.35),
                                          width: 1.0,
                                        )
                                      : null,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: ListTile(
                                    dense: true,
                                    visualDensity: const VisualDensity(vertical: -2),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    title: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected ? colors.primaryGradStart : colors.textPrimary,
                                      ),
                                    ),
                                    trailing: isSelected
                                        ? Icon(Icons.check_circle_rounded, color: colors.primaryGradStart, size: 18)
                                        : null,
                                    onTap: () => Navigator.of(context).pop(item),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
