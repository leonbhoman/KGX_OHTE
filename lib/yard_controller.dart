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

// --- STEP 1: INITIAL PASS (PHYSICAL CONTACT STATUS) ---
    bool isClosed(String name) => switchStates[name] ?? true;

    // Seaside Forward Flow (Remains linearly clean)
    final bool forwardC24 = isClosed('C24'); 
    final bool forwardC16 = forwardC24 && isClosed('C16');
    final bool forwardC32 = forwardC16 && isClosed('C32');
    final bool forwardC17 = forwardC24 && isClosed('C17');
    final bool forwardC10 = forwardC17 && isClosed('C10');

    // Landside Raw Input
    final bool forwardC25 = isClosed('C25');


    // --- STEP 2: SOLVE THE LANDSIDE DISTRIBUTION BUS LOOP ---
    // The outfeed bus state and internal common bus state depend entirely on each other.
    // We can evaluate if the Landside common distribution bus gets power from ANY valid source.
    
    // Source A: Direct forward feed from C25
    bool landsideBusHasPower = forwardC25;

    // Source B: Back-feed from Seaside via closed C35
    bool landsideOutfeedHasPowerFromC35 = forwardC10 && isClosed('C35');

    // If back-feed power is available at the outfeed gate, it can reach the internal common bus 
    // if any of the closed loop paths (Switch pair closed) are complete.
    if (landsideOutfeedHasPowerFromC35) {
      if ((isClosed('C12') && isClosed('C19')) ||
          (isClosed('C13') && isClosed('C20')) ||
          (isClosed('C14') && isClosed('C21')) ||
          (isClosed('C15') && isClosed('C22'))) {
        landsideBusHasPower = true;
      }
    }

    // Now determine if the Landside Outfeed Bus itself is energized.
    // It is live if the internal bus feeds out through any closed switch, OR if C35 is directly back-feeding it.
    bool landsideOutfeedHasPower = landsideOutfeedHasPowerFromC35 || 
        (landsideBusHasPower && (isClosed('C12') || isClosed('C13') || isClosed('C14') || isClosed('C15')));


    // --- STEP 3: CALCULATE INDIVIDUAL YARD SECTION STATES ---
    final Map<String, bool> computedTrackStates = {};

    // A. Seaside track groups
    computedTrackStates['C16R46to52'] = forwardC16;
    computedTrackStates['C32R53to59'] = forwardC32;
    computedTrackStates['SeasideOutFeed'] = forwardC10 || (landsideOutfeedHasPower && isClosed('C35'));
    computedTrackStates['C17R40to45'] = forwardC17 || (isClosed('C35') && landsideOutfeedHasPower && isClosed('C10'));

    // B. Landside track groups (Bound directly to the resolved statuses of the buses)
    computedTrackStates['LandsideOutFeed'] = landsideOutfeedHasPower;
    
    // C18 is an isolated branch off the main feeder line before the loop mechanics
    computedTrackStates['C18R32to39'] = forwardC25 && isClosed('C18');

    // The Middle Yard Tracks: They are live if the common distribution bus is hot AND their input switch is closed,
    // OR if the outfeed bus is hot and their outfeed switch is closed!
    computedTrackStates['C19R24to31'] = (landsideBusHasPower && isClosed('C19')) || (landsideOutfeedHasPower && isClosed('C12'));
    computedTrackStates['C20R16to23'] = (landsideBusHasPower && isClosed('C20')) || (landsideOutfeedHasPower && isClosed('C13'));
    computedTrackStates['C21R8to15']  = (landsideBusHasPower && isClosed('C21')) || (landsideOutfeedHasPower && isClosed('C14'));
    computedTrackStates['C22R1to7']   = (landsideBusHasPower && isClosed('C22')) || (landsideOutfeedHasPower && isClosed('C15'));

    // C. Handle Incoming Feeders & Isolator Line
    computedTrackStates['SeasideInFeeder1'] = true; 
    computedTrackStates['LandsideInFeeder1'] = true;
    computedTrackStates['SeasideInFeeder2'] = forwardC24;
    computedTrackStates['LandsideInFeeder2'] = forwardC25;
    computedTrackStates['C35_Isolator'] = isClosed('C35');

    
// --- STEP 4: APPLY COLOR REPLACEMENTS AND HOVER TOOLTIPS ---
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