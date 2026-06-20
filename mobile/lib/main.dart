import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' show Random;
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

// ==========================================
// 1. MAP SCREEN
// ==========================================
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<dynamic> _safePoints = [];
  List<dynamic> _unsafeZones = [];
  bool _isLoading = true;
  String _activeLocationName = 'Loading...';
  double _activeLatitude = 28.6139;  // Default: Delhi
  double _activeLongitude = 77.2090;

  // Start/Origin location state
  String _originName = 'Current Location';
  double _originLatitude = 28.6079;
  double _originLongitude = 77.2030;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _originController = TextEditingController();
  final MapController _mapController = MapController();
  final String _backendUrl = 'http://localhost:3000';
  // Seeded random so offsets are stable for a given location per session
  Random _random = Random(42);
  // When true, _fetchPoints won't overwrite lat/lon with backend values
  bool _hasGeocodedCoords = false;

  // Demo Drive and notification state
  bool _showNotification = false;
  String _notificationText = '';
  bool _isDemoRunning = false;
  int _demoStep = 0;
  Timer? _demoTimer;
  LatLng? _simulatedUserLatLng;

  @override
  void initState() {
    super.initState();
    _fetchPoints();
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _searchController.dispose();
    _originController.dispose();
    super.dispose();
  }

  void _triggerNotification(String text) {
    setState(() {
      _notificationText = text;
      _showNotification = true;
    });
    // Auto-dismiss after 5 seconds
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
      final bounds = LatLngBounds(
        LatLng(_originLatitude, _originLongitude),
        LatLng(_activeLatitude, _activeLongitude),
      );
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50.0),
        ),
      );
    } catch (_) {
      final midLat = (_originLatitude + _activeLatitude) / 2;
      final midLng = (_originLongitude + _activeLongitude) / 2;
      _mapController.move(LatLng(midLat, midLng), 13.0);
    }
  }

  Future<void> _startNavigationQuery() async {
    final origin = _originController.text.trim();
    final destination = _searchController.text.trim();
    if (destination.isEmpty) return;

    setState(() {
      _isLoading = true;
      _isDemoRunning = false;
      _simulatedUserLatLng = null;
    });
    _demoTimer?.cancel();

    try {
      // 1. Geocode origin
      double? oLat;
      double? oLng;
      if (origin.isNotEmpty && origin != "Current Location") {
        final originCoords = await _geocodeLocation(origin);
        if (originCoords != null) {
          oLat = originCoords[0];
          oLng = originCoords[1];
        }
      }

      // 2. Geocode destination
      final destCoords = await _geocodeLocation(destination);
      double? dLat;
      double? dLng;
      if (destCoords != null) {
        dLat = destCoords[0];
        dLng = destCoords[1];
      }

      // Update state with coordinates if available
      setState(() {
        if (dLat != null && dLng != null) {
          _activeLatitude = dLat;
          _activeLongitude = dLng;
          _activeLocationName = destination;
          _hasGeocodedCoords = true;
        }
        if (oLat != null && oLng != null) {
          _originLatitude = oLat;
          _originLongitude = oLng;
          _originName = origin;
        }
      });

      // 3. Post to backend simulation to regenerate safety points and database entries
      final response = await http.post(
        Uri.parse('$_backendUrl/api/simulation/start'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'location': destination,
          'latitude': dLat,
          'longitude': dLng,
          'origin': origin.isEmpty ? 'Current Location' : origin,
          'origin_latitude': oLat,
          'origin_longitude': oLng,
        }),
      );

      if (response.statusCode == 200) {
        await _fetchPoints();
        _fitMapToRoute();
      } else {
        throw Exception("Backend navigation start failed");
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
    if (_safePoints.isEmpty || _unsafeZones.isEmpty) {
      _triggerNotification("Unable to run demo: no route or unsafe zones loaded.");
      return;
    }

    final startPoint = LatLng(_originLatitude, _originLongitude);
    final endPoint = LatLng(_activeLatitude, _activeLongitude);
    
    // Extract actual database coordinates for safe points
    final safePoint1 = LatLng(
      (_safePoints[0]['latitude'] as num).toDouble(),
      (_safePoints[0]['longitude'] as num).toDouble(),
    );
    
    // Extract actual database coordinates for unsafe point
    final unsafePoint = LatLng(
      (_unsafeZones[0]['latitude'] as num).toDouble(),
      (_unsafeZones[0]['longitude'] as num).toDouble(),
    );
    
    final safePoint2 = _safePoints.length > 1 
      ? LatLng(
          (_safePoints[1]['latitude'] as num).toDouble(),
          (_safePoints[1]['longitude'] as num).toDouble(),
        )
      : endPoint;

    // Pre-define the demo path:
    // 0: Start Point
    // 1: Safe Point 1 (Normal walking)
    // 2: Heading towards Unsafe Zone (Veering off)
    // 3: Inside Unsafe Zone (Danger!)
    // 4: Recalculating (Back to Safe Point 2)
    // 5: Back to Destination (Arrived)
    
    List<LatLng> demoPath = [
      startPoint,
      safePoint1,
      LatLng((safePoint1.latitude + unsafePoint.latitude) / 2, (safePoint1.longitude + unsafePoint.longitude) / 2),
      unsafePoint,
      safePoint2,
      endPoint,
    ];

    List<String> demoStepsLogs = [
      "Starting Demo: Walking home from metro station...",
      "Walking on Recommended Safe Route (Well-Lit & Busy)...",
      "Alert: User is veering off course towards a dark alleyway!",
      "WARNING: Entered Unsafe Zone (Poorly Lit Alley)! Triggering safety protocols.",
      "Safety Alert: Re-routing user back to Safe Route...",
      "Journey completed. Arrived safely at destination!"
    ];

    setState(() {
      _isDemoRunning = true;
      _demoStep = 0;
      _hasGeocodedCoords = true; // Lock coords so points don't rebuild/shift
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

      // Trigger alerts and notifications based on state
      if (_demoStep == 2) {
        _triggerNotification("⚠️ Warning: Veered off course towards Unsafe Zone!");
      } else if (_demoStep == 3) {
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
      } else if (_demoStep == 4) {
        _triggerNotification("🔄 Recalculating path... Re-routing back to safety.");
      } else if (_demoStep == 5) {
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

  /// Fetches the safety-point metadata from the backend.
  /// If we already have geocoded coords (_hasGeocodedCoords), we keep them
  /// and only pull the point names/descriptions.
  Future<void> _fetchPoints() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // 1. Fetch active location info (only apply coords on cold start)
      final activeResponse = await http.get(Uri.parse('$_backendUrl/api/simulation/active'));
      if (activeResponse.statusCode == 200) {
        final activeData = json.decode(activeResponse.body);
        setState(() {
          _activeLocationName = activeData['name'] ?? 'Global Area';
          _originName = activeData['origin_name'] ?? 'Current Location';
          
          if (!_hasGeocodedCoords) {
            _activeLatitude = (activeData['latitude'] as num?)?.toDouble() ?? 28.6139;
            _activeLongitude = (activeData['longitude'] as num?)?.toDouble() ?? 77.2090;
            _originLatitude = (activeData['origin_latitude'] as num?)?.toDouble() ?? (_activeLatitude - 0.006);
            _originLongitude = (activeData['origin_longitude'] as num?)?.toDouble() ?? (_activeLongitude - 0.006);
          }
        });

        _searchController.text = _activeLocationName;
        _originController.text = _originName;

        if (!_hasGeocodedCoords) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              _fitMapToRoute();
            } catch (e) {
              // Map not ready yet
            }
          });
        }
      }

      // 2. Fetch points of interest for active location
      final pointsResponse = await http.get(Uri.parse('$_backendUrl/api/safety-points'));
      if (pointsResponse.statusCode == 200) {
        final pointsData = json.decode(pointsResponse.body);
        setState(() {
          _safePoints = pointsData['safety_points'] ?? [];
          _unsafeZones = pointsData['unsafe_zones'] ?? [];
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load points');
      }
    } catch (e) {
      debugPrint('Error fetching points: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Geocodes [query] via our backend proxy (which calls Nominatim
  /// server-side with proper User-Agent headers).
  /// Always returns valid [lat, lon] — the backend falls back to
  /// hash-based coords if Nominatim returns empty.
  Future<List<double>?> _geocodeLocation(String query) async {
    try {
      final uri = Uri.parse(
        '$_backendUrl/api/geocode?q=${Uri.encodeComponent(query.trim())}',
      );
      debugPrint('Geocoding via backend proxy: $uri');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lat = (data['lat'] as num?)?.toDouble();
        final lon = (data['lon'] as num?)?.toDouble();
        if (lat != null && lon != null) {
          debugPrint('Geocode result: lat=$lat, lon=$lon (source: ${data['source']})');
          return [lat, lon];
        }
      }
    } catch (e) {
      debugPrint('Geocode proxy error: $e');
    }
    return null;
  }

  // _startSimulation replaced by _startNavigationQuery

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
          'Emergency SOS broadcast initialized. Your coordinates at $_activeLocationName are actively being shared with pre-selected trusted contacts.',
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

  /// Returns a random fractional degree offset between ±[min] and ±[max].
  /// Scaled to 0.001–0.003 (~110m–330m) for realistic local street spacing.
  double _spread({double min = 0.001, double max = 0.003}) {
    final sign = _random.nextBool() ? 1.0 : -1.0;
    return sign * (min + _random.nextDouble() * (max - min));
  }

  List<Marker> get _markers {
    final markers = <Marker>[];

    // ── Origin Marker (Start) ──
    markers.add(
      Marker(
        point: LatLng(_originLatitude, _originLongitude),
        width: 145,
        height: 65,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF171F33).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF6366F1), width: 1.5),
              ),
              child: Text(
                _originName,
                style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.my_location, color: Color(0xFF6366F1), size: 24),
          ],
        ),
      ),
    );

    // ── Destination Marker (To) ──
    markers.add(
      Marker(
        point: LatLng(_activeLatitude, _activeLongitude),
        width: 145,
        height: 65,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF171F33).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFB4AB), width: 1.5),
              ),
              child: Text(
                _activeLocationName,
                style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 2),
            const Icon(Icons.location_on, color: Color(0xFFFFB4AB), size: 24),
          ],
        ),
      ),
    );

    // ── Walking User Pulsing Dot ──
    final userPos = _simulatedUserLatLng ?? LatLng(_originLatitude, _originLongitude);
    markers.add(
      Marker(
        point: userPos,
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

    // ── Safe points: use coordinates from database ──
    for (final point in _safePoints) {
      final lat = (point['latitude'] as num?)?.toDouble() ?? (_activeLatitude + _spread());
      final lng = (point['longitude'] as num?)?.toDouble() ?? (_activeLongitude + _spread());
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 145,
          height: 65,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF171F33).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF4EDEA3), width: 1),
                ),
                child: Text(
                  point['name'] ?? 'Safe Point',
                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: 2),
              const Icon(Icons.check_circle, color: Color(0xFF4EDEA3), size: 20),
            ],
          ),
        ),
      );
    }

    // ── Unsafe zones: use coordinates from database ──
    for (final zone in _unsafeZones) {
      final lat = (zone['latitude'] as num?)?.toDouble() ?? (_activeLatitude + _spread());
      final lng = (zone['longitude'] as num?)?.toDouble() ?? (_activeLongitude + _spread());
      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: 145,
          height: 65,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF171F33).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFB4AB), width: 1),
                ),
                child: Text(
                  zone['name'] ?? 'Unsafe Zone',
                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: 2),
              const Icon(Icons.warning, color: Color(0xFFFFB4AB), size: 20),
            ],
          ),
        ),
      );
    }

    return markers;
  }

  List<LatLng> get _routePoints {
    final points = <LatLng>[];
    // Start at the user's origin position
    points.add(LatLng(_originLatitude, _originLongitude));

    // Generate a waypoint for each safe point
    for (final point in _safePoints) {
      final lat = (point['latitude'] as num?)?.toDouble();
      final lng = (point['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        points.add(LatLng(lat, lng));
      }
    }

    // End at the destination
    points.add(LatLng(_activeLatitude, _activeLongitude));
    return points;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SafePassage Map: $_activeLocationName',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF131B2E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPoints,
          )
        ],
      ),
      body: Stack(
        children: [
          // 1. Integrated Map Canvas
          Positioned.fill(
            child: _isLoading && _safePoints.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(_activeLatitude, _activeLongitude),
                      initialZoom: 15.0,
                      minZoom: 3,
                      maxZoom: 18,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                        subdomains: const ['a', 'b', 'c', 'd'],
                      ),
                      PolylineLayer(
                        polylines: [
                          // 1. Standard Shortcut Path (Gray line, directly from Start to End)
                          Polyline(
                            points: [
                              LatLng(_originLatitude, _originLongitude),
                              LatLng(_activeLatitude, _activeLongitude),
                            ],
                            color: const Color(0xFFC7C4D7).withValues(alpha: 0.5),
                            strokeWidth: 3.0,
                          ),
                          // 2. Safe Detour Path (Green solid glowing line)
                          if (_routePoints.length >= 2)
                            Polyline(
                              points: _routePoints,
                              color: const Color(0xFF4EDEA3),
                              strokeWidth: 6.0,
                              borderColor: const Color(0xFF4EDEA3).withValues(alpha: 0.3),
                              borderStrokeWidth: 3.0,
                            ),
                        ],
                      ),
                      MarkerLayer(
                        markers: _markers,
                      ),
                    ],
                  ),
          ),

          // 2. Search Bar overlay at the top (with a background gradient so it's readable)
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

          // 3. Floating Overlay Badge
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF171F33).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF4EDEA3).withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4EDEA3).withValues(alpha: 0.1),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user, color: Color(0xFF4EDEA3), size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Well-Lit & Crowded',
                      style: TextStyle(
                        color: Color(0xFF4EDEA3),
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

          // 4. Floating SOS Shield Button (hovering above the bottom sheet)
          Positioned(
            bottom: 190,
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

          // 5. Active Bottom Destination Sheet
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20.0),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
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
                            const SizedBox(height: 4),
                            const Text(
                              'Safe Route Active',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '12 min',
                            style: TextStyle(
                              color: Color(0xFF4EDEA3),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '0.8 miles',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Active journey tracking started.')),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Start Walking', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isDemoRunning ? null : _runDemoStep,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4EDEA3),
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
                ],
              ),
            ),
          ),
          // 6. Push Notification Alert Banner Overlay
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
          // Row 1: Start Location (Origin)
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
            ],
          ),
          const Divider(color: Colors.white12, height: 12),
          // Row 2: Destination (To)
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

// ==========================================
// 2. REPORT SCREEN
// ==========================================
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
        throw Exception('Failed to submit report');
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
            
            // Title Input
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

            // Description Input
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

            // Selection buttons
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

            // CTA Submit Button
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

// ==========================================
// 3. TIMELINE SCREEN
// ==========================================
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
          // Sort reports by latest first
          _reports.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load reports');
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
