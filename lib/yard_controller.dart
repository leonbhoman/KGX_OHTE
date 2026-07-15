import 'dart:convert';
import 'package:flutter/services.dart';

class SwitchDefinition {
  final String name;
  final String trackGroupId;
  final bool initialClosed;

  const SwitchDefinition({
    required this.name,
    required this.trackGroupId,
    this.initialClosed = true,
  });
}

class YardController {
  String rawSvgTemplate = '';
  Map<String, List<double>> switchCoordinates = {};
  
  // Tracks the live state of each switch (true = closed/green, false = open/red)
  final Map<String, bool> switchStates = {};

  // Master Table: Connects your switches, track groups, and their initial states
  final List<SwitchDefinition> switchDefinitions = [
    const SwitchDefinition(name: 'C32', trackGroupId: 'C32R53to59'),
    const SwitchDefinition(name: 'C16', trackGroupId: 'C16R46to52'),
    const SwitchDefinition(name: 'C17', trackGroupId: 'C17R40to45'),
    const SwitchDefinition(name: 'C18', trackGroupId: 'C18R32to39'),
    const SwitchDefinition(name: 'C19', trackGroupId: 'C19R24to31'),
    const SwitchDefinition(name: 'C20', trackGroupId: 'C20R16to23'),
    const SwitchDefinition(name: 'C21', trackGroupId: 'C21R8to15'),
    const SwitchDefinition(name: 'C22', trackGroupId: 'C22R1to7'),
    const SwitchDefinition(name: 'C25', trackGroupId: 'LandsideInFeeder2'),
    const SwitchDefinition(name: 'T31', trackGroupId: 'SeasideInFeeder1'),
    const SwitchDefinition(name: 'C24', trackGroupId: 'SeasideInFeeder2'),
    const SwitchDefinition(name: 'C23', trackGroupId: 'LandsideInFeeder1'),
    const SwitchDefinition(name: 'C10', trackGroupId: 'SeasideOutFeed'),
    const SwitchDefinition(name: 'C15', trackGroupId: 'LandsideOutFeed'),
  ];

  // Load coordinates and SVG layout
  Future<void> initializeYardData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/kgx_switch-coords.json');
      switchCoordinates = Map<String, List<double>>.from(jsonDecode(jsonString).map(
        (key, value) => MapEntry(key, List<double>.from(value))
      ));
      
      rawSvgTemplate = await rootBundle.loadString('assets/kgx_yard_map.svg');
      
      // Setup initial switch states from definitions
      for (var definition in switchDefinitions) {
        switchStates[definition.name] = definition.initialClosed;
      }
    } catch (e) {
      print("Error loading yard data: $e");
    }
  }

  // Toggle switch state
  void toggleSwitch(String switchName) {
    if (switchStates.containsKey(switchName)) {
      switchStates[switchName] = !switchStates[switchName]!;
      print("Switch $switchName toggled to: ${switchStates[switchName]! ? 'CLOSED' : 'OPEN'}");
    }
  }

  // Generates SVG code with dynamic CSS overrides to turn open-switch tracks gray
/// Generates the SVG code by targeting ONLY the specific text blocks 
  /// of de-energized track groups and replacing their colors.
/// Generates the SVG code by isolating target track group blocks 
  /// and swapping color codes using simple string replacements.
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;

    for (var definition in switchDefinitions) {
      bool isClosed = switchStates[definition.name] ?? true;
      
      // If the switch is Open, the track segment must turn gray (#444444)
      if (!isClosed) {
        // Find the exact starting tag for this specific track group
        final String searchString = '<g id="${definition.trackGroupId}">';
        final int groupStartIndex = workingCopy.indexOf(searchString);
        
        if (groupStartIndex != -1) {
          // Find the end of this specific group block
          final int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
          
          if (groupEndIndex != -1) {
            // Extract ONLY the inner XML content for this track segment
            String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
            
            // Loop through all colors present in your SVG and swap them to gray
            // This preserves transparency because it completely ignores 'none'
            final List<String> targetColors = [
              '#0000ff', // Blue
              '#00ffff', // Aqua
              '#cc65ff', // Purple
              '#ff0000', // Red
              '#65ff00', // Lime Green
              '#ffcc00', // Yellow
              '#965c00', // Brown
            ];

            for (String color in targetColors) {
              groupContent = groupContent.replaceAll('stroke="$color"', 'stroke="#444444"');
              groupContent = groupContent.replaceAll('fill="$color"', 'fill="#444444"');
            }
            
            // Stitch the modified group text back into the master SVG layout
            workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
          }
        }
      }
    }

    return workingCopy;
  }
  }