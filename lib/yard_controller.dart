import 'dart:convert';
import 'package:flutter/services.dart';

class YardController {
  // Keeps track of which track groups are energized (true) or isolated (false)
  final Map<String, bool> trackStates = {};
  
  // Holds the coordinate locations for all your clickable switch bubbles
Map<String, List<double>> switchCoordinates = {
     
  };

  // 1. Load the JSON data from your asset folder
  Future<void> initializeYardData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/kgx_switch-coords.json');
      switchCoordinates = jsonDecode(jsonString);
      
      // Initialize all track paths to a default state (e.g., true = energized)
      initializeTrackDefaultStates();
    } catch (e) {
      print("Error loading switch coordinates: $e");
    }
  }

  // 2. Set up your default track layout states
  void initializeTrackDefaultStates() {
    // These names match your Illustrator SVG Group IDs exactly!
    List<String> trackGroups = [
      'SeasideOutFeed',
      'LandsideInFeeder1',
      'LandsideInFeeder2',
      'SeasideInFeeder1',
      'SeasideInFeeder2',
      'SeasideOutFeed',
      'LandsideOutFeed',
      '53_to_59',
      '46_to_52',
      '40_to_45',
      '32_to_39',
      '24_to_31',
      '16_to_23',
      '8_to_15',
      '1_to_7'
      
      ''
    ];

    for (var groupId in trackGroups) {
      trackStates[groupId] = true; // Default to fully energized (colored)
    }
  }

  // 3. Logic to toggle states when a switch is flipped
  void toggleSwitch(String switchName) {
    // Example rule logic: Flipping a specific switch isolates a specific track
    if (switchName == 'C32') {
      // Toggle the state of the associated line track group
      trackStates['SeasideOutFeed'] = !trackStates['SeasideOutFeed']!;
    }
      
    print("Switch $switchName flipped! New track states updated.");
  }
}