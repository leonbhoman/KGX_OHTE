import 'dart:convert';
import 'package:flutter/services.dart';

String rawSvgTemplate = '';

class YardController {
  // Keeps track of which track groups are energized (true) or isolated (false)
  final Map<String, bool> trackStates = {};
  
  // Holds the coordinate locations for all your clickable switch bubbles
Map<String, List<double>> switchCoordinates = {
     
  };

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
    // These names match your Illustrator SVG Group IDs exactly!
    List<String> trackGroups = [
      'SeasideOutFeed',
      'LandsideInFeeder1',
      'LandsideInFeeder2',
      'SeasideInFeeder1',
      'SeasideInFeeder2',
      'LandsideOutFeed',
      '53_to_59',
      '46_to_52',
      '40_to_45',
      '32_to_39',
      '24_to_31',
      '16_to_23',
      '8_to_15',
      '1_to_7'
    ];

    for (var groupId in trackGroups) {
      trackStates[groupId] = true; // Default to fully energized (colored)
    }
  }

  // 3. Logic to toggle states when a switch is flipped
  // Maps each clickable switch name directly to its corresponding SVG track group
  final Map<String, String> _switchMap = {
    'C32': '53_to_59',
    'C16' : '46_to_52',
    'C17' : '40_to_45',
    'C18' : '32_to_39',
    'C19' : '24_to_31',
    'C20' : '16_to_23',
    'C21' : '8_to_15',
    'C22' : '1_to_7',
    'C24' : 'LandsideInFeeder2',
    'T31' : 'LandsideInFeeder1',
    'C25' : 'SeasideInFeeder2',
    'C23' : 'SeasideInFeeder1',
    'C10' : 'SeasideOutFeed',
    'C15' : 'LandsideOutFeed'
    // You can easily add more pairs here as you map them out!
  };

  // 3. Logic to toggle states when a switch is flipped
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

  /// Patch: Modifies only the stroke colors belonging to non-energized track groups
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;

    trackStates.forEach((groupId, isEnergized) {
      if (!isEnergized) {
        // Find where this specific track group block starts
        final String searchString = '<g id="$groupId">';
        int groupStartIndex = workingCopy.indexOf(searchString);
        
        if (groupStartIndex != -1) {
          // Find where this group block ends
          int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
          
          if (groupEndIndex != -1) {
            // Extract just the inner path content for this track segment
            String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
            
            // Target the stroke properties inside this group only
            // Swap 'stroke="blue"' with a de-energized gray 'stroke="#444444"'
            groupContent = groupContent.replaceAll('stroke="blue"', 'stroke="#444444"');
            groupContent = groupContent.replaceAll('fill="blue"', 'fill="#444444"'); // For track arrows/polylines
            
            // Re-stitch the modified group text back into the master string layout
            workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
          }
        }
      }
    });

    return workingCopy;
  }


}