import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' show cos, asin, sqrt, Random;
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const SafePassageApp());
}

class SafePassageApp extends StatelessWidget {
  const SafePassageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafePassage',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1326),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF4EDEA3),
          surface: Color(0xFF171F33),
          error: Color(0xFFFFB4AB),
          onSurface: Color(0xFFDAE2FD),
          onSurfaceVariant: Color(0xFFC7C4D7),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFDAE2FD)),
          headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFFDAE2FD)),
          bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, color: Color(0xFFC7C4D7)),
          labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFDAE2FD)),
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return const MapScreen();
      case 1:
        return const ReportScreen();
      case 2:
        return const TimelineScreen();
      default:
        return const MapScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _getScreen(_selectedIndex),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF131B2E),
          border: Border(
            top: BorderSide(color: Colors.white12, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFFC0C1FF),
          unselectedItemColor: const Color(0xFFC7C4D7).withValues(alpha: 0.5),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.add_location_alt_outlined),
              activeIcon: Icon(Icons.add_location_alt),
              label: 'Report',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'Timeline',
            ),
          ],
        ),
      ),
    );
  }
}

class NavigationStep {
  final String instruction;
  final double distance;
  final double duration;
  final String name;

  NavigationStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.name,
  });
}

class SafetyRoute {
  final List<LatLng> points;
  final String name;
  final double distance;
  final int durationMinutes;
  final bool isSafe;
  final String description;
  final List<NavigationStep> steps;

  SafetyRoute({
    required this.points,
    required this.name,
    required this.distance,
    required this.durationMinutes,
    required this.isSafe,
    required this.description,
    required this.steps,
  });
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<dynamic> _safePoints = [];
  List<dynamic> _unsafeZones = [];
  bool _isLoading = true;
  String _activeLocationName = '';
  double _activeLatitude = 28.6139;
  double _activeLongitude = 77.2090;

  String _originName = 'Current Location';
  double _originLatitude = 28.6139;
  double _originLongitude = 77.2090;

  double _userLatitude = 28.6139;
  double _userLongitude = 77.2090;

  double _currentZoom = 15.0;
  LatLng _currentCenter = const LatLng(28.6139, 77.2090);
  bool _showDirections = false;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _originController = TextEditingController();
  final MapController _mapController = MapController();
  final String _backendUrl = 'http://localhost:3000';
  final Random _random = Random(42);

  bool _showNotification = false;
  String _notificationText = '';
  bool _isDemoRunning = false;
  int _demoStep = 0;
  Timer? _demoTimer;
  LatLng? _simulatedUserLatLng;

  List<SafetyRoute> _routes = [];
  int _selectedRouteIndex = 0;
  String _distanceText = '';
  String _timeText = '';
  bool _hasRoute = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocation();
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _searchController.dispose();
    _originController.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    setState(() {
      _isLoading = true;
    });
    try {
      if (!kIsWeb) {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(const Duration(seconds: 2));
        if (!serviceEnabled) {
          throw Exception();
        }
      }
      LocationPermission permission = await Geolocator.checkPermission().timeout(const Duration(seconds: 2));
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(const Duration(seconds: 4));
        if (permission == LocationPermission.denied) {
          throw Exception();
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception();
      }
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      if (mounted) {
        setState(() {
          _userLatitude = position.latitude;
          _userLongitude = position.longitude;
          _originLatitude = position.latitude;
          _originLongitude = position.longitude;
          _originName = 'Current Location';
          _activeLatitude = position.latitude;
          _activeLongitude = position.longitude;
          _activeLocationName = '';
          _safePoints = [];
          _unsafeZones = [];
          _routes = [];
          _selectedRouteIndex = 0;
          _distanceText = '';
          _timeText = '';
          _hasRoute = false;
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.move(LatLng(position.latitude, position.longitude), 15.0);
          } catch (_) {}
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _originLatitude = 28.6139;
          _originLongitude = 77.2090;
          _originName = 'Delhi';
          _activeLatitude = 28.6139;
          _activeLongitude = 77.2090;
          _activeLocationName = '';
          _safePoints = [];
          _unsafeZones = [];
          _routes = [];
          _selectedRouteIndex = 0;
          _distanceText = '';
          _timeText = '';
          _hasRoute = false;
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.move(LatLng(28.6139, 77.2090), 15.0);
          } catch (_) {}
        });
      }
    }
  }

  void _resetMapState() {
    _searchController.clear();
    _originController.clear();
    setState(() {
      _routes = [];
      _selectedRouteIndex = 0;
      _distanceText = '';
      _timeText = '';
      _hasRoute = false;
      _showDirections = false;
      _activeLocationName = '';
      _safePoints = [];
      _unsafeZones = [];
      _originLatitude = _userLatitude;
      _originLongitude = _userLongitude;
      _originName = 'Current Location';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(LatLng(_userLatitude, _userLongitude), 15.0);
      } catch (_) {}
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Search cleared. Ready for a new route.'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF6366F1),
      ),
    );
  }

  void _triggerNotification(String text) {
    setState(() {
      _notificationText = text;
      _showNotification = true;
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _showNotification = false;
        });
      }
    });
  }

  void _fitMapToRoute() {
    try {
      if (_routes.isEmpty || _selectedRouteIndex >= _routes.length) return;
      final points = _routes[_selectedRouteIndex].points;
      if (points.isEmpty) return;
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(top: 100.0, bottom: 260.0, left: 50.0, right: 50.0),
        ),
      );
    } catch (_) {
      final midLat = (_originLatitude + _activeLatitude) / 2;
      final midLng = (_originLongitude + _activeLongitude) / 2;
      _mapController.move(LatLng(midLat, midLng), 13.0);
    }
  }

  double _getDistanceInMiles(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
        (1 - cos((lon2 - lon1) * p)) / 2;
    final distanceInKm = 12742 * asin(sqrt(a));
    return distanceInKm * 0.621371;
  }

  String _buildStepInstruction(String type, String modifier, String name) {
    final roadName = name.isEmpty ? 'local street' : name;
    switch (type) {
      case 'depart':
        return 'Head toward $roadName';
      case 'arrive':
        return 'Arrive at destination';
      case 'merge':
        return 'Merge onto $roadName';
      case 'fork':
        return 'Take the fork ${modifier.replaceAll('_', ' ')} onto $roadName';
      case 'roundabout':
        return 'Enter the roundabout and take exit onto $roadName';
      case 'turn':
        if (modifier.isNotEmpty) {
          return 'Turn ${modifier.replaceAll('_', ' ')} onto $roadName';
        }
        return 'Turn onto $roadName';
      default:
        if (modifier.isNotEmpty) {
          return 'Turn ${modifier.replaceAll('_', ' ')} onto $roadName';
        }
        return 'Continue on $roadName';
    }
  }

  Future<SafetyRoute?> _getOSRMRoute({
    required LatLng start,
    required LatLng end,
    LatLng? waypoint,
    required String name,
    required bool isSafe,
    required String description,
  }) async {
    final coordsString = waypoint != null
        ? '${start.longitude},${start.latitude};${waypoint.longitude},${waypoint.latitude};${end.longitude},${end.latitude}'
        : '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
    final url = 'https://router.project-osrm.org/route/v1/driving/$coordsString?overview=full&geometries=geojson&steps=true';
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final routeData = data['routes'][0];
          final geometry = routeData['geometry'];
          final distanceMeters = (routeData['distance'] as num).toDouble();
          final durationSeconds = (routeData['duration'] as num).toDouble();
          final distanceMiles = distanceMeters * 0.000621371;
          final durationMinutes = (durationSeconds / 60.0).round();
          final List<LatLng> points = [];
          if (geometry != null && geometry['coordinates'] != null) {
            final List<dynamic> coords = geometry['coordinates'];
            for (final coord in coords) {
              points.add(LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              ));
            }
          }
          final List<NavigationStep> steps = [];
          if (routeData['legs'] != null) {
            for (final leg in routeData['legs']) {
              if (leg['steps'] != null) {
                for (final step in leg['steps']) {
                  final sName = step['name'] as String? ?? '';
                  final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
                  final type = maneuver['type'] as String? ?? '';
                  final modifier = maneuver['modifier'] as String? ?? '';
                  final stepDist = (step['distance'] as num?)?.toDouble() ?? 0.0;
                  final stepDuration = (step['duration'] as num?)?.toDouble() ?? 0.0;
                  steps.add(NavigationStep(
                    instruction: _buildStepInstruction(type, modifier, sName),
                    distance: stepDist,
                    duration: stepDuration,
                    name: sName,
                  ));
                }
              }
            }
          }
          return SafetyRoute(
            points: points,
            name: name,
            distance: distanceMiles,
            durationMinutes: durationMinutes > 0 ? durationMinutes : 1,
            isSafe: isSafe,
            description: description,
            steps: steps,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _fetchOSRMRoutes() async {
    final start = LatLng(_originLatitude, _originLongitude);
    final end = LatLng(_activeLatitude, _activeLongitude);
    LatLng? safeWaypoint;
    if (_safePoints.isNotEmpty) {
      final sp = _safePoints[0];
      final lat = (sp['latitude'] as num?)?.toDouble();
      final lng = (sp['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        safeWaypoint = LatLng(lat, lng);
      }
    }
    LatLng? unsafeWaypoint;
    if (_unsafeZones.isNotEmpty) {
      final uz = _unsafeZones[0];
      final lat = (uz['latitude'] as num?)?.toDouble();
      final lng = (uz['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        unsafeWaypoint = LatLng(lat, lng);
      }
    }
    final List<SafetyRoute> fetchedRoutes = [];
    final route1 = await _getOSRMRoute(
      start: start,
      end: end,
      waypoint: safeWaypoint,
      name: 'Safe Passage',
      isSafe: true,
      description: 'Well-Lit & Busy Streets',
    );
    if (route1 != null) fetchedRoutes.add(route1);
    final route2 = await _getOSRMRoute(
      start: start,
      end: end,
      waypoint: null,
      name: 'Main Street',
      isSafe: true,
      description: 'Alternative Main Street Route',
    );
    if (route2 != null) fetchedRoutes.add(route2);
    final route3 = await _getOSRMRoute(
      start: start,
      end: end,
      waypoint: unsafeWaypoint,
      name: 'High-Risk Alley',
      isSafe: false,
      description: 'Poorly Lit / High-Risk Zones',
    );
    if (route3 != null) fetchedRoutes.add(route3);
    if (fetchedRoutes.isEmpty) {
      final fallbackPoints = [start, end];
      fetchedRoutes.add(SafetyRoute(
        points: fallbackPoints,
        name: 'Safe Passage',
        distance: _getDistanceInMiles(start.latitude, start.longitude, end.latitude, end.longitude),
        durationMinutes: 5,
        isSafe: true,
        description: 'Direct Pathway',
        steps: [
          NavigationStep(
            instruction: 'Head toward destination',
            distance: 0,
            duration: 0,
            name: '',
          )
        ],
      ));
    }
    setState(() {
      _routes = fetchedRoutes;
    });
  }

  Future<void> _startNavigationQuery() async {
    final origin = _originController.text.trim();
    final destination = _searchController.text.trim();
    if (destination.isEmpty) return;
    setState(() {
      _isLoading = true;
      _isDemoRunning = false;
      _showDirections = false;
      _simulatedUserLatLng = null;
      _safePoints = [];
      _unsafeZones = [];
      _routes = [];
      _selectedRouteIndex = 0;
      _distanceText = '';
      _timeText = '';
      _hasRoute = false;
    });
    _demoTimer?.cancel();
    try {
      double? oLat;
      double? oLng;
      if (origin.isNotEmpty && origin != "Current Location") {
        final originCoords = await _geocodeLocation(origin, nearLat: _userLatitude, nearLon: _userLongitude);
        if (originCoords != null) {
          oLat = originCoords[0];
          oLng = originCoords[1];
        }
      } else {
        oLat = _originLatitude;
        oLng = _originLongitude;
      }
      final destCoords = await _geocodeLocation(destination, nearLat: _userLatitude, nearLon: _userLongitude);
      double? dLat;
      double? dLng;
      if (destCoords != null) {
        dLat = destCoords[0];
        dLng = destCoords[1];
      }
      if (dLat == null || dLng == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Destination not found. Please try another search.')),
          );
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      if (origin.isNotEmpty && origin != "Current Location" && (oLat == null || oLng == null)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Origin not found. Using current GPS location.')),
          );
        }
        oLat = _originLatitude;
        oLng = _originLongitude;
      }
      setState(() {
        _activeLatitude = dLat!;
        _activeLongitude = dLng!;
        _activeLocationName = destination;
        _originLatitude = oLat!;
        _originLongitude = oLng!;
        _originName = origin.isEmpty ? 'Current Location' : origin;
      });
      final rawDirectDist = _getDistanceInMiles(_originLatitude, _originLongitude, _activeLatitude, _activeLongitude);
      if (rawDirectDist > 500.0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Destination seems too far. Please check the location name and try again.'),
              duration: Duration(seconds: 4),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
          setState(() {
            _isLoading = false;
            _hasRoute = false;
            _routes = [];
            _activeLocationName = '';
          });
        }
        return;
      }
      final response = await http.post(
        Uri.parse('$_backendUrl/api/simulation/start'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'location': destination,
          'latitude': _activeLatitude,
          'longitude': _activeLongitude,
          'origin': _originName,
          'origin_latitude': _originLatitude,
          'origin_longitude': _originLongitude,
        }),
      );
      if (response.statusCode == 200) {
        await _fetchPoints();
        await _fetchOSRMRoutes();
        if (mounted) {
          setState(() {
            _selectedRouteIndex = 0;
            if (_routes.isNotEmpty) {
              final activeRoute = _routes[_selectedRouteIndex];
              _distanceText = '${activeRoute.distance.toStringAsFixed(1)} miles';
              _timeText = '${activeRoute.durationMinutes} min';
              _hasRoute = true;
            }
            _isLoading = false;
          });
          _fitMapToRoute();
        }
      } else {
        throw Exception();
      }
    } catch (e) {
      debugPrint('Error starting navigation: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to calculate navigation route.')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _runDemoStep() {
    if (_routes.isEmpty || _selectedRouteIndex >= _routes.length) {
      _triggerNotification("No routes generated yet.");
      return;
    }

    final activeRoute = _routes[_selectedRouteIndex];
    final List<LatLng> demoPath = List.from(activeRoute.points);

    if (activeRoute.isSafe && _routes.length > 2 && _routes[2].points.length > 1) {
      final unsafePoint = _routes[2].points[1];
      if (demoPath.length > 2) {
        demoPath.insert(2, unsafePoint);
      }
    }

    List<String> demoStepsLogs = [
      "Starting Demo: Walking home from origin...",
      "Walking on Recommended Safe Route (Well-Lit & Busy)...",
      "Alert: User is veering off course towards a dark alleyway!",
      "WARNING: Entered Unsafe Zone (Poorly Lit Alley)! Triggering safety protocols.",
      "Safety Alert: Re-routing user back to Safe Route...",
      "Journey completed. Arrived safely at destination!"
    ];

    while (demoStepsLogs.length < demoPath.length) {
      demoStepsLogs.add("Walking towards destination...");
    }

    setState(() {
      _isDemoRunning = true;
      _demoStep = 0;
    });

    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted || !_isDemoRunning) {
        timer.cancel();
        return;
      }

      if (_demoStep >= demoPath.length) {
        setState(() {
          _isDemoRunning = false;
          _simulatedUserLatLng = null;
        });
        timer.cancel();
        return;
      }

      final currentLatLng = demoPath[_demoStep];
      final currentMsg = demoStepsLogs[_demoStep];

      setState(() {
        _simulatedUserLatLng = currentLatLng;
      });

      _mapController.move(currentLatLng, 15.5);

      if (activeRoute.isSafe && _demoStep == 2) {
        _triggerNotification("⚠️ Warning: Veered off course towards Unsafe Zone!");
      } else if (activeRoute.isSafe && _demoStep == 3) {
        _triggerNotification("🚨 [Guardians Notified] Live location link sent to Mom & Brother!");
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF171F33),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB4AB)),
                SizedBox(width: 10),
                Text('UNSAFE ZONE DETECTED'),
              ],
            ),
            content: const Text(
              'You have entered a poorly lit area. Stealth SOS mode has shared your live location with pre-selected trusted contacts.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: Color(0xFF6366F1))),
              )
            ],
          ),
        );
      } else if (activeRoute.isSafe && _demoStep == 4) {
        _triggerNotification("🔄 Recalculating path... Re-routing back to safety.");
      } else if (_demoStep == demoPath.length - 1) {
        _triggerNotification("✅ Arrived Safely at Destination!");
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentMsg),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF171F33),
          ),
        );
      }

      setState(() {
        _demoStep++;
      });
    });
  }

  Future<void> _fetchPoints() async {
    try {
      final pointsResponse = await http.get(Uri.parse('$_backendUrl/api/safety-points'));
      if (pointsResponse.statusCode == 200) {
        final pointsData = json.decode(pointsResponse.body);
        setState(() {
          _safePoints = pointsData['safety_points'] ?? [];
          _unsafeZones = pointsData['unsafe_zones'] ?? [];
        });
      } else {
        throw Exception();
      }
    } catch (e) {
      debugPrint('Error fetching points: $e');
    }
  }

  Future<List<double>?> _geocodeLocation(String query, {double? nearLat, double? nearLon}) async {
    try {
      String geocodeParams = 'q=${Uri.encodeComponent(query.trim())}';
      if (nearLat != null && nearLon != null) {
        geocodeParams += '&lat=${nearLat.toStringAsFixed(6)}&lon=${nearLon.toStringAsFixed(6)}&radius=0.8';
      }
      final uri = Uri.parse('$_backendUrl/api/geocode?$geocodeParams');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lat = (data['lat'] as num?)?.toDouble();
        final lon = (data['lon'] as num?)?.toDouble();
        final source = data['source'] as String?;
        if (lat != null && lon != null && source == 'nominatim') {
          return [lat, lon];
        }
      }
    } catch (e) {
      debugPrint('Geocode proxy error: $e');
    }
    return null;
  }

  void _triggerStealthSOS() {
    _triggerNotification("🚨 [Guardians Notified] Live location link sent to Mom & Brother!");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171F33),
        title: const Row(
          children: [
            Icon(Icons.shield, color: Color(0xFF4EDEA3)),
            SizedBox(width: 10),
            Text('STEALTH SOS TRIGGERED'),
          ],
        ),
        content: Text(
          'Emergency SOS broadcast initialized. Your coordinates at ${_activeLocationName.isEmpty ? _originName : _activeLocationName} are actively being shared with pre-selected trusted contacts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('DISMISS', style: TextStyle(color: Color(0xFF6366F1))),
          )
        ],
      ),
    );
  }

  double _spread({double min = 0.001, double max = 0.003}) {
    final sign = _random.nextBool() ? 1.0 : -1.0;
    return sign * (min + _random.nextDouble() * (max - min));
  }

  List<Marker> get _markers {
    final markers = <Marker>[];

    markers.add(
      Marker(
        point: LatLng(_originLatitude, _originLongitude),
        width: 140,
        height: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF171F33),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
              ),
              child: Text(
                _originName,
                style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.my_location, color: Color(0xFF6366F1), size: 20),
          ],
        ),
      ),
    );

    if (!_hasRoute) {
      return markers;
    }

    markers.add(
      Marker(
        point: LatLng(_activeLatitude, _activeLongitude),
        width: 140,
        height: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF171F33),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFB4AB), width: 1.5),
              ),
              child: Text(
                _activeLocationName,
                style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.location_on, color: Color(0xFFFFB4AB), size: 20),
          ],
        ),
      ),
    );

    if (_isDemoRunning && _simulatedUserLatLng != null) {
      markers.add(
        Marker(
          point: _simulatedUserLatLng!,
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFF6366F1),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      );
    }

    for (final point in _safePoints) {
      final lat = (point['latitude'] as num?)?.toDouble() ?? (_activeLatitude + _spread());
      final lng = (point['longitude'] as num?)?.toDouble() ?? (_activeLongitude + _spread());
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 140,
          height: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF171F33),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF4EDEA3), width: 1),
                ),
                child: Text(
                  point['name'] ?? 'Safe Point',
                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              const Icon(Icons.check_circle, color: Color(0xFF4EDEA3), size: 18),
            ],
          ),
        ),
      );
    }

    for (final zone in _unsafeZones) {
      final lat = (zone['latitude'] as num?)?.toDouble() ?? (_activeLatitude + _spread());
      final lng = (zone['longitude'] as num?)?.toDouble() ?? (_activeLongitude + _spread());
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 140,
          height: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF171F33),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFB4AB), width: 1),
                ),
                child: Text(
                  zone['name'] ?? 'Unsafe Zone',
                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              const Icon(Icons.warning, color: Color(0xFFFFB4AB), size: 18),
            ],
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _activeLocationName.isEmpty ? 'SafePassage Map' : 'SafePassage Map: $_activeLocationName',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF131B2E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Search',
            onPressed: _resetMapState,
          )
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(_activeLatitude, _activeLongitude),
                      initialZoom: 15.0,
                      minZoom: 3,
                      maxZoom: 18,
                      onMapEvent: (MapEvent event) {
                        _currentZoom = event.camera.zoom;
                        _currentCenter = event.camera.center;
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                      ),
                      PolylineLayer(
                        polylines: _routes.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final route = entry.value;
                          final isSelected = idx == _selectedRouteIndex;
                          final baseColor = route.isSafe ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
                          return Polyline(
                            points: route.points,
                            color: isSelected ? baseColor : baseColor.withValues(alpha: 0.35),
                            strokeWidth: isSelected ? 6.0 : 3.5,
                            borderColor: isSelected ? baseColor.withValues(alpha: 0.3) : Colors.transparent,
                            borderStrokeWidth: isSelected ? 3.0 : 0.0,
                          );
                        }).toList(),
                      ),
                      MarkerLayer(
                        markers: _markers,
                      ),
                    ],
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0B1326).withValues(alpha: 0.95),
                    const Color(0xFF0B1326).withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: _buildSearchBar(),
            ),
          ),
          if (_hasRoute)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171F33).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: (_routes[_selectedRouteIndex].isSafe ? const Color(0xFF22C55E) : const Color(0xFFEF4444)).withValues(alpha: 0.3), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: (_routes[_selectedRouteIndex].isSafe ? const Color(0xFF22C55E) : const Color(0xFFEF4444)).withValues(alpha: 0.1),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _routes[_selectedRouteIndex].isSafe ? Icons.verified_user : Icons.warning_amber_rounded,
                        color: _routes[_selectedRouteIndex].isSafe ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _routes[_selectedRouteIndex].isSafe ? 'Well-Lit & Crowded' : 'High-Risk Alley',
                        style: TextStyle(
                          color: _routes[_selectedRouteIndex].isSafe ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: _hasRoute ? 245 : 30,
            right: 20,
            child: FloatingActionButton.large(
              onPressed: _triggerStealthSOS,
              backgroundColor: const Color(0xFF131B2E).withValues(alpha: 0.85),
              shape: const CircleBorder(
                side: BorderSide(color: Color(0x996366F1), width: 2),
              ),
              child: const Icon(
                Icons.shield,
                color: Color(0xFF6366F1),
                size: 40,
              ),
            ),
          ),
          Positioned(
            bottom: _hasRoute ? 310 : 90,
            left: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildZoomButton(
                  icon: Icons.add,
                  onTap: () {
                    final newZoom = (_currentZoom + 1.0).clamp(3.0, 18.0);
                    _mapController.move(_currentCenter, newZoom);
                    setState(() {
                      _currentZoom = newZoom;
                    });
                  },
                ),
                const SizedBox(height: 4),
                _buildZoomButton(
                  icon: Icons.remove,
                  onTap: () {
                    final newZoom = (_currentZoom - 1.0).clamp(3.0, 18.0);
                    _mapController.move(_currentCenter, newZoom);
                    setState(() {
                      _currentZoom = newZoom;
                    });
                  },
                ),
              ],
            ),
          ),
          if (_hasRoute)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF171F33),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TO: ${_activeLocationName.toUpperCase()}',
                        style: const TextStyle(
                          color: Color(0xFFC0C1FF),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _routes.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final route = entry.value;
                            final isSelected = idx == _selectedRouteIndex;
                            final routeColor = route.isSafe ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedRouteIndex = idx;
                                  _distanceText = '${route.distance.toStringAsFixed(1)} miles';
                                  _timeText = '${route.durationMinutes} min';
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? routeColor.withValues(alpha: 0.15) : const Color(0xFF0B1326),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected ? routeColor : Colors.white10,
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          route.isSafe ? Icons.verified_user : Icons.warning_amber_rounded,
                                          color: routeColor,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          route.name,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : Colors.white70,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${route.durationMinutes} min • ${route.distance.toStringAsFixed(1)} mi',
                                      style: TextStyle(
                                        color: isSelected ? routeColor : Colors.white38,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _routes[_selectedRouteIndex].description,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _routes[_selectedRouteIndex].isSafe ? 'Recommended Route' : 'Avoid if possible',
                                style: TextStyle(
                                  color: _routes[_selectedRouteIndex].isSafe ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _timeText,
                                style: TextStyle(
                                  color: _routes[_selectedRouteIndex].isSafe ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _distanceText,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _showDirections = !_showDirections;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(_showDirections ? 'Hide Steps' : 'Start Walking', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isDemoRunning ? null : _runDemoStep,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF22C55E),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(_isDemoRunning ? 'Running...' : 'Demo Drive', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Trip share link copied to clipboard.')),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('Share Trip', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                      if (_showDirections && _routes.isNotEmpty && _selectedRouteIndex < _routes.length) ...[
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 8),
                        const Text(
                          'TURN-BY-TURN DIRECTIONS',
                          style: TextStyle(
                            color: Color(0xFFC0C1FF),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _routes[_selectedRouteIndex].steps.length,
                            itemBuilder: (context, idx) {
                              final step = _routes[_selectedRouteIndex].steps[idx];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      _getDirectionIcon(step.instruction),
                                      color: const Color(0xFFC0C1FF),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            step.instruction,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${(step.distance * 3.28084).round()} ft • ${(step.duration / 60.0).toStringAsFixed(1)} min',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (_showNotification)
            Positioned(
              top: 90,
              left: 20,
              right: 20,
              child: AnimatedOpacity(
                opacity: _showNotification ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.emergency_share, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _notificationText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                        onPressed: () {
                          setState(() {
                            _showNotification = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _useCurrentLocationAsOrigin() {
    setState(() {
      _originLatitude = _userLatitude;
      _originLongitude = _userLongitude;
      _originName = 'Current Location';
      _originController.text = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Origin set to your current GPS location.'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF6366F1),
      ),
    );
  }

  Widget _buildZoomButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF171F33).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  IconData _getDirectionIcon(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('left')) {
      return Icons.arrow_back;
    } else if (lower.contains('right')) {
      return Icons.arrow_forward;
    } else if (lower.contains('arrive')) {
      return Icons.location_on;
    } else if (lower.contains('head') || lower.contains('continue')) {
      return Icons.arrow_upward;
    }
    return Icons.navigation_outlined;
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171F33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.circle_outlined, color: Color(0xFF6366F1), size: 16),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _originController,
                  onSubmitted: (_) => _startNavigationQuery(),
                  decoration: const InputDecoration(
                    hintText: 'Start Location (From)',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _useCurrentLocationAsOrigin,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5), width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.my_location, color: Color(0xFF6366F1), size: 11),
                      SizedBox(width: 3),
                      Text('GPS', style: TextStyle(color: Color(0xFF6366F1), fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 12),
          Row(
            children: [
              const Icon(Icons.location_on, color: Color(0xFFFFB4AB), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _startNavigationQuery(),
                  decoration: const InputDecoration(
                    hintText: 'Choose Destination (To)',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.navigation, color: Color(0xFF4EDEA3), size: 20),
                onPressed: _startNavigationQuery,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedRisk = 'Safe & Busy';
  bool _isSubmitting = false;
  String _activeLocationName = 'Loading...';
  final String _backendUrl = 'http://localhost:3000';

  final List<Map<String, dynamic>> _riskOptions = [
    {
      'label': 'Safe & Busy',
      'icon': Icons.verified_user,
      'color': const Color(0xFF4EDEA3),
      'value': 'Safe & Busy'
    },
    {
      'label': 'Poorly Lit',
      'icon': Icons.wb_twilight,
      'color': const Color(0xFFFFB4AB),
      'value': 'Poorly Lit'
    },
    {
      'label': 'Suspicious Crowd',
      'icon': Icons.group,
      'color': const Color(0xFFE5E7EB),
      'value': 'Suspicious Crowd'
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchActiveLocation();
  }

  Future<void> _fetchActiveLocation() async {
    try {
      final response = await http.get(Uri.parse('$_backendUrl/api/simulation/active'));
      if (response.statusCode == 200) {
        final activeData = json.decode(response.body);
        setState(() {
          _activeLocationName = activeData['name'] ?? 'Active Simulation';
        });
      }
    } catch (e) {
      debugPrint('Error fetching active location: $e');
    }
  }

  Future<void> _submitReport() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title for the report.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/api/reports'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'risk_type': _selectedRisk,
        }),
      );

      if (response.statusCode == 201) {
        _titleController.clear();
        _descriptionController.clear();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Safety pin dropped successfully!')),
        );
      } else {
        throw Exception();
      }
    } catch (e) {
      debugPrint('Error submitting report: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect to Express backend.')),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drop Safety Pin', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF131B2E),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Safety Update',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Reporting for: $_activeLocationName',
              style: const TextStyle(color: Color(0xFFC0C1FF), fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title / Location Name',
                labelStyle: const TextStyle(color: Color(0xFFC7C4D7)),
                filled: true,
                fillColor: const Color(0xFF171F33),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description / Observations',
                labelStyle: const TextStyle(color: Color(0xFFC7C4D7)),
                filled: true,
                fillColor: const Color(0xFF171F33),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Select Safety Status',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Column(
              children: _riskOptions.map((opt) {
                final isSelected = _selectedRisk == opt['value'];
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedRisk = opt['value'];
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? opt['color'].withValues(alpha: 0.15) : const Color(0xFF171F33),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? opt['color'] : Colors.white10,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(opt['icon'], color: opt['color']),
                            const SizedBox(width: 12),
                            Text(
                              opt['label'],
                              style: TextStyle(
                                color: isSelected ? Colors.white : const Color(0xFFC7C4D7),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: isSelected ? opt['color'] : Colors.white24, width: 2),
                            color: isSelected ? opt['color'] : Colors.transparent,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, size: 12, color: Colors.black)
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 4,
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'DROP SAFETY PIN',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<dynamic> _reports = [];
  bool _isLoading = true;
  final String _backendUrl = 'http://localhost:3000';

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.get(Uri.parse('$_backendUrl/api/reports'));
      if (response.statusCode == 200) {
        setState(() {
          _reports = json.decode(response.body);
          _reports.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
          _isLoading = false;
        });
      } else {
        throw Exception();
      }
    } catch (e) {
      debugPrint('Error fetching reports: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Protocol Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF131B2E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchReports,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history, color: Color(0xFFC0C1FF)),
                      SizedBox(width: 8),
                      Text(
                        'Recent Safety Updates',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _reports.isEmpty
                        ? const Center(
                            child: Text(
                              'No safety updates reported yet.\nUse the Report screen to submit one.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _reports.length,
                            itemBuilder: (context, index) {
                              final report = _reports[index];
                              final time = DateTime.parse(report['timestamp']).toLocal();
                              final timeString = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF171F33),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          report['risk_type'] ?? 'Unknown',
                                          style: TextStyle(
                                            color: report['risk_type'] == 'Safe & Busy'
                                                ? const Color(0xFF4EDEA3)
                                                : const Color(0xFFFFB4AB),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          timeString,
                                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      report['title'] ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                    ),
                                    if (report['description'] != null && report['description'].isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        report['description'],
                                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
