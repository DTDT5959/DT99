import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Single source of truth for the local SQLite database.
///
/// Schema is deliberately "sync ready": every table has a text primary key
/// (UUID) rather than an autoincrement int, plus `updated_at` and
/// `is_synced` columns, so a future cloud-sync layer can be bolted on
/// without a migration that touches primary keys.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'dragon_fruit_flower_counter.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createFieldBoundariesTable(db);
    }
    if (oldVersion < 3) {
      await _addFarmImportedAtColumn(db);
    }
  }

  Future<void> _createFieldBoundariesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_boundaries (
        id TEXT PRIMARY KEY,
        farm_id TEXT NOT NULL,
        vertices TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (farm_id) REFERENCES farms (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_boundaries_farm ON field_boundaries (farm_id)');
  }

  /// Farm Sharing (spec §27): a nullable marker so an imported farm can
  /// show a subtle "Imported" badge. Purely informational — nothing reads
  /// this column to gate functionality, and it's left NULL for every
  /// locally-created farm.
  Future<void> _addFarmImportedAtColumn(Database db) async {
    await db.execute('ALTER TABLE farms ADD COLUMN imported_at TEXT');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE farms (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        imported_at TEXT,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE posts (
        id TEXT PRIMARY KEY,
        farm_id TEXT NOT NULL,
        post_code TEXT NOT NULL,
        color TEXT NOT NULL,
        position_x REAL NOT NULL,
        position_y REAL NOT NULL,
        notes TEXT,
        latitude REAL,
        longitude REAL,
        qr_code TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (farm_id) REFERENCES farms (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE flower_counts (
        id TEXT PRIMARY KEY,
        post_id TEXT NOT NULL,
        date TEXT NOT NULL,
        flower_count INTEGER NOT NULL,
        counted_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE photos (
        id TEXT PRIMARY KEY,
        post_id TEXT NOT NULL,
        image_path TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('''
      CREATE TABLE field_boundaries (
        id TEXT PRIMARY KEY,
        farm_id TEXT NOT NULL,
        vertices TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (farm_id) REFERENCES farms (id) ON DELETE CASCADE
      )
    ''');

    batch.execute('CREATE INDEX idx_posts_farm ON posts (farm_id)');
    batch.execute('CREATE INDEX idx_counts_post_date ON flower_counts (post_id, date)');
    batch.execute('CREATE UNIQUE INDEX idx_counts_post_date_unique ON flower_counts (post_id, date)');
    batch.execute('CREATE INDEX idx_photos_post ON photos (post_id)');
    batch.execute('CREATE INDEX idx_boundaries_farm ON field_boundaries (farm_id)');

    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
