const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const DB_PATH = path.join(__dirname, 'database.json');

app.use(cors());
app.use(express.json());

// Helper to calculate simple hash code
function getHashCode(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash);
  }
  return Math.abs(hash);
}

// Get center coordinates for any location name
function getLocationCenter(name) {
  const normalized = name.trim().toLowerCase();
  
  // High-fidelity matching for popular places
  if (normalized.includes('srm') || normalized.includes('kattankulathur')) {
    return { latitude: 12.8230, longitude: 80.0416 };
  } else if (normalized.includes('connaught place') || normalized.includes('cp')) {
    return { latitude: 28.6304, longitude: 77.2177 };
  } else if (normalized.includes('london bridge') || normalized.includes('london')) {
    return { latitude: 51.5072, longitude: -0.0754 };
  } else if (normalized.includes('times square') || normalized.includes('new york')) {
    return { latitude: 40.7580, longitude: -73.9855 };
  } else if (normalized.includes('chennai central') || normalized.includes('main station')) {
    return { latitude: 13.0827, longitude: 80.2707 };
  }

  // Fallback to deterministic hashing
  const hash = getHashCode(name);
  const latitude = 10.0 + (hash % 30) + ((hash % 1000) / 1000.0);
  const longitude = 70.0 + (hash % 50) + (((hash >> 3) % 1000) / 1000.0);
  return { latitude: parseFloat(latitude.toFixed(4)), longitude: parseFloat(longitude.toFixed(4)) };
}

// Helper to perform geocoding using Nominatim with fallback
async function geocode(query, options = {}) {
  if (!query || query.trim() === '') {
    return null;
  }
  const cleanQuery = query.trim();
  const { lat, lon, radius = 0.5 } = options;

  const buildNominatimUrl = (q, extraParams = '', bounded = false) => {
    let url = `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(q)}&limit=5&addressdetails=1${extraParams}`;
    if (bounded && lat !== undefined && lon !== undefined) {
      const minLon = (parseFloat(lon) - radius).toFixed(6);
      const maxLat = (parseFloat(lat) + radius).toFixed(6);
      const maxLon = (parseFloat(lon) + radius).toFixed(6);
      const minLat = (parseFloat(lat) - radius).toFixed(6);
      url += `&viewbox=${minLon},${maxLat},${maxLon},${minLat}&bounded=1`;
    }
    return url;
  };

  const fetchNominatim = async (url) => {
    const https = require('https');
    return new Promise((resolve, reject) => {
      const request = https.get(url, {
        headers: { 'User-Agent': 'SafePassageHackathonDemoApp/1.0' }
      }, (response) => {
        let body = '';
        response.on('data', chunk => body += chunk);
        response.on('end', () => {
          try { resolve(JSON.parse(body)); } catch (e) { reject(new Error('Failed to parse Nominatim response')); }
        });
      });
      request.on('error', reject);
      request.setTimeout(8000, () => { request.destroy(); reject(new Error('Nominatim request timed out')); });
    });
  };

  const toResult = (item) => ({
    lat: parseFloat(item.lat),
    lon: parseFloat(item.lon),
    display_name: item.display_name || cleanQuery,
    source: 'nominatim',
  });

  const poiStrategies = [
    { keywords: ['police', 'thana', 'chowki', 'station'], extraParams: '&amenity=police' },
    { keywords: ['market', 'bazaar', 'bazar', 'haat', 'mandi'], extraParams: '&amenity=marketplace' },
    { keywords: ['mall', 'plaza', 'shopping'], extraParams: '&shop=mall' },
    { keywords: ['hospital', 'clinic', 'medical'], extraParams: '&amenity=hospital' },
    { keywords: ['school', 'college', 'university'], extraParams: '&amenity=school' },
    { keywords: ['bus stand', 'bus station', 'bus stop'], extraParams: '&amenity=bus_station' },
    { keywords: ['railway', 'train station', 'junction'], extraParams: '&railway=station' },
  ];

  const lowerQuery = cleanQuery.toLowerCase();
  let matchedStrategy = null;
  for (const strategy of poiStrategies) {
    if (strategy.keywords.some(kw => lowerQuery.includes(kw))) {
      matchedStrategy = strategy;
      break;
    }
  }

  try {
    if (lat !== undefined && lon !== undefined) {
      const boundedUrl = buildNominatimUrl(cleanQuery, '', true);
      const boundedData = await fetchNominatim(boundedUrl);
      if (Array.isArray(boundedData) && boundedData.length > 0) {
        return toResult(boundedData[0]);
      }

      if (matchedStrategy) {
        const poiBoundedUrl = buildNominatimUrl(cleanQuery, matchedStrategy.extraParams, true);
        const poiBoundedData = await fetchNominatim(poiBoundedUrl);
        if (Array.isArray(poiBoundedData) && poiBoundedData.length > 0) {
          return toResult(poiBoundedData[0]);
        }

        const poiUnboundedUrl = buildNominatimUrl(cleanQuery, matchedStrategy.extraParams, false);
        const poiUnboundedData = await fetchNominatim(poiUnboundedUrl);
        if (Array.isArray(poiUnboundedData) && poiUnboundedData.length > 0) {
          return toResult(poiUnboundedData[0]);
        }
      }

      const unboundedUrl = buildNominatimUrl(cleanQuery, '', false);
      const unboundedData = await fetchNominatim(unboundedUrl);
      if (Array.isArray(unboundedData) && unboundedData.length > 0) {
        return toResult(unboundedData[0]);
      }
    } else {
      if (matchedStrategy) {
        const poiUrl = buildNominatimUrl(cleanQuery, matchedStrategy.extraParams, false);
        const poiData = await fetchNominatim(poiUrl);
        if (Array.isArray(poiData) && poiData.length > 0) {
          return toResult(poiData[0]);
        }
      }

      const generalUrl = buildNominatimUrl(cleanQuery, '', false);
      const generalData = await fetchNominatim(generalUrl);
      if (Array.isArray(generalData) && generalData.length > 0) {
        return toResult(generalData[0]);
      }
    }
  } catch (err) {
    console.error('Geocode helper error:', err.message);
  }

  const coords = getLocationCenter(cleanQuery);
  return {
    lat: coords.latitude,
    lon: coords.longitude,
    display_name: cleanQuery,
    source: 'fallback',
  };
}

// Generate points of interest procedurally along the path between origin and target lat/lng
function generateProceduralPoints(name, lat, lng, originLat, originLng) {
  // If origin is not provided, generate default ones around the destination
  if (originLat === undefined || originLng === undefined) {
    originLat = lat - 0.005;
    originLng = lng - 0.005;
  }

  const lat1 = originLat;
  const lng1 = originLng;
  const lat2 = lat;
  const lng2 = lng;

  const dLat = lat2 - lat1;
  const dLng = lng2 - lng1;

  // Perpendicular offset to move unsafe zones and safe zones to opposite sides of the path
  const offsetLat = -dLng * 0.2;
  const offsetLng = dLat * 0.2;

  // Safe detour points on one side of the straight line
  const sp1Lat = lat1 * 0.6 + lat2 * 0.4 - offsetLat * 0.5;
  const sp1Lng = lng1 * 0.6 + lng2 * 0.4 - offsetLng * 0.5;

  const sp2Lat = lat1 * 0.3 + lat2 * 0.7 - offsetLat * 0.5;
  const sp2Lng = lng1 * 0.3 + lng2 * 0.7 - offsetLng * 0.5;

  // Unsafe areas on the opposite side of the straight line
  const uz1Lat = lat1 * 0.5 + lat2 * 0.5 + offsetLat * 0.8;
  const uz1Lng = lng1 * 0.5 + lng2 * 0.5 + offsetLng * 0.8;

  const uz2Lat = lat1 * 0.8 + lat2 * 0.2 + offsetLat * 0.6;
  const uz2Lng = lng1 * 0.8 + lng2 * 0.2 + offsetLng * 0.6;

  return {
    safety_points: [
      {
        id: `safe-${Date.now()}-1`,
        name: `${name} Well-Lit Transit Hub`,
        type: "Transit Station",
        latitude: parseFloat(sp1Lat.toFixed(6)),
        longitude: parseFloat(sp1Lng.toFixed(6)),
        description: "Well-lit transit terminal with regular security patrols and CCTV surveillance.",
        is_safe: true
      },
      {
        id: `safe-${Date.now()}-2`,
        name: `${name} Public Hospital Entrance`,
        type: "24-7 Security Gate",
        latitude: parseFloat(sp2Lat.toFixed(6)),
        longitude: parseFloat(sp2Lng.toFixed(6)),
        description: "Open 24/7 with emergency services, bright overhead lights, and active security desk.",
        is_safe: true
      }
    ],
    unsafe_zones: [
      {
        id: `unsafe-${Date.now()}-1`,
        name: `${name} East Dark Corridor`,
        type: "Poorly Lit Alley",
        latitude: parseFloat(uz1Lat.toFixed(6)),
        longitude: parseFloat(uz1Lng.toFixed(6)),
        risk_level: "High",
        description: "Narrow alleyway with broken street lamps. Avoid walking alone after dark.",
        is_safe: false
      },
      {
        id: `unsafe-${Date.now()}-2`,
        name: `${name} West Empty Underpass`,
        type: "Isolated Path",
        latitude: parseFloat(uz2Lat.toFixed(6)),
        longitude: parseFloat(uz2Lng.toFixed(6)),
        risk_level: "Medium",
        description: "Isolated pedestrian path behind commercial buildings, poorly populated during late hours.",
        is_safe: false
      }
    ]
  };
}

// Read database file and migrations
function readDatabase() {
  try {
    if (!fs.existsSync(DB_PATH)) {
      writeDatabase(getInitialDbState());
    }
    const data = fs.readFileSync(DB_PATH, 'utf8');
    let db = JSON.parse(data);
    
    // Migrating from old flat model to simulations model if necessary
    if (!db.simulations) {
      const oldReports = db.reports || [];
      const srmName = "SRM Kattankulathur";
      db = {
        active_location: srmName,
        simulations: {
          [srmName]: {
            name: srmName,
            latitude: 12.8230,
            longitude: 80.0416,
            safety_points: db.safety_points || [],
            unsafe_zones: db.unsafe_zones || [],
            reports: oldReports
          }
        }
      };
      writeDatabase(db);
    }
    if (!db.active_location || !db.simulations || !db.simulations[db.active_location]) {
      db.active_location = "SRM Kattankulathur";
      writeDatabase(db);
    }
    return db;
  } catch (err) {
    console.error('Error reading database:', err);
    return getInitialDbState();
  }
}

function getInitialDbState() {
  const srmName = "SRM Kattankulathur";
  return {
    active_location: srmName,
    simulations: {
      [srmName]: {
        name: srmName,
        latitude: 12.8230,
        longitude: 80.0416,
        safety_points: [
          {
            id: "safe-01",
            name: "SRM Kattankulathur Railway Station",
            type: "Transit Station",
            latitude: 12.8206,
            longitude: 80.0381,
            description: "High footfall, well-lit transit hub with constant security presence.",
            is_safe: true
          },
          {
            id: "safe-02",
            name: "SRM Hospital Main Entrance",
            type: "Hospital / 24-7 Security",
            latitude: 12.8213,
            longitude: 80.0463,
            description: "24/7 active medical center, high security coverage, and bright lighting.",
            is_safe: true
          }
        ],
        unsafe_zones: [
          {
            id: "unsafe-01",
            name: "Tech Park Backside Corridor",
            type: "Poorly Lit Alley",
            latitude: 12.8260,
            longitude: 80.0395,
            risk_level: "High",
            description: "Poorly illuminated narrow walkway, isolated after hours.",
            is_safe: false
          }
        ],
        reports: []
      }
    }
  };
}

function writeDatabase(data) {
  try {
    fs.writeFileSync(DB_PATH, JSON.stringify(data, null, 2), 'utf8');
  } catch (err) {
    console.error('Error writing database:', err);
  }
}

// ----------------------------------------------------
// API ENDPOINTS
// ----------------------------------------------------

// Root Endpoint - returns current active simulation status
app.get('/', (req, res) => {
  const db = readDatabase();
  const active = db.simulations[db.active_location];
  res.json({
    name: "SafePassage Safety App API Simulation Engine",
    status: "healthy",
    active_location: db.active_location,
    coordinates: {
      latitude: active.latitude,
      longitude: active.longitude
    },
    endpoints: {
      "GET /": "Simulation information (this response)",
      "GET /api/simulation/active": "Retrieve active simulation location details",
      "POST /api/simulation/start": "Start/switch to a simulated location globally",
      "GET /api/safety-points": "Retrieve safe and unsafe points for the active simulation",
      "GET /api/reports": "Retrieve reports list for the active simulation",
      "POST /api/reports": "Drop a new safety pin for the active simulation"
    }
  });
});

// ── GEOCODE PROXY ──
// Proxies geocoding through the backend so Flutter Web avoids
// the browser's forbidden-header restriction on User-Agent.
app.get('/api/geocode', async (req, res) => {
  const query = req.query.q;
  if (!query || query.trim() === '') {
    return res.status(400).json({ error: 'Query parameter "q" is required.' });
  }
  const nearLat = req.query.lat ? parseFloat(req.query.lat) : undefined;
  const nearLon = req.query.lon ? parseFloat(req.query.lon) : undefined;
  const radius = req.query.radius ? parseFloat(req.query.radius) : 0.5;

  let result;
  if (nearLat !== undefined && nearLon !== undefined) {
    result = await geocode(query, { lat: nearLat, lon: nearLon, radius });
    if (!result || result.source === 'fallback') {
      const unbounded = await geocode(query);
      if (unbounded && unbounded.source === 'nominatim') {
        result = unbounded;
      }
    }
  } else {
    result = await geocode(query);
  }

  res.json(result);
});

// GET the active simulation environment state
app.get('/api/simulation/active', (req, res) => {
  const db = readDatabase();
  const active = db.simulations[db.active_location];
  res.json({
    name: db.active_location,
    latitude: active.latitude,
    longitude: active.longitude,
    origin_name: active.origin_name || "Current Location",
    origin_latitude: active.origin_latitude || (active.latitude - 0.006),
    origin_longitude: active.origin_longitude || (active.longitude - 0.006)
  });
});

// POST to start a new simulation location (Dynamic Search)
app.post('/api/simulation/start', async (req, res) => {
  const { location, latitude, longitude, origin, origin_latitude, origin_longitude } = req.body;
  if (!location || location.trim() === '') {
    return res.status(400).json({ error: "Location name is required." });
  }

  const db = readDatabase();
  const targetName = location.trim();
  const originName = origin ? origin.trim() : "Current Location";

  const exists = !!db.simulations[targetName];
  const isFallback = exists && db.simulations[targetName].source !== 'nominatim';

  if (!exists || isFallback || origin !== undefined) {
    let lat = latitude;
    let lng = longitude;
    let oLat = origin_latitude;
    let oLng = origin_longitude;
    let source = (latitude !== undefined && longitude !== undefined) ? 'nominatim' : 'unknown';

    if (lat === undefined || lng === undefined) {
      const geocoded = await geocode(targetName);
      if (geocoded) {
        lat = geocoded.lat;
        lng = geocoded.lon;
        source = geocoded.source;
      }
    }

    if (oLat === undefined || oLng === undefined) {
      if (origin && originName !== "Current Location") {
        const geocodedOrigin = await geocode(originName);
        if (geocodedOrigin) {
          oLat = geocodedOrigin.lat;
          oLng = geocodedOrigin.lon;
        }
      }
      if (oLat === undefined || oLng === undefined) {
        oLat = lat ? lat - 0.006 : 28.6079;
        oLng = lng ? lng - 0.006 : 77.2030;
      }
    }

    const generated = generateProceduralPoints(targetName, lat, lng, oLat, oLng);
    
    db.simulations[targetName] = {
      name: targetName,
      latitude: lat,
      longitude: lng,
      origin_name: originName,
      origin_latitude: oLat,
      origin_longitude: oLng,
      source: source,
      safety_points: generated.safety_points,
      unsafe_zones: generated.unsafe_zones,
      reports: exists ? db.simulations[targetName].reports : []
    };
  } else if (latitude !== undefined && longitude !== undefined) {
    db.simulations[targetName].latitude = latitude;
    db.simulations[targetName].longitude = longitude;
    db.simulations[targetName].source = 'nominatim';
    
    let oLat = origin_latitude || db.simulations[targetName].origin_latitude || (latitude - 0.006);
    let oLng = origin_longitude || db.simulations[targetName].origin_longitude || (longitude - 0.006);
    db.simulations[targetName].origin_latitude = oLat;
    db.simulations[targetName].origin_longitude = oLng;
    if (origin) db.simulations[targetName].origin_name = originName;

    const generated = generateProceduralPoints(targetName, latitude, longitude, oLat, oLng);
    db.simulations[targetName].safety_points = generated.safety_points;
    db.simulations[targetName].unsafe_zones = generated.unsafe_zones;
  }

  db.active_location = targetName;
  writeDatabase(db);

  res.json({
    message: `Simulation switched to ${targetName}`,
    active_location: db.simulations[targetName]
  });
});

// GET safety points of interest for the currently active simulation
app.get('/api/safety-points', (req, res) => {
  const db = readDatabase();
  const active = db.simulations[db.active_location];
  res.json({
    safety_points: active.safety_points,
    unsafe_zones: active.unsafe_zones
  });
});

// GET reports for the currently active simulation
app.get('/api/reports', (req, res) => {
  const db = readDatabase();
  const active = db.simulations[db.active_location];
  res.json(active.reports);
});

// POST a new report for the active simulation
app.post('/api/reports', (req, res) => {
  const { title, description, latitude, longitude, risk_type } = req.body;
  
  const db = readDatabase();
  const active = db.simulations[db.active_location];

  const newReport = {
    id: `report-${Date.now()}`,
    title: title || 'Safety Incident',
    description: description || '',
    latitude: latitude ? parseFloat(latitude) : active.latitude,
    longitude: longitude ? parseFloat(longitude) : active.longitude,
    risk_type: risk_type || 'Unknown',
    timestamp: new Date().toISOString()
  };

  active.reports.push(newReport);
  writeDatabase(db);

  res.status(201).json({
    message: 'Safety report registered successfully.',
    report: newReport
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`====================================================`);
  console.log(`SafePassage Simulation Backend running on port ${PORT}`);
  console.log(`====================================================`);
});
