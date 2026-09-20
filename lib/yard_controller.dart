import 'dart:convert';
import 'package:flutter/services.dart';

/// Defines switch metadata for UI tracking
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

/// Represents an edge in the electrical graph connecting two track sections across a switch
class YardConnection {
  final String sectionA;
  final String sectionB;
  final String switchName;

  const YardConnection(this.sectionA, this.sectionB, this.switchName);
}

class YardController {
  String rawSvgTemplate = '';
  Map<String, List<double>> switchCoordinates = {};
  final Map<String, bool> switchStates = {};

  // Section Insulators dictionary mapping switches to physical insulators
  final Map<String, List<String>> switchSectionInsulators = {
    'C24' : ['H2'],
    'C16' : ['H4'],
    'C32' : ['H19', 'H20'],
    'C17' : ['H5'],
    'C10' : ['H27'],
    'C35' : ['H35'],
    'C25' : ['H3'],
    'C22' : ['H16'],
    'C15' : ['H26'],
    'C18' : ['H6', 'H35', 'H21'],
    'C19' : ['H7'],
    'C12' : ['H22', 'H8'],
    'C13' : ['H23', 'H9', 'H10', 'H11'],
    'C14' : ['H25'],
    'C20' : ['H9', 'H10', 'H11'], 
    'C21' : ['H14'], 
  };

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
    const SwitchDefinition(name: 'C15', trackGroupId: 'LandsideOutFeed'),
    const SwitchDefinition(name: 'C14', trackGroupId: 'LandsideOutFeed'),
    const SwitchDefinition(name: 'C13', trackGroupId: 'LandsideOutFeed'),
    const SwitchDefinition(name: 'C12', trackGroupId: 'LandsideOutFeed'),
    const SwitchDefinition(name: 'C10', trackGroupId: 'SeasideOutFeed'),
    const SwitchDefinition(name: 'C35', trackGroupId: 'C35_Isolator', initialClosed: false),
  ];

  /// Topological graph connections representing switch bridges between track sections
  final List<YardConnection> yardTopology = const [
    YardConnection('SeasideInFeeder1',  'SeasideInFeeder2',  'C24'),
    YardConnection('SeasideInFeeder2',  'C16R46to52',        'C16'),
    YardConnection('C16R46to52',        'C32R53to59',        'C32'),
    YardConnection('SeasideInFeeder2',  'C17R40to45',        'C17'),
    YardConnection('C17R40to45',        'SeasideOutFeed',    'C10'),
    YardConnection('SeasideOutFeed',    'LandsideOutFeed',   'C35'),
    YardConnection('LandsideInFeeder1', 'LandsideInFeeder2',  'C25'),
    YardConnection('LandsideInFeeder2', 'C18R32to39',        'C18'),
    YardConnection('LandsideInFeeder2', 'C19R24to31',        'C19'),
    YardConnection('C19R24to31',        'LandsideOutFeed',   'C12'),
    YardConnection('LandsideInFeeder2', 'C20R16to23',        'C20'),
    YardConnection('C20R16to23',        'LandsideOutFeed',   'C13'),
    YardConnection('LandsideInFeeder2', 'C21R8to15',         'C21'),
    YardConnection('C21R8to15',        'LandsideOutFeed',   'C14'),
    YardConnection('LandsideInFeeder2', 'C22R1to7',          'C22'),
    YardConnection('C22R1to7',          'LandsideOutFeed',   'C15'),
  ];

  Future<void> initializeYardData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/kgx_switch-coords.json');
      switchCoordinates = Map<String, List<double>>.from(jsonDecode(jsonString).map(
        (key, value) => MapEntry(key, List<double>.from(value))
      ));
      
      rawSvgTemplate = await rootBundle.loadString('assets/kgx_yard_map.svg');
      
      for (var definition in switchDefinitions) {
        switchStates[definition.name] = definition.initialClosed;
      }
    } catch (e) {
      print("Error loading yard data: $e");
    }
  }

  void toggleSwitch(String switchName) {
    if (switchStates.containsKey(switchName)) {
      switchStates[switchName] = !switchStates[switchName]!;
    }
  }

  /// Evaluates track energization states using Breadth-First Search (BFS) graph traversal
  Map<String, bool> _evaluateTrackStates({
    List<String> activeSources = const ['SeasideInFeeder1', 'LandsideInFeeder1'],
  }) {
    final Map<String, bool> trackStates = {};
    
    // 1. Build Adjacency Map from Topology
    final Map<String, List<YardConnection>> adjacencyMap = {};
    for (var conn in yardTopology) {
      adjacencyMap.putIfAbsent(conn.sectionA, () => []).add(conn);
      adjacencyMap.putIfAbsent(conn.sectionB, () => []).add(conn);
    }

    // 2. Initialize Queue with Active Infeed Substation Sources
    final List<String> queue = List.from(activeSources);
    for (String source in activeSources) {
      trackStates[source] = true;
    }

    // 3. BFS Graph Traversal
    while (queue.isNotEmpty) {
      final String currentSection = queue.removeAt(0);

      final connections = adjacencyMap[currentSection] ?? [];
      for (var conn in connections) {
        final String neighbor = (conn.sectionA == currentSection) ? conn.sectionB : conn.sectionA;
        final bool isSwitchClosed = switchStates[conn.switchName] ?? true;

        // If the connecting switch is closed and the adjacent track isn't energized yet
        if (isSwitchClosed && !(trackStates[neighbor] ?? false)) {
          trackStates[neighbor] = true;
          queue.add(neighbor); // Enqueue neighbor to explore further outward
        }
      }
    }

    // 4. Set Isolator switch state indicator
    trackStates['C35_Isolator'] = switchStates['C35'] ?? false;

    return trackStates;
  }

  String buildDynamicSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;
    final computedTrackStates = _evaluateTrackStates();

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
          
          if (trackDescriptions.containsKey(trackGroupId)) {
            final String tooltipXml = '<title>${trackDescriptions[trackGroupId]}</title>';
            groupContent = groupContent.replaceFirst('>', '>\n$tooltipXml');
          }

          if (!isEnergized) {
            final List<String> targetColors = [
              '#0000ff', '#00ffff', '#cc65ff', '#ff0000', '#65ff00', '#ffcc00', '#965c00',
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

  /// Generates an SVG string inverted for WHITE PAPER printing including switch nodes
  String buildPrintableSvgCode() {
    if (rawSvgTemplate.isEmpty) return '';

    String workingCopy = rawSvgTemplate;
    final computedTrackStates = _evaluateTrackStates();

    workingCopy = workingCopy.replaceAll('fill="#121212"', 'fill="#ffffff"');
    workingCopy = workingCopy.replaceAll('fill="#000000"', 'fill="#ffffff"');
    workingCopy = workingCopy.replaceAll('background:#121212', 'background:#ffffff');

    computedTrackStates.forEach((trackGroupId, isEnergized) {
      final String searchString = '<g id="$trackGroupId">';
      final int groupStartIndex = workingCopy.indexOf(searchString);

      if (groupStartIndex != -1) {
        final int groupEndIndex = workingCopy.indexOf('</g>', groupStartIndex);
        if (groupEndIndex != -1) {
          String groupContent = workingCopy.substring(groupStartIndex, groupEndIndex);

          if (isEnergized) {
            groupContent = groupContent.replaceAll('stroke-width="2"', 'stroke-width="4"');
            final List<String> targetColors = [
              '#0000ff', '#00ffff', '#cc65ff', '#ff0000', '#65ff00', '#ffcc00', '#965c00',
            ];
            for (String color in targetColors) {
              groupContent = groupContent.replaceAll('stroke="$color"', 'stroke="#000000"');
            }
          } else {
            groupContent = groupContent.replaceAll('stroke-width="2"', 'stroke-width="1.5"');
            final List<String> targetColors = [
              '#0000ff', '#00ffff', '#cc65ff', '#ff0000', '#65ff00', '#ffcc00', '#965c00', '#444444'
            ];
            for (String color in targetColors) {
              groupContent = groupContent.replaceAll('stroke="$color"', 'stroke="#bbbbbb"');
              groupContent = groupContent.replaceAll('fill="$color"', 'fill="#bbbbbb"');
            }
          }
          workingCopy = workingCopy.replaceRange(groupStartIndex, groupEndIndex, groupContent);
        }
      }
    });

    StringBuffer switchNodesSvg = StringBuffer();
    switchNodesSvg.write('<g id="PrintableSwitchNodes">');

    switchCoordinates.forEach((switchName, coords) {
      if (coords.length >= 2) {
        final double x = coords[0];
        final double y = coords[1];
        final bool isClosed = switchStates[switchName] ?? true;

        if (isClosed) {
          switchNodesSvg.write('''
            <circle cx="$x" cy="$y" r="14" fill="#ffffff" stroke="#000000" stroke-width="3"/>
            <text x="$x" y="${y + 4}" font-family="Arial" font-size="10" font-weight="bold" fill="#000000" text-anchor="middle">$switchName</text>
          ''');
        } else {
          switchNodesSvg.write('''
            <circle cx="$x" cy="$y" r="14" fill="#f0f0f0" stroke="#888888" stroke-width="1.5" stroke-dasharray="3,2"/>
            <text x="$x" y="${y + 4}" font-family="Arial" font-size="9" font-weight="bold" fill="#888888" text-anchor="middle">$switchName</text>
          ''');
        }
      }
    });

    switchNodesSvg.write('</g>');

    final int closingSvgIndex = workingCopy.lastIndexOf('</svg>');
    if (closingSvgIndex != -1) {
      workingCopy = workingCopy.replaceRange(
        closingSvgIndex,
        closingSvgIndex,
        '${switchNodesSvg.toString()}\n',
      );
    }

    return workingCopy;
  }

  /// Generates a structured summary of isolated switches and their section insulators
  String getIsolatedSwitchesSummary() {
    final openSwitches = switchStates.entries
        .where((entry) => !entry.value)
        .map((entry) => entry.key)
        .toList();

    if (openSwitches.isEmpty) return 'None (Normal Feeding)';

    List<String> formattedEntries = [];
    for (String sw in openSwitches) {
      if (switchSectionInsulators.containsKey(sw) &&
          switchSectionInsulators[sw]!.isNotEmpty) {
        final insulators = switchSectionInsulators[sw]!.join(', ');
        formattedEntries.add('$sw ($insulators)');
      } else {
        formattedEntries.add(sw);
      }
    }

    return formattedEntries.join(' | ');
  }
}