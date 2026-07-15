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
  final List<SwitchDefinition> switchDefinitions = [const SwitchDefinition(name: 'C32', trackGroupId: 'C32R53to59'),
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
    
    // Switches involved in the LandsideOutFeed logic:
    const SwitchDefinition(name: 'C15', trackGroupId: 'LandsideOutFeed'),
    const SwitchDefinition(name: 'C14', trackGroupId: 'LandsideOutFeed'),
    const SwitchDefinition(name: 'C13', trackGroupId: 'LandsideOutFeed'),
    const SwitchDefinition(name: 'C12', trackGroupId: 'LandsideOutFeed'),

    // The Seaside control switch:
    const SwitchDefinition(name: 'C10', trackGroupId: 'SeasideOutFeed'),

    // C35 acts as a Tie/Isolating Switch (starts OPEN/Red by default)
    const SwitchDefinition(name: 'C35', trackGroupId: 'C35_Isolator', initialClosed: false),
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
  /// Generates the SVG code by evaluating our control logic rules 
  /// and replacing colors in the de-energized track blocks.
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;

    // --- STEP 1: CALCULATE THE ENERGIZED STATE OF EACH TRACK GROUP ---
    final Map<String, bool> computedTrackStates = {};

    // Standard 1-to-1 default tracks
    for (var definition in switchDefinitions) {
      // Skip groups that have custom logic rules below
      if (definition.trackGroupId == 'LandsideOutFeed' || 
          definition.trackGroupId == 'SeasideOutFeed' ||
          definition.trackGroupId == 'C35_Isolator') {
        continue;
      }
      computedTrackStates[definition.trackGroupId] = switchStates[definition.name] ?? true;
    }

    // A. Evaluate the Base States (before C35 logic is applied)
    // LandsideOutFeed base state: Energized if C12, C13, C14, OR C15 is closed
    bool landsideBaseEnergized = (switchStates['C12'] ?? true) ||
                                 (switchStates['C13'] ?? true) ||
                                 (switchStates['C14'] ?? true) ||
                                 (switchStates['C15'] ?? true);

    // SeasideOutFeed base state: Energized if C10 is closed
    bool seasideBaseEnergized = switchStates['C10'] ?? true;

    // B. Apply C35 Tie/Isolator Logic
    bool finalLandsideOutState = landsideBaseEnergized;
    bool finalSeasideOutState = seasideBaseEnergized;

    bool isC35Closed = switchStates['C35'] ?? false;
    if (isC35Closed) {
      // If the bridge is closed, power from either side energizes both sides
      bool combinedPower = landsideBaseEnergized || seasideBaseEnergized;
      finalLandsideOutState = combinedPower;
      finalSeasideOutState = combinedPower;
    }

    // Save final calculated track states
    computedTrackStates['LandsideOutFeed'] = finalLandsideOutState;
    computedTrackStates['SeasideOutFeed'] = finalSeasideOutState;


    // --- STEP 2: APPLY SWAP COLOR REPLACEMENTS ON DE-ENERGIZED TRACKS ---
    computedTrackStates.forEach((trackGroupId, isEnergized) {
      if (!isEnergized) {
        final String searchString = '<g id="$trackGroupId">';
        final int groupStartIndex = workingCopy.indexOf(searchString);
        
        if (groupStartIndex != -1) {
          final int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
          
          if (groupEndIndex != -1) {
            String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
            
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
            
            workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
          }
        }
      }
    });

    return workingCopy;
  }
}