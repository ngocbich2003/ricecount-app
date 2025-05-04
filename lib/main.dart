import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/project_list_screen.dart';
import 'screens/auth_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart'; // Thêm import cho theme

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fetch the available cameras before initializing the app.
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    if (kDebugMode) {
      print('Error in fetching the cameras: $e');
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthService(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Riceseed Counter',
      theme: AppTheme.riceSeedTheme, // Sử dụng theme mới
      debugShowCheckedModeBanner: false,
      home: Consumer<AuthService>(
        builder: (context, authService, _) {
          return authService.isLoggedIn
              ? const ProjectListScreen()
              : const AuthScreen();
        },
      ),
    );
  }
}
