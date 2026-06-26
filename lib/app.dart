import 'package:flutter/material.dart';

import 'features/auth/auth_gate.dart';

class CampSugarManagerApp extends StatelessWidget {
  const CampSugarManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1F7A6B),
      brightness: Brightness.light,
    );

    final textTheme = ThemeData.light(useMaterial3: true).textTheme;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Camp Sugar Manager',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF2F6F5),
        textTheme: textTheme.copyWith(
          headlineSmall: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
          titleLarge: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleMedium: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.35),
        ),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          backgroundColor: const Color(0xFFF2F6F5),
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          side: BorderSide(color: colorScheme.outlineVariant),
          selectedColor: colorScheme.primaryContainer,
          checkmarkColor: colorScheme.onPrimaryContainer,
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: colorScheme.primaryContainer,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final base = textTheme.labelSmall ?? const TextStyle();
            if (states.contains(WidgetState.selected)) {
              return base.copyWith(fontWeight: FontWeight.w700);
            }
            return base.copyWith(fontWeight: FontWeight.w500);
          }),
        ),
        tabBarTheme: TabBarThemeData(
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
            borderRadius: BorderRadius.circular(999),
          ),
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
