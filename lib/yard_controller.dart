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

 /// Generates the SVG code by evaluating our control logic rules 
  /// and replacing colors in the de-energized track blocks.
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;

    // --- STEP 1: PROPAGATE POWER THROUGH THE SWITCHES ---
    // We create a map of which switches actually have incoming power to pass on.
    final Map<String, bool> switchHasPower = {};

    // Helper: Checks if a switch is physically closed (true)
    bool isClosed(String name) => switchStates[name] ?? true;

    // A. Define Seaside Power Flow (fed from C24)
    final bool hasPowerC24 = isClosed('C24'); 
    final bool hasPowerC16 = hasPowerC24 && isClosed('C16');
    final bool hasPowerC32 = hasPowerC16 && isClosed('C32');
    final bool hasPowerC17 = hasPowerC16 && isClosed('C17'); // Note: C16 feeds BOTH C32 and C17 in your tree.
    
    // C10 is fed if EITHER (C24 is closed AND C17 is closed) OR (C24 is closed and C10 is closed directly)
    // Based on C24 => [..., C10] and C17 => [C10]
    final bool hasPowerC10 = hasPowerC24 && hasPowerC17 && isClosed('C10');

    // B. Define Landside Power Flow (fed from C25)
    final bool hasPowerC25 = isClosed('C25');
    final bool hasPowerC18 = hasPowerC25 && isClosed('C18');
    final bool hasPowerC19 = hasPowerC18 && isClosed('C19');
    final bool hasPowerC20 = hasPowerC19 && isClosed('C20');
    final bool hasPowerC21 = hasPowerC20 && isClosed('C21');
    final bool hasPowerC22 = hasPowerC21 && isClosed('C22');

    // C. Define Feeders to the Landside Outfeed (C12, C13, C14, C15)
    // Based on your rules, these are fed down the main trunk C25 -> C22,
    // but also have individual parent gating switches (e.g. C19 => [C12], C20 => [C13], etc.)
    final bool hasPowerC12 = hasPowerC22 && hasPowerC19 && isClosed('C12');
    final bool hasPowerC13 = hasPowerC22 && hasPowerC20 && isClosed('C13');
    final bool hasPowerC14 = hasPowerC22 && hasPowerC21 && isClosed('C14');
    final bool hasPowerC15 = hasPowerC22 && hasPowerC22 && isClosed('C15'); // C22 feeds C15

    // Store computed switch power states
    switchHasPower['C24'] = hasPowerC24;
    switchHasPower['C16'] = hasPowerC16;
    switchHasPower['C32'] = hasPowerC32;
    switchHasPower['C17'] = hasPowerC17;
    switchHasPower['C10'] = hasPowerC10;
    
    switchHasPower['C25'] = hasPowerC25;
    switchHasPower['C18'] = hasPowerC18;
    switchHasPower['C19'] = hasPowerC19;
    switchHasPower['C20'] = hasPowerC20;
    switchHasPower['C21'] = hasPowerC21;
    switchHasPower['C22'] = hasPowerC22;

    switchHasPower['C12'] = hasPowerC12;
    switchHasPower['C13'] = hasPowerC13;
    switchHasPower['C14'] = hasPowerC14;
    switchHasPower['C15'] = hasPowerC15;


    // --- STEP 2: CALCULATE THE ENERGIZED STATE OF EACH TRACK GROUP ---
    final Map<String, bool> computedTrackStates = {};

    // Default tracks: A track segment is only energized if its feeding switch is physically closed AND has power.
    for (var definition in switchDefinitions) {
      if (definition.trackGroupId == 'LandsideOutFeed' || 
          definition.trackGroupId == 'SeasideOutFeed' ||
          definition.trackGroupId == 'C35_Isolator') {
        continue;
      }
      
      // Look up if the switch associated with this track segment actually has power flowing through it
      computedTrackStates[definition.trackGroupId] = switchHasPower[definition.name] ?? isClosed(definition.name);
    }

    // Evaluate the Base Outfeed States (before C35 bridging is applied)
    // LandsideOutFeed is energized if ANY of its feeding switches (C12, C13, C14, C15) has active power flow
    bool landsideBaseEnergized = hasPowerC12 || hasPowerC13 || hasPowerC14 || hasPowerC15;

    // SeasideOutFeed is energized if C10 has active power flow
    bool seasideBaseEnergized = hasPowerC10;

    // Apply C35 Tie/Isolator Logic
    bool finalLandsideOutState = landsideBaseEnergized;
    bool finalSeasideOutState = seasideBaseEnergized;

    if (isClosed('C35')) {
      // If C35 is CLOSED, power bridges across. 
      // This means if EITHER side has active power, BOTH outfeeds become energized!
      if (landsideBaseEnergized || seasideBaseEnergized) {
        finalLandsideOutState = true;
        finalSeasideOutState = true;
      }
    }

    // Save final calculated track states
    computedTrackStates['LandsideOutFeed'] = finalLandsideOutState;
    computedTrackStates['SeasideOutFeed'] = finalSeasideOutState;


    // --- STEP 3: APPLY SWAP COLOR REPLACEMENTS ON DE-ENERGIZED TRACKS ---
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