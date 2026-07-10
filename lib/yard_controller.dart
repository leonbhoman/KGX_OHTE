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

  // 2. Set up your default switch button states
  void initializeTrackDefaultStates() {
    // Register the actual switch button names rather than raw layout groups
    _switchMap.keys.forEach((switchName) {
      trackStates[switchName] = true; // Default to closed/energized
    });
  }

  // 3. Maps each clickable switch name directly to its corresponding SVG track group
  final Map<String, String> _switchMap = {
    'C32' : 'C32R53to59',
    'C16' : 'C16R46to52',
    'C17' : 'C17R40to45',
    'C18' : 'C18R32to39',
    'C19' : 'C19R24to31',
    'C20' : 'C20R16to23',
    'C21' : 'C21R8to15',
    'C22' : 'C22R1to7',
    'C25' : 'LandsideInFeeder2', 
    'T31' : 'SeasideInFeeder1', 
    'C24' : 'SeasideInFeeder2', 
    'C23' : 'LandsideInFeeder1', 
    'C10' : 'SeasideOutFeed', 
    'C15' : 'LandsideOutFeed' 
  };

  // 4. Logic to toggle states when a switch is flipped
  void toggleSwitch(String switchName) {
    if (trackStates.containsKey(switchName)) {
      trackStates[switchName] = !trackStates[switchName]!;
      print("Switch $switchName physically flipped to: ${trackStates[switchName]}");
    }
  }

  /// Patch: Modifies track colors belonging to non-energized track groups
/// Patch: Modifies track colors belonging to non-energized track groups
  /// Patch: Modifies track colors belonging to non-energized track groups
/// Patch: Modifies track colors belonging to non-energized track groups
/// Patch: Modifies track colors belonging to non-energized track groups
/// Patch: Replaces raw color values with gray within de-energized layers
/// Diagnostic Patch: Modifies track colors and logs exactly where strings mismatch
/// Diagnostic Patch: Modifies track colors and logs exactly where strings mismatch
/// Patch: Replaces specific hex colors within target de-energized groups
/// Patch: Replaces specific hex colors within target de-energized groups taking cascading feeds into account
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;

    // Define your exact yard interlocking power cascade rules
    bool switchC24 = trackStates['C24'] ?? true;
    bool switchC16 = trackStates['C16'] ?? true;
    bool switchC17 = trackStates['C17'] ?? true;

    // Evaluate the live cascading states
    Map<String, bool> computedEnergizedStates = {
      'SeasideOutFeed'   : (trackStates['C10'] ?? true) && switchC17 && switchC24, // C17 -> C10 cascade
      'LandsideInFeeder1': trackStates['C23'] ?? true,
      'LandsideInFeeder2': trackStates['C25'] ?? true,
      'SeasideInFeeder1' : trackStates['T31'] ?? true,
      'SeasideInFeeder2' : switchC24, 
      'LandsideOutFeed'  : trackStates['C15'] ?? true,
      'C16R46to52'       : switchC16 && switchC24, // C24 -> C16 cascade
      'C32R53to59'       : (trackStates['C32'] ?? true) && switchC16 && switchC24, // C16 -> C32 cascade
      'C17R40to45'       : switchC17 && switchC24, // C24 -> C17 cascade
      'C18R32to39'       : trackStates['C18'] ?? true,
      'C19R24to31'       : trackStates['C19'] ?? true,
      'C20R16to23'       : trackStates['C20'] ?? true,
      'C21R8to15'        : trackStates['C21'] ?? true,
      'C22R1to7'         : trackStates['C22'] ?? true,
    };

    computedEnergizedStates.forEach((groupId, isEnergized) {
      if (!isEnergized) {
        final String searchString = '<g id="$groupId">';
        int groupStartIndex = workingCopy.indexOf(searchString);
        
        if (groupStartIndex == -1) return;

        int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
        if (groupEndIndex == -1) return;

        String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
        
        // Dark gray transitions
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