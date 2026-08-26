import 'dart:convert';
import 'package:flutter/services.dart';

String rawSvgTemplate = '';

class YardController {
  // Map containing the ON/OFF toggle states for every switch button (true = closed/ON, false = open/OFF)
  final Map<String, bool> switchStates = {};

  // Computed states for each colored SVG track group (true = energized, false = dead/gray)
  final Map<String, bool> trackStates = {};

  // Coordinate map for rendering clickable switch overlays
  Map<String, List<double>> switchCoordinates = {};

  Future<void> initializeYardData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/kgx_switch-coords.json');
      switchCoordinates = Map<String, List<double>>.from(
        jsonDecode(jsonString).map((key, value) => MapEntry(key, List<double>.from(value)))
      );

      rawSvgTemplate = await rootBundle.loadString('assets/kgx_yard_map.svg');

      // Initialize all switches as closed (ON) by default
      initializeDefaultStates();
      recalculateYardStates();
    } catch (e) {
      print("Error loading yard data: $e");
    }
  }

  void initializeDefaultStates() {
    List<String> allSwitches = [
      'C10', 'C12', 'C13', 'C14', 'C15', 'C16', 'C17', 'C18', 
      'C19', 'C20', 'C21', 'C22', 'C23', 'C24', 'C25', 'C32', 'C35'
    ];
    for (var sw in allSwitches) {
      switchStates[sw] = true;
    }
  }

  void toggleSwitch(String switchName) {
    if (switchStates.containsKey(switchName)) {
      switchStates[switchName] = !switchStates[switchName]!;
      recalculateYardStates();
    }
  }

  /// Calculates electrical energization for all track segments based on switch states
  void recalculateYardStates() {
    // Helper function to read switch state safely
    bool isClosed(String name) => switchStates[name] ?? true;

    // --- STEP 1: DEFINE FEED BUSES & SEASIDE BIDIRECTIONAL FLOW ---
    
    // Landside Inbound Bus (Power right after C25)
    bool landsideInboundBusHasPower = isClosed('C25');

    // Landside Outfeed Bus (Right-hand common rail for C12-C15)
    bool landsideOutfeedHasPower = landsideInboundBusHasPower && 
        (isClosed('C12') || isClosed('C13') || isClosed('C14') || isClosed('C15') || isClosed('C18'));

    // Seaside Raw Forward Feeder (Left side of C24)
    final bool rawSeasideFeeder = true;
    final bool seasideForwardSupply = rawSeasideFeeder && isClosed('C24');

    // Seaside Outfeed Rail (at C10 / C35 boundary):
    // Hot if forward supply reaches C10 (C24 ON && C17 ON && C10 ON),
    // OR if C35 is ON and Landside is feeding power from below!
    bool seasideOutfeedHasPower = (seasideForwardSupply && isClosed('C17') && isClosed('C10')) ||
        (isClosed('C35') && landsideOutfeedHasPower);

    // If Seaside Outfeed got power from C35, update Landside Outfeed back-feed logic:
    if (isClosed('C35') && seasideOutfeedHasPower) {
      landsideOutfeedHasPower = true;
    }

    // Resolve Landside Inbound Bus back-feed (if C25 is OFF but C35/Landside Outfeed is live):
    if (!landsideInboundBusHasPower && landsideOutfeedHasPower) {
      if ((isClosed('C12') && isClosed('C19')) ||
          (isClosed('C13') && isClosed('C20')) ||
          (isClosed('C14') && isClosed('C21')) ||
          (isClosed('C15') && isClosed('C22')) ||
          isClosed('C18')) {
        landsideInboundBusHasPower = true;
      }
    }

    // --- STEP 2: ASSIGN COMPUTED TRACK STATES ---

    // A. Seaside Track Sections (Bidirectional through C10 & C17 back to C24)
    trackStates['C16R46to52'] = seasideForwardSupply && isClosed('C16');
    trackStates['C32R53to59'] = trackStates['C16R46to52']! && isClosed('C32');
    trackStates['SeasideOutFeed'] = seasideOutfeedHasPower;
    trackStates['C17R40to45'] = seasideForwardSupply || (seasideOutfeedHasPower && isClosed('C10'));

    // B. Landside Common Rails
    trackStates['LandsideOutFeed'] = landsideOutfeedHasPower;
    trackStates['LandsideInFeeder2'] = isClosed('C25') || landsideInboundBusHasPower;

    // C. Middle Yard Tracks
    trackStates['C18R32to39'] = landsideInboundBusHasPower && isClosed('C18');
    trackStates['C19R24to31'] = (landsideInboundBusHasPower && isClosed('C19')) || (landsideOutfeedHasPower && isClosed('C12'));
    trackStates['C20R16to23'] = (landsideInboundBusHasPower && isClosed('C20')) || (landsideOutfeedHasPower && isClosed('C13'));
    trackStates['C21R8to15']  = (landsideInboundBusHasPower && isClosed('C21')) || (landsideOutfeedHasPower && isClosed('C14'));
    trackStates['C22R1to7']   = (landsideInboundBusHasPower && isClosed('C22')) || (landsideOutfeedHasPower && isClosed('C15'));

    // D. Feeders & Isolators
    trackStates['SeasideInFeeder1'] = true; 
    trackStates['LandsideInFeeder1'] = true;
    trackStates['SeasideInFeeder2'] = seasideForwardSupply;
    trackStates['C35_Isolator'] = isClosed('C35');
  }

  /// Re-colors the SVG template according to `trackStates`
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;

    trackStates.forEach((groupId, isEnergized) {
      if (!isEnergized) {
        String searchString = '<g id="_$groupId">';
        int groupStartIndex = workingCopy.indexOf(searchString);
        
        if (groupStartIndex == -1) {
          searchString = '<g id="$groupId">';
          groupStartIndex = workingCopy.indexOf(searchString);
        }
        
        if (groupStartIndex != -1) {
          int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
          
          if (groupEndIndex != -1) {
            String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
            
            // Turn non-energized tracks gray (#444444)
            groupContent = groupContent.replaceAll('stroke="#0000ff"', 'stroke="#444444"');
            groupContent = groupContent.replaceAll('fill="#0000ff"', 'fill="#444444"'); 
            groupContent = groupContent.replaceAll('stroke="#00ffff"', 'stroke="#444444"');
            groupContent = groupContent.replaceAll('fill="#00ffff"', 'fill="#444444"'); 
            
            workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
          }
        }
      }
    });

    return workingCopy;
  }
}