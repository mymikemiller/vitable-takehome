import 'package:flutter/material.dart';
import 'services/chat_api_service.dart';
import 'state/chat_controller.dart';
import 'theme/app_theme.dart';
import 'ui/chat_screen.dart';

void main() {
  runApp(const VitableApp());
}

class VitableApp extends StatefulWidget {
  const VitableApp({super.key});

  @override
  State<VitableApp> createState() => _VitableAppState();
}

class _VitableAppState extends State<VitableApp> {
  // ChatController is instantiated once here and injected via constructors.
  // No global singletons — architecture is testable and extensible.
  late final ChatController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChatController(
      apiService: ChatApiService(
        // Backend URL — update for production deployment.
        // For local dev: http://localhost:8000
        baseUrl: 'https://vitable-takehome-backend.onrender.com',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vitable Health',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: ChatScreen(controller: _controller),
    );
  }
}
