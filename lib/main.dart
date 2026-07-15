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

      // Retrieve state of target track group linked to this switch
      final String? targetGroup = _controller.switchMap[switchName];
      final bool isSwitchClosed = _controller.trackStates[targetGroup] ?? false;

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
      body: InteractiveViewer(
        maxScale: 5.0,
        minScale: 0.5,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
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
                    
                    // Render interactive overlay switches
                    ..._buildSwitchNodes(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}