import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('chat_history.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        output TEXT NOT NULL,
        thinking TEXT NOT NULL
      )
    ''');
  }

  Future<void> saveMessage(String role, String output, String thinking) async {
    final db = await instance.database;
    await db.insert('messages', {
      'role': role,
      'output': output,
      'thinking': thinking,
    });
  }

  Future<List<Map<String, dynamic>>> fetchMessages() async {
    final db = await instance.database;
    return await db.query('messages', orderBy: 'id ASC');
  }
  
  Future<void> clearHistory() async {
    final db = await instance.database;
    await db.delete('messages');
  }
}