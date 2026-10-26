import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'presentation/chat/chat_screen.dart';

class LainApp extends StatelessWidget {
  const LainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LAIN',
      debugShowCheckedModeBanner: false,
      theme: lainTheme(),
      home: const ChatScreen(),
    );
  }
}
