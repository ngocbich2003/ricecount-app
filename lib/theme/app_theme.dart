import 'package:flutter/material.dart';

class AppTheme {
  static final ThemeData riceSeedTheme = ThemeData(
    primaryColor:
        const Color(0xFF8CB48A), // Màu xanh lá đậm hơn cho các điểm nhấn
    scaffoldBackgroundColor: Colors.white, // Nền trắng
    cardColor: Colors.white, // Card màu trắng
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF8CB48A), // Màu xanh lá đậm cho AppBar
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF8CB48A),
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(
        color: Color(0xFF2E572C), // Màu xanh đậm cho tiêu đề
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      bodyMedium: TextStyle(
        color: Color(0xFF666666), // Màu xám cho text thường
        fontSize: 14,
      ),
      labelMedium: TextStyle(
        color: Color(0xFF8CB48A), // Màu xanh lá cho các nhãn
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
      hintStyle: TextStyle(
        color: Colors.grey[400],
        fontSize: 16,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF8CB48A),
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFEEEEEE),
      thickness: 1,
    ),
  );
}
