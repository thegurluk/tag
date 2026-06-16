# Mobile App

Flutter MVP for the road awareness map.

## What It Does

- Fetches active locations from `http://46.101.231.239:3010/api/locations/active`
- Shows active alerts on Google Maps
- Requests current location permission
- Colors markers by backend status: red, yellow, blue
- Opens a detail panel when a marker is tapped
- Calculates standard or motorcycle routes through the backend
- Draws returned route polylines on the map

## Run

Add a Google Maps key before running on a device.

Android:

Set this in `android/local.properties`:

```properties
GOOGLE_MAPS_API_KEY=your_key
```

Then run:

```bash
flutter run --dart-define=API_BASE_URL=http://46.101.231.239:3010/api
```

iOS:

Replace `YOUR_GOOGLE_MAPS_IOS_KEY` in `ios/Runner/Info.plist`.

The backend must also have `GOOGLE_MAPS_API_KEY` configured with Routes API
access, because route calculation is proxied through `/api/routes/calculate`.

## Checks

```bash
flutter analyze
flutter test
flutter build apk --debug
```
