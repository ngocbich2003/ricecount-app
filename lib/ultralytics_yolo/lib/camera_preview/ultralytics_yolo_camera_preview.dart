import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:ultralytics_yolo/ultralytics_yolo_platform_interface.dart';

const String _viewType = 'ultralytics_yolo_camera_preview';

/// A widget that displays the camera preview and run inference on the frames
/// using a Ultralytics YOLO model.
class UltralyticsYoloCameraPreview extends StatefulWidget {
  /// Constructor to create a [UltralyticsYoloCameraPreview].
  const UltralyticsYoloCameraPreview({
    required this.controller,
    this.loadingPlaceholder,
    super.key,
  });

  /// The controller for the camera preview.
  final UltralyticsYoloCameraController controller;
  /// The placeholder widget displayed while the predictor is loading.
  final Widget? loadingPlaceholder;

  @override
  State<UltralyticsYoloCameraPreview> createState() =>
      _UltralyticsYoloCameraPreviewState();
}

class _UltralyticsYoloCameraPreviewState
    extends State<UltralyticsYoloCameraPreview> {
  final _ultralyticsYoloPlatform = UltralyticsYoloPlatform.instance;

  double _currentZoomFactor = 1;

  final double _zoomSensitivity = 0.05;

  final double _minZoomLevel = 1;

  final double _maxZoomLevel = 5;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UltralyticsYoloCameraValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        return Stack(
          children: [
            // Camera preview
            () {
              final creationParams = <String, dynamic>{
                'lensDirection': widget.controller.value.lensDirection,
              };

              switch (defaultTargetPlatform) {
                case TargetPlatform.android:
                  return AndroidView(
                    viewType: _viewType,
                    creationParams: creationParams,
                    creationParamsCodec: const StandardMessageCodec(),
                  );
                case TargetPlatform.iOS:
                  return UiKitView(
                    viewType: _viewType,
                    creationParams: creationParams,
                    creationParamsCodec: const StandardMessageCodec(),
                  );
                case TargetPlatform.fuchsia ||
                      TargetPlatform.linux ||
                      TargetPlatform.windows ||
                      TargetPlatform.macOS:
                  return Container();
              }
            }(),

            // Zoom detector
            GestureDetector(
              onScaleUpdate: (details) {
                if (details.pointerCount == 2) {
                  // Calculate the new zoom factor
                  var newZoomFactor = _currentZoomFactor * details.scale;

                  // Adjust the sensitivity for zoom out
                  if (newZoomFactor < _currentZoomFactor) {
                    newZoomFactor = _currentZoomFactor -
                        (_zoomSensitivity *
                            (_currentZoomFactor - newZoomFactor));
                  } else {
                    newZoomFactor = _currentZoomFactor +
                        (_zoomSensitivity *
                            (newZoomFactor - _currentZoomFactor));
                  }

                  // Limit the zoom factor to a range between
                  // _minZoomLevel and _maxZoomLevel
                  final clampedZoomFactor =
                      max(_minZoomLevel, min(_maxZoomLevel, newZoomFactor));

                  // Update the zoom factor
                  _ultralyticsYoloPlatform.setZoomRatio(clampedZoomFactor);

                  // Update the current zoom factor for the next update
                  _currentZoomFactor = clampedZoomFactor;
                }
              },
              child: Container(
                height: double.infinity,
                width: double.infinity,
                color: Colors.transparent,
                child: const Center(child: Text('')),
              ),
            ),
          ],
        );
      },
    );
  }
}
