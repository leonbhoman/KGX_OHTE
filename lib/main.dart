import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String _searchQuery = '';

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

  // Quick-toggle switch from search input
  void _submitSearch(String query) {
    final formattedQuery = query.trim().toUpperCase();
    if (_controller.switchStates.containsKey(formattedQuery)) {
      setState(() {
        _controller.toggleSwitch(formattedQuery);
        _searchController.clear();
        _searchQuery = '';
      });
    }
  }

  // --- PRINTING HANDLER ---
  Future<void> _handlePrint() async {
    final pdf = pw.Document();

    final printSvg = _controller.buildPrintableSvgCode();
    final isolatedText = _controller.getIsolatedSwitchesSummary();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'KGX Yard OHTE Control Diagram',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Isolated Switches: $isolatedText',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.red900,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Expanded(
                child: pw.SvgImage(svg: printSvg),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'KGX_OHTE_Diagram.pdf',
    );
  }

  List<Widget> _buildSwitchNodes() {
    final List<Widget> nodes = [];

    _controller.switchCoordinates.forEach((switchName, coords) {
      if (coords.length < 2) return;
      final double x = coords[0];
      final double y = coords[1];

      final bool isSwitchClosed = _controller.switchStates[switchName] ?? true;
      final bool isSearchMatch = _searchQuery.isNotEmpty && 
          switchName.toUpperCase().contains(_searchQuery);

      nodes.add(
        Positioned(
          left: x - 14, 
          top: y - 14,
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
                message: 'Switch $switchName (Click to toggle)',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: isSearchMatch ? 28 : 24,  
                  height: isSearchMatch ? 28 : 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222), 
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSearchMatch 
                          ? Colors.amberAccent 
                          : (isSwitchClosed ? Colors.greenAccent : Colors.redAccent), 
                      width: isSearchMatch ? 3.5 : 2.5,
                    ),
                    boxShadow: isSearchMatch
                        ? [const BoxShadow(color: Colors.amberAccent, blurRadius: 8, spreadRadius: 2)]
                        : [],
                  ),
                  child: Center(
                    child: Text(
                      switchName, 
                      style: TextStyle(
                        fontSize: 8, 
                        fontWeight: FontWeight.bold, 
                        color: isSearchMatch 
                            ? Colors.amberAccent 
                            : (isSwitchClosed ? Colors.greenAccent : Colors.redAccent),
                      ),
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
    final List<Map<String, dynamic>> zones = [
      {'left': 600.0, 'width': 150, 'top': 35.0, 'height': 40.0,   'label': 'Roads 53 to 59'},
      {'left': 530.0, 'width': 150, 'top': 120.0, 'height': 60.0, 'label': 'Roads 46 to 52'},
      {'left': 520.0, 'width': 180, 'top': 190.0, 'height': 45.0,  'label': 'Roads 40 to 45'},
      {'left': 510.0, 'width': 180, 'top': 250.0, 'height': 65.0, 'label': 'Roads 32 to 39'},
      {'left': 520.0, 'width': 180, 'top': 325.0, 'height': 65.0, 'label': 'Roads 24 to 31'},
      {'left': 540.0, 'width': 150, 'top': 400.0, 'height': 120.0,  'label': 'Roads 16 to 23'},
      {'left': 575.0, 'width': 125, 'top': 530.0, 'height': 65.0,  'label': 'Roads 8 to 15'},
      {'left': 540.0, 'width': 160, 'top': 600.0, 'height': 85.0,  'label': 'Roads 1 to 7'},
    ];

    return zones.map((zone) {
      return Positioned(
        left: zone['left'],
        width: zone['width'],
        top: zone['top'],
        height: zone['height'],
        child: Tooltip(
          message: zone['label'],
          waitDuration: const Duration(milliseconds: 200),
          child: MouseRegion(
            cursor: SystemMouseCursors.help,
            child: const SizedBox.expand(),
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

    final String svgString = _controller.buildDynamicSvgCode();

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('KGX Yard OHTE Control Simulator'),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          Container(
            width: 180,
            height: 36,
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Search switch...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toUpperCase();
                });
              },
              onSubmitted: _submitSearch,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print Diagram',
            onPressed: _handlePrint,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5.0,
          minScale: 0.2,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(200),
          child: Container(
            width: 1605,
            height: 1111,
            color: Colors.black,
            child: Stack(
              children: [
                if (svgString.isNotEmpty)
                  SvgPicture.string(
                    svgString,
                    width: 1605,
                    height: 1111,
                  ),
                ..._buildRoadHoverZones(),
                ..._buildSwitchNodes(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}