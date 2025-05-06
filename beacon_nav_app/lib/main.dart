import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/home_screen.dart';

const apiKey =
    'AIzaSyBTEiIqlnJe4a8L2H9WMPeqFBVTQ2PllYA'; // Replace with your actual API key

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  Gemini.init(apiKey: apiKey, enableDebugging: true);

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(camera: camera),
    );
  }
}
