import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/app_state.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/complete_profile_screen.dart';
import 'screens/blocked_screen.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'services/app_refs.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Premium Status Bar & System UI
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  
  // Firebase initialization
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    } else {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  
  final prefs = await SharedPreferences.getInstance();
  runApp(CustomerApp(prefs: prefs));
}

class CustomerApp extends StatefulWidget {
  const CustomerApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  late final AppState _state;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _state = AppState();
    _state.init(widget.prefs).then((_) {
      if (mounted) setState(() => _ready = true);
    });
    AppRefs.state = _state;
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      );
    }
    AppRefs.state = _state;
    final brand = AppTheme.brandFromState(_state);

    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: _state.restaurantName,
          locale: const Locale('ar'),
          navigatorKey: appNavigatorKey,
          theme: _buildLightTheme(brand),
          darkTheme: _buildDarkTheme(brand),
          themeMode: _state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox(),
            );
          },
          home: SplashScreen(prefs: widget.prefs, state: _state),
          routes: {
            OnboardingScreen.route: (_) => OnboardingScreen(prefs: widget.prefs, state: _state),
            AuthScreen.route: (_) => AuthScreen(prefs: widget.prefs, state: _state),
            CompleteProfileScreen.route: (_) => CompleteProfileScreen(prefs: widget.prefs, state: _state),
            HomeScreen.route: (_) => HomeScreen(prefs: widget.prefs, state: _state),
            BlockedScreen.route: (_) => BlockedScreen(prefs: widget.prefs, state: _state),
          },
        );
      },
    );
  }

  ThemeData _buildLightTheme(BrandSchemes brand) {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Cairo',
      colorScheme: brand.light,
      textTheme: AppTheme.arabicTextTheme,
      scaffoldBackgroundColor: AppTheme.scaffoldBg,
      
      // Premium AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 2,
        shadowColor: Colors.black.withOpacity(0.1),
        titleTextStyle: AppTheme.arabicTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800, 
          color: const Color(0xFF1A1A1A),
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF1A1A1A),
          size: 24,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),
      
      // Premium Cards
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppTheme.cardBg,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        margin: const EdgeInsets.symmetric(
          vertical: AppTheme.spaceS,
          horizontal: 0,
        ),
      ),
      
      // Premium Input Fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide(
            color: brand.light.outline,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide(
            color: brand.light.outline,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide(
            color: brand.light.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: const BorderSide(
            color: AppTheme.errorColor,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: const BorderSide(
            color: AppTheme.errorColor,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceM,
          vertical: AppTheme.spaceM,
        ),
        hintStyle: TextStyle(
          color: brand.light.onSurfaceVariant,
          fontSize: 14,
        ),
      ),
      
      // أزرار احترافية (زوايا دائرية وظل خفيف)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand.light.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: brand.light.primary.withOpacity(0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceL,
            vertical: AppTheme.spaceM,
          ),
          textStyle: AppTheme.arabicTextTheme.labelLarge,
        ),
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: brand.light.primary,
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: brand.light.outline,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceL,
            vertical: AppTheme.spaceM,
          ),
          textStyle: AppTheme.arabicTextTheme.labelLarge,
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand.light.primary,
          side: BorderSide(
            color: brand.light.primary,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceL,
            vertical: AppTheme.spaceM,
          ),
          textStyle: AppTheme.arabicTextTheme.labelLarge,
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand.light.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceM,
            vertical: AppTheme.spaceS,
          ),
          textStyle: AppTheme.arabicTextTheme.labelMedium,
        ),
      ),
      
      // Premium Chips
      chipTheme: ChipThemeData(
        backgroundColor: brand.light.surfaceContainerHighest,
        selectedColor: brand.light.primary,
        labelStyle: AppTheme.arabicTextTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceM,
          vertical: AppTheme.spaceS,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          side: BorderSide.none,
        ),
      ),
      
      // Bottom Navigation Bar
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: brand.light.primary,
        unselectedItemColor: brand.light.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: AppTheme.arabicTextTheme.labelSmall,
        unselectedLabelStyle: AppTheme.arabicTextTheme.labelSmall,
      ),
      
      // شريط التنقل السفلي (Material 3) — احترافي وواضح
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Colors.white,
        elevation: 8,
        shadowColor: Colors.black.withOpacity(0.08),
        indicatorColor: Color.lerp(brand.light.primary.withOpacity(0.15), brand.light.secondary.withOpacity(0.2), 0.3) ?? brand.light.primary.withOpacity(0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTheme.arabicTextTheme.labelSmall?.copyWith(
              color: brand.light.primary,
              fontWeight: FontWeight.w700,
            );
          }
          return AppTheme.arabicTextTheme.labelSmall?.copyWith(
            color: brand.light.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: brand.light.primary, size: 26);
          }
          return IconThemeData(color: brand.light.onSurfaceVariant, size: 24);
        }),
      ),
      
      // Floating Action Button
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand.light.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
      
      // Divider
      dividerTheme: DividerThemeData(
        color: brand.light.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }

  ThemeData _buildDarkTheme(BrandSchemes brand) {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Cairo',
      brightness: Brightness.dark,
      colorScheme: brand.dark,
      textTheme: AppTheme.arabicTextTheme,
      scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF141414),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 2,
        shadowColor: Colors.black.withOpacity(0.3),
        titleTextStyle: AppTheme.arabicTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
          size: 24,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF1A1A1A),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        margin: const EdgeInsets.symmetric(
          vertical: AppTheme.spaceS,
        ),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide(
            color: brand.dark.outline,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: const BorderSide(
            color: Color(0xFF2A2A2A),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide(
            color: brand.dark.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: const BorderSide(
            color: AppTheme.errorColor,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: const BorderSide(
            color: AppTheme.errorColor,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceM,
          vertical: AppTheme.spaceM,
        ),
        hintStyle: const TextStyle(
          color: Color(0xFF666666),
          fontSize: 14,
        ),
      ),
      
      // Premium Buttons in Dark Mode
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand.dark.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: brand.dark.primary.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceL,
            vertical: AppTheme.spaceM,
          ),
          textStyle: AppTheme.arabicTextTheme.labelLarge,
        ),
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E1E1E),
          foregroundColor: brand.dark.primary,
          elevation: 0,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            side: BorderSide(
              color: brand.dark.outline,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceL,
            vertical: AppTheme.spaceM,
          ),
          textStyle: AppTheme.arabicTextTheme.labelLarge,
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brand.dark.primary,
          side: BorderSide(
            color: brand.dark.primary,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceL,
            vertical: AppTheme.spaceM,
          ),
          textStyle: AppTheme.arabicTextTheme.labelLarge,
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand.dark.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spaceM,
            vertical: AppTheme.spaceS,
          ),
          textStyle: AppTheme.arabicTextTheme.labelMedium,
        ),
      ),
      
      // Premium Chips in Dark Mode
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1E1E1E),
        selectedColor: brand.dark.primary,
        labelStyle: AppTheme.arabicTextTheme.labelMedium?.copyWith(
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceM,
          vertical: AppTheme.spaceS,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          side: BorderSide.none,
        ),
      ),
      
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF141414),
        selectedItemColor: brand.dark.primary,
        unselectedItemColor: const Color(0xFF888888),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: AppTheme.arabicTextTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: AppTheme.arabicTextTheme.labelSmall,
      ),
      
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF141414),
        indicatorColor: brand.dark.primary.withOpacity(0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTheme.arabicTextTheme.labelSmall?.copyWith(
              color: brand.dark.primary,
              fontWeight: FontWeight.bold,
            );
          }
          return AppTheme.arabicTextTheme.labelSmall?.copyWith(
            color: const Color(0xFF888888),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: brand.dark.primary, size: 24);
          }
          return const IconThemeData(color: Color(0xFF888888), size: 24);
        }),
      ),
      
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand.dark.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
      ),
      
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A2A2A),
        thickness: 1,
        space: 1,
      ),
    );
  }
}
