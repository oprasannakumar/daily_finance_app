import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/account_balance_model.dart';
import '../services/google_auth_service.dart';
import '../services/quick_nav_controller.dart';
import '../services/storage_service.dart';
import '../theme/app_theme_colors.dart';
import '../utils/currency_formatter.dart';
import '../widgets/glass_surface.dart';
import '../widgets/theme_toggle_button.dart';

/// Unified command center hub grouping analytics, invoices, EMIs, masters,
/// templates, cloud sync, and AI configuration into a modern Bento grid.
class WorkspaceHubScreen extends StatefulWidget {
  final double bottomContentPadding;
  final ValueChanged<String>? onNavigateTool;

  const WorkspaceHubScreen({
    super.key,
    this.bottomContentPadding = 0.0,
    this.onNavigateTool,
  });

  @override
  State<WorkspaceHubScreen> createState() => _WorkspaceHubScreenState();
}

class _WorkspaceHubScreenState extends State<WorkspaceHubScreen> {
  final StorageService _storage = StorageService.instance;

  LiveAccountBalanceSummary? _balances;
  int _pendingSyncCount = 0;
  int _activeEmiCount = 0;
  int _templateCount = 0;
  int _recurringCount = 0;
  int _invoiceCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOverview();
    _storage.transactionsNotifier.addListener(_loadOverview);
    _storage.balanceConfigNotifier.addListener(_loadOverview);
    _storage.emiPlansNotifier.addListener(_loadOverview);
  }

  @override
  void dispose() {
    _storage.transactionsNotifier.removeListener(_loadOverview);
    _storage.balanceConfigNotifier.removeListener(_loadOverview);
    _storage.emiPlansNotifier.removeListener(_loadOverview);
    super.dispose();
  }

  Future<void> _loadOverview() async {
    try {
      final results = await Future.wait<dynamic>([
        _storage.getLiveAccountBalances(),
        _storage.getPendingSyncDetails(),
        _storage.getCachedEmiPlans(),
        _storage.getTemplates(),
        _storage.getRecurringTransactions(),
        _storage.getCachedInvoices(),
      ]);
      if (!mounted) return;
      final pending = results[1] as ({List saves, List deletes});
      final emis = results[2] as List;
      final templates = results[3] as List;
      final recurrings = results[4] as List;
      final invoices = results[5] as List;
      setState(() {
        _balances = results[0] as LiveAccountBalanceSummary;
        _pendingSyncCount = pending.saves.length + pending.deletes.length;
        _activeEmiCount = emis.where((e) => (e.status as String).toUpperCase() == 'ACTIVE').length;
        _templateCount = templates.length;
        _recurringCount = recurrings.length;
        _invoiceCount = invoices.length;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _open(String routeLabel) {
    HapticFeedback.selectionClick();
    if (widget.onNavigateTool != null) {
      widget.onNavigateTool!(routeLabel);
    } else {
      QuickNavController.instance.navigateTo(routeLabel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppThemeColors.of(context);
    final b = _balances;
    final liquidTotal = b != null
        ? (b.totalBankBalance + b.totalCashBalance + b.totalWalletBalance)
        : 0.0;
    final dueBills = b?.totalDueBillsCount ?? 0;

    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: buildGlassAppBarFlexibleSpace(context),
          title: Row(
            children: [
              GradientText(
                'Command Hub',
                gradient: LinearGradient(
                  colors: isDark
                      ? [colors.purpleAccent, colors.secondaryGradStart]
                      : [colors.heroGradStart, colors.primaryGradEnd],
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.purpleAccent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Tools & Studio',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: colors.purpleAccent,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: ThemeToggleRotatingButton(
                isDark: isDark,
                onToggle: () => _storage.toggleDarkMode(),
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadOverview,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + widget.bottomContentPadding),
            children: [
              // 1. Hero Wealth & Sync Summary Banner
              GlassContainer(
                borderRadius: BorderRadius.circular(24),
                blurSigma: 20,
                padding: const EdgeInsets.all(18),
                gradientColors: isDark
                    ? [
                        colors.heroGradStart.withValues(alpha: 0.65),
                        colors.heroGradEnd.withValues(alpha: 0.45),
                      ]
                    : [
                        const Color(0xF0FFFFFF),
                        const Color(0xE0EDE9FE),
                      ],
                borderColor: isDark
                    ? Colors.white.withValues(alpha: 0.22)
                    : colors.heroGradStart.withValues(alpha: 0.25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'LIQUID WEALTH SNAPSHOT',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: isDark ? Colors.white70 : colors.textSecondary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: (_pendingSyncCount > 0
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF10B981))
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (_pendingSyncCount > 0
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFF10B981))
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _pendingSyncCount > 0
                                    ? Icons.cloud_upload_rounded
                                    : Icons.cloud_done_rounded,
                                size: 12,
                                color: _pendingSyncCount > 0
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF10B981),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _pendingSyncCount > 0
                                    ? '$_pendingSyncCount Pending'
                                    : 'Synced',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: _pendingSyncCount > 0
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLoading
                          ? 'Loading...'
                          : '₹${IndianCurrency.formatSmart(liquidTotal)}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: isDark ? Colors.white : colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MiniHeroChip(
                          icon: Icons.account_balance_rounded,
                          label: 'Banks ₹${IndianCurrency.formatSmart(b?.totalBankBalance ?? 0)}',
                          color: colors.secondaryGradStart,
                        ),
                        const SizedBox(width: 8),
                        _MiniHeroChip(
                          icon: Icons.credit_card_rounded,
                          label: dueBills > 0 ? '$dueBills Bills Due' : 'Cards Clear',
                          color: dueBills > 0 ? const Color(0xFFF43F5E) : colors.purpleAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. Bento Workspace Grid
              Text(
                'WORKSPACES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.32,
                children: [
                  _BentoToolCard(
                    title: 'Financial Health',
                    subtitle: 'Liquidity, trends & gauges',
                    icon: Icons.analytics_rounded,
                    gradientColors: const [Color(0xFF6366F1), Color(0xFF3B82F6)],
                    onTap: () => _open('Dashboard'),
                  ),
                  _BentoToolCard(
                    title: 'Invoice Studio',
                    subtitle: '$_invoiceCount saved · OCR + AI',
                    icon: Icons.document_scanner_rounded,
                    gradientColors: const [Color(0xFFFF5C38), Color(0xFFEC4899)],
                    onTap: () => _open('Invoices'),
                  ),
                  _BentoToolCard(
                    title: 'EMI Tracker',
                    subtitle: '$_activeEmiCount active installment plans',
                    icon: Icons.credit_score_rounded,
                    gradientColors: const [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                    onTap: () => _open('EMIs'),
                  ),
                  _BentoToolCard(
                    title: 'Manage Masters',
                    subtitle: 'Categories, banks & cards',
                    icon: Icons.tune_rounded,
                    gradientColors: const [Color(0xFF00C9A7), Color(0xFF0EA5E9)],
                    onTap: () => _open('Masters'),
                  ),
                  _BentoToolCard(
                    title: 'Saved Templates',
                    subtitle: '$_templateCount quick-fill shortcuts',
                    icon: Icons.bookmarks_rounded,
                    gradientColors: const [Color(0xFFF59E0B), Color(0xFFFF5C38)],
                    onTap: () => _open('Templates'),
                  ),
                  _BentoToolCard(
                    title: 'Recurring Bills',
                    subtitle: '$_recurringCount scheduled rules',
                    icon: Icons.autorenew_rounded,
                    gradientColors: const [Color(0xFF10B981), Color(0xFF06B6D4)],
                    onTap: () => _open('Recurring'),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 3. Integrations & Settings Strip
              Text(
                'CLOUD & AI ENGINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<GoogleUserProfile?>(
                valueListenable: GoogleAuthService.instance.currentUserNotifier,
                builder: (context, gUser, _) {
                  return InkWell(
                    onTap: () => _open('Google Sheets'),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: glassTileDecoration(
                        context,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF10B981), Color(0xFF0EA5E9)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.table_chart_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Google Sheets Sync',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  gUser?.email ?? 'Tap to connect Google Account',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => _open('API Keys'),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: glassTileDecoration(
                    context,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: colors.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AI Engine & API Keys',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Configure Groq, Gemini keys & OCR models',
                              style: TextStyle(fontSize: 12, color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
                    ],
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

class _MiniHeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniHeroChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BentoToolCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _BentoToolCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppThemeColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: glassTileDecoration(
          context,
          borderRadius: BorderRadius.circular(20),
          borderColor: gradientColors.first.withValues(alpha: 0.28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: gradientColors.first.withValues(alpha: 0.32),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                Icon(Icons.arrow_outward_rounded, size: 16, color: colors.textSecondary),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
