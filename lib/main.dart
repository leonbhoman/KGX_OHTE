import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'yard_controller.dart';

void main() {
  runApp(const KgxOhteApp());
}

class KgxOhteApp extends StatelessWidget {
  const KgxOhteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KGX OHTE Interactive Diagram',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF111111), // Match your dark SVG background
      ),
      home: const YardMapScreen(),
    );
  }
}

class YardMapScreen extends StatefulWidget {
  const YardMapScreen({super.key});

  @override
  State<YardMapScreen> createState() => _YardMapScreenState();
}

class _YardMapScreenState extends State<YardMapScreen> {
  final YardController _controller = YardController();
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _controller.initializeYardData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kingsrest Marshalling Yard - OHTE Isolation Map'),
        elevation: 2,
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error loading layout: ${snapshot.error}'));
          }

          return SizedBox.expand(
            child: InteractiveViewer(
              minScale: 0.2,
              maxScale: 5.0,
              constrained: false, // Keeps your map reading horizontally layout-wide
              boundaryMargin: const EdgeInsets.all(500),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Stack(
                  children: [
                    // Layer 1: Base SVG map
                    SvgPicture.string(
                      _controller.buildDynamicSvgCode(),
                      width: 1605.08,
                      height: 1111.32,
                      fit: BoxFit.none,
                      alignment: Alignment.topLeft,
                    ),
                    // Layer 2: Clickable switch overlays
                    ..._buildSwitchNodes(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // This defines the missing method cleanly within the state class bounds
  List<Widget> _buildSwitchNodes() {
    final List<Widget> nodes = [];

    _controller.switchCoordinates.forEach((switchName, coords) {
      if (coords.length < 2) return;
      final double x = (coords[0] as num).toDouble();
      final double y = (coords[1] as num).toDouble();

      nodes.add(
        Positioned(
          left: x - 12, // Perfectly centers your 24px button over the coordinate point
          top: y - 12,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // Tells Flutter: treat the whole box area as clickable
              onTap: () {
                setState(() {
                  _controller.toggleSwitch(switchName);
                });
              },
              child: Tooltip(
                message: 'Switch $switchName',
                child: Container(
                  width: 24,  // Keeping your preferred compact dimensions
                  height: 24,
                  decoration: BoxDecoration(
                    // Solid dark background color captures clicks 100% across the circle's interior
                    color: const Color(0xFF222222), 
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.yellow, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      switchName, 
                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.yellow)
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });

    return nodes;
  }
}