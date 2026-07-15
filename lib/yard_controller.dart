import 'dart:convert';
import 'package:flutter/services.dart';

String rawSvgTemplate = '';

class YardController {
  // Keeps track of which track groups are energized (true) or isolated (false)
  final Map<String, bool> trackStates = {};
  
  // Holds the coordinate locations for all your clickable switch bubbles
  Map<String, List<double>> switchCoordinates = {};

  // 1. Load the JSON data and SVG asset
  Future<void> initializeYardData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/kgx_switch-coords.json');
      switchCoordinates = Map<String, List<double>>.from(jsonDecode(jsonString).map(
        (key, value) => MapEntry(key, List<double>.from(value))
      ));
      
      // Keep using .svg since that's your actual working project asset format
      rawSvgTemplate = await rootBundle.loadString('assets/kgx_yard_map.svg');
      
      initializeTrackDefaultStates();
    } catch (e) {
      print("Error loading yard data: $e");
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

  // 3. Maps each clickable switch name directly to its corresponding SVG track group
  final Map<String, String> switchMap = {
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
    final String? targetGroup = switchMap[switchName];

    if (targetGroup != null && trackStates.containsKey(targetGroup)) {
      trackStates[targetGroup] = !trackStates[targetGroup]!;
      print("Switch $switchName flipped! Toggled track group: $targetGroup");
    } else {
      print("Switch $switchName flipped, but no track group is assigned to it yet.");
    }
  }

  /// Modifies only the stroke and fill colors belonging to non-energized track groups
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;

    trackStates.forEach((groupId, isEnergized) {
      if (!isEnergized) {
        // Find where this specific track group block starts (checking both with and without leading underscore)
        String searchString = '<g id="_$groupId">';
        int groupStartIndex = workingCopy.indexOf(searchString);
        
        if (groupStartIndex == -1) {
          searchString = '<g id="$groupId">';
          groupStartIndex = workingCopy.indexOf(searchString);
        }
        
        if (groupStartIndex != -1) {
          // Find where this group block ends
          int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
          
          if (groupEndIndex != -1) {
            // Extract just the inner path content for this track segment
            String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
            
            // Target your newly standardized hex values instead of word colors
            // 1. Target Blue (#0000ff)
            groupContent = groupContent.replaceAll('stroke="#0000ff"', 'stroke="#444444"');
            groupContent = groupContent.replaceAll('fill="#0000ff"', 'fill="#444444"'); 
            
            // 2. Target Aqua (#00ffff)
            groupContent = groupContent.replaceAll('stroke="#00ffff"', 'stroke="#444444"');
            groupContent = groupContent.replaceAll('fill="#00ffff"', 'fill="#444444"'); 
            
            // Re-stitch the modified group text back into the master string layout
            workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
          }
        }
      }
    });

    return workingCopy;
  }
}