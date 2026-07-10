import 'dart:convert';
import 'package:flutter/services.dart';

String rawSvgTemplate = '';

class YardController {
  // Keeps track of which track groups are energized (true) or isolated (false)
  final Map<String, bool> trackStates = {};
  
  // Holds the coordinate locations for all your clickable switch bubbles
  Map<String, List<double>> switchCoordinates = {};

  // 1. Load the JSON data from your asset folder
  Future<void> initializeYardData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/kgx_switch-coords.json');
      switchCoordinates = Map<String, List<double>>.from(jsonDecode(jsonString).map(
        (key, value) => MapEntry(key, List<double>.from(value))
      ));
      
      // Load the raw asset text template once on startup
      rawSvgTemplate = await rootBundle.loadString('assets/kgx_yard_map.svg');
      
      initializeTrackDefaultStates();
    } catch (e) {
      print("Error loading switch coordinates: $e");
    }
  }

  // 2. Set up your default track layout states
  void initializeTrackDefaultStates() {
    List<String> trackGroups = [
      'SeasideOutFeed',
      'LandsideInFeeder1',
      'LandsideInFeeder2',
      'SeasideInFeeder1',
      'SeasideInFeeder2',
      'LandsideOutFeed',
      'C32R53to59',
      'C16R46to52',
      'C17R40to45',
      'C18R32to39',
      'C19R24to31',
      'C20R16to23',
      'C21R8to15',
      'C22R1to7'
    ];

    for (var groupId in trackGroups) {
      trackStates[groupId] = true; // Default to fully energized (colored)
    }
  }

  // Look up dictionary mapping your physical switch button labels to their layout group IDs
  final Map<String, String> _switchMap = {
    'T28': 'C32R53to59',       // Map the JSON label to the SVG group
    'T29': 'C16R46to52',
    'T30': 'C17R40to45',
    'T34': 'C18R32to39',
    'T27': 'C19R24to31',
    'T26': 'C20R16to23',
    'C21': 'C21R8to15',        // Keep if JSON labels match
    'C22': 'C22R1to7',
    'C25': 'LandsideInFeeder2',
    'T31': 'SeasideInFeeder1',
    'C24': 'SeasideInFeeder2',
    'C23': 'LandsideInFeeder1',
    'C10': 'SeasideOutFeed',
    'C15': 'LandsideOutFeed',
  };

// 4. Logic to toggle states when a switch is flipped
  void toggleSwitch(String switchName) {
    // A clean lookup map inside the function to bridge the button label to the SVG group name
    final Map<String, String> switchToGroupMap = {
      'C32': 'C32R53to59',
      'C16': 'C16R46to52',
      'C17': 'C17R40to45',
      'C18': 'C18R32to39',
      'C19': 'C19R24to31',
      'C20': 'C20R16to23',
      'C21': 'C21R8to15',
      'C22': 'C22R1to7',
      'C25': 'LandsideInFeeder2',
      'T31': 'SeasideInFeeder1',
      'C24': 'SeasideInFeeder2',
      'C23': 'LandsideInFeeder1',
      'C10': 'SeasideOutFeed',
      'C15': 'LandsideOutFeed',
    };

    final String? targetGroup = switchToGroupMap[switchName];

    if (targetGroup != null && trackStates.containsKey(targetGroup)) {
      trackStates[targetGroup] = !trackStates[targetGroup]!;
      print("Switch $switchName flipped! Toggled track group: $targetGroup");
    } else {
      print("⚠️ Click registered for '$switchName', but it isn't mapped to a valid track group.");
    }
  }  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;

    // 1. Read the raw, independent state of the parent groups
    bool switchC24Active = trackStates['SeasideInFeeder2'] ?? true;
    bool switchC16Active = trackStates['C16R46to52'] ?? true;
    bool switchC17Active = trackStates['C17R40to45'] ?? true;

    // 2. Compute the cascading interlocking rules live
    Map<String, bool> computedEnergizedStates = {
      // Direct pass-throughs
      'LandsideInFeeder1': trackStates['LandsideInFeeder1'] ?? true,
      'LandsideInFeeder2': trackStates['LandsideInFeeder2'] ?? true,
      'SeasideInFeeder1' : trackStates['SeasideInFeeder1'] ?? true,
      'LandsideOutFeed'  : trackStates['LandsideOutFeed'] ?? true,
      'C18R32to39'       : trackStates['C18R32to39'] ?? true,
      'C19R24to31'       : trackStates['C19R24to31'] ?? true,
      'C20R16to23'       : trackStates['C20R16to23'] ?? true,
      'C21R8to15'        : trackStates['C21R8to15'] ?? true,
      'C22R1to7'         : trackStates['C22R1to7'] ?? true,
      
      // Cascading elements
      'SeasideInFeeder2' : switchC24Active, 
      'C16R46to52'       : switchC16Active && switchC24Active, // C24 turns off C16
      'C17R40to45'       : switchC17Active && switchC24Active, // C24 turns off C17
      'C32R53to59'       : (trackStates['C32R53to59'] ?? true) && switchC16Active && switchC24Active, // C16 or C24 turns off C32
      'SeasideOutFeed'   : (trackStates['SeasideOutFeed'] ?? true) && switchC17Active && switchC24Active, // C17 or C24 turns off C10
    };

    // 3. Apply colors to the layout based on the computed live states
    computedEnergizedStates.forEach((groupId, isEnergized) {
      if (!isEnergized) {
        final String searchString = '<g id="$groupId">';
        int groupStartIndex = workingCopy.indexOf(searchString);
        
        if (groupStartIndex == -1) return;

        int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
        if (groupEndIndex == -1) return;

        String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
        
        groupContent = groupContent.replaceAll('stroke="#ff0000"', 'stroke="#444444"');
        groupContent = groupContent.replaceAll('stroke="#0000ff"', 'stroke="#444444"');
        groupContent = groupContent.replaceAll('stroke="#00ffff"', 'stroke="#444444"');

        groupContent = groupContent.replaceAll('fill="#ff0000"', 'fill="#444444"');
        groupContent = groupContent.replaceAll('fill="#0000ff"', 'fill="#444444"');
        groupContent = groupContent.replaceAll('fill="#00ffff"', 'fill="#444444"');

        workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
      }
    });

    return workingCopy;
  }}