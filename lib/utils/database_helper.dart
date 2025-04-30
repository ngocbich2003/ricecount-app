import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io';
import 'dart:convert';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  DatabaseHelper._privateConstructor();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'projects.db');

    return await openDatabase(
      path,
      version: 4, // Tăng version lên 4
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE images (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              project_id INTEGER NOT NULL,
              file_path TEXT NOT NULL,
              is_predicted INTEGER DEFAULT 0,
              prediction_result TEXT,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
            )
          ''');
        }
        if (oldVersion < 3) {
          // Create users table
          await db.execute('''
            CREATE TABLE users(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT UNIQUE NOT NULL,
              password TEXT NOT NULL,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        }
        if (oldVersion < 4) {
          // Create detection_results table
          await db.execute('''
            CREATE TABLE detection_results(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              project_id INTEGER NOT NULL,
              image_path TEXT NOT NULL,
              germ_count INTEGER DEFAULT 0,
              not_germ_count INTEGER DEFAULT 0,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
            )
          ''');
        }
      },
    );
  }

  Future _onCreate(Database db, int version) async {
    // Create users table
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    
    // Create projects table with user_id field
    await db.execute('''
      CREATE TABLE projects(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        user_id TEXT NOT NULL,
        preview_image TEXT,
        created_at TEXT NOT NULL,
        total_images INTEGER DEFAULT 0,
        detected_images INTEGER DEFAULT 0,
        germinated_count INTEGER DEFAULT 0,
        not_germinated_count INTEGER DEFAULT 0
      )
    ''');
    
    // Create images table
    await db.execute('''
      CREATE TABLE images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        is_predicted INTEGER DEFAULT 0,
        prediction_result TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');
    
    // Create detection_results table
    await db.execute('''
      CREATE TABLE detection_results(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        image_path TEXT NOT NULL, 
        germ_count INTEGER DEFAULT 0,
        not_germ_count INTEGER DEFAULT 0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');
  }

  // User authentication methods
  Future<bool> registerUser(String username, String password) async {
    final db = await database;
    try {
      await db.insert(
        'users',
        {
          'username': username,
          'password': password,
          'created_at': DateTime.now().toIso8601String(),
        },
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> loginUser(String username, String password) async {
    final db = await database;
    final users = await db.query(
      'users',
      where: 'username = ? AND password = ?',
      whereArgs: [username, password],
    );
    
    if (users.isNotEmpty) {
      return users.first;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getProjects(String userId) async {
    final db = await database;
    return await db.query(
      'projects',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
    );
  }

  Future<int> addProject(String name, String userId) async {
    final db = await database;
    return await db.insert(
      'projects',
      {
        'name': name,
        'user_id': userId,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> updateProjectFiles(int projectId, List<String> filePaths) async {
    final db = await database;
    
    // Xóa các ảnh cũ
    await db.delete(
      'images',
      where: 'project_id = ?',
      whereArgs: [projectId],
    );
    
    // Thêm các ảnh mới
    final batch = db.batch();
    for (var filePath in filePaths) {
      batch.insert('images', {
        'project_id': projectId,
        'file_path': filePath,
        'is_predicted': 0,
      });
    }
    
    await batch.commit(noResult: true);
  }

  Future<List<File>> getProjectFiles(int projectId) async {
    final db = await database;
    final result = await db.query(
      'images',
      columns: ['file_path'],
      where: 'project_id = ?',
      whereArgs: [projectId],
    );

    return result.map((row) => File(row['file_path'] as String)).toList();
  }

  Future<void> deleteProject(int projectId) async {
    final db = await database;
    await db.delete(
      'projects',
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<int> addImage(int projectId, String filePath) async {
    final db = await database;
    return await db.insert('images', {
      'project_id': projectId,
      'file_path': filePath,
      'is_predicted': 0,
    });
  }

  Future<void> bulkAddImages(int projectId, List<String> filePaths) async {
    final db = await database;
    final batch = db.batch();
    
    for (var filePath in filePaths) {
      batch.insert('images', {
        'project_id': projectId,
        'file_path': filePath,
        'is_predicted': 0,
      });
    }
    
    await batch.commit(noResult: true);
  }

  Future<void> updateImagePrediction(int imageId, String predictionResult) async {
    final db = await database;
    await db.update(
      'images',
      {
        'prediction_result': predictionResult,
        'is_predicted': 1,
      },
      where: 'id = ?',
      whereArgs: [imageId],
    );
  }

  Future<List<Map<String, dynamic>>> getProjectImages(int projectId) async {
    final db = await database;
    return await db.query(
      'images',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getUnpredictedImages(int projectId) async {
    final db = await database;
    return await db.query(
      'images',
      where: 'project_id = ? AND is_predicted = 0',
      whereArgs: [projectId],
    );
  }

  Future<List<Map<String, dynamic>>> getPredictedImages(int projectId) async {
    final db = await database;
    return await db.query(
      'images',
      where: 'project_id = ? AND is_predicted = 1',
      whereArgs: [projectId],
    );
  }

  Future<void> deleteImage(int imageId) async {
    final db = await database;
    await db.delete(
      'images',
      where: 'id = ?',
      whereArgs: [imageId],
    );
  }

  Future<int> getProjectImageCount(int projectId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM images WHERE project_id = ?',
      [projectId],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<int> getDetectedImageCount(int projectId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM images WHERE project_id = ? AND is_predicted = 1',
      [projectId],
    );
    return result.first['count'] as int? ?? 0;
  }

  Future<Map<String, int>> getProjectCounts(int projectId) async {
    final db = await database;
    
    final List<Map<String, dynamic>> images = await db.query(
      'images',
      where: 'project_id = ? AND is_predicted = 1',
      whereArgs: [projectId],
    );
    
    int totalGerminated = 0;
    int totalNotGerminated = 0;
    
    for (var image in images) {
      final predictionResult = image['prediction_result'] as String?;
      if (predictionResult != null && predictionResult.isNotEmpty) {
        try {
          final Map<String, dynamic> jsonData = jsonDecode(predictionResult);
          totalGerminated += jsonData['germinated_count'] as int? ?? 0;
          totalNotGerminated += jsonData['not_germinated_count'] as int? ?? 0;
        } catch (e) {
        }
      }
    }
    
    return {
      'germinated_count': totalGerminated,
      'not_germinated_count': totalNotGerminated,
    };
  }

  Future<String?> getFirstProjectImage(int projectId) async {
    final db = await database;
    final images = await db.query(
      'images',
      columns: ['file_path'],
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at ASC',
      limit: 1
    );
    
    if (images.isNotEmpty) {
      return images.first['file_path'] as String?;
    }
    
    final projects = await db.query(
      'projects',
      columns: ['files'],
      where: 'id = ?',
      whereArgs: [projectId],
    );
    
    if (projects.isNotEmpty && projects.first['files'] != null) {
      final filesStr = projects.first['files'] as String;
      if (filesStr.isNotEmpty) {
        final files = filesStr.split(',');
        if (files.isNotEmpty) {
          return files.first;
        }
      }
    }
    
    return null;
  }

  Future<Map<String, dynamic>> getDetectionResults(int projectId) async {
    final db = await database;
    
    // Get detected images
    final detectedImagesResult = await db.query(
      'detection_results',
      where: 'project_id = ?',
      whereArgs: [projectId],
    );
    
    Map<String, bool> detectedImages = {};
    Map<String, Map<String, int>> detectionResults = {};
    
    for (var row in detectedImagesResult) {
      final imagePath = row['image_path'] as String;
      final germCount = row['germ_count'] as int? ?? 0;
      final notGermCount = row['not_germ_count'] as int? ?? 0;
      
      // Mark image as detected
      detectedImages[imagePath] = true;
      
      // Store detection counts
      detectionResults[imagePath] = {
        'germ': germCount,
        'not_germ': notGermCount,
      };
    }
    
    print('Detected images: $detectedImages'); // Debug
    print('Detection results: $detectionResults'); // Debug
    
    return {
      'detected_images': detectedImages,
      'detection_results': detectionResults,
    };
  }

  Future<int> saveDetectionResult(int projectId, String imagePath, int germCount, int notGermCount) async {
    final db = await database;
    
    // Check if a result already exists for this image
    final existing = await db.query(
      'detection_results',
      where: 'project_id = ? AND image_path = ?',
      whereArgs: [projectId, imagePath],
    );
    
    if (existing.isNotEmpty) {
      // Update existing record
      return await db.update(
        'detection_results',
        {
          'germ_count': germCount,
          'not_germ_count': notGermCount,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      // Insert new record
      return await db.insert(
        'detection_results',
        {
          'project_id': projectId,
          'image_path': imagePath,
          'germ_count': germCount,
          'not_germ_count': notGermCount,
          'created_at': DateTime.now().toIso8601String(),
        },
      );
    }
  }
}