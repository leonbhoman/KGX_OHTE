import 'dart:convert';
import 'package:flutter/services.dart';

class YardController {
  // Master text template loaded from assets
  String rawSvgTemplate = '';

  // Keeps track of the local toggle position of each physical switch (true = ON, false = OFF)
  final Map<String, bool> switchPositions = {};
  
  // Holds the coordinate locations for clickable switch bubbles from JSON
  Map<String, List<double>> switchCoordinates = {};

  // 1. Maps each clickable switch name directly to its corresponding SVG track group ID
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

  // 2. Phase 2: Power Dependency Hierarchy Map (Parent Switches)
  // Short ID -> List of Short IDs that MUST be ON for this switch to receive power.
  final Map<String, List<String>> _powerDependencies = {
    'C16': ['C24'],
    'C17': ['C24'],
    'C32': ['C24', 'C16'],
    'C10': ['C24', 'C17'],
  };

  // Initialize data
  Future<void> initializeYardData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/kgx_switch-coords.json');
      switchCoordinates = Map<String, List<double>>.from(jsonDecode(jsonString).map(
        (key, value) => MapEntry(key, List<double>.from(value))
      ));
      
      rawSvgTemplate = await rootBundle.loadString('assets/kgx_yard_map.svg');
      
      initializeDefaultSwitchPositions();
    } catch (e) {
      print("Error loading yard data: $e");
    }
  }

  // Default all physical switches to ON (Energized)
  void initializeDefaultSwitchPositions() {
    _switchMap.keys.forEach((switchId) {
      switchPositions[switchId] = true;
    });
  }

  // Toggle switch position
  void toggleSwitch(String switchName) {
    if (switchPositions.containsKey(switchName)) {
      switchPositions[switchName] = !switchPositions[switchName]!;
      print("Physical Switch $switchName flipped to: ${switchPositions[switchName]}");
    } else {
      print("Switch $switchName not found in registry.");
    }
  }

  /// Phase 2: Evaluates whether a track group is functionally energized based on upstream parents
  bool isTrackGroupEnergized(String groupId) {
    // Find the switch that directly controls this group
    final entry = _switchMap.entries.firstWhere(
      (element) => element.value == groupId,
      orElse: () => const MapEntry('', ''),
    );

    final String switchId = entry.key;
    if (switchId.isEmpty) return true; // If unmapped, default to energized

    // Check if the local switch itself is turned OFF
    if (switchPositions[switchId] == false) {
      return false;
    }

    // Check upstream dependencies recursively
    final parents = _powerDependencies[switchId];
    if (parents != null) {
      for (var parentId in parents) {
        // If any parent switch is OFF or itself lacks power, this child loses power
        if (switchPositions[parentId] == false) {
          return false;
        }
        // Recursive check if parents have multiple layer depth hierarchies
        final parentGroupId = _switchMap[parentId];
        if (parentGroupId != null && !isTrackGroupEnergized(parentGroupId)) {
          return false;
        }
      }
    }

    return true; // Passed all checks
  }

  /// Generates the dynamically altered SVG string payload
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;

    _switchMap.forEach((switchId, groupId) {
      final bool energized = isTrackGroupEnergized(groupId);

      if (!energized) {
        // Robust RegEx matching: finds <g id="groupId" ... > regardless of inline attributes
        final RegExp groupRegex = RegExp('<g[^>]*id=["\']$groupId["\'][^>]*>');
        final Match? match = groupRegex.firstMatch(workingCopy);

        if (match != null) {
          int groupStartIndex = match.start;
          // Locate the closing group tag relative to this opening tag
          int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);

          if (groupEndIndex != -1) {
            String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);

            // De-energize look and feel
            groupContent = groupContent.replaceAll('stroke="blue"', 'stroke="#444444"');
            groupContent = groupContent.replaceAll('fill="blue"', 'fill="#444444"');

            workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
          }
        }
      }
    });

    return workingCopy;
  }
}