import 'dart:convert';
import 'package:flutter/services.dart';

String rawSvgTemplate = '';

/// Represents a physical connection between two track sections through a switch
class TrackConnection {
  final String neighbor;
  final String switchName;

  TrackConnection({required this.neighbor, required this.switchName});
}

class YardController {
  // Active state of each switch: true = CLOSED (conducting), false = OPEN (isolated)
  final Map<String, bool> switchStates = {};

  // Track state cache calculated dynamically after switch toggles: true = Hot, false = Dead
  final Map<String, bool> trackStates = {};

  // Holds the coordinate locations for all clickable switches
  Map<String, List<double>> switchCoordinates = {};

  // Define the master power feeds (where power enters the yard)
  // For safety/default, we assume power is fed into these main boundaries:
  final List<String> powerSources = [
    'SeasideInFeeder1',
    'SeasideInFeeder2',
    'LandsideInFeeder1',
    'LandsideInFeeder2',
  ];

  // The connectivity graph representing how track sections touch via switches
  final Map<String, List<TrackConnection>> networkGraph = {
    // Seaside Outfeed connects to Landside Outfeed via C35 (Normally Open)
    'SeasideOutFeed': [
      TrackConnection(neighbor: 'LandsideOutFeed', switchName: 'C35'),
      TrackConnection(neighbor: 'C32R53to59', switchName: 'C10'),
    ],
    
    // Landside Outfeed (Aqua) has 4 parallel redundant feeds!
    'LandsideOutFeed': [
      TrackConnection(neighbor: 'SeasideOutFeed', switchName: 'C35'),
      TrackConnection(neighbor: 'C22R1to7', switchName: 'C15'),
      TrackConnection(neighbor: 'C21R8to15', switchName: 'C14'),
      TrackConnection(neighbor: 'C20R16to23', switchName: 'C13'),
      TrackConnection(neighbor: 'C19R24to31', switchName: 'C12'),
    ],

    // Individual bus sections separated by series switches
    'C32R53to59': [
      TrackConnection(neighbor: 'SeasideOutFeed', switchName: 'C10'),
      TrackConnection(neighbor: 'C16R46to52', switchName: 'C32'),
    ],
    'C16R46to52': [
      TrackConnection(neighbor: 'C32R53to59', switchName: 'C32'),
      TrackConnection(neighbor: 'C17R40to45', switchName: 'C16'),
    ],
    'C17R40to45': [
      TrackConnection(neighbor: 'C16R46to52', switchName: 'C16'),
      TrackConnection(neighbor: 'C18R32to39', switchName: 'C17'),
    ],
    'C18R32to39': [
      TrackConnection(neighbor: 'C17R40to45', switchName: 'C17'),
      TrackConnection(neighbor: 'C19R24to31', switchName: 'C18'),
    ],
    'C19R24to31': [
      TrackConnection(neighbor: 'C18R32to39', switchName: 'C18'),
      TrackConnection(neighbor: 'C20R16to23', switchName: 'C19'),
      TrackConnection(neighbor: 'LandsideOutFeed', switchName: 'C12'), // Redundant path to Aqua
    ],
    'C20R16to23': [
      TrackConnection(neighbor: 'C19R24to31', switchName: 'C19'),
      TrackConnection(neighbor: 'C21R8to15', switchName: 'C20'),
      TrackConnection(neighbor: 'LandsideOutFeed', switchName: 'C13'), // Redundant path to Aqua
    ],
    'C21R8to15': [
      TrackConnection(neighbor: 'C20R16to23', switchName: 'C20'),
      TrackConnection(neighbor: 'C22R1to7', switchName: 'C21'),
      TrackConnection(neighbor: 'LandsideOutFeed', switchName: 'C14'), // Redundant path to Aqua
    ],
    'C22R1to7': [
      TrackConnection(neighbor: 'C21R8to15', switchName: 'C21'),
      TrackConnection(neighbor: 'LandsideOutFeed', switchName: 'C15'), // Redundant path to Aqua
    ],
  };

  Future<void> initializeYardData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/kgx_switch-coords.json');
      switchCoordinates = Map<String, List<double>>.from(jsonDecode(jsonString).map(
        (key, value) => MapEntry(key, List<double>.from(value))
      ));
      
      rawSvgTemplate = await rootBundle.loadString('assets/kgx_yard_map.svg');
      
      initializeDefaultStates();
    } catch (e) {
      print("Error loading yard data: $e");
    }
  }

  void initializeDefaultStates() {
    // Define all switch names
    List<String> switches = [
      'C32', 'C16', 'C17', 'C18', 'C19', 'C20', 'C21', 'C22',
      'C25', 'T31', 'C24', 'C23', 'C10', 'C15', 'C12', 'C13', 'C14',
      'C35' // Emergency Bypass Switch
    ];

    for (var sw in switches) {
      if (sw == 'C35') {
        switchStates[sw] = false; // "Normally Open" (Emergency only)
      } else {
        switchStates[sw] = true;  // "Normally Closed" (Energized defaults)
      }
    }

    // Run the initial connectivity check
    recalculateTrackEnergization();
  }

  /// Traverses the entire electrical graph starting from power feeds.
  /// Any section connected to a source via closed switches stays energized.
  void recalculateTrackEnergization() {
    // Set all track sections to unenergized by default
    networkGraph.keys.forEach((trackId) {
      trackStates[trackId] = false;
    });
    for (var source in powerSources) {
      trackStates[source] = true; 
    }

    // Queue for Breadth-First Search (BFS)
    List<String> queue = [];
    Set<String> visited = {};

    // Seed our search with active power source sections
    for (var source in powerSources) {
      queue.add(source);
      visited.add(source);
    }

    while (queue.isNotEmpty) {
      String current = queue.removeAt(0);
      trackStates[current] = true; // This track is verified ENERGIZED

      // Check all neighbors linked to this segment
      List<TrackConnection>? connections = networkGraph[current];
      if (connections != null) {
        for (var conn in connections) {
          // If the switch bridging these two tracks is CLOSED (active/true)
          bool switchIsClosed = switchStates[conn.switchName] ?? false;

          if (switchIsClosed && !visited.contains(conn.neighbor)) {
            visited.add(conn.neighbor);
            queue.add(conn.neighbor);
          }
        }
      }
    }
  }

  void toggleSwitch(String switchName) {
    if (switchStates.containsKey(switchName)) {
      switchStates[switchName] = !switchStates[switchName]!;
      
      // Every time a switch position flips, recalculate electrical flow!
      recalculateTrackEnergization();
      print("Switch $switchName toggled. State is now: ${switchStates[switchName]}");
    }
  }

  /// Strips color to #444444 inside any track groups that lost connection to power sources
  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;
    final RegExp hexStrokeRegex = RegExp(r'stroke="#[0-9a-fA-F]{6}"');
    final RegExp hexFillRegex = RegExp(r'fill="#[0-9a-fA-F]{6}"');

    trackStates.forEach((groupId, isEnergized) {
      if (!isEnergized) {
        final String searchString = '<g id="$groupId">';
        int groupStartIndex = workingCopy.indexOf(searchString);
        
        if (groupStartIndex != -1) {
          int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
          if (groupEndIndex != -1) {
            String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);
            
            groupContent = groupContent
                .replaceAll(hexStrokeRegex, 'stroke="#444444"')
                .replaceAll(hexFillRegex, 'fill="#444444"');
            
            workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
          }
        }
      }
    });

    return workingCopy;
  }
}