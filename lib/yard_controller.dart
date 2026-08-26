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

// --- STEP 1: INITIAL PHYSICAL SWITCH STATES ---
    bool isClosed(String name) => switchStates[name] ?? true;

    // --- STEP 2: DEFINE TRACK ZONE FEED BUSES ---
    // The Seaside feed lines (Upper track)
    final bool rawSeasideFeeder = true;
    final bool forwardC24 = rawSeasideFeeder && isClosed('C24');
    final bool forwardC16 = forwardC24 && isClosed('C16');
    final bool forwardC32 = forwardC16 && isClosed('C32');
    final bool forwardC17 = forwardC24 && isClosed('C17');
    final bool forwardC10 = forwardC17 && isClosed('C10');

    // The Landside Main Outfeed Bus (Right-hand side common rail)
    // Live if Seaside feeds it via C35, OR if any middle line pushes power into it from the left.
    bool landsideOutfeedHasPower = forwardC10 && isClosed('C35');

    // The Landside Common Inbound Bus (The rail between C25 and the middle switches)
    // Live if C25 is closed forward, OR if any valid closed path back-feeds it from a live outfeed.
    bool landsideInboundBusHasPower = isClosed('C25');

    // To prevent a single-pass calculation miss, we look at both forward and reverse paths explicitly
    if (!landsideInboundBusHasPower) {
      // If C25 is open, can we back-feed this inbound bus from the outfeed?
      // Yes, if the outfeed has power and any valid track bridge is complete.
      if (landsideOutfeedHasPower) {
        if ((isClosed('C12') && isClosed('C19')) ||
            (isClosed('C13') && isClosed('C20')) ||
            (isClosed('C14') && isClosed('C21')) ||
            (isClosed('C15') && isClosed('C22')) ||
            isClosed('C18')) { // C18 is a direct spur
          landsideInboundBusHasPower = true;
        }
      }
    }

    // Now re-verify the outfeed bus: if inbound is live, it can energize the outfeed rail
    if (landsideInboundBusHasPower) {
      if (isClosed('C12') || isClosed('C13') || isClosed('C14') || isClosed('C15')) {
        landsideOutfeedHasPower = true;
      }
    }

    // --- STEP 3: ASSIGN LOGICAL STATES TO ALL TRACK SEGMENTS ---
    final Map<String, bool> computedTrackStates = {};

    // A. Seaside Track Sections
    computedTrackStates['C16R46to52'] = forwardC16;
    computedTrackStates['C32R53to59'] = forwardC32;
    computedTrackStates['C17R40to45'] = forwardC17; 
    computedTrackStates['SeasideOutFeed'] = forwardC10;

    // B. Landside Common Rails
    computedTrackStates['LandsideOutFeed'] = landsideOutfeedHasPower;
    
    // This is the section right after C25 that was dead in Screenshot 2:
    computedTrackStates['LandsideInFeeder2'] = isClosed('C25') || landsideInboundBusHasPower;

    // C. Individual Middle Yard Track Blocks
    // A yard section is energized if power comes from the left (Inbound Bus + Left Switch closed)
    // OR if power comes from the right (Outfeed Bus + Right Switch closed).
    computedTrackStates['C18R32to39'] = landsideInboundBusHasPower && isClosed('C18');
    computedTrackStates['C19R24to31'] = (landsideInboundBusHasPower && isClosed('C19')) || (landsideOutfeedHasPower && isClosed('C12'));
    computedTrackStates['C20R16to23'] = (landsideInboundBusHasPower && isClosed('C20')) || (landsideOutfeedHasPower && isClosed('C13'));
    computedTrackStates['C21R8to15']  = (landsideInboundBusHasPower && isClosed('C21')) || (landsideOutfeedHasPower && isClosed('C14'));
    computedTrackStates['C22R1to7']   = (landsideInboundBusHasPower && isClosed('C22')) || (landsideOutfeedHasPower && isClosed('C15'));

    // Fixed Feeders & Isolators
    computedTrackStates['SeasideInFeeder1'] = true; 
    computedTrackStates['LandsideInFeeder1'] = true;
    computedTrackStates['SeasideInFeeder2'] = forwardC24;
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