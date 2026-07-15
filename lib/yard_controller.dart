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
  
  // This map tracks the live state of each switch (true = closed/green, false = open/red)
  final Map<String, bool> switchStates = {};

  // Master Definition Table connecting Switches, Tracks, and their Initial States
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
    
    // Example: If C35 is added to your coordinates, it will automatically default to Open (Red)
    const SwitchDefinition(name: 'C35', trackGroupId: 'C32R53to59', initialClosed: false), 
  ];

  // Load configuration and set up initial states
  Future<void> initializeYardData() async {
    try {
      // 1. Load coordinates
      final String jsonString = await rootBundle.loadString('assets/kgx_switch-coords.json');
      switchCoordinates = Map<String, List<double>>.from(jsonDecode(jsonString).map(
        (key, value) => MapEntry(key, List<double>.from(value))
      ));
      
      // 2. Load SVG layout
      rawSvgTemplate = await rootBundle.loadString('assets/kgx_yard_map.svg');
      
      // 3. Initialize active switch states from our definitions
      for (var definition in switchDefinitions) {
        switchStates[definition.name] = definition.initialClosed;
      }
    } catch (e) {
      print("Error initializing yard data: $e");
    }
  }

  // Toggle switch state
  void toggleSwitch(String switchName) {
    if (switchStates.containsKey(switchName)) {
      switchStates[switchName] = !switchStates[switchName]!;
      print("Switch $switchName toggled to: ${switchStates[switchName]! ? 'CLOSED' : 'OPEN'}");
    }
  }

  // Generates SVG code with injected CSS styles to turn non-energized tracks gray
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    // Generate CSS rules to dynamically override track colors
    String cssOverrides = '';

    for (var definition in switchDefinitions) {
      bool isClosed = switchStates[definition.name] ?? true;
      
      // If the switch is Open, the track is de-energized (turns gray #444444)
      if (!isClosed) {
        cssOverrides += '''
          #${definition.trackGroupId} path, 
          #${definition.trackGroupId} line, 
          #${definition.trackGroupId} polyline, 
          #${definition.trackGroupId} rect, 
          #${definition.trackGroupId} circle {
            stroke: #444444 !important;
            fill: #444444 !important;
          }
        ''';
      }
    }

    if (cssOverrides.isEmpty) {
      return rawSvgTemplate;
    }

    // Inject the CSS style block right after the opening <svg> tag
    final String styleBlock = '<style>$cssOverrides</style>';
    final int insertIndex = rawSvgTemplate.indexOf('>');
    
    if (insertIndex != -1) {
      return rawSvgTemplate.replaceRange(
        insertIndex + 1, 
        insertIndex + 1, 
        '\n$styleBlock\n'
      );
    }

    return rawSvgTemplate;
  }
}