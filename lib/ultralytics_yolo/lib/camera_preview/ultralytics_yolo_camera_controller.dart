import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo_platform_interface.dart';

/// The state of the camera
class UltralyticsYoloCameraValue {
  /// Constructor to create an instance of [UltralyticsYoloCameraValue]
  UltralyticsYoloCameraValue({
    required this.lensDirection,
  });

  /// The direction of the camera lens
  final int lensDirection;

  /// Creates a copy of this [UltralyticsYoloCameraValue] but with
  /// the given fields
  UltralyticsYoloCameraValue copyWith({
    int? lensDirection,
  }) =>
      UltralyticsYoloCameraValue(
        lensDirection: lensDirection ?? this.lensDirection,
      );
}

/// ValueNotifier that holds the state of the camera
class UltralyticsYoloCameraController
    extends ValueNotifier<UltralyticsYoloCameraValue> {
  /// Constructor to create an instance of [UltralyticsYoloCameraController]
  UltralyticsYoloCameraController()
      : super(
          UltralyticsYoloCameraValue(
            lensDirection: 1,
          ),
        );

  final _ultralyticsYoloPlatform = UltralyticsYoloPlatform.instance;

  /// Toggles the direction of the camera lens
  Future<void> toggleLensDirection() async {
    try {
      // Update state first to show loading state if needed
      final newLensDirection = value.lensDirection == 0 ? 1 : 0;
      value = value.copyWith(lensDirection: newLensDirection);
      
      // Request camera switch
      final result = await _ultralyticsYoloPlatform.setLensDirection(
        newLensDirection,
        );
      
      if (result != 'Success') {
        // Revert state if failed
        value = value.copyWith(lensDirection: value.lensDirection == 0 ? 1 : 0);
        throw Exception('Failed to switch camera: $result');
      }
    } catch (e) {
      // Handle errors and revert state
      value = value.copyWith(lensDirection: value.lensDirection == 0 ? 1 : 0);
      rethrow;
    }
  }

  /// Closes the camera
  Future<void> closeCamera() async {
    await _ultralyticsYoloPlatform.closeCamera();
  }

  /// Starts the camera
  Future<void> startCamera() async {
    await _ultralyticsYoloPlatform.startCamera();
  }

  /// Stops the camera
  Future<void> pauseLivePrediction() async {
    await _ultralyticsYoloPlatform.pauseLivePrediction();
  }
}
