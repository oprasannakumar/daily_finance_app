import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme_colors.dart';
import 'glass_surface.dart';

class SwipeableDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const SwipeableDatePickerDialog({
    super.key,
    required this.initialDate,
    this.firstDate,
    this.lastDate,
  });

  static Future<DateTime?> show({
    required BuildContext context,
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) {
    return showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      builder: (context) => SwipeableDatePickerDialog(
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
  }

  @override
  State<SwipeableDatePickerDialog> createState() => _SwipeableDatePickerDialogState();
}

class _SwipeableDatePickerDialogState extends State<SwipeableDatePickerDialog> {
  late DateTime _selectedDate;
  late DateTime _displayMonth;
  bool _isYearPickerMode = false;
  double _slideDirection = 1.0;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _displayMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
  }

  void _goToPreviousMonth() {
    setState(() {
      _slideDirection = -1.0;
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1, 1);
    });
  }

  void _goToNextMonth() {
    setState(() {
      _slideDirection = 1.0;
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 1);
    });
  }

  void _goToPreviousYear() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year - 1, _displayMonth.month, 1);
    });
  }

  void _goToNextYear() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year + 1, _displayMonth.month, 1);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    Navigator.of(context).pop(now);
  }

  // Handle Swipe Gesture
  void _handleDragEnd(DragEndDetails details) {
    final vx = details.primaryVelocity ?? 0.0;
    // Horizontal swipe for months
    if (vx.abs() > 200) {
      if (vx < 0) {
        // Swiped Left -> Next Month
        _goToNextMonth();
      } else {
        // Swiped Right -> Previous Month
        _goToPreviousMonth();
      }
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final vy = details.primaryVelocity ?? 0.0;
    // Vertical swipe for years
    if (vy.abs() > 200) {
      if (vy < 0) {
        // Swiped Up -> Next Year
        _goToNextYear();
      } else {
        // Swiped Down -> Previous Year
        _goToPreviousYear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = AppThemeColors.of(context);
    final formattedSelected = DateFormat('dd/MMM/yyyy').format(_selectedDate);
    final weekdayName = DateFormat('EEEE').format(_selectedDate);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(24),
          blurSigma: 22,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: colors.primaryGradient,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          weekdayName.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        InkWell(
                          onTap: _goToToday,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.today, size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Today',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formattedSelected,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Controls Bar: Month, Year, and Navigation Buttons
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: colors.inputBg.withValues(alpha: 0.55),
              child: Row(
                children: [
                  // Fast Year Jump Back
                  IconButton(
                    icon: const Icon(Icons.keyboard_double_arrow_left, size: 20),
                    tooltip: 'Previous Year (Swipe Down)',
                    onPressed: _goToPreviousYear,
                    visualDensity: VisualDensity.compact,
                  ),
                  // Month Jump Back
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 22),
                    tooltip: 'Previous Month (Swipe Right)',
                    onPressed: _goToPreviousMonth,
                    visualDensity: VisualDensity.compact,
                  ),

                  // Month & Year title (clickable to toggle year grid)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          _isYearPickerMode = !_isYearPickerMode;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('MMMM yyyy').format(_displayMonth),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _isYearPickerMode
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                              color: colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Month Jump Forward
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 22),
                    tooltip: 'Next Month (Swipe Left)',
                    onPressed: _goToNextMonth,
                    visualDensity: VisualDensity.compact,
                  ),
                  // Fast Year Jump Forward
                  IconButton(
                    icon: const Icon(Icons.keyboard_double_arrow_right, size: 20),
                    tooltip: 'Next Year (Swipe Up)',
                    onPressed: _goToNextYear,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Calendar Body or Year Picker Body with Gestures
            GestureDetector(
              onHorizontalDragEnd: _handleDragEnd,
              onVerticalDragEnd: _handleVerticalDragEnd,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 290,
                child: _isYearPickerMode
                    ? _buildYearPicker(colorScheme)
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return ClipRect(
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: Offset(_slideDirection, 0.0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey('cal_${_displayMonth.year}_${_displayMonth.month}'),
                          child: _buildCalendarGrid(colorScheme),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(ColorScheme colorScheme) {
    final daysInMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_displayMonth.year, _displayMonth.month, 1).weekday; // 1 = Mon, 7 = Sun
    final offset = (firstWeekday - 1); // 0 for Mon ... 6 for Sun

    const weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          // Weekday Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((w) {
              final isWeekend = (w == 'Sa' || w == 'Su');
              return SizedBox(
                width: 38,
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isWeekend ? Colors.redAccent : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          // Days grid
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.1,
              ),
              itemCount: 42, // 6 weeks
              itemBuilder: (context, index) {
                final dayNumber = index - offset + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }

                final currentDate = DateTime(_displayMonth.year, _displayMonth.month, dayNumber);
                final isSelected = _selectedDate.year == currentDate.year &&
                    _selectedDate.month == currentDate.month &&
                    _selectedDate.day == currentDate.day;
                final isToday = now.year == currentDate.year &&
                    now.month == currentDate.month &&
                    now.day == currentDate.day;

                return InkWell(
                  onTap: () {
                    // Just tapping on the date is enough!
                    Navigator.of(context).pop(currentDate);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? colorScheme.primary : Colors.transparent,
                      border: isToday && !isSelected
                          ? Border.all(color: colorScheme.primary, width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : (isToday ? colorScheme.primary : colorScheme.onSurface),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearPicker(ColorScheme colorScheme) {
    final currentYear = _displayMonth.year;
    final startYear = currentYear - 15;
    final years = List.generate(31, (i) => startYear + i);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: years.length,
      itemBuilder: (context, index) {
        final year = years[index];
        final isSelected = year == _displayMonth.year;
        return ListTile(
          dense: true,
          selected: isSelected,
          selectedTileColor: colorScheme.primaryContainer,
          title: Center(
            child: Text(
              '$year',
              style: TextStyle(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
              ),
            ),
          ),
          onTap: () {
            setState(() {
              _displayMonth = DateTime(year, _displayMonth.month, 1);
              _selectedDate = DateTime(year, _selectedDate.month, _selectedDate.day);
              _isYearPickerMode = false;
            });
          },
        );
      },
    );
  }
}

class DateRangePickerResult {
  final DateTime? start;
  final DateTime? end;
  final bool isAllTime;
  final String presetName;

  const DateRangePickerResult({
    this.start,
    this.end,
    this.isAllTime = false,
    this.presetName = 'Custom',
  });
}

/// A matching swipeable date range picker dialog.
/// If user selects the same date twice, selects single date.
/// If user selects two different dates, selects date range.
class SwipeableDateRangePickerDialog extends StatefulWidget {
  final DateTime initialStartDate;
  final DateTime initialEndDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? currentPreset;

  const SwipeableDateRangePickerDialog({
    super.key,
    required this.initialStartDate,
    required this.initialEndDate,
    this.firstDate,
    this.lastDate,
    this.currentPreset,
  });

  static Future<DateRangePickerResult?> show({
    required BuildContext context,
    required DateTime initialStartDate,
    required DateTime initialEndDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String? currentPreset,
  }) {
    return showDialog<DateRangePickerResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) => SwipeableDateRangePickerDialog(
        initialStartDate: initialStartDate,
        initialEndDate: initialEndDate,
        firstDate: firstDate,
        lastDate: lastDate,
        currentPreset: currentPreset,
      ),
    );
  }

  @override
  State<SwipeableDateRangePickerDialog> createState() => _SwipeableDateRangePickerDialogState();
}

class _SwipeableDateRangePickerDialogState extends State<SwipeableDateRangePickerDialog> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  late DateTime _displayMonth;
  bool _isYearPickerMode = false;
  double _slideDirection = 1.0;

  @override
  void initState() {
    super.initState();
    _rangeStart = DateTime(
      widget.initialStartDate.year,
      widget.initialStartDate.month,
      widget.initialStartDate.day,
    );
    _rangeEnd = DateTime(
      widget.initialEndDate.year,
      widget.initialEndDate.month,
      widget.initialEndDate.day,
    );
    _displayMonth = DateTime(_rangeEnd!.year, _rangeEnd!.month, 1);
  }

  void _goToPreviousMonth() {
    setState(() {
      _slideDirection = -1.0;
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1, 1);
    });
  }

  void _goToNextMonth() {
    setState(() {
      _slideDirection = 1.0;
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 1);
    });
  }

  void _goToPreviousYear() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year - 1, _displayMonth.month, 1);
    });
  }

  void _goToNextYear() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year + 1, _displayMonth.month, 1);
    });
  }

  void _goToToday() {
    _selectPreset('Today');
  }

  void _selectPreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case 'All Time':
        Navigator.of(context).pop(const DateRangePickerResult(isAllTime: true, presetName: 'All Time'));
        break;
      case 'Today':
        Navigator.of(context).pop(DateRangePickerResult(start: today, end: today, presetName: 'Today'));
        break;
      case 'Yesterday':
        final y = today.subtract(const Duration(days: 1));
        Navigator.of(context).pop(DateRangePickerResult(start: y, end: y, presetName: 'Yesterday'));
        break;
      case 'This Week':
        final mon = today.subtract(Duration(days: today.weekday - 1));
        final sun = mon.add(const Duration(days: 6));
        Navigator.of(context).pop(DateRangePickerResult(start: mon, end: sun, presetName: 'This Week'));
        break;
      case 'This Month':
        final start = DateTime(today.year, today.month, 1);
        final nextM = (today.month < 12) ? DateTime(today.year, today.month + 1, 1) : DateTime(today.year + 1, 1, 1);
        final end = nextM.subtract(const Duration(days: 1));
        Navigator.of(context).pop(DateRangePickerResult(start: start, end: end, presetName: 'This Month'));
        break;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final vx = details.primaryVelocity ?? 0.0;
    if (vx.abs() > 200) {
      if (vx < 0) {
        _goToNextMonth();
      } else {
        _goToPreviousMonth();
      }
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final vy = details.primaryVelocity ?? 0.0;
    if (vy.abs() > 200) {
      if (vy < 0) {
        _goToNextYear();
      } else {
        _goToPreviousYear();
      }
    }
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _onDateTapped(DateTime date) {
    setState(() {
      if (_rangeStart == null || (_rangeStart != null && _rangeEnd != null)) {
        // First selection of a new cycle
        _rangeStart = date;
        _rangeEnd = null;
      } else {
        // Second tap!
        if (_isSameDay(_rangeStart, date)) {
          // Selected same date 2 times -> single date!
          _rangeEnd = date;
          Navigator.of(context).pop(DateRangePickerResult(start: _rangeStart!, end: _rangeEnd!, presetName: 'Custom'));
        } else {
          // Selected two dates -> date range!
          if (date.isBefore(_rangeStart!)) {
            _rangeEnd = _rangeStart;
            _rangeStart = date;
          } else {
            _rangeEnd = date;
          }
          Navigator.of(context).pop(DateRangePickerResult(start: _rangeStart!, end: _rangeEnd!, presetName: 'Custom'));
        }
      }
    });
  }

  String _formatHeader() {
    final fmt = DateFormat('dd/MMM/yyyy');
    if (_rangeStart == null) {
      return 'Select Date';
    }
    if (_rangeEnd == null) {
      return fmt.format(_rangeStart!);
    }
    if (_isSameDay(_rangeStart, _rangeEnd)) {
      return fmt.format(_rangeStart!);
    }
    return '${fmt.format(_rangeStart!)}  ➔  ${fmt.format(_rangeEnd!)}';
  }

  String _getHeaderSubtitle() {
    if (_rangeStart != null && _rangeEnd == null) {
      return 'Tap again for 1 day, or tap 2nd date for range';
    }
    if (_rangeStart != null && _rangeEnd != null && _isSameDay(_rangeStart, _rangeEnd)) {
      return 'Single day selected';
    }
    return 'Tap a date twice for 1 day, or 2 dates for a range';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = AppThemeColors.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(24),
          blurSigma: 22,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: colors.primaryGradient,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DATE / RANGE PICKER',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        InkWell(
                          onTap: _goToToday,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.today, size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Today',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatHeader(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _getHeaderSubtitle(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Presets Selector Bar inside Flatpicker
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                color: colors.inputBg.withValues(alpha: 0.55),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All Time', 'Today', 'Yesterday', 'This Week', 'This Month'].map((preset) {
                      final isSelected = widget.currentPreset == preset;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: InkWell(
                          onTap: () => _selectPreset(preset),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: isSelected ? colors.primaryGradient : null,
                              color: isSelected ? null : colors.inputBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.transparent
                                    : colors.inputBorder,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              preset,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                ),
              ),
            ),

            // Controls Bar: Month, Year, and Navigation Buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_double_arrow_left, size: 20),
                    tooltip: 'Previous Year (Swipe Down)',
                    onPressed: _goToPreviousYear,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 22),
                    tooltip: 'Previous Month (Swipe Right)',
                    onPressed: _goToPreviousMonth,
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          _isYearPickerMode = !_isYearPickerMode;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('MMMM yyyy').format(_displayMonth),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _isYearPickerMode
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                              color: colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 22),
                    tooltip: 'Next Month (Swipe Left)',
                    onPressed: _goToNextMonth,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_double_arrow_right, size: 20),
                    tooltip: 'Next Year (Swipe Up)',
                    onPressed: _goToNextYear,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Calendar Body or Year Picker Body with Gestures
            GestureDetector(
              onHorizontalDragEnd: _handleDragEnd,
              onVerticalDragEnd: _handleVerticalDragEnd,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 290,
                child: _isYearPickerMode
                    ? _buildYearPicker(colorScheme)
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return ClipRect(
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: Offset(_slideDirection, 0.0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey('cal_${_displayMonth.year}_${_displayMonth.month}'),
                          child: _buildCalendarGrid(colorScheme),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 12),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(ColorScheme colorScheme) {
    final daysInMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_displayMonth.year, _displayMonth.month, 1).weekday;
    final offset = (firstWeekday - 1);

    const weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekdays.map((w) {
              final isWeekend = (w == 'Sa' || w == 'Su');
              return SizedBox(
                width: 38,
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isWeekend ? Colors.redAccent : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.1,
              ),
              itemCount: 42,
              itemBuilder: (context, index) {
                final dayNumber = index - offset + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }

                final currentDate = DateTime(_displayMonth.year, _displayMonth.month, dayNumber);
                final isStart = _isSameDay(_rangeStart, currentDate);
                final isEnd = _isSameDay(_rangeEnd, currentDate);
                final isInRange = _rangeStart != null &&
                    _rangeEnd != null &&
                    currentDate.isAfter(_rangeStart!) &&
                    currentDate.isBefore(_rangeEnd!);
                final isToday = now.year == currentDate.year &&
                    now.month == currentDate.month &&
                    now.day == currentDate.day;

                Color? bgColor;
                BorderRadius? borderRadius;
                if (isStart && isEnd) {
                  bgColor = colorScheme.primary;
                  borderRadius = BorderRadius.circular(20);
                } else if (isStart) {
                  bgColor = colorScheme.primary;
                  borderRadius = const BorderRadius.horizontal(left: Radius.circular(20));
                } else if (isEnd) {
                  bgColor = colorScheme.primary;
                  borderRadius = const BorderRadius.horizontal(right: Radius.circular(20));
                } else if (isInRange) {
                  bgColor = colorScheme.primary.withValues(alpha: 0.18);
                  borderRadius = BorderRadius.zero;
                }

                final isPrimarySelected = isStart || isEnd;

                return InkWell(
                  onTap: () => _onDateTapped(currentDate),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor ?? Colors.transparent,
                      borderRadius: borderRadius ?? BorderRadius.circular(20),
                      border: isToday && !isPrimarySelected && !isInRange
                          ? Border.all(color: colorScheme.primary, width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isPrimarySelected || isToday ? FontWeight.bold : FontWeight.normal,
                          color: isPrimarySelected
                              ? colorScheme.onPrimary
                              : (isInRange
                                  ? colorScheme.primary
                                  : (isToday ? colorScheme.primary : colorScheme.onSurface)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearPicker(ColorScheme colorScheme) {
    final currentYear = _displayMonth.year;
    final startYear = currentYear - 15;
    final years = List.generate(31, (i) => startYear + i);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: years.length,
      itemBuilder: (context, index) {
        final year = years[index];
        final isSelected = year == _displayMonth.year;
        return ListTile(
          dense: true,
          selected: isSelected,
          selectedTileColor: colorScheme.primaryContainer,
          title: Center(
            child: Text(
              '$year',
              style: TextStyle(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
              ),
            ),
          ),
          onTap: () {
            setState(() {
              _displayMonth = DateTime(year, _displayMonth.month, 1);
              _isYearPickerMode = false;
            });
          },
        );
      },
    );
  }
}
