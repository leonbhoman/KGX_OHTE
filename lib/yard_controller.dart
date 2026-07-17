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

// --- STEP 1: INITIAL STATE & SEASIDE LINE ---
    bool isClosed(String name) => switchStates[name] ?? true;

    // Seaside Forward Supply
    final bool forwardC24 = isClosed('C24'); 
    final bool forwardC16 = forwardC24 && isClosed('C16');
    final bool forwardC32 = forwardC16 && isClosed('C32');
    final bool forwardC17 = forwardC24 && isClosed('C17');
    final bool forwardC10 = forwardC17 && isClosed('C10');

    // Landside Raw Main Input
    final bool forwardC25 = isClosed('C25');


    // --- STEP 2: CALCULATE THE TWO PARALLEL GROUPS ---
    
    // Group A: The Outfeed Bus Group [C12, C13, C14, C15]
    // Tied directly to C35. It has power if C35 is feeding it from Seaside,
    // OR if any individual outfeed switch is pushing power into it from a live yard section.
    bool outfeedGroupHasPower = forwardC10 && isClosed('C35');

    // Group B: The Inner Distribution Group [C18, C19, C20, C21, C22]
    // Under normal conditions (C35 OFF), this isn't a unified group. 
    // But if C25 is ON, the distribution bar feeding them is hot.
    bool landsideInboundBusHasPower = forwardC25;

    // Apply Addendum Rule #3 & Sheet 2 Logic:
    // If C35 is ON, they act as a parallel group. If the outfeed has power 
    // AND any of the yard sections form a path back through their switches, 
    // power back-feeds the entire inbound distribution bar.
    if (isClosed('C35') && outfeedGroupHasPower) {
      if (isClosed('C18') || isClosed('C19') || isClosed('C20') || isClosed('C21') || isClosed('C22')) {
        landsideInboundBusHasPower = true;
      }
    }

    // Recalculate outfeed group: If the inbound bus got power from C25, 
    // and any outfeed switch is closed, it can power the outfeed group forward.
    if (landsideInboundBusHasPower && 
       (isClosed('C12') || isClosed('C13') || isClosed('C14') || isClosed('C15'))) {
      outfeedGroupHasPower = true;
    }


    // --- STEP 3: ASSIGN LOGICAL STATES TO TRACK SEGMENTS ---
    final Map<String, bool> computedTrackStates = {};

    // Seaside Tracks
    computedTrackStates['C16R46to52'] = forwardC16;
    computedTrackStates['C32R53to59'] = forwardC32;
    computedTrackStates['SeasideOutFeed'] = forwardC10 || (outfeedGroupHasPower && isClosed('C35'));
    computedTrackStates['C17R40to45'] = forwardC17 || (isClosed('C35') && outfeedGroupHasPower && isClosed('C10'));

    // Landside Outfeed Bus (Shared by definition of Addendum Rule #2)
    computedTrackStates['LandsideOutFeed'] = outfeedGroupHasPower;
    
    // C18 is an isolated branch off the inbound bus (Addendum Rule #1: inherits parent state)
    computedTrackStates['C18R32to39'] = landsideInboundBusHasPower && isClosed('C18');

    // Middle Yard Tracks: Inherit power if their parent bus is hot and switch is closed,
    // OR if they are being back-fed from the powered outfeed group through their right-hand switch.
    computedTrackStates['C19R24to31'] = (landsideInboundBusHasPower && isClosed('C19')) || (outfeedGroupHasPower && isClosed('C12'));
    computedTrackStates['C20R16to23'] = (landsideInboundBusHasPower && isClosed('C20')) || (outfeedGroupHasPower && isClosed('C13'));
    computedTrackStates['C21R8to15']  = (landsideInboundBusHasPower && isClosed('C21')) || (outfeedGroupHasPower && isClosed('C14'));
    computedTrackStates['C22R1to7']   = (landsideInboundBusHasPower && isClosed('C22')) || (outfeedGroupHasPower && isClosed('C15'));

    // Feeders
    computedTrackStates['SeasideInFeeder1'] = true; 
    computedTrackStates['LandsideInFeeder1'] = true;
    computedTrackStates['SeasideInFeeder2'] = forwardC24;
    computedTrackStates['LandsideInFeeder2'] = forwardC25;
    computedTrackStates['C35_Isolator'] = isClosed('C35');


// --- STEP 4: APPLY COLOR REPLACEMENTS AND HOVER TOOLTIPS ------
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