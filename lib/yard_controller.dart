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
      '_53_to_59',
      '_46_to_52',
      '_40_to_45',
      '_32_to_39',
      '_24_to_31',
      '_16_to_23',
      '_8_to_15',
      '_1_to_7'
    ];

    for (var groupId in trackGroups) {
      trackStates[groupId] = true; // Default to fully energized (colored)
    }
  }

  // 3. Maps each clickable switch name directly to its corresponding SVG track group
  final Map<String, String> _switchMap = {
    'C32' : '_53_to_59',
    'C16' : '_46_to_52',
    'C17' : '_40_to_45',
    'C18' : '_32_to_39',
    'C19' : '_24_to_31',
    'C20' : '_16_to_23',
    'C21' : '_8_to_15',
    'C22' : '_1_to_7',
    'C25' : 'LandsideInFeeder2',
    'T31' : 'LandsideInFeeder1',
    'C24' : 'SeasideInFeeder2',
    'C23' : 'SeasideInFeeder1',
    'C10' : 'SeasideOutFeed',
    'C15' : 'LandsideOutFeed'
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
            
            // 1. Wildcard match: Convert ANY existing inline stroke color to gray
            groupContent = groupContent.replaceAll(RegExp(r'stroke="[^"]*"'), 'stroke="#444444"');
            
            // 2. Wildcard match: Convert ANY inline fill color to gray (but preserve transparency)
            groupContent = groupContent.replaceAllMapped(RegExp(r'fill="([^"]*)"'), (match) {
              final String fillValue = match.group(1) ?? '';
              return fillValue == 'none' ? 'fill="none"' : 'fill="#444444"';
            });
            
            // 3. Catch paths relying on CSS classes by forcing an inline gray stroke override
            // SVG rules dictate that inline attributes always override stylesheet classes.
            groupContent = groupContent.replaceAllMapped(RegExp(r'class="([^"]*)"'), (match) {
              final String classAttr = match.group(0) ?? '';
              return '$classAttr stroke="#444444"';
            });
            
            // Re-stitch the modified group text back into the master string layout
            workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
          }
        }
      }
    });

    return workingCopy;
  }}