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

// --- STEP 1: PROPAGATE FORWARD POWER (FROM MAIN FEEDERS) ---
    bool isClosed(String name) => switchStates[name] ?? true;

    // A. Forward Seaside Power Flow (Fed from incoming C24)
    final bool forwardC24 = isClosed('C24'); 
    final bool forwardC16 = forwardC24 && isClosed('C16');
    final bool forwardC32 = forwardC16 && isClosed('C32');
    final bool forwardC17 = forwardC24 && isClosed('C17');
    final bool forwardC10 = forwardC17 && isClosed('C10');

    // B. Forward Landside Power Flow (Fed in PARALLEL from incoming C25)
    final bool forwardC25 = isClosed('C25');
    final bool forwardC18 = forwardC25 && isClosed('C18');
    final bool forwardC19 = forwardC25 && isClosed('C19');
    final bool forwardC20 = forwardC25 && isClosed('C20');
    final bool forwardC21 = forwardC25 && isClosed('C21');
    final bool forwardC22 = forwardC25 && isClosed('C22');

    // Forward supply hitting the outfeed isolation gates
    final bool forwardC12 = forwardC19 && isClosed('C12');
    final bool forwardC13 = forwardC20 && isClosed('C13');
    final bool forwardC14 = forwardC21 && isClosed('C14');
    final bool forwardC15 = forwardC22 && isClosed('C15');


    // --- STEP 2: EVALUATE INTER-TIE BRIDGE & BACK-FEED LOGIC (C35) ---
    // Determine base outfeed bus power from forward supply lines
    bool landsideOutfeedHasPower = forwardC12 || forwardC13 || forwardC14 || forwardC15;
    bool seasideOutfeedHasPower = forwardC10;

    // Track if genuine cross-over back-feeding is occurring through C35
    bool isBackFeedingFromSeasideToLandside = false;
    bool isBackFeedingFromLandsideToSeaside = false;

    if (isClosed('C35')) {
      // If Seaside is live and Landside has no forward power, Seaside back-feeds Landside
      if (seasideOutfeedHasPower && !landsideOutfeedHasPower) {
        isBackFeedingFromSeasideToLandside = true;
        landsideOutfeedHasPower = true;
      }
      // If Landside is live and Seaside has no forward power, Landside back-feeds Seaside
      else if (landsideOutfeedHasPower && !seasideOutfeedHasPower) {
        isBackFeedingFromLandsideToSeaside = true;
        seasideOutfeedHasPower = true;
      }
      // If both sides are live anyway, the outfeed buses are both powered normally
      else if (landsideOutfeedHasPower && seasideOutfeedHasPower) {
        // Both keep power naturally
      }
    }


    // --- STEP 3: CALCULATE COMBINED ENERGIZED TRACK STATES ---
    final Map<String, bool> computedTrackStates = {};

    // A. Seaside track groups
    computedTrackStates['C16R46to52'] = forwardC16;
    computedTrackStates['C32R53to59'] = forwardC32;
    computedTrackStates['SeasideOutFeed'] = seasideOutfeedHasPower;
    
    // C17 is hot if forward powered OR back-fed from Landside through C35 and closed C10
    computedTrackStates['C17R40to45'] = forwardC17 || (isBackFeedingFromLandsideToSeaside && isClosed('C10'));

    // B. Landside track groups
    computedTrackStates['C18R32to39'] = forwardC18;
    computedTrackStates['LandsideOutFeed'] = landsideOutfeedHasPower;

    // FIX: Landside yard sections only illuminate if they get forward power from their feeder 
    // OR if power is genuinely back-feeding from the Seaside line and their outfeed switch is closed!
    computedTrackStates['C19R24to31'] = forwardC19 || (isBackFeedingFromSeasideToLandside && isClosed('C12'));
    computedTrackStates['C20R16to23'] = forwardC20 || (isBackFeedingFromSeasideToLandside && isClosed('C13'));
    computedTrackStates['C21R8to15']  = forwardC21 || (isBackFeedingFromSeasideToLandside && isClosed('C14'));
    computedTrackStates['C22R1to7']   = forwardC22 || (isBackFeedingFromSeasideToLandside && isClosed('C15'));


    // C. Handle Incoming Feeders & Isolator Line
    // InFeeder1 represents the incoming feed from the left (always live)
    computedTrackStates['SeasideInFeeder1'] = true; 
    computedTrackStates['LandsideInFeeder1'] = true;
    
    // InFeeder2 represents the track segment to the right of the switch
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