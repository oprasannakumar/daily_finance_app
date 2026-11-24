import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/transaction_model.dart';
import '../utils/currency_formatter.dart';

class StatementFilterOptions {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? accountFilter;
  final String? purposeFilter;
  final String? spentForFilter;
  final String? flowFilter; // 'All', 'Withdraw', 'Deposit', 'Transfer'
  final String title;

  const StatementFilterOptions({
    this.startDate,
    this.endDate,
    this.accountFilter,
    this.purposeFilter,
    this.spentForFilter,
    this.flowFilter,
    this.title = 'Account Statement',
  });

  bool matches(FinanceTransaction tx) {
    if (startDate != null) {
      final start = DateTime(startDate!.year, startDate!.month, startDate!.day);
      if (tx.date.isBefore(start)) return false;
    }
    if (endDate != null) {
      final end = DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59);
      if (tx.date.isAfter(end)) return false;
    }
    if (flowFilter != null && flowFilter != 'All') {
      if (tx.flow.toLowerCase() != flowFilter!.toLowerCase()) return false;
    }
    if (purposeFilter != null && purposeFilter != 'All') {
      if (tx.purpose.toLowerCase() != purposeFilter!.toLowerCase()) return false;
    }
    if (spentForFilter != null && spentForFilter != 'All') {
      if (tx.spentFor.toLowerCase() != spentForFilter!.toLowerCase()) return false;
    }
    if (accountFilter != null && accountFilter != 'All') {
      final accLower = accountFilter!.toLowerCase();
      final hasInBreakdown = tx.breakdowns.any((b) => b.effectiveAccount.toLowerCase() == accLower);
      final hasInToBreakdown = (tx.toBreakdowns ?? []).any((b) => b.effectiveAccount.toLowerCase() == accLower);
      if (!hasInBreakdown && !hasInToBreakdown) return false;
    }
    return true;
  }
}

class StatementSummary {
  final int totalTransactions;
  final double totalInflows;
  final double totalOutflows;
  final double netCashFlow;
  final Map<String, double> purposeBreakdown;
  final Map<String, double> accountDebits;
  final Map<String, double> accountCredits;

  StatementSummary({
    required this.totalTransactions,
    required this.totalInflows,
    required this.totalOutflows,
    required this.netCashFlow,
    required this.purposeBreakdown,
    required this.accountDebits,
    required this.accountCredits,
  });

  factory StatementSummary.calculate(List<FinanceTransaction> transactions) {
    double inflows = 0.0;
    double outflows = 0.0;
    final Map<String, double> purposes = {};
    final Map<String, double> debits = {};
    final Map<String, double> credits = {};

    for (final tx in transactions) {
      final isTransfer = tx.isSelfTransfer || tx.flow.toLowerCase().contains('transfer');
      final isDeposit = tx.flow.toLowerCase().contains('deposit');

      if (isDeposit) {
        inflows += tx.totalAmount;
        for (final b in tx.breakdowns) {
          final acc = b.effectiveAccount;
          if (acc.isNotEmpty && acc != 'None') {
            credits[acc] = (credits[acc] ?? 0.0) + b.amount;
          }
        }
      } else if (!isTransfer) {
        // Withdrawal / Expense
        outflows += tx.totalAmount;
        final p = tx.purpose.trim().isEmpty ? 'General' : tx.purpose.trim();
        purposes[p] = (purposes[p] ?? 0.0) + tx.totalAmount;

        for (final b in tx.breakdowns) {
          final acc = b.effectiveAccount;
          if (acc.isNotEmpty && acc != 'None') {
            debits[acc] = (debits[acc] ?? 0.0) + b.amount;
          }
        }
      } else {
        // Self Transfer: record debits and credits
        for (final b in tx.breakdowns) {
          final acc = b.effectiveAccount;
          if (acc.isNotEmpty && acc != 'None') {
            debits[acc] = (debits[acc] ?? 0.0) + b.amount;
          }
        }
        for (final b in tx.toBreakdowns ?? []) {
          final acc = b.effectiveAccount;
          if (acc.isNotEmpty && acc != 'None') {
            credits[acc] = (credits[acc] ?? 0.0) + b.amount;
          }
        }
      }
    }

    return StatementSummary(
      totalTransactions: transactions.length,
      totalInflows: inflows,
      totalOutflows: outflows,
      netCashFlow: inflows - outflows,
      purposeBreakdown: purposes,
      accountDebits: debits,
      accountCredits: credits,
    );
  }
}

class StatementExportService {
  static final StatementExportService instance = StatementExportService._internal();
  StatementExportService._internal();

  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _timestampFormat = DateFormat('dd MMM yyyy, hh:mm a');

  /// Filters transactions based on options.
  List<FinanceTransaction> filterTransactions({
    required List<FinanceTransaction> transactions,
    required StatementFilterOptions options,
  }) {
    final filtered = transactions.where(options.matches).toList();
    filtered.sort((a, b) => b.date.compareTo(a.date)); // Newest first
    return filtered;
  }

  /// Generates CSV content formatted for Excel with UTF-8 BOM.
  String generateCsvReport({
    required List<FinanceTransaction> transactions,
    required StatementFilterOptions options,
  }) {
    final buffer = StringBuffer();
    // Prepend UTF-8 BOM so Excel opens it with correct UTF-8 encoding
    buffer.write('\uFEFF');

    // Report Header
    buffer.writeln('"DAILY FINANCE STATEMENT"');
    buffer.writeln('"Report:","${options.title}"');
    buffer.writeln('"Generated On:","${_timestampFormat.format(DateTime.now())}"');
    if (options.startDate != null || options.endDate != null) {
      final startStr = options.startDate != null ? _dateFormat.format(options.startDate!) : 'Start';
      final endStr = options.endDate != null ? _dateFormat.format(options.endDate!) : 'Present';
      buffer.writeln('"Period:","$startStr to $endStr"');
    }
    if (options.accountFilter != null && options.accountFilter != 'All') {
      buffer.writeln('"Account Filter:","${options.accountFilter}"');
    }
    if (options.purposeFilter != null && options.purposeFilter != 'All') {
      buffer.writeln('"Purpose Filter:","${options.purposeFilter}"');
    }
    buffer.writeln();

    // Summary Section
    final summary = StatementSummary.calculate(transactions);
    buffer.writeln('"SUMMARY"');
    buffer.writeln('"Total Transactions:","${summary.totalTransactions}"');
    buffer.writeln('"Total Inflow (Deposits):","Rs. ${IndianCurrency.format(summary.totalInflows)}"');
    buffer.writeln('"Total Outflow (Expenses):","Rs. ${IndianCurrency.format(summary.totalOutflows)}"');
    buffer.writeln('"Net Cash Flow:","Rs. ${IndianCurrency.format(summary.netCashFlow)}"');
    buffer.writeln();

    // Column Headers
    buffer.writeln(
      '"Date","Ref ID","Flow","Purpose","Spent For","Payment Mode","From Account","Amount (INR)","To Mode","To Account","Invoice","Narration","Split Details"',
    );

    // Data Rows
    for (final tx in transactions) {
      final dateStr = _dateFormat.format(tx.date);
      final refStr = _escapeCsv(tx.referenceId);
      final flowStr = _escapeCsv(tx.flow);
      final purposeStr = _escapeCsv(tx.purpose);
      final spentForStr = _escapeCsv(tx.spentFor);

      // From modes & accounts
      final fromModes = tx.breakdowns.map((b) => b.paymentType ?? '').where((s) => s.isNotEmpty).join(' + ');
      final fromAccs = tx.breakdowns.map((b) => b.effectiveAccount).where((s) => s.isNotEmpty).join(' + ');

      // To modes & accounts
      final toModes = (tx.toBreakdowns ?? []).map((b) => b.paymentType ?? '').where((s) => s.isNotEmpty).join(' + ');
      final toAccs = (tx.toBreakdowns ?? []).map((b) => b.effectiveAccount).where((s) => s.isNotEmpty).join(' + ');

      final amountVal = tx.totalAmount.toStringAsFixed(2);
      final invoiceStr = _escapeCsv(tx.invoice);
      final narrationStr = _escapeCsv(tx.narration);

      // Split summary
      String splitStr = '';
      if (tx.isSplitMode && tx.splitRecipients != null && tx.splitRecipients!.isNotEmpty) {
        splitStr = tx.splitRecipients!.map((s) => '${s.name}: ${s.amount}').join('; ');
      }
      final splitCsv = _escapeCsv(splitStr);

      buffer.writeln(
        '"$dateStr","$refStr","$flowStr","$purposeStr","$spentForStr","${_escapeCsv(fromModes)}","${_escapeCsv(fromAccs)}",$amountVal,"${_escapeCsv(toModes)}","${_escapeCsv(toAccs)}","$invoiceStr","$narrationStr","$splitCsv"',
      );
    }

    return buffer.toString();
  }

  /// Exports CSV and triggers device share intent.
  Future<void> exportAndShareCsv({
    required List<FinanceTransaction> transactions,
    required StatementFilterOptions options,
  }) async {
    final csvContent = generateCsvReport(transactions: transactions, options: options);
    final tempDir = await getTemporaryDirectory();
    final fileName = 'DailyFinance_Statement_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(csvContent);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: options.title,
        text: 'Daily Finance Statement (${transactions.length} records)',
      ),
    );
  }

  /// Generates a PDF statement document.
  Future<Uint8List> generatePdfReport({
    required List<FinanceTransaction> transactions,
    required StatementFilterOptions options,
  }) async {
    final pdf = pw.Document();
    final summary = StatementSummary.calculate(transactions);

    final fontRegular = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();
    final fontSemiBold = await PdfGoogleFonts.openSansSemiBold();

    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
    );

    final periodStr = (options.startDate != null || options.endDate != null)
        ? '${options.startDate != null ? _dateFormat.format(options.startDate!) : "Start"}  -  ${options.endDate != null ? _dateFormat.format(options.endDate!) : "Present"}'
        : 'All Time Records';

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'DAILY FINANCE',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 16,
                        color: PdfColor.fromHex('#4F46E5'),
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      options.title,
                      style: pw.TextStyle(
                        font: fontSemiBold,
                        fontSize: 12,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Period: $periodStr',
                      style: pw.TextStyle(font: fontSemiBold, fontSize: 9, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'Generated: ${_timestampFormat.format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Daily Finance Ledger - Confidential',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            pw.SizedBox(height: 12),
            // Financial Summary Cards
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 1),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPdfSummaryCard(
                    title: 'TOTAL INFLOW',
                    amount: 'Rs. ${IndianCurrency.format(summary.totalInflows)}',
                    color: PdfColor.fromHex('#059669'), // Green
                    fontBold: fontBold,
                  ),
                  _buildPdfSummaryDivider(),
                  _buildPdfSummaryCard(
                    title: 'TOTAL OUTFLOW',
                    amount: 'Rs. ${IndianCurrency.format(summary.totalOutflows)}',
                    color: PdfColor.fromHex('#DC2626'), // Red
                    fontBold: fontBold,
                  ),
                  _buildPdfSummaryDivider(),
                  _buildPdfSummaryCard(
                    title: 'NET BALANCE',
                    amount: 'Rs. ${IndianCurrency.format(summary.netCashFlow)}',
                    color: summary.netCashFlow >= 0
                        ? PdfColor.fromHex('#059669')
                        : PdfColor.fromHex('#DC2626'),
                    fontBold: fontBold,
                  ),
                  _buildPdfSummaryDivider(),
                  _buildPdfSummaryCard(
                    title: 'TRANSACTIONS',
                    amount: '${summary.totalTransactions}',
                    color: PdfColor.fromHex('#4F46E5'), // Indigo
                    fontBold: fontBold,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Top Spending Breakdown (if applicable)
            if (summary.purposeBreakdown.isNotEmpty) ...[
              pw.Text(
                'Spending by Purpose',
                style: pw.TextStyle(font: fontSemiBold, fontSize: 11, color: PdfColors.grey800),
              ),
              pw.SizedBox(height: 6),
              pw.Wrap(
                spacing: 8,
                runSpacing: 4,
                children: summary.purposeBreakdown.entries.take(8).map((entry) {
                  final pct = summary.totalOutflows > 0 ? (entry.value / summary.totalOutflows * 100).toStringAsFixed(1) : '0';
                  return pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#EEF2FF'),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      '${entry.key}: Rs. ${IndianCurrency.format(entry.value)} ($pct%)',
                      style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#3730A3')),
                    ),
                  );
                }).toList(),
              ),
              pw.SizedBox(height: 16),
            ],

            // Itemized Transaction Table
            pw.Text(
              'Itemized Transactions (${transactions.length})',
              style: pw.TextStyle(font: fontSemiBold, fontSize: 11, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              context: context,
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColor.fromHex('#F1F5F9'), width: 0.5),
                bottom: pw.BorderSide(color: PdfColor.fromHex('#CBD5E1'), width: 1),
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F1F5F9'),
              ),
              headerHeight: 22,
              cellHeight: 20,
              headerStyle: pw.TextStyle(
                font: fontSemiBold,
                fontSize: 8,
                color: PdfColor.fromHex('#334155'),
              ),
              cellStyle: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey900,
              ),
              headers: [
                'Date',
                'Ref ID',
                'Flow',
                'Purpose',
                'Account / Mode',
                'Spent For',
                'Narration',
                'Amount (INR)',
              ],
              columnWidths: {
                0: const pw.FixedColumnWidth(48), // Date
                1: const pw.FixedColumnWidth(55), // Ref ID
                2: const pw.FixedColumnWidth(42), // Flow
                3: const pw.FixedColumnWidth(60), // Purpose
                4: const pw.FixedColumnWidth(75), // Account / Mode
                5: const pw.FixedColumnWidth(45), // Spent For
                6: const pw.FlexColumnWidth(),    // Narration
                7: const pw.FixedColumnWidth(65), // Amount
              },
              data: transactions.map((tx) {
                final dateStr = _dateFormat.format(tx.date);
                final refStr = tx.referenceId;
                final flowStr = tx.flow;
                final purposeStr = tx.purpose.isNotEmpty ? tx.purpose : '-';
                final spentForStr = tx.spentFor.isNotEmpty ? tx.spentFor : '-';

                String accMode = tx.breakdowns.map((b) => '${b.paymentType ?? ""}: ${b.effectiveAccount}').join('\n');
                if (tx.isSelfTransfer && tx.toBreakdowns != null && tx.toBreakdowns!.isNotEmpty) {
                  accMode += '\n-> ${tx.toBreakdowns!.map((b) => b.effectiveAccount).join(', ')}';
                }

                final amountStr = 'Rs. ${IndianCurrency.format(tx.totalAmount)}';
                final narrationStr = tx.narration.isNotEmpty ? tx.narration : '-';

                return [
                  dateStr,
                  refStr,
                  flowStr,
                  purposeStr,
                  accMode,
                  spentForStr,
                  narrationStr,
                  amountStr,
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Direct in-app preview or print of the PDF report.
  Future<void> previewOrPrintPdf({
    required List<FinanceTransaction> transactions,
    required StatementFilterOptions options,
  }) async {
    final pdfBytes = await generatePdfReport(transactions: transactions, options: options);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: '${options.title}.pdf',
    );
  }

  /// Share PDF file via WhatsApp, Email, Drive, etc.
  Future<void> sharePdfReport({
    required List<FinanceTransaction> transactions,
    required StatementFilterOptions options,
  }) async {
    final pdfBytes = await generatePdfReport(transactions: transactions, options: options);
    final fileName = 'DailyFinance_Statement_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
  }

  pw.Widget _buildPdfSummaryCard({
    required String title,
    required String amount,
    required PdfColor color,
    required pw.Font fontBold,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          title,
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          amount,
          style: pw.TextStyle(font: fontBold, fontSize: 10, color: color),
        ),
      ],
    );
  }

  pw.Widget _buildPdfSummaryDivider() {
    return pw.Container(
      height: 24,
      width: 0.8,
      color: PdfColor.fromHex('#CBD5E1'),
    );
  }

  String _escapeCsv(String val) {
    return val.replaceAll('"', '""').replaceAll('\n', ' ');
  }

  /// Generates a PDF statement document for borrowers.
  Future<Uint8List> generateBorrowerPdfReport({
    required List<LoanEntry> entries,
    String title = 'Borrowers Ledger Statement',
    String? borrowerFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdf = pw.Document();
    final summary = BorrowerStatementSummary.calculate(entries);

    final fontRegular = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();
    final fontSemiBold = await PdfGoogleFonts.openSansSemiBold();

    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
    );

    final periodStr = (startDate != null || endDate != null)
        ? '${startDate != null ? _dateFormat.format(startDate) : "Start"}  -  ${endDate != null ? _dateFormat.format(endDate) : "Present"}'
        : 'All Time Records';

    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'DAILY FINANCE',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 16,
                        color: PdfColor.fromHex('#4F46E5'),
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      borrowerFilter != null && borrowerFilter.isNotEmpty
                          ? 'Borrower Statement: $borrowerFilter'
                          : title,
                      style: pw.TextStyle(
                        font: fontSemiBold,
                        fontSize: 12,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Period: $periodStr',
                      style: pw.TextStyle(font: fontSemiBold, fontSize: 9, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      'Generated: ${_timestampFormat.format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Borrowers Ledger - Daily Finance',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          final isSingleBorrower = borrowerFilter != null && borrowerFilter.isNotEmpty;

          return [
            pw.SizedBox(height: 12),
            // Summary Cards
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 1),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPdfSummaryCard(
                    title: 'TOTAL GIVEN (LENT)',
                    amount: IndianCurrency.formatSmart(summary.totalGiven),
                    color: PdfColor.fromHex('#EA580C'),
                    fontBold: fontBold,
                  ),
                  _buildPdfSummaryDivider(),
                  _buildPdfSummaryCard(
                    title: 'TOTAL RECEIVED (RECOVERED)',
                    amount: IndianCurrency.formatSmart(summary.totalReceived),
                    color: PdfColor.fromHex('#16A34A'),
                    fontBold: fontBold,
                  ),
                  _buildPdfSummaryDivider(),
                  _buildPdfSummaryCard(
                    title: 'NET OUTSTANDING DUE',
                    amount: IndianCurrency.formatSmart(summary.netDue.abs()),
                    color: summary.netDue > 0
                        ? PdfColor.fromHex('#DC2626')
                        : (summary.netDue < 0 ? PdfColor.fromHex('#2563EB') : PdfColors.grey700),
                    fontBold: fontBold,
                  ),
                  _buildPdfSummaryDivider(),
                  _buildPdfSummaryCard(
                    title: 'TOTAL LOGS',
                    amount: '${summary.totalEntries}',
                    color: PdfColor.fromHex('#4F46E5'),
                    fontBold: fontBold,
                  ),
                ],
              ),
            ),

            if (!isSingleBorrower && summary.borrowerBreakdowns.length > 1) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'BORROWER OUTSTANDING SUMMARY',
                style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey800),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.5),
                headerStyle: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#334155')),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                headers: ['Borrower Name', 'Total Given (₹)', 'Total Received (₹)', 'Net Balance (₹)', 'Status'],
                data: summary.borrowerBreakdowns.entries.map((entry) {
                  final b = entry.value;
                  final status = b.net > 0 ? 'Pending Due' : (b.net < 0 ? 'Overpaid' : 'Settled');
                  return [
                    entry.key,
                    IndianCurrency.formatSmart(b.given),
                    IndianCurrency.formatSmart(b.received),
                    IndianCurrency.formatSmart(b.net.abs()),
                    status,
                  ];
                }).toList(),
              ),
            ],

            pw.SizedBox(height: 16),
            pw.Text(
              'ITEMIZED LOAN & SETTLEMENT LOGS',
              style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey800),
            ),
            pw.SizedBox(height: 6),

            // Itemized Logs Table
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.5),
              headerStyle: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#4F46E5')),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
              headers: ['Date', 'Borrower', 'Narration / Description', 'Account / Mode', 'Given (₹)', 'Received (₹)', 'Ref ID'],
              data: entries.map((entry) {
                return [
                  _dateFormat.format(entry.date),
                  entry.borrower,
                  entry.narration.isEmpty ? '-' : entry.narration,
                  entry.account.isEmpty ? '-' : entry.account,
                  entry.givenAmount > 0 ? IndianCurrency.formatSmart(entry.givenAmount) : '-',
                  entry.receivedAmount > 0 ? IndianCurrency.formatSmart(entry.receivedAmount) : '-',
                  entry.referenceId,
                ];
              }).toList(),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Direct in-app preview or print of the Borrower PDF report.
  Future<void> previewOrPrintBorrowerPdf(
    BuildContext context, {
    required List<LoanEntry> entries,
    String title = 'Borrowers Ledger Statement',
    String? borrowerFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdfBytes = await generateBorrowerPdfReport(
      entries: entries,
      title: title,
      borrowerFilter: borrowerFilter,
      startDate: startDate,
      endDate: endDate,
    );
    final fileName = borrowerFilter != null && borrowerFilter.isNotEmpty
        ? 'Borrower_Statement_${borrowerFilter.replaceAll(' ', '_')}.pdf'
        : 'Borrowers_Ledger_Statement.pdf';
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: fileName,
    );
  }

  /// Share Borrower PDF file via WhatsApp, Email, Drive, etc.
  Future<void> shareBorrowerPdfReport({
    required List<LoanEntry> entries,
    String title = 'Borrowers Ledger Statement',
    String? borrowerFilter,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdfBytes = await generateBorrowerPdfReport(
      entries: entries,
      title: title,
      borrowerFilter: borrowerFilter,
      startDate: startDate,
      endDate: endDate,
    );
    final borrowerTag = borrowerFilter != null && borrowerFilter.isNotEmpty
        ? '_${borrowerFilter.replaceAll(' ', '_')}'
        : '';
    final fileName = 'Borrower_Statement${borrowerTag}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
  }
}

class BorrowerStatementSummary {
  final int totalEntries;
  final double totalGiven;
  final double totalReceived;
  final double netDue;
  final Map<String, ({double given, double received, double net})> borrowerBreakdowns;

  BorrowerStatementSummary({
    required this.totalEntries,
    required this.totalGiven,
    required this.totalReceived,
    required this.netDue,
    required this.borrowerBreakdowns,
  });

  factory BorrowerStatementSummary.calculate(List<LoanEntry> entries) {
    double given = 0.0;
    double received = 0.0;
    final Map<String, ({double given, double received, double net})> map = {};

    for (final e in entries) {
      given += e.givenAmount;
      received += e.receivedAmount;
      final b = e.borrower.trim().isEmpty ? 'General' : e.borrower.trim();
      final curr = map[b] ?? (given: 0.0, received: 0.0, net: 0.0);
      map[b] = (
        given: curr.given + e.givenAmount,
        received: curr.received + e.receivedAmount,
        net: (curr.given + e.givenAmount) - (curr.received + e.receivedAmount),
      );
    }

    return BorrowerStatementSummary(
      totalEntries: entries.length,
      totalGiven: given,
      totalReceived: received,
      netDue: given - received,
      borrowerBreakdowns: map,
    );
  }
}
