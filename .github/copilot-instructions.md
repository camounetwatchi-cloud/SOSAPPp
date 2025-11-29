# Copilot Instructions for SOS App

This is a Flutter-based emergency SOS application designed for quick emergency calling with location sharing and alarm functionality.

## Architecture Overview

**Single-Page, Stateful Design**: The app uses a monolithic structure (`lib/main.dart`) with one main screen (`SOSHomePage`). All state management is handled through StatefulWidget with `setState()`.

**Key Components**:
- `MyApp`: Material app shell with red theme (`ColorScheme.fromSeed(seedColor: Colors.red)`)
- `_SOSHomePageState`: Manages three critical features:
  1. **Emergency Calling**: Launches tel:// URI to dial 112
  2. **Geolocation**: Uses `geolocator` package to get position with permission handling
  3. **Alarm Sound**: Loops `assets/alarm_sound.mp3` using `audioplayers` package

## Critical Workflows

### Building & Running
- **Android**: `flutter run` (requires Android SDK and emulator/device)
- **iOS**: `flutter run` (requires Xcode, may need `pod repo update`)
- **All platforms**: `flutter pub get` to fetch dependencies first
- **Clean rebuild**: `flutter clean; flutter pub get; flutter run`

### Permission Handling Pattern
Always follow the `_handleLocationPermission()` flow:
1. Check if location service is enabled (`Geolocator.isLocationServiceEnabled()`)
2. Check current permission status (`Geolocator.checkPermission()`)
3. Request if denied, handle permanent denial gracefully
4. Return boolean to control downstream flow

### State Management Pattern
Use `setState()` with loading flags and message updates:
```dart
setState(() {
  _isLoading = true;
  _locationMessage = "Updating...";
});
// async operation
setState(() {
  _isLoading = false;
  _locationMessage = result;
});
```

## Key Dependencies & Integration Points

| Package | Purpose | Key Methods |
|---------|---------|-------------|
| `url_launcher` | Emergency calls | `launchUrl(Uri(scheme: 'tel', path: '112'))` |
| `geolocator` | Location services | `requestPermission()`, `getCurrentPosition()` |
| `audioplayers` | Alarm sound | `setReleaseMode(ReleaseMode.loop)`, `play(AssetSource(...))` |

## Project-Specific Patterns

### Asset Management
- Audio files stored in `assets/` directory and declared in `pubspec.yaml`:
  ```yaml
  assets:
    - assets/alarm_sound.mp3
  ```
- Reference via `AssetSource('alarm_sound.mp3')` in code

### Error Handling
- Wrap async operations in try-catch blocks
- Display errors via `SnackBar` with context:
  ```dart
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Error message'), backgroundColor: Colors.orange)
  );
  ```
- Use French messages (app is French-localized)

### Dialog Patterns
Use `showDialog()` with `AlertDialog` for confirmations, particularly before emergency calls:
```dart
showDialog(
  context: context,
  builder: (BuildContext context) {
    return AlertDialog(
      title: const Text('Appel d\'urgence'),
      content: const Text('Voulez-vous appeler le 112 maintenant ?'),
      actions: [/* cancel/confirm buttons */],
    );
  },
);
```

### UI Design Conventions
- **Primary color**: Red (`Colors.red`) for SOS elements and main button
- **Accent colors**: Orange for secondary actions, Blue for utility buttons
- **Large touch targets**: Main SOS button is 200x200px circular
- **Material Design 3**: `useMaterial3: true` enabled

## Resource Cleanup
Always dispose of resource-intensive objects:
```dart
@override
void dispose() {
  _audioPlayer.dispose();  // Critical for audio player
  super.dispose();
}
```

## Testing
- Basic widget tests exist in `test/widget_test.dart` (scaffold verification)
- No extensive test coverage; use manual testing on devices for permissions/location/audio
- Test on both Android and iOS due to platform-specific permission handling

## Lint Configuration
Uses `package:flutter_lints/flutter.yaml`. Key rules:
- `avoid_print` is disabled (logs used in error handling)
- Default Dart/Flutter best practices enforced

## Common Development Tasks

**Add new feature**: Follow the stateful widget pattern with permission checks before accessing platform features
**Fix permissions issue**: Check `_handleLocationPermission()` logic; most issues come from permission request flow
**Deploy**: Ensure `pubspec.yaml` version matches release requirement and all platform-specific configs are updated
**Debug audio**: Verify `alarm_sound.mp3` exists in `assets/`; missing file shows orange SnackBar error

## Important Notes

- App targets Flutter 3.0+ with Material Design 3
- Entirely in French (localization strings, error messages)
- No complex state management library (Provider, Riverpod, etc.) - keep it simple
- All UI is in a single file; maintain that pattern for this size of app
