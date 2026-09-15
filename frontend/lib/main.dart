/// App entry point.
///
/// Sets up the Riverpod [ProviderScope], applies the CRED-inspired theme,
/// and configures GoRouter for declarative navigation.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/api_service.dart';
import 'core/theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/manage_screen.dart';
import 'screens/transactions_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Splash screen (shown while the persisted session is checked)
// ═══════════════════════════════════════════════════════════════════════════

class _SplashScreen extends ConsumerStatefulWidget {
  const _SplashScreen();

  @override
  ConsumerState<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Check persisted auth state on launch
    Future.microtask(() => ref.read(authProvider.notifier).checkSession());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet,
                size: 64, color: AppColors.neonGreen),
            const SizedBox(height: AppSpacing.md),
            Text('Expense Tracker', style: AppTypography.displaySmall),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Router
// ═══════════════════════════════════════════════════════════════════════════

final routerProvider = Provider<GoRouter>((ref) {
  // Listen to auth state changes to trigger redirects
  final authStatus = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    // Chatty in release; only useful while developing routing.
    debugLogDiagnostics: kDebugMode,

    // ── Redirect logic ──────────────────────────────────────────────
    redirect: (context, state) {
      final isAuth = authStatus == AuthStatus.authenticated;
      final isLoggingIn = state.matchedLocation == '/login';
      final isSplash = state.matchedLocation == '/';

      // Still checking session → stay on splash
      if (authStatus == AuthStatus.unknown) return null;

      // Not logged in → send to login (unless already there)
      if (!isAuth && !isLoggingIn) return '/login';

      // Logged in but on login/splash → send to home
      if (isAuth && (isLoggingIn || isSplash)) return '/home';

      return null;
    },

    // ── Routes ──────────────────────────────────────────────────────
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/manage',
        builder: (context, state) => const ManageScreen(),
      ),
      GoRoute(
        path: '/transactions',
        builder: (context, state) => const TransactionsScreen(),
      ),
    ],
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// App widget
// ═══════════════════════════════════════════════════════════════════════════

class ExpenseTrackerApp extends ConsumerWidget {
  const ExpenseTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Expense Tracker',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// main()
// ═══════════════════════════════════════════════════════════════════════════

/// Declare the bundled fonts on the app's licences page.
///
/// Space Grotesk and Inter are both SIL OFL 1.1, which requires the licence
/// to be distributed with the font. `google_fonts` used to do this for us;
/// now that the files are in `assets/fonts/`, we do it ourselves.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in const {
      'SpaceGrotesk': 'assets/fonts/SpaceGrotesk-OFL.txt',
      'Inter': 'assets/fonts/Inter-OFL.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks(
        [entry.key],
        await rootBundle.loadString(entry.value),
      );
    }
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();

  // Lock to portrait + set system UI overlay
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.trueBlack,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    const ProviderScope(
      child: ExpenseTrackerApp(),
    ),
  );
}
