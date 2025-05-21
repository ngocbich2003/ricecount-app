import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as xl; // Thêm tiền tố 'xl' cho package excel
import '../utils/database_helper.dart';
import '/screens/preview_screen.dart';
import '/screens/camera_screen.dart';

class CapturesScreen extends StatefulWidget {
  final int projectId;

  const CapturesScreen({
    super.key,
    required this.projectId,
  });

  @override
  State<CapturesScreen> createState() => _CapturesScreenState();
}

class _CapturesScreenState extends State<CapturesScreen> {
  final ImagePicker _picker = ImagePicker();
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<File> _imageFileList = [];
  Map<String, bool> _detectedImages =
      {}; // Track which images have been processed
  Map<String, Map<String, int>> _detectionResults =
      {}; // Store detection results for each image
  bool _isLoading = false; // Loading indicator

  int get totalImages => _imageFileList.length;
  int get detectedImages =>
      _detectedImages.values.where((detected) => detected).length;
  int get totalGermCount => _getDetectionCount('germ');
  int get totalNotGermCount => _getDetectionCount('not_germ');
  String get germinationRate {
    if (totalGermCount + totalNotGermCount == 0) return '0.0%';
    return '${((totalGermCount / (totalGermCount + totalNotGermCount)) * 100).toStringAsFixed(1)}%';
  }

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  int _getDetectionCount(String category) {
    int count = 0;
    for (var result in _detectionResults.values) {
      count += result[category] ?? 0;
    }
    return count;
  }

  Future<void> _loadAllData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final files = await _dbHelper.getProjectFiles(widget.projectId);
      final results = await _dbHelper.getDetectionResults(widget.projectId);

      setState(() {
        _imageFileList = files;
        _detectedImages = results['detected_images'] ?? {};
        _detectionResults = results['detection_results'] ?? {};
        _isLoading = false;
      });
      for (var file in _imageFileList) {
        if (_detectedImages[file.path] == true) {
          print('Germ count: ${_detectionResults[file.path]?['germ']}');
          print('Not germ count: ${_detectionResults[file.path]?['not_germ']}');
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchImagesFromDatabase() async {
    final files = await _dbHelper.getProjectFiles(widget.projectId);
    setState(() {
      _imageFileList = files;
    });
    await _fetchDetectionResults();
  }

  Future<void> _fetchDetectionResults() async {
    try {
      // 1. Truy vấn trực tiếp cơ sở dữ liệu để debug
      final db = await _dbHelper.database;
      final rawResults = await db.query(
        'detection_results',
        where: 'project_id = ?',
        whereArgs: [widget.projectId],
      );

      print(
          'RAW DB DATA: Found ${rawResults.length} records in detection_results');
      for (var row in rawResults) {
        print(
            '  - Record: ${row['image_path']} | Germ: ${row['germ_count']} | Not Germ: ${row['not_germ_count']}');
      }

      // 2. Lấy kết quả phát hiện qua helper method
      final results = await _dbHelper.getDetectionResults(widget.projectId);

      // 3. Cập nhật state với dữ liệu mới
      setState(() {
        _detectedImages = results['detected_images'] ?? {};
        _detectionResults = results['detection_results'] ?? {};
      });

      // 4. Debug thông tin chi tiết
      print('PROCESSED DATA:');
      print('  - Detected images: ${_detectedImages.length}');
      print('  - Detection results: ${_detectionResults.length}');
      print('  - Total images: $totalImages');
      print('  - Detected images count: $detectedImages');
      print('  - Total germ count: $totalGermCount');
      print('  - Total not germ count: $totalNotGermCount');

      // 5. Debug từng file cụ thể để kiểm tra matching
      for (var file in _imageFileList) {
        final path = file.path;
        final isDetected = _detectedImages[path] ?? false;
        final result = _detectionResults[path];

        print('IMAGE CHECK: ${_getFilenameFromPath(path)}');
        print('  - Path: $path');
        print('  - Is detected: $isDetected');
        if (isDetected && result != null) {
          print('  - Germ count: ${result['germ']}');
          print('  - Not germ count: ${result['not_germ']}');
        } else if (!isDetected) {
          print('  - Not detected yet');
        } else {
          print('  - ERROR: Detection marked but no results found');
        }
      }
    } catch (e) {
      print('Error fetching detection results: $e');
      print(e.toString());
    }
  }

  Future<void> _saveDetectionResult(
      File imageFile, Map<String, int> results) async {
    try {
      final germCount = results['germ'] ?? 0;
      final notGermCount = results['not_germ'] ?? 0;

      print('SAVING DETECTION: ${_getFilenameFromPath(imageFile.path)}');
      print('  - Path: ${imageFile.path}');
      print('  - Germ count: $germCount');
      print('  - Not germ count: $notGermCount');

      final savedId = await _dbHelper.saveDetectionResult(
        widget.projectId,
        imageFile.path,
        germCount,
        notGermCount,
      );

      print('  - Save result ID: $savedId');

      // Refresh the detection results after saving
      await _fetchDetectionResults();
    } catch (e) {
      print('Error saving detection result: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile =
          await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _imageFileList.add(File(pickedFile.path));
        });
        await _saveToDatabase();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _saveToDatabase() async {
    final filePaths = _imageFileList.map((file) => file.path).toList();
    await _dbHelper.updateProjectFiles(widget.projectId, filePaths);
  }

  String _getFilenameFromPath(String path) {
    final List<String> parts = path.split(RegExp(r'[/\\]'));
    return parts.last;
  }

  Future<void> _exportToExcel() async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Detection Results'];

      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = xl.TextCellValue('Project ID');
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
          .value = xl.TextCellValue('Total Images');
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0))
          .value = xl.TextCellValue('Detected Images');
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0))
          .value = xl.TextCellValue('Germ Count');
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0))
          .value = xl.TextCellValue('Not Germ Count');

      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = xl.IntCellValue(widget.projectId);
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
          .value = xl.IntCellValue(totalImages);
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1))
          .value = xl.IntCellValue(detectedImages);
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1))
          .value = xl.IntCellValue(totalGermCount);
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1))
          .value = xl.IntCellValue(totalNotGermCount);

      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3))
          .value = xl.TextCellValue('Image');
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3))
          .value = xl.TextCellValue('Detected');
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 3))
          .value = xl.TextCellValue('Germ Count');
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 3))
          .value = xl.TextCellValue('Not Germ Count');

      int rowIndex = 4;
      for (var image in _imageFileList) {
        final path = image.path;
        final filename = _getFilenameFromPath(path);
        final isDetected = _detectedImages[path] ?? false;
        final results = _detectionResults[path] ?? {};

        sheet
            .cell(xl.CellIndex.indexByColumnRow(
                columnIndex: 0, rowIndex: rowIndex))
            .value = xl.TextCellValue(filename);
        sheet
            .cell(xl.CellIndex.indexByColumnRow(
                columnIndex: 1, rowIndex: rowIndex))
            .value = xl.TextCellValue(isDetected ? 'Yes' : 'No');
        sheet
            .cell(xl.CellIndex.indexByColumnRow(
                columnIndex: 2, rowIndex: rowIndex))
            .value = xl.IntCellValue(results['germ'] ?? 0);
        sheet
            .cell(xl.CellIndex.indexByColumnRow(
                columnIndex: 3, rowIndex: rowIndex))
            .value = xl.IntCellValue(results['not_germ'] ?? 0);

        rowIndex++;
      }

      final directory = await getApplicationDocumentsDirectory();
      final fileTime = DateTime.now().millisecondsSinceEpoch;
      final filePath =
          '${directory.path}/rice_detection_results_$fileTime.xlsx';
      final file = File(filePath);

      await file.writeAsBytes(excel.encode()!);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel file exported to $filePath'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting Excel file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('View Project', style: theme.appBarTheme.titleTextStyle),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: theme.appBarTheme.elevation,
        iconTheme: theme.appBarTheme.iconTheme,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Project Statistics',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(Icons.image, totalImages.toString(),
                                'Total', theme),
                            _buildStatItem(Icons.check_circle_outline,
                                detectedImages.toString(), 'Detected', theme),
                            _buildStatItem(Icons.check_circle,
                                totalGermCount.toString(), 'Germ', theme),
                            _buildStatItem(
                                Icons.cancel_outlined,
                                totalNotGermCount.toString(),
                                'Not Germ',
                                theme),
                            _buildStatItem(
                                Icons.percent, germinationRate, ' Rate', theme),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.add_photo_alternate,
                          label: 'Add Images',
                          color: const Color.fromARGB(255, 54, 154, 161),
                          onTap: _pickImage,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.camera_alt,
                          label: 'Capture',
                          color: Colors.green,
                          onTap: () async {
                            final capturedImages =
                                await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => CameraScreen(
                                  projectId: widget.projectId,
                                ),
                              ),
                            );
                            if (capturedImages != null) {
                              setState(() {
                                _imageFileList.addAll(capturedImages);
                              });
                              await _saveToDatabase();
                              await _fetchDetectionResults();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.file_download,
                          label: 'Export Info',
                          color: const Color.fromARGB(255, 228, 204, 84),
                          onTap: _exportToExcel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _imageFileList.isEmpty
                        ? Center(
                            child: Text(
                              'No images yet',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1,
                            ),
                            itemCount: _imageFileList.length,
                            itemBuilder: (context, index) {
                              final imageFile = _imageFileList[index];
                              final isDetected =
                                  _detectedImages[imageFile.path] ?? false;

                              return GestureDetector(
                                onTap: () {
                                  Navigator.of(context)
                                      .push(
                                    MaterialPageRoute(
                                      builder: (context) => PreviewScreen(
                                        fileList: _imageFileList,
                                        imageFile: imageFile,
                                        projectId: widget.projectId,
                                      ),
                                    ),
                                  )
                                      .then((_) {
                                    _fetchImagesFromDatabase();
                                    _fetchDetectionResults();
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDetected
                                          ? Colors.green
                                          : Colors.grey[300]!,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.2),
                                        spreadRadius: 1,
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.file(
                                          imageFile,
                                          fit: BoxFit.cover,
                                        ),
                                        if (isDetected)
                                          Positioned(
                                            bottom: 8,
                                            right: 8,
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.check,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadAllData,
        backgroundColor: theme.floatingActionButtonTheme.backgroundColor,
        foregroundColor: theme.floatingActionButtonTheme.foregroundColor,
        tooltip: 'Refresh Data',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildStatItem(
      IconData icon, String value, String label, ThemeData theme) {
    return Column(
      children: [
        Icon(icon, color: theme.primaryColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }

  void updateDetectionResults(File imageFile, int germCount, int notGermCount) {
    setState(() {
      _detectedImages[imageFile.path] = true;
      _detectionResults[imageFile.path] = {
        'germ': germCount,
        'not_germ': notGermCount,
      };
    });

    _saveDetectionResult(imageFile, {
      'germ': germCount,
      'not_germ': notGermCount,
    });
  }
}
