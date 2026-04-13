import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color background       = Color(0xFF0D0D0D);
  static const Color surface          = Color(0xFF1A1A1A);
  static const Color surfaceElevated  = Color(0xFF222222);
  static const Color sidebar          = Color(0xFF111111);
  static const Color gold             = Color(0xFFD4AF37);
  static const Color goldLight        = Color(0xFFE8C547);
  static const Color goldDark         = Color(0xFFB8960C); // used inside goldGradient
  static const Color white            = Color(0xFFFFFFFF);
  static const Color whiteSecondary   = Color(0xFFCCCCCC);
  static const Color whiteTertiary    = Color(0xFF888888);
  static const Color error            = Color(0xFFE53935);
  static const Color success          = Color(0xFF43A047);
  static const Color warning          = Color(0xFFFFA726);
  static const Color info             = Color(0xFF29B6F6);
  // removed: lowStock (duplicate of gold), inStock (duplicate of success)
  static const Color cardBorder       = Color(0xFF2A2A2A);
  static const Color inputFill        = Color(0xFF1E1E1E);
  static const Color divider          = Color(0xFF2A2A2A);

  static const LinearGradient goldGradient = LinearGradient(
    colors: [goldDark, gold, goldLight],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient sidebarGradient = LinearGradient(
    colors: [Color(0xFF111111), Color(0xFF1A1400)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppStrings {
  AppStrings._();

  static const String appName              = 'KNZ Scent';
  static const String appSubtitle         = 'S C E N T';
  static const String adminPortal         = 'Admin Portal';
  static const String luxuryFragranceHouse = 'Luxury Fragrance House';
  // removed: signIn, register (inline strings used in login/register screens)
  static const String username            = 'USERNAME';
  static const String password            = 'PASSWORD';
  static const String enterPortal         = 'ENTER PORTAL';
  static const String defaultLogin        = 'HUSTLE GRIND';
  static const String overview            = 'Overview';
  static const String inventory           = 'Inventory';
  static const String orders              = 'Orders';
  static const String products            = 'Products';
  static const String analytics           = 'Analytics';
  static const String signOut             = 'SIGN OUT';
  static const String totalProducts       = 'TOTAL PRODUCTS';
  static const String totalOrders         = 'TOTAL ORDERS';
  static const String lowStockItems       = 'LOW STOCK ITEMS';
  static const String totalRevenue        = 'TOTAL REVENUE';
  static const String lowStockAlerts      = 'Low Stock Alerts';
  // removed: recentActivity, orderTracker, productCatalogue, analyticsReports,
  //          editStock, update, createOrder, newOrder (all inline in screens)
  static const String addProduct          = 'Add Product';
  static const String addNewProduct       = 'Add New Product';
  static const String productName         = 'PRODUCT NAME';
  static const String category            = 'CATEGORY';
  static const String price               = 'PRICE (₱)';
  static const String stockQty            = 'STOCK QTY';
  static const String minStockLevel       = 'MIN STOCK LEVEL';
  static const String description         = 'DESCRIPTION';
  static const String cancel              = 'Cancel';
}

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle brandName = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.gold,
    letterSpacing: 4,
  );

  static const TextStyle brandSubtitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w300,
    color: AppColors.gold,
    letterSpacing: 8,
  );

  static const TextStyle sectionHeader = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.white,
  );

  static const TextStyle cardTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.gold,
  );

  static const TextStyle cardLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.whiteTertiary,
    letterSpacing: 1.5,
  );

  // removed: bodyText (unused — screens use inline TextStyle or whiteSecondary directly)

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    color: AppColors.whiteTertiary,
    letterSpacing: 1.2,
  );

  static const TextStyle navItem = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.whiteSecondary,
  );

  static const TextStyle navItemActive = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.gold,
  );
}
