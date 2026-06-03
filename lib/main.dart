import 'package:aptmatepro/features/auth/presentation/dashboard_screen.dart';
import 'package:aptmatepro/features/auth/presentation/login_screen.dart';
import 'package:aptmatepro/features/auth/presentation/splash_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'theme/app_theme.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:responsive_framework/responsive_framework.dart';

// THIS MUST BE A TOP-LEVEL FUNCTION. IT CANNOT BE INSIDE A CLASS.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

// Global notification plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 1. Initialize Local Notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  // Define the settings
  const InitializationSettings initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'), // Ensure this icon exists in android/app/src/main/res/drawable
  );

  // Inject the settings using the strictly required named parameter
  await flutterLocalNotificationsPlugin.initialize(
    settings: initSettings, // EXPLICITLY NAMED PARAMETER
  );


  // 2. Create the Notification Channel for Sound
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Society Alerts',
    importance: Importance.max,
    playSound: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const ProviderScope(child: AptMateApp()));
}

class AptMateApp extends StatelessWidget {
  const AptMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Society',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) => ResponsiveBreakpoints.builder(
        child: ResponsiveScaledBox(
          width: 392, // THIS IS YOUR NARZO 70x BASELINE WIDTH
          child: child!,
        ),
        breakpoints: [
          const Breakpoint(start: 0, end: 450, name: MOBILE),
          const Breakpoint(start: 451, end: 800, name: TABLET),
          const Breakpoint(start: 801, end: 1920, name: DESKTOP),
        ],
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: AppTheme.background,
              body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            );
          }

          // 2. A valid token was found. Wrap the Dashboard in the Splash Screen.
          if (snapshot.hasData && snapshot.data != null) {
            return const SplashScreen(destination: DashboardScreen());
          }

          // 3. No token found. Wrap the Login in the Splash Screen.
          return const SplashScreen(destination: LoginScreen());
        },
      ),
    );
  }
}