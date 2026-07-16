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
    final Map<String, bool> switchHasPower = {};

    // Helper: Checks if a switch is physically closed (true)
    bool isClosed(String name) => switchStates[name] ?? true;

    // A. Seaside Power Flow (fed from C24)
    final bool hasPowerC24 = isClosed('C24'); 
    final bool hasPowerC16 = hasPowerC24 && isClosed('C16');
    final bool hasPowerC32 = hasPowerC16 && isClosed('C32');
    final bool hasPowerC17 = hasPowerC16 && isClosed('C17');
    final bool hasPowerC10 = hasPowerC24 && hasPowerC17 && isClosed('C10');

    // B. Landside Power Flow (fed in PARALLEL from C25)
    final bool hasPowerC25 = isClosed('C25');
    final bool hasPowerC18 = hasPowerC25 && isClosed('C18');
    final bool hasPowerC19 = hasPowerC25 && isClosed('C19');
    final bool hasPowerC20 = hasPowerC25 && isClosed('C20');
    final bool hasPowerC21 = hasPowerC25 && isClosed('C21');
    final bool hasPowerC22 = hasPowerC25 && isClosed('C22');

    // C. Individual Outfeed lines (Each fed by its parent switch)
    final bool hasPowerC12 = hasPowerC19 && isClosed('C12');
    final bool hasPowerC13 = hasPowerC20 && isClosed('C13');
    final bool hasPowerC14 = hasPowerC21 && isClosed('C14');
    final bool hasPowerC15 = hasPowerC22 && isClosed('C15');

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

    // Default tracks: A track segment is only energized if its feeding switch has active power flow.
    for (var definition in switchDefinitions) {
      if (definition.trackGroupId == 'LandsideOutFeed' || 
          definition.trackGroupId == 'SeasideOutFeed' ||
          definition.trackGroupId == 'C35_Isolator') {
        continue;
      }
      
      computedTrackStates[definition.trackGroupId] = switchHasPower[definition.name] ?? isClosed(definition.name);
    }

    // Evaluate the Base Outfeed States (before C35 bridging is applied)
    // LandsideOutFeed is energized if ANY of its feeding branches actually carry power
    bool landsideBaseEnergized = hasPowerC12 || hasPowerC13 || hasPowerC14 || hasPowerC15;

    // SeasideOutFeed is energized if C10 has active power flow
    bool seasideBaseEnergized = hasPowerC10;

    // Apply C35 Tie/Isolator Logic
    bool finalLandsideOutState = landsideBaseEnergized;
    bool finalSeasideOutState = seasideBaseEnergized;

    if (isClosed('C35')) {
      if (landsideBaseEnergized || seasideBaseEnergized) {
        finalLandsideOutState = true;
        finalSeasideOutState = true;
      }
    }

    // Save final calculated track states
    computedTrackStates['LandsideOutFeed'] = finalLandsideOutState;
    computedTrackStates['SeasideOutFeed'] = finalSeasideOutState;


// --- STEP 3: APPLY COLOR REPLACEMENTS AND HOVER TOOLTIPS ---
    // Mapping of group IDs to friendly descriptive text
    final Map<String, String> trackDescriptions = {
      'C32R53to59': 'Roads 53 to 59',
      'C16R46to52': 'Roads 46 to 52',
      'C17R40to45': 'Roads 40 to 45',
      'C18R32to39': 'Roads 32 to 39',
      'C19R24to31': 'Roads 24 to 31',
      'C20R16to23': 'Roads 16 to 23',
      'C21R8to15': 'Roads 8 to 15',
      'C22R1to7': 'Roads 1 to 7',
      'LandsideInFeeder1': 'Landside Input Feeder 1',
      'LandsideInFeeder2': 'Landside Input Feeder 2',
      'SeasideInFeeder1': 'Seaside Input Feeder 1',
      'SeasideInFeeder2': 'Seaside Input Feeder 2',
      'LandsideOutFeed': 'Landside Output Feed',
      'SeasideOutFeed': 'Seaside Output Feed',
    };

    computedTrackStates.forEach((trackGroupId, isEnergized) {
      final String searchString = '<g id="$trackGroupId">';
      final int groupStartIndex = workingCopy.indexOf(searchString);
      
      if (groupStartIndex != -1) {
        final int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
        
        if (groupEndIndex != -1) {
          String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
          
          // 1. Inject SVG Hover Tooltip (Title tag) if a description exists
          if (trackDescriptions.containsKey(trackGroupId)) {
            final String tooltipXml = '<title>${trackDescriptions[trackGroupId]}</title>';
            // Inject cleanly right after the opening group tag
            groupContent = groupContent.replaceFirst('>', '>\n$tooltipXml');
          }

          // 2. Turn de-energized tracks gray
          if (!isEnergized) {
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
          }
          
          workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
        }
      }
    });

    return workingCopy;
  }
}