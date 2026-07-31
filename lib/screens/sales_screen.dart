// ─────────────────────────────────────────────────────────────────────────────
// sales_screen.dart — Full sales ledger table (Feature 8)
// Columns: Item ID | Item Name | SRP | Discounted Price | Qty |
//          Customer Name | Date Purchased | Total Sales
// Features: sortable columns, date-range + reseller filter, pagination (50/page)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/sales_record_model.dart';
import '../core/money.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

enum _SortField {
  itemName,
  srp,
  discountedPrice,
  quantity,
  customer,
  date,
  total,
}

class _SalesScreenState extends State<SalesScreen> {
  static const int _pageSize = 50;

  // ── Filters ───────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool?
  _resellerFilter; // null = all, true = resellers only, false = regular only

  // ── Sort ─────────────────────────────────────────────────────────────────
  _SortField _sortField = _SortField.date;
  bool _sortAsc = false; // Most recent first by default

  // ── Pagination ────────────────────────────────────────────────────────────
  int _currentPage = 0;

  final _dateFmt = DateFormat('MM/dd/yy');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filtering + sorting pipeline ─────────────────────────────────────────

  List<SalesRecord> _filtered(List<SalesRecord> all) {
    return all.where((r) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!r.itemName.toLowerCase().contains(q) &&
            !r.customerName.toLowerCase().contains(q) &&
            !r.orderId.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (_fromDate != null && r.datePurchased.isBefore(_fromDate!)) {
        return false;
      }
      if (_toDate != null &&
          r.datePurchased.isAfter(_toDate!.add(const Duration(days: 1)))) {
        return false;
      }
      if (_resellerFilter != null && r.isReseller != _resellerFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  List<SalesRecord> _sorted(List<SalesRecord> rows) {
    rows.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.itemName:
          cmp = a.itemName.compareTo(b.itemName);
          break;
        case _SortField.srp:
          cmp = a.srp.compareTo(b.srp);
          break;
        case _SortField.discountedPrice:
          cmp = a.discountedPrice.compareTo(b.discountedPrice);
          break;
        case _SortField.quantity:
          cmp = a.quantity.compareTo(b.quantity);
          break;
        case _SortField.customer:
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case _SortField.date:
          cmp = a.datePurchased.compareTo(b.datePurchased);
          break;
        case _SortField.total:
          cmp = a.totalSales.compareTo(b.totalSales);
          break;
      }
      return _sortAsc ? cmp : -cmp;
    });
    return rows;
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = field == _SortField.itemName || field == _SortField.customer;
      }
      _currentPage = 0;
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
      builder: (context, child) => Theme(
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
        _currentPage = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState(),
      builder: (context, _) {
        final all = AppState().salesRecords;
        final filtered = _sorted(_filtered(all));
        final pageCount = ((filtered.length + _pageSize - 1) / _pageSize)
            .ceil()
            .clamp(1, 9999);
        if (_currentPage >= pageCount) _currentPage = pageCount - 1;
        final pageRows = filtered
            .skip(_currentPage * _pageSize)
            .take(_pageSize)
            .toList();

        // Summary totals for visible filtered set
        final totalSales = filtered.fold(
          Money.zero,
          (s, r) => s + r.totalSales,
        );
        final totalDiscount = filtered.fold(
          Money.zero,
          (s, r) => s + r.discountAmount,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildFilterBar(),
            _buildSummaryRow(filtered.length, totalSales, totalDiscount),
            Expanded(child: _buildTable(pageRows)),
            _buildPagination(filtered.length, pageCount),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 16),
      decoration: const BoxDecoration(
        gradient: AppColors.sidebarGradient,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: const Row(
        children: [
          Icon(Icons.table_chart_outlined, color: AppColors.gold, size: 22),
          SizedBox(width: 10),
          Text(
            'Sales Table',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search
          SizedBox(
            width: 200,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppColors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search item / customer…',
                hintStyle: const TextStyle(
                  color: AppColors.whiteTertiary,
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.whiteTertiary,
                  size: 18,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () => setState(() {
                          _searchCtrl.clear();
                          _searchQuery = '';
                          _currentPage = 0;
                        }),
                        child: const Icon(
                          Icons.close,
                          color: AppColors.whiteTertiary,
                          size: 16,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceElevated,
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.cardBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: AppColors.gold,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (v) => setState(() {
                _searchQuery = v;
                _currentPage = 0;
              }),
            ),
          ),

          // Date range
          _FilterChip(
            label: _fromDate != null
                ? '${_dateFmt.format(_fromDate!)} – ${_dateFmt.format(_toDate!)}'
                : 'All Dates',
            icon: Icons.calendar_today_outlined,
            active: _fromDate != null,
            onTap: _pickDateRange,
            onClear: _fromDate != null
                ? () => setState(() {
                    _fromDate = null;
                    _toDate = null;
                    _currentPage = 0;
                  })
                : null,
          ),

          // Reseller filter
          _FilterChip(
            label: _resellerFilter == null
                ? 'All Orders'
                : (_resellerFilter! ? 'Resellers Only' : 'Regular Only'),
            icon: Icons.people_outline,
            active: _resellerFilter != null,
            onTap: () => setState(() {
              _resellerFilter = _resellerFilter == null
                  ? true
                  : (_resellerFilter! ? false : null);
              _currentPage = 0;
            }),
            onClear: _resellerFilter != null
                ? () => setState(() {
                    _resellerFilter = null;
                    _currentPage = 0;
                  })
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(int count, Money totalSales, Money totalDiscount) {
    return Container(
      color: AppColors.surfaceElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '$count record${count == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppColors.whiteTertiary,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          if (totalDiscount > 0) ...[
            Text(
              'Discount: ${totalDiscount.format()}',
              style: const TextStyle(color: AppColors.warning, fontSize: 12),
            ),
            const SizedBox(width: 16),
          ],
          Text(
            'Total: ${totalSales.format()}',
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<SalesRecord> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.table_rows_outlined,
              color: AppColors.whiteTertiary,
              size: 48,
            ),
            SizedBox(height: 12),
            Text(
              'No sales records match your filters',
              style: TextStyle(color: AppColors.whiteSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      physics: const ClampingScrollPhysics(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.surface),
          dataRowColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.gold.withValues(alpha: 0.08)
                : AppColors.background,
          ),
          border: TableBorder.all(color: AppColors.cardBorder, width: 0.5),
          columnSpacing: 16,
          headingTextStyle: const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
          ),
          dataTextStyle: const TextStyle(
            color: AppColors.whiteSecondary,
            fontSize: 12,
          ),
          columns: [
            _sortCol('Item ID', null), // fixed, no sort
            _sortCol('Item Name', _SortField.itemName),
            _sortCol('SRP', _SortField.srp),
            _sortCol('Disc. Price', _SortField.discountedPrice),
            _sortCol('Qty', _SortField.quantity),
            _sortCol('Customer', _SortField.customer),
            _sortCol('Date', _SortField.date),
            _sortCol('Total Sales', _SortField.total),
          ],
          rows: rows
              .map(
                (r) => DataRow(
                  cells: [
                    DataCell(
                      Text(
                        r.orderId,
                        style: const TextStyle(
                          color: AppColors.whiteTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        children: [
                          if (r.isReseller)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.people,
                                color: AppColors.gold,
                                size: 13,
                              ),
                            ),
                          Flexible(child: Text(r.itemName)),
                        ],
                      ),
                    ),
                    DataCell(Text(r.srp.format())),
                    DataCell(
                      Text(
                        r.discountedPrice.format(),
                        style: TextStyle(
                          color: r.discountPercent > 0
                              ? AppColors.gold
                              : AppColors.whiteSecondary,
                        ),
                      ),
                    ),
                    DataCell(Text(r.quantity.toString())),
                    DataCell(Text(r.customerName)),
                    DataCell(Text(_dateFmt.format(r.datePurchased))),
                    DataCell(
                      Text(
                        r.totalSales.format(),
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  DataColumn _sortCol(String label, _SortField? field) {
    final isActive = field != null && _sortField == field;
    return DataColumn(
      label: GestureDetector(
        onTap: field != null ? () => _toggleSort(field) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: AppColors.gold,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPagination(int total, int pageCount) {
    if (pageCount <= 1) return const SizedBox.shrink();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: AppColors.gold),
            onPressed: _currentPage > 0
                ? () => setState(() => _currentPage--)
                : null,
          ),
          Text(
            'Page ${_currentPage + 1} of $pageCount',
            style: const TextStyle(color: AppColors.whiteSecondary),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: AppColors.gold),
            onPressed: _currentPage < pageCount - 1
                ? () => setState(() => _currentPage++)
                : null,
          ),
          const SizedBox(width: 12),
          Text(
            '$total rows · $_pageSize per page',
            style: const TextStyle(
              color: AppColors.whiteTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable filter chip widget ───────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.gold.withValues(alpha: 0.15)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.gold : AppColors.cardBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? AppColors.gold : AppColors.whiteTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? AppColors.gold : AppColors.whiteSecondary,
                fontSize: 12,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 13, color: AppColors.gold),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
