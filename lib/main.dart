import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:open_vibrance/widgets/dot_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // initialize acrylic & window_manager
  await acrylic.Window.initialize();
  await windowManager.ensureInitialized();

  runApp(const DotApp());
}

class DotApp extends StatelessWidget {
  const DotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DotWindow(),
    );
  }
}
