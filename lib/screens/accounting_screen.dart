// ─────────────────────────────────────────────────────────────────────────────
// accounting_screen.dart — Feature 3: Full accounting ledger
// Tabs: All Sales | Reseller Sales | Customized Orders
// Date range picker, summary cards, per-row breakdown table
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/order_model.dart';
import '../services/accounting_service.dart';
import '../dialogs/export_dialog.dart';

class AccountingScreen extends StatefulWidget {
  const AccountingScreen({super.key, this.accountingReport});

  final AccountingReport? accountingReport;

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  DateTime? _fromDate;
  DateTime? _toDate;

  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final _dateFmt = DateFormat('MM/dd/yy');

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.gold),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState(),
      builder: (context, _) {
        final state = AppState();
        final report =
            widget.accountingReport ??
            AccountingService.instance.summarize(
              orders: state.orders,
              debts: state.debts,
              customOrders: state.customOrders,
              period: AccountingPeriod(from: _fromDate, to: _toDate),
            );
        final orders = report.recognizedOrders;

        final top = MediaQuery.of(context).padding.top;

        return Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(20, top + 16, 20, 0),
              decoration: const BoxDecoration(
                gradient: AppColors.sidebarGradient,
                border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.account_balance_outlined,
                        color: AppColors.gold,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Accounting',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.download_outlined,
                          color: AppColors.whiteTertiary,
                        ),
                        tooltip: 'Export',
                        onPressed: () =>
                            showExportDialog(context, ExportType.accounting),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Date filter chip
                  GestureDetector(
                    onTap: _pickDateRange,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _fromDate != null
                            ? AppColors.gold.withValues(alpha: 0.12)
                            : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _fromDate != null
                              ? AppColors.gold
                              : AppColors.cardBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 13,
                            color: AppColors.gold,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _fromDate != null
                                ? '${_dateFmt.format(_fromDate!)} – ${_dateFmt.format(_toDate!)}'
                                : 'All time',
                            style: TextStyle(
                              color: _fromDate != null
                                  ? AppColors.gold
                                  : AppColors.whiteSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (_fromDate != null) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => setState(() {
                                _fromDate = null;
                                _toDate = null;
                              }),
                              child: const Icon(
                                Icons.close,
                                size: 13,
                                color: AppColors.gold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Summary cards row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _SummaryCard(
                          'Gross Sales (SRP)',
                          report.grossSales.format(),
                          AppColors.whiteSecondary,
                          Icons.bar_chart,
                        ),
                        const SizedBox(width: 10),
                        _SummaryCard(
                          'Total Discounts',
                          report.discounts.format(),
                          AppColors.warning,
                          Icons.discount_outlined,
                        ),
                        const SizedBox(width: 10),
                        _SummaryCard(
                          'Net Sales\n(after all discounts)',
                          report.netSales.format(),
                          AppColors.gold,
                          Icons.trending_up,
                        ),
                        const SizedBox(width: 10),
                        _SummaryCard(
                          'Custom Orders',
                          report.customOrderReceipts.format(),
                          AppColors.info,
                          Icons.draw_outlined,
                        ),
                        const SizedBox(width: 10),
                        _SummaryCard(
                          'Debt Collections',
                          report.debtCollections.format(),
                          AppColors.success,
                          Icons.payments_outlined,
                        ),
                        const SizedBox(width: 10),
                        _SummaryCard(
                          'Cash Received',
                          report.cashReceived.format(),
                          AppColors.gold,
                          Icons.account_balance_wallet_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tabs
                  TabBar(
                    controller: _tabCtrl,
                    labelColor: AppColors.gold,
                    unselectedLabelColor: AppColors.whiteTertiary,
                    indicatorColor: AppColors.gold,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    tabs: const [
                      Tab(text: 'Paid Sales'),
                      Tab(text: 'Reseller'),
                      Tab(text: 'Customized'),
                    ],
                  ),
                ],
              ),
            ),

            // ── Tab views ─────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _OrderTable(orders: orders, currency: _currency),
                  _OrderTable(
                    orders: orders.where((o) => o.isReseller).toList(),
                    currency: _currency,
                  ),
                  _CustomPaymentTable(rows: report.customOrderPayments),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CustomPaymentTable extends StatelessWidget {
  const _CustomPaymentTable({required this.rows});

  final List<CustomOrderCollectionRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'No custom-order receipts',
          style: TextStyle(color: AppColors.whiteTertiary),
        ),
      );
    }
    final dateFormat = DateFormat('MM/dd/yy');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Customer')),
          DataColumn(label: Text('Amount')),
          DataColumn(label: Text('Paid')),
          DataColumn(label: Text('Note')),
        ],
        rows: rows
            .map(
              (row) => DataRow(
                cells: [
                  DataCell(Text(row.order.customerName)),
                  DataCell(Text(row.payment.amount.format())),
                  DataCell(Text(dateFormat.format(row.payment.paidAt))),
                  DataCell(Text(row.payment.note ?? '')),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Summary card widget ───────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCard(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.whiteTertiary,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Per-order ledger table ────────────────────────────────────────────────────
class _OrderTable extends StatelessWidget {
  final List<Order> orders;
  final NumberFormat currency;

  const _OrderTable({required this.orders, required this.currency});

  static final _dateFmt = DateFormat('MM/dd/yy');

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(
        child: Text(
          'No records',
          style: TextStyle(color: AppColors.whiteTertiary),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      physics: const ClampingScrollPhysics(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.surface),
          dataRowColor: WidgetStateProperty.all(AppColors.background),
          border: TableBorder.all(color: AppColors.cardBorder, width: 0.5),
          columnSpacing: 14,
          headingTextStyle: const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 0.8,
          ),
          dataTextStyle: const TextStyle(
            color: AppColors.whiteSecondary,
            fontSize: 11,
          ),
          columns: const [
            DataColumn(label: Text('Order ID')),
            DataColumn(label: Text('Customer')),
            DataColumn(label: Text('SRP')),
            DataColumn(label: Text('Discount')),
            DataColumn(label: Text('Customer Pay')),
            DataColumn(label: Text('Date')),
          ],
          rows: orders.map((o) {
            final breakdown = AccountingService.instance.orderBreakdown(o);
            final totalDiscount = breakdown.discount;
            final hasDiscount = totalDiscount > 0;
            // SRP = sum of (srpPrice × qty) per item — true catalog price before any discount
            final srpAmount = breakdown.srpTotal;
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    o.orderId,
                    style: const TextStyle(color: AppColors.gold, fontSize: 10),
                  ),
                ),
                DataCell(Text(o.customerName)),
                DataCell(Text(srpAmount.format())),
                DataCell(
                  Text(
                    hasDiscount ? '− ${totalDiscount.format()}' : '—',
                    style: TextStyle(
                      color: hasDiscount
                          ? AppColors.warning
                          : AppColors.whiteTertiary,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    breakdown.customerPayTotal.format(),
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                DataCell(Text(_dateFmt.format(o.orderDate))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
