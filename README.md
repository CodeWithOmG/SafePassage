# Guardian Path Navigator (SafePassage)

Guardian Path Navigator is an intelligent safety navigation assistant designed to guide pedestrians along well-lit, busy, and safe paths, with real-time incident reporting and an automated stealth SOS beacon.

## Project Structure

The project has been organized systematically into three main layers:

```
SRM HACKATHON/
├── backend/            # Express.js simulation engine server & mock database
├── frontend/           # Static web/Stitch mockup views (HTML + Tailwind CSS)
└── mobile/             # Flutter mobile application
```

---

## Getting Started

### 1. Static Frontend Mockups
The static HTML screens show the UI components generated from Stitch under the **Empowered Calm** dark theme guidelines.

To run:
- Simply open the dashboard at [frontend/index.html](file:///d:/SRM%20HACKATHON/frontend/index.html) in any modern web browser.
- From there, you can launch:
  - **SafePassage Map**: Interactive map with safe detour routing and SOS action.
  - **Report Safety Status**: Bento-style overlay to drop safety condition pins.
  - **Emergency Broadcast**: Audio, GPS, and protocol timeline logs view.

### 2. Backend Simulation Server
The backend stores safety points, registers user-reported safety pins, and generates mock detour routes procedurally.

To run:
1. Open a terminal and navigate to the backend folder:
   ```bash
   cd backend
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Start the server:
   ```bash
   npm start
   ```
The server will run on `http://localhost:3000`.

### 3. Flutter Mobile App
The mobile app is a fully integrated Flutter application that consumes safety data from the simulation server.

To run:
1. Make sure Flutter SDK is installed and configured.
2. Open a terminal and navigate to the mobile folder:
   ```bash
   cd mobile
   ```
3. Fetch packages:
   ```bash
   flutter pub get
   ```
4. Run the app:
   ```bash
   flutter run
   ```

---

## Workspace Tools
- `.gitignore`: Configured to exclude local dependency directories (`node_modules`), package cache (`.pub_cache`), build files (`build/`, `.dart_tool/`), and IDE configurations (`.idea/`, `.vscode/`, `.iml` files).
