import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/database_helper.dart';
import 'captures_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _filteredProjects = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProjects();
    _searchController.addListener(_filterProjects);
  }

  Future<void> _fetchProjects() async {
    setState(() {
      _isLoading = true;
    });
    
    final projects = await _dbHelper.getProjects();
    final List<Map<String, dynamic>> enrichedProjects = [];
    
    for (var project in projects) {
      final projectId = project['id'] as int;
      final totalImages = await _dbHelper.getProjectImageCount(projectId);
      final detectedImages = await _dbHelper.getDetectedImageCount(projectId);
      final counts = await _dbHelper.getProjectCounts(projectId);
      final previewImagePath = await _dbHelper.getFirstProjectImage(projectId);
      
      enrichedProjects.add({
        ...project,
        'total_images': totalImages,
        'detected_images': detectedImages,
        'germinated_count': counts['germinated_count'] ?? 0,
        'not_germinated_count': counts['not_germinated_count'] ?? 0,
        'preview_image': previewImagePath,
      });
    }
    
    setState(() {
      _projects = enrichedProjects;
      _filteredProjects = enrichedProjects;
      _isLoading = false;
    });
  }

  void _filterProjects() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProjects = _projects
          .where((project) => project['name'].toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _deleteProject(int projectId) async {
    await _dbHelper.deleteProject(projectId);
    _fetchProjects();
  }

  Future<void> _addProject() async {
    final TextEditingController controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Project'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter project name'),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await _dbHelper.addProject(controller.text);
                Navigator.of(context).pop();
                _fetchProjects();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rice Count'),
        centerTitle: true,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.amber),
              child: Text(
                'Menu',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFF8E1),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30.0),
                bottomRight: Radius.circular(30.0),
              ),
            ),
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search project',
                hintStyle: const TextStyle(color: Colors.black54),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20.0),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.black54),
              ),
              style: const TextStyle(color: Colors.black),
            ),
          ),
          Expanded(
            child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
              itemCount: _filteredProjects.length,
              itemBuilder: (context, index) {
                final project = _filteredProjects[index];
                final hasPreview = project['preview_image'] != null;
                
                return Card(
                  margin: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 8.0),
                  elevation: 3,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CapturesScreen(
                            projectId: project['id'],
                          ),
                        ),
                      ).then((_) => _fetchProjects());
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ảnh preview hoặc placeholder
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 100,
                              height: 100,
                              child: hasPreview
                                ? Image.file(
                                    File(project['preview_image']),
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                          child: Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                                        ),
                                      );
                                    },
                                  )
                                : Container(
                                    color: Colors.grey.shade200,
                                    child: const Center(
                                      child: Icon(Icons.image, size: 40, color: Colors.grey),
                                    ),
                                  ),
                            ),
                          ),
                          
                          const SizedBox(width: 16),
                          
                          // Thông tin project
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Project title và delete button
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        project['name'],
                                        style: const TextStyle(
                                          fontSize: 18, 
                                          fontWeight: FontWeight.bold
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Delete Project'),
                                            content: const Text(
                                                'Are you sure you want to delete this project?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context).pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context).pop(true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          _deleteProject(project['id']);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                
                                const Divider(),
                                
                                // Thông tin thống kê
                                Text(
                                  'Images: ${project['total_images']} total, ${project['detected_images']} detected',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'Germinated: ${project['germinated_count']}',
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.w500
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Not germinated: ${project['not_germinated_count']}',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w500
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 8),
                                
                                // View project button
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => CapturesScreen(
                                            projectId: project['id'],
                                          ),
                                        ),
                                      ).then((_) => _fetchProjects());
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: Colors.blue,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('View Project'),
                                  ),
                                ),
                              ],
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
      floatingActionButton: FloatingActionButton(
        onPressed: _addProject,
        child: const Icon(Icons.add),
      ),
    );
  }
}
