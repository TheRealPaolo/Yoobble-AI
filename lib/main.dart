import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:meta_seo/meta_seo.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';
import 'models/user.dart';
import 'services/authentication.dart';
import 'services/database.dart';
import 'stripe/paywall.dart';
import 'templates/splashscreen_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotjsonenv.load(fileName: "local.json");
  if (kIsWeb) {
    MetaSEO().config();
  }

  await Firebase.initializeApp(
      options: const FirebaseOptions(
          apiKey: "",
          authDomain: "",
          projectId: "",
          storageBucket: "",
          messagingSenderId: "",
          appId: "",
          measurementId: ""));

  // Add MetaSEO just into Web platform condition
  if (kIsWeb) {
    // Define MetaSEO object
    MetaSEO meta = MetaSEO();
    // add meta seo data for web app as you want
    meta.author(author: 'Paolo');
    meta.description(
        description:
            'Revolutionize Document Analysis with PyperStrategy, PyperStrategy is an advanced document analysis tool designed to streamline your workflow,\nproviding in-depth insights and saving you valuable time');
    meta.keywords(
        keywords:
            'Document, AI, Analysis, ChatPDF, PyperStrategy, Unlock, Financial ,Insights, Financial Insights,Instant Analysis ,Forecasting, Invoices , Receipts, Balance Sheets , Income Statements,Correspondence, Emails , Reports , Studies, CV, Cover Letters, resume, Payroll ,Onboarding Forms, Contract, Legal Acts ,Procedures legal document');
  }

  runApp(
    MultiProvider(
      providers: [
        StreamProvider<AppUser?>.value(
          initialData: null,
          value: AuthenticationService().user,
        ),
        StreamProvider<List<AppUserData>>.value(
          initialData: const [],
          value: DatabaseService().users,
        ),
        Provider<SubscriptionBottomSheet>(
            create: (_) => const SubscriptionBottomSheet()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, deviceType) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Yoobble',
          home: const SplashScreenWrapper(),
          theme: ThemeData.light(),
        );
      },
    );
  }
}
