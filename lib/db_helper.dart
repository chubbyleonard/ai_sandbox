import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('private_brain.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    // Incremented version to 2 to force a database schema upgrade
    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        title TEXT,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT,
        role TEXT,
        output TEXT,
        thinking TEXT,
        timestamp TEXT
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS messages');
      await db.execute('DROP TABLE IF EXISTS sessions');
      await _createDB(db, newVersion);
    }
  }

  Future<void> createSession(String id, String title) async {
    final db = await instance.database;
    await db.insert('sessions', {
      'id': id,
      'title': title,
      'created_at': DateTime.now().toIso8601String()
    });
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    final db = await instance.database;
    return await db.query('sessions', orderBy: 'created_at DESC');
  }

  Future<void> deleteSession(String id) async {
    final db = await instance.database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
    await db.delete('messages', where: 'session_id = ?', whereArgs: [id]);
  }

  Future<void> saveMessage(String sessionId, String role, String output, String thinking) async {
    final db = await instance.database;
    await db.insert('messages', {
      'session_id': sessionId,
      'role': role,
      'output': output,
      'thinking': thinking,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> fetchMessages(String sessionId) async {
    final db = await instance.database;
    return await db.query('messages', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'id ASC');
  }
}