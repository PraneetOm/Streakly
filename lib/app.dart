// import 'package:flutter/material.dart';
// import 'screens/habit_list_screen.dart';

// class HabitTrackerApp extends StatelessWidget {
//   const HabitTrackerApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Habit Tracker',
//       theme: ThemeData(
//         primarySwatch: Colors.indigo,
//         useMaterial3: true,
//       ),
//       home: const HabitListScreen(),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

class HabitTrackerApp extends StatelessWidget {
  const HabitTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Habit Tracker',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[50],
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}