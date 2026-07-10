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
    // These names match your Illustrator SVG Group IDs exactly (with leading underscores)!
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
    'C25' : 'LandsideInFeeder2', // right
    'T31' : 'SeasideInFeeder1', // right
    'C24' : 'SeasideInFeeder2', // right
    'C23' : 'LandsideInFeeder1', // right
    'C10' : 'SeasideOutFeed', // right
    'C15' : 'LandsideOutFeed' // right
  };

  // 4. Logic to toggle states when a switch is flipped
  void toggleSwitch(String switchName) {
    // Get the track group linked to this switch from our map
    final String? targetGroup = _switchMap[switchName];

    if (targetGroup != null && trackStates.containsKey(targetGroup)) {
      trackStates[targetGroup] = !trackStates[targetGroup]!;
      print("Switch $switchName flipped! Toggled track group: $targetGroup");
    } else {
      print("Switch $switchName flipped, but no track group is assigned to it yet.");
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
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) {
      print("❌ DEBUG: rawSvgTemplate is completely EMPTY!");
      return '';
    }

    String workingCopy = rawSvgTemplate;
    print("--- SVG Generation Cycle Started ---");

    trackStates.forEach((groupId, isEnergized) {
      if (!isEnergized) {
        final String searchString = '<g id="$groupId">';
        int groupStartIndex = workingCopy.indexOf(searchString);
        
        if (groupStartIndex == -1) {
          print("❌ ERROR: Could not find tag matching '$searchString' anywhere in the SVG string layout!");
          return;
        }

        int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
        if (groupEndIndex == -1) {
          print("❌ ERROR: Found start of group for '$groupId', but could not locate its matching closing '</g>' tag!");
          return;
        }

        // Isolate the text slice for this group
        String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
        int originalLength = groupContent.length;

        // Perform straight text substitutions targeting the yard segments
        groupContent = groupContent.replaceAll('="red"', '="#444444"');
        groupContent = groupContent.replaceAll('=red', '="#444444"');
        groupContent = groupContent.replaceAll('="blue"', '="#444444"');
        groupContent = groupContent.replaceAll('=blue', '="#444444"');
        
        // Feeders substitution fallback
        groupContent = groupContent.replaceAll(RegExp(r'stroke="[^"]*"'), 'stroke="#444444"');
        groupContent = groupContent.replaceAllMapped(RegExp(r'fill="([^"]*)"'), (match) {
          final String fillValue = match.group(1) ?? '';
          return fillValue == 'none' ? 'fill="none"' : 'fill="#444444"';
        });

        if (groupContent.length == originalLength) {
          String snippet = groupContent.length > 60 ? groupContent.substring(0, 60) : groupContent;
          print("⚠️ WARNING: Found group '$groupId', but no color text changes were made inside it. Content snippet: $snippet");
        } else {
          print("✅ SUCCESS: Successfully replaced color characters inside track group '$groupId'!");
        }

        // Stitch back into master template
        workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
      }
    });

    return workingCopy;
  }}