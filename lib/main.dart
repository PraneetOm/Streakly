import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/splash_screen.dart'; // Make sure this path is correct
import 'models/habit.dart';
import 'models/session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

    await Supabase.initialize(
    url: 'https://ucrngdoitipxmfgovlrm.supabase.co',	
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVjcm5nZG9pdGlweG1mZ292bHJtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAxODkzMzYsImV4cCI6MjA4NTc2NTMzNn0.ceWrjGgjdJ_TRNn4FnDIw-IaK0sO44alq1wvAUZqXqU',
  );await Hive.initFlutter();
  Hive.registerAdapter(HabitTypeAdapter());
  Hive.registerAdapter(HabitAdapter());
  Hive.registerAdapter(SessionsAdapter());
  Hive.registerAdapter(HabitFrequencyAdapter()); 

  await Hive.openBox<Habit>('habits');
  await Hive.openBox<Sessions>('sessions');
  await Hive.openBox('settings');

  runApp(const HabitTrackerApp());
}

class HabitTrackerApp extends StatelessWidget {
  const HabitTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Habit Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      // 🔥 THIS IS THE FIX: Tell the app to start at the Splash Screen!
      home: const SplashScreen(), 
    );
  }
}