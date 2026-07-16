import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'yard_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KGX Yard Map',
      theme: ThemeData.dark(),
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupController();
  }

  Future<void> _setupController() async {
    await _controller.initializeYardData();
    setState(() {
      _isLoading = false;
    });
  }

List<Widget> _buildSwitchNodes() {
    final List<Widget> nodes = [];

    _controller.switchCoordinates.forEach((switchName, coords) {
      if (coords.length < 2) return;
      final double x = coords[0];
      final double y = coords[1];

      final bool isSwitchClosed = _controller.switchStates[switchName] ?? true;

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
                message: 'Switch $switchName',
                child: Container(
                  width: 24,  
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222), 
                    shape: BoxShape.circle,
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
                        color: isSwitchClosed ? Colors.greenAccent : Colors.redAccent,
                      )
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

  List<Widget> _buildRoadHoverZones() {
    // Defines the precise vertical bounds (Top coordinate, Height) and labels 
    // for the 9 distinct track blocks in the center of your SVG canvas.
    final List<Map<String, dynamic>> zones = [
      {'left': 600.0, 'width': 150, 'top': 35.0, 'height': 40.0,   'label': 'Roads 53 to 59'}, // Blue
      {'left': 530.0, 'width': 150, 'top': 120.0, 'height': 60.0, 'label': 'Roads 46 to 52'}, // Red
      {'left': 520.0, 'width': 180, 'top': 190.0, 'height': 45.0,  'label': 'Roads 40 to 45'}, // Brown
      {'left': 510.0, 'width': 180, 'top': 250.0, 'height': 65.0, 'label': 'Roads 32 to 39'}, // Green
      {'left': 520.0, 'width': 180, 'top': 325.0, 'height': 65.0, 'label': 'Roads 24 to 31'}, // Red
      {'left': 540.0, 'width': 150, 'top': 400.0, 'height': 120.0,  'label': 'Roads 16 to 23'}, // Yellow
      {'left': 570.0, 'width': 130, 'top': 530.0, 'height': 65.0,  'label': 'Roads 8 to 15'},  // Green
      {'left': 540.0, 'width': 160, 'top': 600.0, 'height': 85.0,  'label': 'Roads 1 to 7'},   // Red
      ];

    return zones.map((zone) {
      return Positioned(
        left: zone['left'],         // Anchors right in the middle of the map (green box area)
        width: zone['width'],        // Generous width for easy hovering
        top: zone['top'],
        height: zone['height'],
        child: Tooltip(
          message: zone['label'],
          waitDuration: const Duration(milliseconds: 200),
          child: MouseRegion(
            cursor: SystemMouseCursors.help,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2), // Translucent green fill
                border: Border.all(
                  color: Colors.greenAccent, 
                  width: 2.0, // Bright green outline
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Regenerate the updated SVG code based on switch positions
    final String svgString = _controller.buildDynamicSvgCode();

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('KGX Yard OHTE Control Simulator'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5.0,
          minScale: 0.2, // Allows zooming out further to see the whole yard
          constrained: false, // CRITICAL: Tells Flutter this is an unconstrained 2D canvas
          boundaryMargin: const EdgeInsets.all(200), // Gives comfortable panning space past the edges
          child: Container(
            width: 1605, // Hardcoded to match SVG viewBox width
            height: 1111, // Hardcoded to match SVG viewBox height
            color: Colors.black,
            child: Stack(
                  children: [
                    // Render the dynamically updated SVG string
                    if (svgString.isNotEmpty)
                      SvgPicture.string(
                        svgString,
                        width: 1605,
                        height: 1111,
                      ),
                    
                    // 1. Invisible Road Hover Zones (Placed below switches so they don't block clicks)
                    ..._buildRoadHoverZones(),

                    // 2. Render interactive overlay switches
                    ..._buildSwitchNodes(),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}