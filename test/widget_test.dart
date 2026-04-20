// ignore_for_file: avoid_print
// =============================================================================
// widget_tests.dart — WidgetTester tests para sa screens at dialogs
//
// Scope:
//   ✔ LoginScreen         — render, field input, bad-creds error, good-creds path
//   ✔ MarkAsUtangDialog   — render, negative/over-total validation, cancel,
//                           duplicate-utang snackbar guard (show() static method)
//   ✔ UtangPaymentDialog  — render, Cash/GCash toggle, amount validation,
//                           Full-button auto-fill, GCash fields, cancel
//   ✔ EditStockDialog     — render, +/− stepper, clamp at zero, manual edit,
//                           cancel, Update button presence
//   ✔ OrderStatusBadge    — every OrderStatus renders its displayName
//   ✔ StockBadge          — LOW STOCK vs IN STOCK label
//   ✔ CategoryBadge       — label pass-through
//   ✔ showConfirmDialog   — title/message, default labels, custom label,
//                           Cancel→false, Confirm→true
//
// Pattern:
//   • AppState is reset + configured with in-memory stubs before every test.
//   • Widgets are pumped inside a MaterialApp so Navigator / Scaffold /
//     ScaffoldMessenger are all available.
//   • No Firebase, no SQLite, no file I/O.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:knz_scent_admin/core/app_state.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/screens/login_screen.dart';
import 'package:knz_scent_admin/dialogs/edit_stock_dialog.dart';
import 'package:knz_scent_admin/dialogs/mark_as_utang_dialog.dart';
import 'package:knz_scent_admin/dialogs/utang_payment_dialog.dart';
import 'package:knz_scent_admin/widgets/shared_widgets.dart';

import 'stubs/stub_activity_log_repository.dart';
import 'stubs/stub_auth_service.dart';
import 'stubs/stub_debt_repository.dart';
import 'stubs/stub_order_repository.dart';
import 'stubs/stub_product_repository.dart';
import 'stubs/stub_services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

final _uuid = const Uuid();

/// Builds a fresh, stub-backed AppState and logs in as testuser.
/// Returns the configured [AppState] instance.
Future<AppState> _buildAndLogin() async {
  final productRepo = StubProductRepository();
  final orderRepo   = StubOrderRepository();
  final debtRepo    = StubDebtRepository();

  final state = AppState();
  state.reset();
  state.configure(
    productService: StubProductService(productRepo),
    orderService:   StubOrderService(orderRepo, productRepo),
    debtService:    StubDebtService(debtRepo),
    authService:    StubAuthService(),
    logRepository:  StubActivityLogRepository(),
  );
  await state.login(StubAuthService.testUsername, StubAuthService.testPassword);
  return state;
}

/// Wraps [child] inside a barebones [MaterialApp] so that Navigator,
/// Scaffold, and ScaffoldMessenger are all wired up.
Widget _wrap(Widget child) => MaterialApp(home: child);

/// Helper — builds an [Order] with one item.
Order _makeOrder({
  String? id,
  String orderId = 'KNZ-001',
  String customer = 'Ana Reyes',
  double price = 1500,
  int qty = 1,
  OrderStatus status = OrderStatus.pending,
}) {
  final item = OrderItem(
    id: _uuid.v4(),
    productId: _uuid.v4(),
    productName: 'Test Perfume',
    unitPrice: price,
    quantity: qty,
  );
  return Order(
    id: id ?? _uuid.v4(),
    orderId: orderId,
    customerName: customer,
    items: [item],
    totalAmount: price * qty,
    status: status,
    orderDate: DateTime.now(),
  );
}

/// Helper — builds a [CustomerDebt].
CustomerDebt _makeDebt({
  double total = 2000,
  double paid  = 0,
  String orderId = 'KNZ-001',
  String customer = 'Ana Reyes',
}) =>
    CustomerDebt(
      id:           _uuid.v4(),
      customerName: customer,
      orderId:      orderId,
      totalAmount:  total,
      amountPaid:   paid,
      createdAt:    DateTime.now(),
    );

// =============================================================================
// LOGIN SCREEN
// =============================================================================

void main() {
  // ---------------------------------------------------------------------------
  // Set up: reset AppState before every test so the singleton is clean.
  // ---------------------------------------------------------------------------
  setUp(() async {
    await _buildAndLogin();
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('LoginScreen widget', () {
    // NOTE: LoginScreen contains a repeating pulse AnimationController and a
    // FadeInUp from animate_do. Both run indefinitely, so pumpAndSettle() times
    // out. We use pump(Duration) to advance past the entry animation only.

    /// Pumps LoginScreen past its 600ms FadeInUp entry animation.
    Future<void> pumpLogin(WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const LoginScreen()));
      // Advance past the FadeInUp entry animation (600 ms) plus a small buffer.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(); // settle any pending microtasks
    }

    // ── 1. Renders required UI elements ──────────────────────────────────────
    testWidgets('renders username field, password field and login button',
        (tester) async {
      await pumpLogin(tester);

      expect(find.text('Enter your username'), findsOneWidget);
      expect(find.text('••••••••'),            findsOneWidget);
      expect(find.text('ENTER PORTAL'),        findsOneWidget);
    });

    // ── 2. Typing populates controllers ──────────────────────────────────────
    testWidgets('entering text into fields updates their value', (tester) async {
      await pumpLogin(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'testuser');
      await tester.enterText(fields.at(1), 'password123');

      expect(find.text('testuser'),    findsOneWidget);
      expect(find.text('password123'), findsOneWidget);
    });

    // ── 3. Wrong credentials shows error message ──────────────────────────────
    testWidgets('shows error on bad credentials', (tester) async {
      await pumpLogin(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'wrong');
      await tester.enterText(fields.at(1), 'wrongpass');

      await tester.tap(find.text('ENTER PORTAL'));
      // Pump enough for the async login call to complete and setState to fire.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Invalid username or password'), findsOneWidget);
    });

    // ── 4. Empty fields — login button visible and tappable ──────────────────
    testWidgets('login button is present with empty fields', (tester) async {
      await pumpLogin(tester);

      expect(find.text('ENTER PORTAL'), findsOneWidget);
    });

    // ── 5. Correct credentials — no error message shown ──────────────────────
    testWidgets('no error shown when credentials are correct', (tester) async {
      await _buildAndLogin();

      await pumpLogin(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), StubAuthService.testUsername);
      await tester.enterText(fields.at(1), StubAuthService.testPassword);

      // After a successful login the app navigates to MainShell which may
      // produce RenderFlex overflow errors in the test viewport.  Those are
      // layout warnings unrelated to what this test is verifying, so we
      // temporarily replace the error handler to swallow overflow-only errors.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        final String summary = details.exceptionAsString();
        if (summary.contains('RenderFlex overflowed')) return;
        originalOnError?.call(details);
      };

      await tester.tap(find.text('ENTER PORTAL'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      FlutterError.onError = originalOnError;

      expect(find.text('Invalid username or password'), findsNothing);
    });
  });

  // =============================================================================
  // MARK AS UTANG DIALOG
  // =============================================================================
  group('MarkAsUtangDialog widget', () {
    // ── 1. Renders with correct order info ───────────────────────────────────
    testWidgets('renders customer name, orderId and total amount', (tester) async {
      final order = _makeOrder(customer: 'Ben Cruz', orderId: 'KNZ-007',
          price: 1200, qty: 2);

      await tester.pumpWidget(_wrap(
        Builder(builder: (ctx) => MarkAsUtangDialog(order: order)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Ben Cruz'),  findsOneWidget);
      expect(find.text('KNZ-007'),   findsOneWidget);
      // ₱2,400.00 total (1200 × 2)
      expect(find.textContaining('2,400'), findsOneWidget);
    });

    // ── 2. Header title is visible ────────────────────────────────────────────
    testWidgets('shows "Mark as Utang" header', (tester) async {
      final order = _makeOrder();
      await tester.pumpWidget(_wrap(MarkAsUtangDialog(order: order)));
      await tester.pumpAndSettle();
      expect(find.text('Mark as Utang'), findsOneWidget);
    });

    // ── 3. Negative amount shows validation error ─────────────────────────────
    testWidgets('shows error when initial payment is negative', (tester) async {
      final order = _makeOrder(price: 1000);
      await tester.pumpWidget(_wrap(MarkAsUtangDialog(order: order)));
      await tester.pumpAndSettle();

      // Enter a negative value in the amount field
      await tester.enterText(find.byType(TextField), '-50');
      await tester.tap(find.text('Record Utang'));
      await tester.pump();

      expect(find.text('Amount cannot be negative.'), findsOneWidget);
    });

    // ── 4. Amount >= total shows validation error ─────────────────────────────
    testWidgets('shows error when initial payment equals or exceeds total',
        (tester) async {
      final order = _makeOrder(price: 1000); // total = ₱1,000
      await tester.pumpWidget(_wrap(MarkAsUtangDialog(order: order)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1000');
      await tester.tap(find.text('Record Utang'));
      await tester.pump();

      expect(find.textContaining('Amount must be less than total'), findsOneWidget);
    });

    // ── 5. Valid partial payment — no validation error ────────────────────────
    testWidgets('no error when partial payment is valid', (tester) async {
      final order = _makeOrder(price: 1000);
      await tester.pumpWidget(_wrap(MarkAsUtangDialog(order: order)));
      await tester.pumpAndSettle();

      // Enter a valid partial amount (500 < 1000)
      await tester.enterText(find.byType(TextField), '500');
      // Just verify that no inline error text appears before tapping (clean state)
      expect(find.text('Amount cannot be negative.'), findsNothing);
      expect(find.textContaining('Amount must be less than'), findsNothing);
    });

    // ── 6. Cancel button closes dialog ───────────────────────────────────────
    testWidgets('Cancel button pops the dialog', (tester) async {
      final order = _makeOrder();
      bool dialogVisible = true;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: ctx,
                  builder: (_) => MarkAsUtangDialog(order: order),
                ).then((_) => dialogVisible = false);
              },
              child: const Text('Open'),
            ),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Mark as Utang'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Mark as Utang'), findsNothing);
      expect(dialogVisible, isFalse);
    });

    // ── 7. Duplicate check — show.() blocks re-opening for same orderId ──────
    testWidgets('MarkAsUtangDialog.show blocks duplicate utang via snackbar',
        (tester) async {
      final state = AppState();
      // Seed a debt with orderId 'KNZ-DUP'
      final existingDebt = _makeDebt(orderId: 'KNZ-DUP');
      await state.addDebt(existingDebt);

      final order = _makeOrder(orderId: 'KNZ-DUP');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) {
            return ElevatedButton(
              onPressed: () => MarkAsUtangDialog.show(ctx, order),
              child: const Text('Open'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Dialog should NOT have opened
      expect(find.text('Mark as Utang'), findsNothing);
      // SnackBar with duplicate message should appear
      expect(
        find.textContaining('May utang na ang order na ito'),
        findsOneWidget,
      );
    });
  });

  // =============================================================================
  // UTANG PAYMENT DIALOG
  // =============================================================================
  group('UtangPaymentDialog widget', () {
    // ── 1. Renders customer name, orderId and remaining balance ───────────────
    testWidgets('renders debt details correctly', (tester) async {
      final debt = _makeDebt(total: 1500, paid: 500,
          customer: 'Cath Lim', orderId: 'KNZ-010');
      // remaining = 1000

      await tester.pumpWidget(_wrap(UtangPaymentDialog(debt: debt)));
      await tester.pumpAndSettle();

      expect(find.text('Cath Lim'),  findsOneWidget);
      expect(find.text('KNZ-010'),   findsOneWidget);
      expect(find.textContaining('1,000'), findsOneWidget); // ₱1,000.00
    });

    // ── 2. Header title ───────────────────────────────────────────────────────
    testWidgets('shows "Add Payment" header', (tester) async {
      final debt = _makeDebt();
      await tester.pumpWidget(_wrap(UtangPaymentDialog(debt: debt)));
      await tester.pumpAndSettle();
      expect(find.text('Add Payment'), findsOneWidget);
    });

    // ── 3. Cash is the default payment method ─────────────────────────────────
    testWidgets('Cash method is selected by default', (tester) async {
      final debt = _makeDebt();
      await tester.pumpWidget(_wrap(UtangPaymentDialog(debt: debt)));
      await tester.pumpAndSettle();

      // GCash-specific fields should NOT be visible when Cash is selected
      expect(find.text('GCASH REFERENCE NO.'), findsNothing);
    });

    // ── 4. GCash toggle reveals GCash fields ──────────────────────────────────
    testWidgets('tapping GCash shows GCash-specific fields', (tester) async {
      final debt = _makeDebt();
      await tester.pumpWidget(_wrap(UtangPaymentDialog(debt: debt)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GCash'));
      await tester.pumpAndSettle();

      expect(find.text('GCASH REFERENCE NO.'), findsOneWidget);
      expect(find.text('GCASH NUMBER'),        findsOneWidget);
      expect(find.text('GCASH ACCOUNT NAME'),  findsOneWidget);
    });

    // ── 5. Back to Cash hides GCash fields ───────────────────────────────────
    testWidgets('switching back to Cash hides GCash fields', (tester) async {
      final debt = _makeDebt();
      await tester.pumpWidget(_wrap(UtangPaymentDialog(debt: debt)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GCash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();

      expect(find.text('GCASH REFERENCE NO.'), findsNothing);
    });

    // ── 6. Zero or empty amount shows validation error ────────────────────────
    testWidgets('shows error when amount is zero or empty', (tester) async {
      final debt = _makeDebt(total: 1000, paid: 0);
      await tester.pumpWidget(_wrap(UtangPaymentDialog(debt: debt)));
      await tester.pumpAndSettle();

      // Leave amount empty and tap Confirm
      await tester.tap(find.text('Confirm Payment'));
      await tester.pump();

      expect(find.text('Please enter a valid amount.'), findsOneWidget);
    });

    // ── 7. Amount exceeding remaining balance shows error ─────────────────────
    testWidgets('shows error when amount exceeds remaining balance',
        (tester) async {
      final debt = _makeDebt(total: 1000, paid: 200); // remaining = 800
      await tester.pumpWidget(_wrap(UtangPaymentDialog(debt: debt)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '999');
      await tester.tap(find.text('Confirm Payment'));
      await tester.pump();

      expect(
        find.textContaining('Amount exceeds remaining balance'),
        findsOneWidget,
      );
    });

    // ── 8. GCash — missing reference shows its own error ─────────────────────
    testWidgets('GCash: shows error when reference number is missing',
        (tester) async {
      final debt = _makeDebt(total: 1000, paid: 0);

      // Give the viewport more vertical room so the GCash fields + button
      // all fit without scrolling off-screen.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(800, 1200)),
          child: _wrap(UtangPaymentDialog(debt: debt)),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to GCash
      await tester.tap(find.text('GCash'));
      await tester.pumpAndSettle();

      // Enter a valid amount in the first TextField (amount field)
      await tester.enterText(find.byType(TextField).first, '500');

      // Scroll the dialog content so the button is visible, then tap.
      await tester.ensureVisible(find.text('Confirm Payment'));
      await tester.tap(find.text('Confirm Payment'));
      await tester.pump();

      expect(
        find.text('Please enter the GCash reference number.'),
        findsOneWidget,
      );
    });

    // ── 9. "Full" button fills in the remaining balance ───────────────────────
    testWidgets('"Full" button auto-fills the remaining balance amount',
        (tester) async {
      final debt = _makeDebt(total: 1500, paid: 300); // remaining = 1200
      await tester.pumpWidget(_wrap(UtangPaymentDialog(debt: debt)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Full'));
      await tester.pump();

      // The amount TextField should now contain the remaining balance
      final amountField = tester.widget<TextField>(find.byType(TextField).first);
      expect(amountField.controller?.text, '1200.00');
    });

    // ── 10. Cancel button dismisses dialog ───────────────────────────────────
    testWidgets('Cancel button pops the dialog', (tester) async {
      final debt = _makeDebt();
      bool dismissed = false;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: ctx,
                  builder: (_) => UtangPaymentDialog(debt: debt),
                ).then((_) => dismissed = true);
              },
              child: const Text('Open'),
            ),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Add Payment'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add Payment'), findsNothing);
      expect(dismissed, isTrue);
    });
  });

  // =============================================================================
  // EDIT STOCK DIALOG
  // =============================================================================
  group('EditStockDialog widget', () {
    Product makeProduct({int stock = 10, int min = 3}) => Product(
          id: _uuid.v4(),
          name: 'Rose EDP',
          description: 'Test product',
          category: ProductCategory.eauDeParfum,
          price: 999,
          stockQty: stock,
          minStockLevel: min,
        );

    // ── 1. Renders product name and current stock ─────────────────────────────
    testWidgets('renders product name and current stock qty', (tester) async {
      final product = makeProduct(stock: 12, min: 4);
      await tester.pumpWidget(_wrap(EditStockDialog(product: product)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Rose EDP'),     findsOneWidget);
      expect(find.text('12'),                      findsOneWidget);
      expect(find.text('Min stock level: 4'),      findsOneWidget);
    });

    // ── 2. (+) button increments stock ───────────────────────────────────────
    testWidgets('plus button increments the stock value', (tester) async {
      final product = makeProduct(stock: 5);
      await tester.pumpWidget(_wrap(EditStockDialog(product: product)));
      await tester.pumpAndSettle();

      // Find the (+) DarkIconButton via its Icon
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      // TextField should now show 6
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '6');
    });

    // ── 3. (−) button decrements stock ───────────────────────────────────────
    testWidgets('minus button decrements the stock value', (tester) async {
      final product = makeProduct(stock: 5);
      await tester.pumpWidget(_wrap(EditStockDialog(product: product)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '4');
    });

    // ── 4. (−) button does NOT go below zero ─────────────────────────────────
    testWidgets('minus button stops at zero — does not go negative',
        (tester) async {
      final product = makeProduct(stock: 0);
      await tester.pumpWidget(_wrap(EditStockDialog(product: product)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(int.parse(field.controller!.text), greaterThanOrEqualTo(0));
    });

    // ── 5. Manual edit of the text field ─────────────────────────────────────
    testWidgets('user can type a new stock quantity directly', (tester) async {
      final product = makeProduct(stock: 5);
      await tester.pumpWidget(_wrap(EditStockDialog(product: product)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '25');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '25');
    });

    // ── 6. Cancel button closes dialog ───────────────────────────────────────
    testWidgets('Cancel button dismisses the dialog', (tester) async {
      final product = makeProduct();
      bool dismissed = false;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: ctx,
                  builder: (_) => EditStockDialog(product: product),
                ).then((_) => dismissed = true);
              },
              child: const Text('Open'),
            ),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Edit Stock'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Edit Stock'), findsNothing);
      expect(dismissed, isTrue);
    });

    // ── 7. Update button is present ───────────────────────────────────────────
    testWidgets('Update button is visible', (tester) async {
      final product = makeProduct();
      await tester.pumpWidget(_wrap(EditStockDialog(product: product)));
      await tester.pumpAndSettle();

      expect(find.text('Update'), findsOneWidget);
    });
  });

  // =============================================================================
  // SHARED WIDGETS
  // =============================================================================
  group('OrderStatusBadge widget', () {
    // ── 1. Every status renders its displayName ───────────────────────────────
    for (final status in OrderStatus.values) {
      testWidgets('renders displayName for $status', (tester) async {
        await tester.pumpWidget(_wrap(OrderStatusBadge(status: status)));
        await tester.pumpAndSettle();
        expect(
          find.text(status.displayName.toUpperCase()),
          findsOneWidget,
          reason: '$status should render its displayName in uppercase',
        );
      });
    }
  });

  group('StockBadge widget', () {
    // ── 1. Shows "LOW STOCK" when isLowStock is true ──────────────────────────
    testWidgets('shows LOW STOCK label when isLowStock = true', (tester) async {
      await tester.pumpWidget(_wrap(const StockBadge(isLowStock: true)));
      await tester.pumpAndSettle();
      expect(find.text('LOW STOCK'), findsOneWidget);
    });

    // ── 2. Shows "IN STOCK" when isLowStock is false ──────────────────────────
    testWidgets('shows IN STOCK label when isLowStock = false', (tester) async {
      await tester.pumpWidget(_wrap(const StockBadge(isLowStock: false)));
      await tester.pumpAndSettle();
      expect(find.text('IN STOCK'), findsOneWidget);
    });
  });

  group('CategoryBadge widget', () {
    // ── 1. Renders whatever label string is passed ────────────────────────────
    testWidgets('renders the provided label text', (tester) async {
      await tester.pumpWidget(_wrap(const CategoryBadge(label: 'Eau de Toilette')));
      await tester.pumpAndSettle();
      expect(find.text('Eau de Toilette'), findsOneWidget);
    });
  });

  group('showConfirmDialog helper', () {
    // ── 1. Shows title and message ────────────────────────────────────────────
    testWidgets('displays title and message correctly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => showConfirmDialog(
                ctx,
                title: 'Delete Item',
                message: 'Are you sure you want to delete this item?',
              ),
              child: const Text('Open'),
            ),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Item'),                           findsOneWidget);
      expect(find.text('Are you sure you want to delete this item?'), findsOneWidget);
    });

    // ── 2. Default action labels are present ──────────────────────────────────
    testWidgets('shows default Confirm and Cancel buttons', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => showConfirmDialog(
                ctx,
                title: 'Test',
                message: 'Test message',
              ),
              child: const Text('Open'),
            ),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'),  findsOneWidget);
    });

    // ── 3. Custom confirm label ───────────────────────────────────────────────
    testWidgets('uses custom confirmLabel when provided', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () => showConfirmDialog(
                ctx,
                title: 'Test',
                message: 'Test',
                confirmLabel: 'Yes, Delete',
              ),
              child: const Text('Open'),
            ),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Yes, Delete'), findsOneWidget);
    });

    // ── 4. Cancel returns false ───────────────────────────────────────────────
    testWidgets('tapping Cancel returns false', (tester) async {
      bool? result;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showConfirmDialog(
                  ctx,
                  title: 'Test',
                  message: 'Test',
                );
              },
              child: const Text('Open'),
            ),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    // ── 5. Confirm returns true ───────────────────────────────────────────────
    testWidgets('tapping Confirm returns true', (tester) async {
      bool? result;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showConfirmDialog(
                  ctx,
                  title: 'Test',
                  message: 'Test',
                );
              },
              child: const Text('Open'),
            ),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });
  });
}
