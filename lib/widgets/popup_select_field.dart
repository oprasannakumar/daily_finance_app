import 'package:flutter/material.dart';

/// A sleek popup-based selector that looks identical to a TextFormField (46px height),
/// but opens an elegant dialog popup to select an option instead of a native drop-down menu.
/// Never sets a default value; displays "Select" until the user explicitly selects an option.
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
            final hasValue = selectedValue != null && selectedValue.isNotEmpty;
            final displayValue = hasValue ? selectedValue : placeholder;

            final Color fillColor = isDark ? const Color(0xFF1B2042) : Colors.white;
            final Color borderColor = isDark ? const Color(0xFF2C3360) : const Color(0xFFCBD5E1);
            final Color textColor = hasValue
                ? (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B))
                : (isDark ? const Color(0xFF8E9AC2) : const Color(0xFF94A3B8));
            final Color activeBorderColor = isDark ? const Color(0xFFA78BFA) : const Color(0xFFFF5C38);

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
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: fillColor,
                  constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor, width: 1.2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: state.hasError ? const Color(0xFFEF4444) : borderColor,
                      width: 1.2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: activeBorderColor, width: 1.8),
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 26, maxWidth: 26, maxHeight: 26),
                  suffixIcon: Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: isDark ? const Color(0xFF818CF8) : const Color(0xFF64748B),
                  ),
                ),
                child: Text(
                  displayValue,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.15,
                    fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                    color: textColor,
                  ),
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
  List<String> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items
            .where((item) => item.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF151932) : Colors.white;
    final primaryAccent = isDark ? const Color(0xFFA78BFA) : const Color(0xFFFF5C38);
    final textMain = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final borderColor = isDark ? const Color(0xFF262C54) : const Color(0xFFF1F5F9);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 6,
      backgroundColor: dialogBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
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
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.list_alt_rounded, size: 20, color: primaryAccent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Select ${widget.title}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textMain,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search bar (if enabled)
            if (widget.enableSearch)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(fontSize: 13, color: textMain),
                    decoration: InputDecoration(
                      hintText: 'Search options...',
                      hintStyle: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF8E9AC2) : const Color(0xFF94A3B8)),
                      prefixIcon: Icon(Icons.search, size: 18, color: isDark ? const Color(0xFF8E9AC2) : const Color(0xFF94A3B8)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      fillColor: isDark ? const Color(0xFF1E2242) : const Color(0xFFF8FAFC),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderColor),
                      ),
                    ),
                  ),
                ),
              ),

            Divider(height: 12, thickness: 1, color: borderColor),

            // Options list
            Flexible(
              child: _filteredItems.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          'No matching options',
                          style: TextStyle(color: isDark ? const Color(0xFF8E9AC2) : const Color(0xFF94A3B8), fontSize: 13),
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
                            color: isSelected
                                ? primaryAccent.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              visualDensity: const VisualDensity(vertical: -2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              title: Text(
                                item,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? primaryAccent : textMain,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(Icons.check_circle_rounded, color: primaryAccent, size: 18)
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
    );
  }
}
