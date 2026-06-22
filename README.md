# Guardian Path Navigator (SafePassage)

SafePassage is an intelligent safety-first navigation assistant designed to guide pedestrians along well-lit, busy, and safe paths. It features real-time incident reporting, dynamic POI safety overlays, and an automated stealth SOS beacon.

---

## 🚀 Tech Stack

| Layer | Component | Technologies |
| :--- | :--- | :--- |
| **Client / Presentation** | Mobile & Web App | **Flutter (Dart)**, `flutter_map` (OpenStreetMap integration), `latlong2` vector math. |
| **Application Controller** | Backend Proxy & Simulation Engine | **Node.js (Express)**, `cors`, `node-fetch`. |
| **Map & Routing Services** | Routing Engine | **Open Source Routing Machine (OSRM)** community API (`router.project-osrm.org`). |
| **Geocoding & POI Data** | OSM Services | **Nominatim Geocoding API** (address lookup) and **Overpass API** (live safety POIs extraction). |
| **State Persistence** | Database | **Mock JSON Database** (`backend/database.json`). |

---

## 🏗️ System Architecture

The following diagram illustrates the components, data flows, and interactions between the presentation layer, Express backend API, database, and OpenStreetMap endpoints:

```mermaid
graph TD
    %% Frontend Components
    subgraph Client [Flutter Web / Mobile Client]
        UI[UI Viewport: Map, Report Panel, SOS Beacon]
        Search[Dual Search Controller]
        FMap[FlutterMap Canvas / OSM Dark Tiles]
        SOS[SOS Controller & Walk Simulator]
    end

    %% Backend Components
    subgraph Server [Node.js Express Server]
        API[Express Endpoint Router]
        Router[Safety Routing Engine]
    end

    %% External & Storage
    subgraph Data [Data & External APIs]
        DB["database.json (Simulation Store)"]
        NomAPI[Nominatim Geocoding API]
        Overpass[Overpass API (OSM POI Retrieval)]
    end

    %% Connections
    UI -->|1. Submit Search Queries| Search
    Search -->|2. Request Coordinates & POIs| API
    API -->|3. Address Geocoding Request| NomAPI
    NomAPI -->|4. Return Coordinates| API
    API -->|5. Fetch Safety POIs (Hospitals, Police)| Overpass
    Overpass -->|6. Return Local Points of Interest| API
    API -->|7. Persist Active Location & Reports| DB
    API -->|8. Calculate Safety Path Vectors| Router
    Router -->|9. Output Clean Safe Detours| API
    API -->|10. Send Coordinates, POIs, & Paths| Search
    Search -->|11. Draw Custom Polylines & Markers| FMap
    FMap -->|12. Monitor Coordinates| SOS
    SOS -->|13. Fire Warning Notifications & Overlays| UI

    %% Layout Helpers
    SOS ~~~ DB
    Router ~~~ NomAPI
```

---

## 🛠️ How It Works (Core Features)

### 1. Safety-First Routing (OSRM)
Instead of routing purely for speed (which often directs pedestrians through dark shortcuts), SafePassage queries the OSRM engine and overlays safety coordinates. It evaluates paths and displays three choices to the user:
*   🟢 **Safe Passage**: Automatically detours the user through safe/well-lit waypoints.
*   🟢 **Main Street**: Routes the user via direct commercial thoroughfares.
*   🔴 **High-Risk Alley**: Visualizes the unsafe route that passes directly through flagged danger zones.

### 2. Live POI Layer (Overpass API Integration)
Users can toggle the live POI layer on the map to query the OSM Overpass database in real-time. SafePassage retrieves nearby:
*   👮 **Police Stations** (`amenity=police`)
*   🏥 **Hospitals/Clinics** (`amenity=hospital`)
*   🛍️ **Malls/Markets** (`shop=mall`, `shop=supermarket`)
*   ⭐ **Famous Places/Landmarks** (`tourism=attraction`, `tourism=museum`)

It maps them with custom color-coded indicators (e.g. blue for police, red for hospitals) and allows the user to click any point of interest to instantly set it as a destination or navigate there.

### 3. Tap-to-Select Address (Nominatim Reverse Geocoding)
Tapping anywhere on the map drops a pulsing marker pin and triggers an asynchronous reverse-geocoding request to the Nominatim API. A bottom sheet slides up presenting the physical address, allowing users to:
*   Set the point as the start coordinate.
*   Set the point as the destination coordinate.
*   Calculate and trigger active navigation immediately.

### 4. Bento-Style Incident Reporting
A bento-grid overlay allows users to report live localized hazards:
*   ⚠️ **Poor Lighting**
*   🚨 **Suspicious Crowd/Harassment**
*   🚧 **Unsafe Road/Construction**
*   💚 **Safe & Busy** (positive reinforcement)

These reports immediately update the central store and are displayed as custom marker indicators for all active commuters.

---

## 📂 Project Structure

```
Hackathon/
├── backend/            # Express.js backend API & geocoding proxy
│   ├── database.json   # Simulated store for pins and active simulation coordinates
│   ├── package.json    # Backend script manager & modules
│   └── server.js       # Main server file, geocoding logic, and POI query parser
├── frontend/           # Static HTML layouts & UI prototype views
└── mobile/             # Flutter application directory
    ├── lib/            # App source code
    │   └── main.dart   # Interactive map, simulation engine, and UI controller
    ├── test/           # Unit & Widget test suite
    └── pubspec.yaml    # Flutter dependency configuration
```

---

## 🚀 Setup & Installation

### 1. Backend Server Setup
The backend serves as a proxy to circumvent CORS restrictions and hosts local endpoints.
1.  Open your terminal and navigate to the backend directory:
    ```bash
    cd backend
    ```
2.  Install required dependencies:
    ```bash
    npm install
    ```
3.  Start the Express server:
    ```bash
    npm start
    ```
    *The server runs locally at `http://localhost:3000`.*

### 2. Flutter Mobile Application
Ensure you have the Flutter SDK configured on your system.
1.  Navigate to the mobile directory:
    ```bash
    cd mobile
    ```
2.  Retrieve Flutter packages:
    ```bash
    flutter pub get
    ```
3.  Launch the application:
    *   **To run on Web (runs locally on port 8080)**:
        ```bash
        flutter run -d chrome --web-port=8080
        ```
    *   **To compile a production Web build**:
        ```bash
        flutter build web
        ```

---

## 🧪 Verification & Testing

### Static Analysis
Verify code syntax and lint constraints inside the mobile directory:
```bash
flutter analyze
```

### Automated Tests
Run the widget and unit test suites:
```bash
flutter test
```
