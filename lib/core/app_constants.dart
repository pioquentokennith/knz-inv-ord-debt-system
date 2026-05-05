// ─────────────────────────────────────────────────────────────────────────────
// app_constants.dart — Global design tokens and string constants
// Purpose : Single source of truth for colors, text styles, and UI strings.
//           Centralizing these prevents magic numbers scattered across screens.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

// All app-wide color tokens — use these instead of raw Color() values in widgets
class AppColors {
  // Private constructor — prevents instantiation; this class is purely static
  AppColors._();

  // ── Background layers (darkest → lightest) ────────────────────────────────
  static const Color background       = Color(0xFF0D0D0D); // Main scaffold background
  static const Color surface          = Color(0xFF1A1A1A); // Card / dialog surface
  static const Color surfaceElevated  = Color(0xFF222222); // Elevated card / snackbar
  static const Color sidebar          = Color(0xFF111111); // Navigation rail / drawer

  // ── Brand accent colors ───────────────────────────────────────────────────
  static const Color gold             = Color(0xFFD4AF37); // Primary brand color
  static const Color goldLight        = Color(0xFFE8C547); // Lighter gold for hover states
  static const Color goldDark         = Color(0xFFB8960C); // Darker gold — used inside goldGradient

  // ── Text colors (brightest → dimmest) ────────────────────────────────────
  static const Color white            = Color(0xFFFFFFFF); // Primary text
  static const Color whiteSecondary   = Color(0xFFCCCCCC); // Secondary / body text
  static const Color whiteTertiary    = Color(0xFF888888); // Placeholder / label text

  // ── Semantic status colors ────────────────────────────────────────────────
  static const Color error            = Color(0xFFE53935); // Errors, destructive actions
  static const Color success          = Color(0xFF43A047); // Success, in-stock indicators
  static const Color warning          = Color(0xFFFFA726); // Warnings, low-stock alerts
  static const Color info             = Color(0xFF29B6F6); // Info badges / processing status

  // ── Border and input colors ───────────────────────────────────────────────
  // removed: lowStock (duplicate of gold), inStock (duplicate of success)
  static const Color cardBorder       = Color(0xFF2A2A2A); // Thin card border stroke
  static const Color inputFill        = Color(0xFF1E1E1E); // Text field background fill
  static const Color divider          = Color(0xFF2A2A2A); // List/section divider lines

  // ── Gradients ─────────────────────────────────────────────────────────────
  // Horizontal gold sweep — used for premium headings and primary buttons
  static const LinearGradient goldGradient = LinearGradient(
    colors: [goldDark, gold, goldLight],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Vertical dark fade — used on the navigation sidebar for depth
  static const LinearGradient sidebarGradient = LinearGradient(
    colors: [Color(0xFF111111), Color(0xFF1A1400)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

// Static UI string constants — keeps all user-visible text in one place
// for easy localization or branding changes
class AppStrings {
  AppStrings._(); // Private constructor — static-only class

  // ── Brand identity ────────────────────────────────────────────────────────
  static const String appName              = 'KNZ Scent';        // App / brand name
  static const String appSubtitle         = 'TRUSTED BY SCENT LOVERS'; // Spaced tagline on login screen
  static const String adminPortal         = 'Admin Portal';      // Shown in app header
  static const String luxuryFragranceHouse = 'Luxury Fragrance House'; // Sub-branding

  // ── Login / auth screen labels ────────────────────────────────────────────
  // removed: signIn, register (inline strings used in login/register screens)
  static const String username            = 'USERNAME';          // Login field label
  static const String password            = 'PASSWORD';          // Password field label
  static const String enterPortal         = 'ENTER PORTAL';      // Submit button text
  static const String defaultLogin        = 'HUSTLE GRIND';      // Placeholder / motivational

  // ── Navigation labels ─────────────────────────────────────────────────────
  static const String overview            = 'Overview';          // Dashboard tab
  static const String inventory           = 'Inventory';         // Stock management tab
  static const String orders              = 'Orders';            // Order list tab
  static const String products            = 'Products';          // Product catalogue tab
  static const String analytics           = 'Analytics';         // Reports tab
  static const String signOut             = 'SIGN OUT';          // Logout button

  // ── Dashboard summary card labels ─────────────────────────────────────────
  static const String totalProducts       = 'TOTAL PRODUCTS';    // Metric card header
  static const String totalOrders         = 'TOTAL ORDERS';      // Metric card header
  static const String lowStockItems       = 'LOW STOCK ITEMS';   // Alert card header
  static const String lowStockAlerts      = 'Low Stock Alerts';  // Section title

  // ── Product dialog labels ─────────────────────────────────────────────────
  // removed: recentActivity, orderTracker, productCatalogue, analyticsReports,
  //          editStock, update, createOrder, newOrder (all inline in screens)
  static const String addProduct          = 'Add Product';       // FAB tooltip
  static const String addNewProduct       = 'Add New Product';   // Dialog title
  static const String productName         = 'PRODUCT NAME';      // Form field label
  static const String category            = 'CATEGORY';          // Dropdown label
  static const String price               = 'PRICE (₱)';         // Price field label
  static const String stockQty            = 'STOCK QTY';         // Quantity field label
  static const String minStockLevel       = 'MIN STOCK LEVEL';   // Minimum stock field label
  static const String description         = 'DESCRIPTION';       // Description field label
  static const String cancel              = 'Cancel';            // Cancel button text
}

// Reusable TextStyle presets — apply via .copyWith() if local tweaks are needed
class AppTextStyles {
  AppTextStyles._(); // Private constructor — static-only class

  // Large bold gold title on login/splash screens
  static const TextStyle brandName = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.gold,
    letterSpacing: 4,
  );

  // Slim spaced subtitle beneath the brand name (e.g. "TRUSTED BY SCENT LOVERS")
  static const TextStyle brandSubtitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w300,
    color: AppColors.gold,
    letterSpacing: 2,
  );

  // Screen section headings (e.g. "Recent Orders", "Low Stock Alerts")
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.white,
  );

  // Large metric value inside summary/stat cards
  static const TextStyle cardTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.gold,
  );

  // Small all-caps label above a metric value in stat cards
  static const TextStyle cardLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.whiteTertiary,
    letterSpacing: 1.5,
  );

  // removed: bodyText (unused — screens use inline TextStyle or whiteSecondary directly)

  // Tiny caption / tag text used for timestamps and badge labels
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    color: AppColors.whiteTertiary,
    letterSpacing: 1.2,
  );

  // Inactive navigation item text
  static const TextStyle navItem = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.whiteSecondary,
  );

  // Active / selected navigation item text — gold and slightly heavier
  static const TextStyle navItemActive = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.gold,
  );
}
