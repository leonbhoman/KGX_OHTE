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

  // --- PLANNER / OCCUPATION FIELD CONTROLLERS ---
  final TextEditingController _plannerController = TextEditingController();
  final TextEditingController _technicianController = TextEditingController();
  final TextEditingController _noticeController = TextEditingController();
  final TextEditingController _timeGrantedController = TextEditingController();
  final TextEditingController _timeReturnedController = TextEditingController();

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

  // --- PRINTING HANDLER WITH METADATA HEADER ---
  Future<void> _handlePrint() async {
    final pdf = pw.Document();

    final printSvg = _controller.buildPrintableSvgCode();
    final isolatedText = _controller.getIsolatedSwitchesSummary();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Title Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'KGX YARD OHTE ISOLATION DIAGRAM',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'Notice / Occ #: ${_noticeController.text.isEmpty ? 'N/A' : _noticeController.text}',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),

              // Planner & Technician Metadata Box
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey600, width: 1),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Planner: ${_plannerController.text.isEmpty ? '________' : _plannerController.text}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Technician: ${_technicianController.text.isEmpty ? '________' : _technicianController.text}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Time Granted: ${_timeGrantedController.text.isEmpty ? '________' : _timeGrantedController.text}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Time Returned: ${_timeReturnedController.text.isEmpty ? '________' : _timeReturnedController.text}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),

              // Isolated Switches & Section Insulators Summary Banner
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                color: PdfColors.red100,
                child: pw.Text(
                  'ISOLATED SWITCHES & INSULATORS: $isolatedText',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.red900,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),

              // SVG Map Section
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
      name: 'KGX_OHTE_Isolation_Plan.pdf',
    );
  }

  Widget _buildPlannerField(String label, TextEditingController controller, {double width = 120}) {
    return Container(
      width: width,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide.none,
          ),
        ),
      ),
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
    final String isolatedSummary = _controller.getIsolatedSwitchesSummary();

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('KGX Yard OHTE Occupation Switching            OCC Control Telephone 011 544 9785', style: TextStyle(fontSize: 16)),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          // Planner Metadata Inputs
          _buildPlannerField('Planner', _plannerController, width: 110),
          _buildPlannerField('Technician', _technicianController, width: 110),
          _buildPlannerField('Occ / Notice #', _noticeController, width: 100),
          _buildPlannerField('Time Granted', _timeGrantedController, width: 90),
          _buildPlannerField('Time Returned', _timeReturnedController, width: 90),

          // Search Switch Input
          Container(
            width: 130,
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 11),
                prefixIcon: const Icon(Icons.search, size: 14, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 12, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 6),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
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

        // Live updating de-energized switches & section insulators banner
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28.0),
          child: Container(
            width: double.infinity,
            color: const Color(0xFF2D1515),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.redAccent),
                  const SizedBox(width: 6),
                  const Text(
                    'ISOLATED SWITCHES & SECTION INSULATORS: ',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent),
                  ),
                  Text(
                    isolatedSummary,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
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