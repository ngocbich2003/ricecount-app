// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:io' as io;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import '/screens/captures_screen.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:ultralytics_yolo/yolo_model.dart';
import '../utils/database_helper.dart';
import 'dart:ui';

class PreviewScreen extends StatefulWidget {
  final File imageFile;
  final List<File> fileList;
  final int projectId;

  const PreviewScreen({
    super.key,
    required this.imageFile,
    required this.fileList,
    required this.projectId,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  ObjectDetector? objectDetector;
  List<DetectedObject?>? detections;
  bool isLoading = false;
  Size? imageSize;
  bool isPredicted = false;
  int germinatedCount = 0;
  int notGerminatedCount = 0;
  int? imageDbId;
  bool isSaving = false;
  final GlobalKey _screenshotKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadImageSize();
    _checkPredictionStatus();
  }

  Future<void> _loadImageSize() async {
    final image = await decodeImageFromList(widget.imageFile.readAsBytesSync());
    setState(() {
      imageSize = Size(image.width.toDouble(), image.height.toDouble());
    });
  }

  Future<void> _checkPredictionStatus() async {
    setState(() {
      isLoading = true;
    });

    try {
      final db = await DatabaseHelper.instance.database;
      final imagePath = widget.imageFile.path;

      final List<Map<String, dynamic>> images = await db.query(
        'images',
        where: 'file_path = ? AND project_id = ?',
        whereArgs: [imagePath, widget.projectId],
      );

      if (images.isNotEmpty) {
        final image = images.first;
        final isPredictedValue = image['is_predicted'] as int;
        setState(() {
          imageDbId = image['id'] as int;
          isPredicted = isPredictedValue == 1;
        });

        if (isPredicted) {
          // Có kết quả prediction, hiển thị lên màn hình
          final predictionResult = image['prediction_result'] as String?;
          if (predictionResult != null && predictionResult.isNotEmpty) {
            _displayPredictionFromDatabase(predictionResult);
          }
        }
      } else {
        // Nếu không tìm thấy, thêm ảnh mới vào database
        final newImageId = await DatabaseHelper.instance.addImage(
          widget.projectId,
          widget.imageFile.path,
        );
        setState(() {
          imageDbId = newImageId;
          isPredicted = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("Failed to check prediction status: $e");
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _displayPredictionFromDatabase(String predictionJson) {
    try {
      final Map<String, dynamic> jsonData = jsonDecode(predictionJson);

      setState(() {
        germinatedCount = jsonData['germinated_count'] ?? 0;
        notGerminatedCount = jsonData['not_germinated_count'] ?? 0;

        final List<dynamic> detectionsList = jsonData['detections'] ?? [];
        if (detectionsList.isEmpty) return;

        final List<DetectedObject?> loadedDetections =
            detectionsList.map((item) {
          final bbox = item['bbox'];
          return DetectedObject(
            index: item['class_id'],
            label: item['label'],
            confidence: item['confidence'],
            boundingBox: Rect.fromLTWH(
              bbox['x'],
              bbox['y'],
              bbox['width'],
              bbox['height'],
            ),
          );
        }).toList();

        detections = loadedDetections;
      });
    } catch (e) {
      if (kDebugMode) {
        print("Error parsing prediction result: $e");
      }
    }
  }

  Future<String> _copy(String assetPath) async {
    final path = '${(await getApplicationSupportDirectory()).path}/$assetPath';
    await io.Directory(dirname(path)).create(recursive: true);
    final file = io.File(path);

    // Delete the file if it exists
    if (await file.exists()) {
      await file.delete();
    }

    // Write new file
    final byteData = await rootBundle.load(assetPath);
    await file.writeAsBytes(byteData.buffer
        .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));

    return file.path;
  }

  Future<void> detectObjects() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      // Xóa kết quả trước đó nếu là re-run
      if (isPredicted) {
        detections = null;
        germinatedCount = 0;
        notGerminatedCount = 0;
      }
    });

    try {
      if (objectDetector == null) {
        if (kDebugMode) {
          print("Initializing detector...");
        }
        final modelPath = await _copy('assets/yolo11_obb_float32.tflite');
        final metadataPath = await _copy('assets/metadata.yaml');
        final model = LocalYoloModel(
          id: '',
          task: Task.detect,
          format: Format.tflite,
          modelPath: modelPath,
          metadataPath: metadataPath,
        );
        objectDetector = ObjectDetector(model: model);
        await objectDetector?.loadModel();
        objectDetector?.setNumItemsThreshold(250);
        objectDetector?.setConfidenceThreshold(0.5);
        objectDetector?.setIouThreshold(0.15);
        if (kDebugMode) {
          print('Model loaded successfully');
        }
      }

      if (kDebugMode) {
        print("Starting object detection...");
      }
      final results = await objectDetector!.detect(
        imagePath: widget.imageFile.path,
      );

      if (results != null && results.isNotEmpty) {
        if (kDebugMode) {
          print("Got ${results.length} detections");
        }

        // Đếm số lượng mỗi class
        int germinated = 0;
        int notGerminated = 0;

        for (var detection in results) {
          if (detection == null) continue;
          if (detection.index == 0) {
            germinated++;
          } else if (detection.index == 1) {
            notGerminated++;
          }
        }

        setState(() {
          detections = results;
          germinatedCount = germinated;
          notGerminatedCount = notGerminated;
        });

        // Lưu kết quả vào database
        final predictionResult = serializePredictionResult(
          results,
          germinated,
          notGerminated,
        );
        await savePredictionToDatabase(predictionResult);

        setState(() {
          isPredicted = true;
        });
      } else {
        if (kDebugMode) {
          print("No detections found");
        }
        // Lưu kết quả rỗng vào database
        await savePredictionToDatabase(
          jsonEncode({
            "germinated_count": 0,
            "not_germinated_count": 0,
            "detections": [],
          }),
        );
        setState(() {
          isPredicted = true;
          germinatedCount = 0;
          notGerminatedCount = 0;
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print("Detection error: $e");
      }
      if (kDebugMode) {
        print("Stack trace: $stackTrace");
      }
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Detection failed: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Hàm chuyển đổi kết quả dự đoán thành chuỗi JSON để lưu vào database
  String serializePredictionResult(
    List<DetectedObject?> results,
    int germinated,
    int notGerminated,
  ) {
    final Map<String, dynamic> resultData = {
      'germinated_count': germinated,
      'not_germinated_count': notGerminated,
      'detections': [],
    };

    final List<Map<String, dynamic>> serializedDetections = [];

    for (var detection in results) {
      if (detection == null) continue;

      serializedDetections.add({
        'label': detection.label,
        'confidence': detection.confidence,
        'class_id': detection.index,
        'bbox': {
          'x': detection.boundingBox.left,
          'y': detection.boundingBox.top,
          'width': detection.boundingBox.width,
          'height': detection.boundingBox.height,
        },
      });
    }

    resultData['detections'] = serializedDetections;
    return jsonEncode(resultData);
  }

  // Hàm lưu kết quả dự đoán vào database
  Future<void> savePredictionToDatabase(String predictionResult) async {
    try {
      final DatabaseHelper dbHelper = DatabaseHelper.instance;
      final Map<String, dynamic> jsonData = jsonDecode(predictionResult);
      final int germCount = jsonData['germinated_count'] ?? 0;
      final int notGermCount = jsonData['not_germinated_count'] ?? 0;

      if (kDebugMode) {
        print("Saving detection results to database:");
        print("  - Image path: ${widget.imageFile.path}");
        print("  - Germinated count: $germCount");
        print("  - Not germinated count: $notGermCount");
      }

      // 1. Lưu vào bảng images như hiện tại
      if (imageDbId != null) {
        await dbHelper.updateImagePrediction(imageDbId!, predictionResult);
        if (kDebugMode) {
          print("Updated prediction for image ID: $imageDbId");
        }
      } else {
        final db = await dbHelper.database;
        final imagePath = widget.imageFile.path;

        final List<Map<String, dynamic>> images = await db.query(
          'images',
          where: 'file_path = ? AND project_id = ?',
          whereArgs: [imagePath, widget.projectId],
        );

        if (images.isNotEmpty) {
          final imageId = images.first['id'] as int;
          await dbHelper.updateImagePrediction(imageId, predictionResult);
          setState(() {
            imageDbId = imageId;
          });
        } else {
          final imageId = await dbHelper.addImage(widget.projectId, imagePath);
          await dbHelper.updateImagePrediction(imageId, predictionResult);
          setState(() {
            imageDbId = imageId;
          });
        }
      }

      // 2. Lưu vào bảng detection_results cho CapturesScreen
      await dbHelper.saveDetectionResult(
          widget.projectId, widget.imageFile.path, germCount, notGermCount);

      if (kDebugMode) {
        print("Successfully saved detection results to both tables");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Failed to save prediction to database: $e");
      }
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Failed to save prediction: $e')),
      );
    }
  }

  Future<void> _saveImageWithBoundingBoxes() async {
    if (isSaving) return;

    setState(() {
      isSaving = true;
    });

    try {
      // Capture màn hình
      final RenderRepaintBoundary boundary = _screenshotKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0); // Tăng chất lượng
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      final buffer = byteData!.buffer.asUint8List();

      // Lưu file
      final downloadsPath = await _getDownloadsPath();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$downloadsPath/detected_image_$timestamp.png';

      final file = File(filePath);
      await file.writeAsBytes(buffer);

      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('Image saved to Downloads folder')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('Failed to save image: $e')),
        );
      }
    } finally {
      setState(() {
        isSaving = false;
      });
    }
  }

  // Add this helper method to get Downloads path
  Future<String> _getDownloadsPath() async {
    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      final downloadsPath = directory?.path.replaceAll(
          '/Android/data/com.nbee.riceseed_count/files', '/Download');
      return downloadsPath ?? '/storage/emulated/0/Download';
    } else {
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/Downloads';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text('Preview', style: TextStyle(color: Colors.white)),
      ),
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cột bên trái chứa các nút
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Detect Objects button
                    SizedBox(
                      width: 150,
                      child: TextButton(
                        onPressed: isLoading ? null : detectObjects,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black,
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          isLoading
                              ? 'Detecting...'
                              : (isPredicted
                                  ? 'Re-run Detection'
                                  : 'Detect Objects'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Download button
                    SizedBox(
                      width: 150,
                      child: TextButton(
                        onPressed: (isPredicted && !isSaving)
                            ? _saveImageWithBoundingBoxes
                            : null,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black,
                          backgroundColor: const Color(0xFFD1E8C3),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          isSaving ? 'Saving...' : 'Download Image',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Delete button
                    SizedBox(
                      width: 150,
                      child: TextButton(
                        onPressed: () async {
                          try {
                            // Xóa file khỏi hệ thống
                            await widget.imageFile.delete();

                            // Xóa file khỏi database
                            final DatabaseHelper dbHelper =
                                DatabaseHelper.instance;

                            // Xóa ảnh từ bảng images nếu có
                            if (imageDbId != null) {
                              await dbHelper.deleteImage(imageDbId!);
                            }

                            final updatedFileList = widget.fileList
                                .map((file) => file.path)
                                .toList();
                            updatedFileList.remove(
                                widget.imageFile.path); // Loại bỏ file đã xóa
                            await dbHelper.updateProjectFiles(
                                widget.projectId, updatedFileList);

                            // Hiển thị thông báo thành công
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Image deleted successfully')),
                              );
                            }

                            // Điều hướng quay lại màn hình CapturesScreen
                            if (mounted) {
                              await Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CapturesScreen(
                                    projectId: widget.projectId,
                                  ),
                                ),
                                (route) => false,
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content:
                                        Text('Failed to delete image: $e')),
                              );
                            }
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Delete Image',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 12),

                // Phần hiển thị thông tin bên phải
                if (isPredicted && !isLoading)
                  Expanded(
                    child: Container(
                      height:
                          150, // Đặt chiều cao bằng với tổng chiều cao của 3 nút
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center, // Căn giữa theo chiều dọc
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 10),
                          const Text(
                            'Detection Info',
                            style: TextStyle(
                              color: Color.fromARGB(255, 16, 32, 32),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Germinated: $germinatedCount',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Not Germinated: $notGerminatedCount',
                            style: const TextStyle(
                              color: Color.fromARGB(255, 201, 73, 64),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total: ${germinatedCount + notGerminatedCount}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RepaintBoundary(
              key: _screenshotKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    widget.imageFile,
                    fit: BoxFit.contain,
                  ),
                  if (detections != null && imageSize != null)
                    CustomPaint(
                      size: Size.infinite,
                      painter: BoundingBoxPainter(
                        detections: detections!,
                        imageSize: imageSize!,
                      ),
                    ),
                  if (isLoading)
                    Container(
                      color: Colors.black.withOpacity(0.5),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject?> detections;
  final Size imageSize;

  BoundingBoxPainter({
    required this.detections,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var imageRatio = imageSize.height / imageSize.width;
    var canvasRatio = size.height / size.width;

    var ofsetX = 0.0;
    var ofsetY = 0.0;

    if (imageRatio < canvasRatio) {
      ofsetY = (size.height - (size.width * imageRatio)) / 2;
    } else {
      ofsetX = (size.width - (size.height / imageRatio)) / 2;
    }

    for (var detection in detections) {
      if (detection == null) continue;
      var color = Colors.red;
      if (detection.index == 0) {
        color = Colors.blue;
      }

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;

      // Scale the bounding box
      final rect = Rect.fromLTWH(
        detection.boundingBox.left + ofsetX,
        detection.boundingBox.top + ofsetY,
        detection.boundingBox.width,
        detection.boundingBox.height,
      );

      canvas.drawRect(rect, paint);

      // Draw label with background
      final labelText = detection.label;

      final textPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Draw white background for text
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left,
          rect.top > textPainter.height
              ? rect.top - textPainter.height
              : rect.top,
          textPainter.width + 8,
          textPainter.height,
        ),
        Paint()..color = Colors.white,
      );

      // Draw text
      textPainter.paint(
        canvas,
        Offset(
          rect.left + 4,
          rect.top > textPainter.height
              ? rect.top - textPainter.height
              : rect.top,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
