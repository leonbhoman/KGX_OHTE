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

// Retrieve the current state of this switch (defaulting to false if unknown)
      bool isSwitchClosed = _controller.switchStates[switchName] ?? false;

      nodes.add(
        Positioned(
          left: x - 12, 
          top: y - 12,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, 
              onTap: () {
                setState(() {
                  _controller.toggleSwitch(switchName);
                });
              },
              child: Tooltip(
                message: 'Switch $switchName (${isSwitchClosed ? "Closed / ON" : "Open / OFF"})',
                child: Container(
                  width: 24,  
                  height: 24,
                  decoration: BoxDecoration(
                    // Solid dark background
                    color: const Color(0xFF222222), 
                    shape: BoxShape.circle,
                    // BORDER turns Green when Closed (ON), and Red when Open (OFF)
                    border: Border.all(
                      color: isSwitchClosed ? Colors.greenAccent : Colors.redAccent, 
                      width: 2.5
                    ),
                  ),
                  child: Center(
                    child: Text(
                      switchName, 
                      style: TextStyle(
                        fontSize: 8, 
                        fontWeight: FontWeight.bold, 
                        // Text changes color to match the border status
                        color: isSwitchClosed ? Colors.greenAccent : Colors.redAccent,
                      )
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );    });

    return nodes;
  }
}