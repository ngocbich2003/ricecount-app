import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/database_helper.dart';
import '/screens/preview_screen.dart';
import '/screens/camera_screen.dart';

class CapturesScreen extends StatefulWidget {
  final int projectId; // Chỉ cần projectId để liên kết với database

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
  List<File> _imageFileList = []; // Danh sách file sẽ được lấy từ database

  @override
  void initState() {
    super.initState();
    _fetchImagesFromDatabase(); // Lấy danh sách file từ database
  }

  Future<void> _fetchImagesFromDatabase() async {
    final files = await _dbHelper.getProjectFiles(widget.projectId);
    setState(() {
      _imageFileList = files;
    });
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _imageFileList.add(File(pickedFile.path));
        });
        await _saveToDatabase(); // Lưu vào database
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Captures',
                style: TextStyle(
                  fontSize: 32.0,
                  color: Colors.white,
                ),
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              children: [
                // Camera Button
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    onTap: () async {
                      final capturedImages = await Navigator.of(context).push(
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
                        await _saveToDatabase(); // Lưu vào database
                      }
                    },
                    child: const Center(
                      child: Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                ),
                // Add Button for gallery
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    onTap: _pickImage,
                    child: const Center(
                      child: Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                ),
                // Existing Images
                for (File imageFile in _imageFileList)
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.black,
                        width: 2,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => PreviewScreen(
                              fileList: _imageFileList,
                              imageFile: imageFile,
                              projectId: widget.projectId, // Pass projectId
                            ),
                          ),
                        );
                      },
                      child: Image.file(
                        imageFile,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
