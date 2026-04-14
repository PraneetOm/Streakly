import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  String _imageUrl = 'https://i.ibb.co/C5G3cTCP/image-2026-04-14-190706911.png';
  
  late AnimationController _masterController;
  late Animation<double> _logoOpacity;
  late Animation<double> _imageOpacity;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _textSlide;

  final List<Map<String, String>> _quotes = [
    {"title": "Win The Day.", "subtitle": "Consistency is the only bridge between you and your goals."},
    {"title": "Keep Pushing.", "subtitle": "Small daily habits build monumental long-term results."},
    {"title": "Stay Focused.", "subtitle": "Motivation gets you started. Habit keeps you going."},
    {"title": "Own Your Time.", "subtitle": "What you do today is important because you are exchanging a day of your life for it."},
    {"title": "Trust The Process.", "subtitle": "Success doesn't come from what you do occasionally, it comes from what you do consistently."}
  ];
  late Map<String, String> _todaysQuote;

  @override
  void initState() {
    super.initState();
    _todaysQuote = _quotes[Random().nextInt(_quotes.length)];
    
    _masterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
    
    _logoOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 15),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 55),
    ]).animate(_masterController);

    _imageOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _masterController, curve: const Interval(0.40, 0.60, curve: Curves.easeIn))
    );

    _textSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _masterController, curve: const Interval(0.45, 0.65, curve: Curves.easeOutCubic))
    );

    // 🔥 FIX: Reduced zoom from 1.15 to 1.1 to prevent aggressive cropping
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _masterController, curve: Curves.easeOutCubic)
    );

    _loadDataAndTransition();
  }

  Future<void> _loadDataAndTransition() async {
    final settingsBox = Hive.box('settings');
    String? savedImage = settingsBox.get('startup_image');
    
    if (savedImage != null && !savedImage.startsWith('http')) {
      if (!File(savedImage).existsSync()) {
        savedImage = _imageUrl; 
        settingsBox.put('startup_image', _imageUrl); 
      }
    }

    if (savedImage != null && mounted) {
      setState(() => _imageUrl = savedImage.toString());
    }

    await _masterController.forward();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 1000), 
          pageBuilder: (_, _, _) => const HomeScreen(),
          transitionsBuilder: (_, animation, _, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  ImageProvider _getImageProvider(String path) {
    if (path.startsWith('http')) {
      return NetworkImage(path);
    } else {
      return FileImage(File(path));
    }
  }

  @override
  void dispose() {
    _masterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      body: Stack(
        fit: StackFit.expand, // 🔥 CRITICAL FIX 1: Forces the Stack to fill the entire screen!
        children: [
          FadeTransition(
            opacity: _imageOpacity,
            child: Stack(
              fit: StackFit.expand, // 🔥 CRITICAL FIX 2: Forces inner stack to fill screen
              children: [
                // Zooming Image
                Positioned.fill(
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Image(
                      image: _getImageProvider(_imageUrl),
                      fit: BoxFit.cover, // Cover ensures no black bars
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                
                // Dark Overlay for readability
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.1),
                          Colors.black.withValues(alpha: 0.6),
                          Colors.black.withValues(alpha: 0.95),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),

                // Sliding/Fading Quote
                SafeArea(
                  child: SizedBox(
                    width: double.infinity, // 🔥 CRITICAL FIX 3: Forces text column to stretch fully
                    child: SlideTransition(
                      position: _textSlide,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end, 
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                              ),
                              child: const Icon(Icons.local_fire_department_rounded, color: Colors.orangeAccent, size: 24),
                            ),
                            const SizedBox(height: 24),
                            
                            Text(
                              _todaysQuote['title']!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.5,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            Text(
                              _todaysQuote['subtitle']!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 32),
                            
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: const SizedBox(
                                height: 3, width: 60,
                                child: LinearProgressIndicator(
                                  backgroundColor: Colors.white24,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          FadeTransition(
            opacity: _logoOpacity,
            child: Container(
              color: Colors.black, 
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded, 
                      color: Colors.orangeAccent, 
                      size: 72
                    ),
                    SizedBox(height: 16),
                    Text(
                      "Streakly",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// import 'dart:io';
// import 'dart:math';
// import 'package:flutter/material.dart';
// import 'package:hive_flutter/hive_flutter.dart';
// import 'home_screen.dart';

// class SplashScreen extends StatefulWidget {
//   const SplashScreen({super.key});

//   @override
//   State<SplashScreen> createState() => _SplashScreenState();
// }

// class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
//   String _imageUrl = 'https://images.unsplash.com/photo-1552508744-1696d4464960?q=80&w=2070&auto=format&fit=crop';
  
//   late AnimationController _masterController;
//   late Animation<double> _logoOpacity;
//   late Animation<double> _imageOpacity;
//   late Animation<double> _scaleAnimation;
//   late Animation<Offset> _textSlide;

//   final List<Map<String, String>> _quotes = [
//     {"title": "Win The Day.", "subtitle": "Consistency is the only bridge between you and your goals."},
//     {"title": "Keep Pushing.", "subtitle": "Small daily habits build monumental long-term results."},
//     {"title": "Stay Focused.", "subtitle": "Motivation gets you started. Habit keeps you going."},
//     {"title": "Own Your Time.", "subtitle": "What you do today is important because you are exchanging a day of your life for it."},
//     {"title": "Trust The Process.", "subtitle": "Success doesn't come from what you do occasionally, it comes from what you do consistently."}
//   ];
//   late Map<String, String> _todaysQuote;

//   @override
//   void initState() {
//     super.initState();
//     _todaysQuote = _quotes[Random().nextInt(_quotes.length)];
    
//     // 🔥 Total animation time: 4.2 seconds
//     _masterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
    
//     // 1. Logo Sequence: Fade In (0-15%), Hold (15-30%), Fade Out (30-45%), Stay Hidden (45-100%)
//     _logoOpacity = TweenSequence<double>([
//       TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 15),
//       TweenSequenceItem(tween: ConstantTween(1.0), weight: 15),
//       TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
//       TweenSequenceItem(tween: ConstantTween(0.0), weight: 55),
//     ]).animate(_masterController);

//     // 2. Image Fade In: Starts exactly as the logo starts fading out (40% - 60%)
//     _imageOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
//       CurvedAnimation(parent: _masterController, curve: const Interval(0.40, 0.60, curve: Curves.easeIn))
//     );

//     // 3. Text Slide Up: Slides up smoothly as the image fades in
//     _textSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
//       CurvedAnimation(parent: _masterController, curve: const Interval(0.45, 0.65, curve: Curves.easeOutCubic))
//     );

//     // 4. Ken Burns Zoom: Slow, continuous zoom from start to finish
//     _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
//       CurvedAnimation(parent: _masterController, curve: Curves.easeOutCubic)
//     );

//     _loadDataAndTransition();
//   }

//   Future<void> _loadDataAndTransition() async {
//     final settingsBox = Hive.box('settings');
//     String? savedImage = settingsBox.get('startup_image');
    
//     // Check if local file was deleted by OS
//     if (savedImage != null && !savedImage.startsWith('http')) {
//       if (!File(savedImage).existsSync()) {
//         savedImage = _imageUrl; 
//         settingsBox.put('startup_image', _imageUrl); 
//       }
//     }

//     if (savedImage != null && mounted) {
//       setState(() => _imageUrl = savedImage.toString());
//     }

//     // Play the full 4.2-second timeline
//     await _masterController.forward();

//     // Transition smoothly to HomeScreen
//     if (mounted) {
//       Navigator.pushReplacement(
//         context,
//         PageRouteBuilder(
//           transitionDuration: const Duration(milliseconds: 1000), 
//           pageBuilder: (_, __, ___) => const HomeScreen(),
//           transitionsBuilder: (_, animation, __, child) {
//             return FadeTransition(opacity: animation, child: child);
//           },
//         ),
//       );
//     }
//   }

//   ImageProvider _getImageProvider(String path) {
//     if (path.startsWith('http')) {
//       return NetworkImage(path);
//     } else {
//       return FileImage(File(path));
//     }
//   }

//   @override
//   void dispose() {
//     _masterController.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.black, // Base layer
//       body: Stack(
//         children: [
//           // ==========================================
//           // LAYER 1: The Custom Background & Quote (Fades in later)
//           // ==========================================
//           FadeTransition(
//             opacity: _imageOpacity,
//             child: Stack(
//               children: [
//                 // Zooming Image
//                 Positioned.fill(
//                   child: ScaleTransition(
//                     scale: _scaleAnimation,
//                     child: Image(
//                       image: _getImageProvider(_imageUrl),
//                       fit: BoxFit.cover,
//                       filterQuality: FilterQuality.high,
//                     ),
//                   ),
//                 ),
                
//                 // Dark Overlay for readability
//                 Positioned.fill(
//                   child: Container(
//                     decoration: BoxDecoration(
//                       gradient: LinearGradient(
//                         colors: [
//                           Colors.black.withValues(alpha: 0.1),
//                           Colors.black.withValues(alpha: 0.6),
//                           Colors.black.withValues(alpha: 0.95),
//                         ],
//                         stops: const [0.0, 0.5, 1.0],
//                         begin: Alignment.topCenter,
//                         end: Alignment.bottomCenter,
//                       ),
//                     ),
//                   ),
//                 ),

//                 // Sliding/Fading Quote
//                 SafeArea(
//                   child: SlideTransition(
//                     position: _textSlide,
//                     child: Padding(
//                       padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
//                       child: Column(
//                         mainAxisAlignment: MainAxisAlignment.end, 
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           // Small glowing brand icon
//                           Container(
//                             padding: const EdgeInsets.all(10),
//                             decoration: BoxDecoration(
//                               color: Colors.orange.withValues(alpha: 0.2),
//                               borderRadius: BorderRadius.circular(14),
//                               border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
//                             ),
//                             child: const Icon(Icons.local_fire_department_rounded, color: Colors.orangeAccent, size: 24),
//                           ),
//                           const SizedBox(height: 24),
                          
//                           Text(
//                             _todaysQuote['title']!,
//                             style: const TextStyle(
//                               color: Colors.white,
//                               fontSize: 42,
//                               fontWeight: FontWeight.w900,
//                               letterSpacing: -1.5,
//                               height: 1.1,
//                             ),
//                           ),
//                           const SizedBox(height: 12),
                          
//                           Text(
//                             _todaysQuote['subtitle']!,
//                             style: TextStyle(
//                               color: Colors.white.withValues(alpha: 0.75),
//                               fontSize: 16,
//                               fontWeight: FontWeight.w500,
//                               height: 1.5,
//                               letterSpacing: 0.2,
//                             ),
//                           ),
//                           const SizedBox(height: 32),
                          
//                           // Tiny elegant loading bar
//                           ClipRRect(
//                             borderRadius: BorderRadius.circular(10),
//                             child: const SizedBox(
//                               height: 3, width: 60,
//                               child: LinearProgressIndicator(
//                                 backgroundColor: Colors.white24,
//                                 color: Colors.white,
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),

//           // ==========================================
//           // LAYER 2: The "Streakly" Brand Reveal (Fades in first, then disappears)
//           // ==========================================
//           FadeTransition(
//             opacity: _logoOpacity,
//             child: Container(
//               color: Colors.black, // Blocks the background until it fades
//               child: const Center(
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Icon(
//                       Icons.local_fire_department_rounded, 
//                       color: Colors.orangeAccent, 
//                       size: 72
//                     ),
//                     SizedBox(height: 16),
//                     Text(
//                       "Streakly",
//                       style: TextStyle(
//                         color: Colors.white,
//                         fontSize: 48,
//                         fontWeight: FontWeight.w900,
//                         letterSpacing: -2.0,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }