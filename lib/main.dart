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
    // Start loading the JSON coordinate data asset on boot
    _initFuture = _controller.initializeYardData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kingsrest Marshalling Yard - OHTE Interaction Matrix'),
        backgroundColor: const Color(0xFF1A1A1A),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Yard State',
            onPressed: () {
              setState(() {
                _controller.initializeTrackDefaultStates();
              });
            },
          )
        ],
      ),
      body: FutureBuilder(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error initializing asset engine: ${snapshot.error}'));
          }

          // Once assets are ready, render the desktop Interactive Canvas
          return SelectionArea( // Great for desktop text/labels
            child: InteractiveViewer(
  maxScale: 5.0,
  minScale: 0.2, 
  boundaryMargin: const EdgeInsets.all(600),
  constrained: false, // <-- CRITICAL ADDITION: Stops Flutter from squashing the map to fit the screen
  child: Center(
    child: Container(
      // MATCH YOUR NEW ILLUSTRATOR VIEWBOX EXACTLY:
      width: 1605.08,  // Match your landscape SVG viewBox width
      height: 1111.32, // Match your landscape SVG viewBox height
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Layer 1: The wide blueprint asset frame
          SvgPicture.asset(
            'assets/kgx_yard_map.svg',
            width: 1605.08,
            height: 1111.32,
            fit: BoxFit.none, // Maps the vector paths exactly 1:1 onto your layout coordinates
            alignment: Alignment.topLeft,
          ),
          
          // Layer 2: Clickable Switch Matrix overlays
          ..._buildSwitchOverlayNodes(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Generates the clickable interactive nodes on top of the map coordinates
  List<Widget> _buildSwitchOverlayNodes() {
    List<Widget> nodes = [];
    
    _controller.switchCoordinates.forEach((switchName, coords) {
      // Clean 1:1 data translation: First position = Horizontal X, Second position = Vertical Y
      final double x = (coords[0] as num).toDouble();
      final double y = (coords[1] as num).toDouble();

      nodes.add(
        Positioned(
          left: x - 12, // Automatically snaps onto the exact vector point line width
          top: y - 12,  // Automatically snaps onto the exact vector point line height
          child: MouseRegion(
            cursor: SystemMouseCursors.click,// Changes cursor to hand on desktop pointer hover
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _controller.toggleSwitch(switchName);
                });
              },
              child: Tooltip(
                message: 'Switch $switchName',
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.yellow.withOpacity(0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.yellow, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      switchName, 
                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)
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