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
      version: 2, // Tăng version để thực hiện migration
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE projects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            files TEXT
          )
        ''');
        
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
      },
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
      },
    );
  }

  Future<List<Map<String, dynamic>>> getProjects() async {
    final db = await database;
    return await db.query('projects');
  }

  Future<int> addProject(String name) async {
    final db = await database;
    return await db.insert('projects', {'name': name});
  }

  Future<void> updateProjectFiles(int projectId, List<String> filePaths) async {
    final db = await database;
    await db.update(
      'projects',
      {'files': filePaths.join(',')},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<List<File>> getProjectFiles(int projectId) async {
    final db = await database;
    final result = await db.query(
      'projects',
      columns: ['files'],
      where: 'id = ?',
      whereArgs: [projectId],
    );

    if (result.isNotEmpty && result.first['files'] != null) {
      final filePaths = (result.first['files'] as String).split(',');
      return filePaths.map((path) => File(path)).toList();
    }
    return [];
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
}