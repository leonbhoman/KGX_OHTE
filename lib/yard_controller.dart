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

    
    // Add additional switch-to-insulator mappings here as needed
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

  Map<String, bool> _evaluateTrackStates() {
    bool isClosed(String name) => switchStates[name] ?? true;

    final bool rawSeasideFeeder = true;
    final bool forwardC24 = rawSeasideFeeder && isClosed('C24');
    final bool forwardC16 = forwardC24 && isClosed('C16');
    final bool forwardC32 = forwardC16 && isClosed('C32');

    bool landsideInboundBusHasPower = isClosed('C25');
    bool landsideOutfeedHasPower = isClosed('C25') && 
        (isClosed('C12') || isClosed('C13') || isClosed('C14') || isClosed('C15') || isClosed('C18'));

    final bool seasideForwardSupply = forwardC24 && isClosed('C17') && isClosed('C10');
    bool seasideOutfeedHasPower = seasideForwardSupply || (isClosed('C35') && landsideOutfeedHasPower);

    if (isClosed('C35') && seasideOutfeedHasPower) {
      landsideOutfeedHasPower = true;
    }

    if (!landsideInboundBusHasPower && landsideOutfeedHasPower) {
      if ((isClosed('C12') && isClosed('C19')) ||
          (isClosed('C13') && isClosed('C20')) ||
          (isClosed('C14') && isClosed('C21')) ||
          (isClosed('C15') && isClosed('C22')) ||
          isClosed('C18')) {
        landsideInboundBusHasPower = true;
      }
    }

    if (landsideInboundBusHasPower) {
      if (isClosed('C12') || isClosed('C13') || isClosed('C14') || isClosed('C15') || isClosed('C18')) {
        landsideOutfeedHasPower = true;
      }
    }

    return {
      'C16R46to52': forwardC16,
      'C32R53to59': forwardC32,
      'SeasideOutFeed': seasideOutfeedHasPower,
      'C17R40to45': (forwardC24 && isClosed('C17')) || (seasideOutfeedHasPower && isClosed('C10') && isClosed('C17')),
      'LandsideOutFeed': landsideOutfeedHasPower,
      'LandsideInFeeder2': isClosed('C25') || landsideInboundBusHasPower,
      'C18R32to39': landsideInboundBusHasPower && isClosed('C18'),
      'C19R24to31': (landsideInboundBusHasPower && isClosed('C19')) || (landsideOutfeedHasPower && isClosed('C12')),
      'C20R16to23': (landsideInboundBusHasPower && isClosed('C20')) || (landsideOutfeedHasPower && isClosed('C13')),
      'C21R8to15':  (landsideInboundBusHasPower && isClosed('C21')) || (landsideOutfeedHasPower && isClosed('C14')),
      'C22R1to7':   (landsideInboundBusHasPower && isClosed('C22')) || (landsideOutfeedHasPower && isClosed('C15')),
      'SeasideInFeeder1': true, 
      'LandsideInFeeder1': true,
      'SeasideInFeeder2': forwardC24,
      'C35_Isolator': isClosed('C35'),
    };
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