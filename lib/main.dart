import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  runApp(const ToDoApp());
}

Future<void> initNotifications() async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
  await flutterLocalNotificationsPlugin.initialize(initSettings);
}

class ToDoApp extends StatefulWidget {
  const ToDoApp({super.key});

  @override
  _ToDoAppState createState() => _ToDoAppState();
}

class _ToDoAppState extends State<ToDoApp> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = !_isDarkMode;
      prefs.setBool('isDarkMode', _isDarkMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aesthetic To-Do',
      theme: _isDarkMode ? _darkTheme : _lightTheme,
      home: TaskListScreen(toggleTheme: _toggleTheme, isDarkMode: _isDarkMode),
    );
  }
}

final _lightTheme = ThemeData(
  primaryColor: Colors.teal,
  scaffoldBackgroundColor: Colors.grey[100],
  colorScheme: const ColorScheme.light(
    primary: Colors.teal,
    secondary: Colors.amber,
  ),
  textTheme: const TextTheme(
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
    bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.teal,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  cardTheme: CardTheme(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 4,
  ),
);

final _darkTheme = ThemeData(
  primaryColor: Colors.teal,
  scaffoldBackgroundColor: Colors.grey[900],
  colorScheme: const ColorScheme.dark(
    primary: Colors.teal,
    secondary: Colors.amber,
  ),
  textTheme: const TextTheme(
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.tealAccent),
    bodyMedium: TextStyle(fontSize: 16, color: Colors.white70),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.teal,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  cardTheme: CardTheme(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 4,
    color: Colors.grey[800],
  ),
);

enum TaskPriority { low, medium, high }

class Task {
  int? id;
  String title;
  bool isCompleted;
  TaskPriority priority;
  DateTime? dueDate;

  Task({
    this.id,
    required this.title,
    this.isCompleted = false,
    this.priority = TaskPriority.low,
    this.dueDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted ? 1 : 0,
      'priority': priority.index,
      'dueDate': dueDate?.toIso8601String(),
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'],
      title: map['title'],
      isCompleted: map['isCompleted'] == 1,
      priority: TaskPriority.values[map['priority']],
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tasks.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final dbFullPath = path.join(dbPath, filePath); // Using path.join to avoid conflicts

    return await openDatabase(
      dbFullPath,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        isCompleted INTEGER NOT NULL,
        priority INTEGER NOT NULL,
        dueDate TEXT
      )
    ''');
  }

  Future<void> insertTask(Task task) async {
    final db = await database;
    await db.insert('tasks', task.toMap());
    if (task.dueDate != null) {
      _scheduleNotification(task);
    }
  }

  Future<List<Task>> getTasks() async {
    final db = await database;
    final result = await db.query('tasks');
    return result.map((map) => Task.fromMap(map)).toList();
  }

  Future<void> updateTask(Task task) async {
    final db = await database;
    await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
    if (task.dueDate != null) {
      _scheduleNotification(task);
    }
  }

  Future<void> deleteTask(int id) async {
    final db = await database;
    await db.delete(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
    );
    // Cancel any scheduled notification
    await FlutterLocalNotificationsPlugin().cancel(id);
  }

  Future<void> _scheduleNotification(Task task) async {
    if (task.dueDate == null || task.id == null) return;

    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    final now = DateTime.now();
    if (task.dueDate!.isBefore(now)) return;

    const androidDetails = AndroidNotificationDetails(
      'task_channel',
      'Task Reminders',
      channelDescription: 'Notifications for task due dates',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const notificationDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await flutterLocalNotificationsPlugin.schedule(
      task.id!,
      'Task Due: ${task.title}',
      'This task is due soon!',
      task.dueDate!,
      notificationDetails,
      androidAllowWhileIdle: true,
    );
  }

  Future close() async {
    final db = await database;
    _database = null;
    await db.close();
  }
}

extension on FlutterLocalNotificationsPlugin {
  schedule(int i, String s, String t, DateTime dateTime, NotificationDetails notificationDetails, {required bool androidAllowWhileIdle}) {}
}

class TaskListScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final bool isDarkMode;

  const TaskListScreen({super.key, required this.toggleTheme, required this.isDarkMode});

  @override
  _TaskListScreenState createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  final TextEditingController _titleController = TextEditingController();
  List<Task> _tasks = [];
  List<Task> _filteredTasks = [];
  String _filter = 'All';
  TaskPriority _selectedPriority = TaskPriority.low;
  DateTime? _selectedDueDate;

  @override
  void initState() {
    super.initState();
    _refreshTaskList();
  }

  Future<void> _refreshTaskList() async {
    final tasks = await _dbHelper.getTasks();
    setState(() {
      _tasks = tasks;
      _applyFilter();
    });
  }

  void _applyFilter() {
    setState(() {
      if (_filter == 'Completed') {
        _filteredTasks = _tasks.where((task) => task.isCompleted).toList();
      } else if (_filter == 'Pending') {
        _filteredTasks = _tasks.where((task) => !task.isCompleted).toList();
      } else {
        _filteredTasks = _tasks;
      }
      _filteredTasks.sort((a, b) => a.priority.index.compareTo(b.priority.index)); // Sort by priority
    });
  }

  Future<void> _addOrUpdateTask({Task? existingTask}) async {
    if (_titleController.text.isNotEmpty) {
      final task = Task(
        id: existingTask?.id,
        title: _titleController.text,
        isCompleted: existingTask?.isCompleted ?? false,
        priority: _selectedPriority,
        dueDate: _selectedDueDate,
      );
      if (existingTask == null) {
        await _dbHelper.insertTask(task);
      } else {
        await _dbHelper.updateTask(task);
      }
      _titleController.clear();
      _selectedDueDate = null;
      _selectedPriority = TaskPriority.low;
      _refreshTaskList();
      Navigator.pop(context);
    }
  }

  Future<void> _toggleTaskCompletion(Task task) async {
    task.isCompleted = !task.isCompleted;
    await _dbHelper.updateTask(task);
    _refreshTaskList();
  }

  Future<void> _deleteTask(int id) async {
    await _dbHelper.deleteTask(id);
    _refreshTaskList();
  }

  void _showTaskDialog({Task? task}) {
    if (task != null) {
      _titleController.text = task.title;
      _selectedPriority = task.priority;
      _selectedDueDate = task.dueDate;
    } else {
      _titleController.clear();
      _selectedPriority = TaskPriority.low;
      _selectedDueDate = null;
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(task == null ? 'Add Task' : 'Edit Task'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<TaskPriority>(
                value: _selectedPriority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(),
                ),
                items: TaskPriority.values
                    .map((priority) => DropdownMenuItem(
                  value: priority,
                  child: Text(priority.toString().split('.').last),
                ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPriority = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text(
                  _selectedDueDate == null
                      ? 'Select Due Date'
                      : DateFormat.yMMMd().format(_selectedDueDate!),
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: dialogContext,
                    initialDate: _selectedDueDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) {
                    setState(() {
                      _selectedDueDate = date;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _addOrUpdateTask(existingTask: task),
            child: Text(task == null ? 'Add' : 'Update'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = isLandscape ? screenWidth * 0.15 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aesthetic To-Do'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal, Colors.cyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.toggleTheme,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _filter = value;
                _applyFilter();
              });
            },
            itemBuilder: (BuildContext popupContext) => [
              const PopupMenuItem(value: 'All', child: Text('All')),
              const PopupMenuItem(value: 'Completed', child: Text('Completed')),
              const PopupMenuItem(value: 'Pending', child: Text('Pending')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.isDarkMode
                ? [Colors.grey[900]!, Colors.grey[800]!]
                : [Colors.grey[100]!, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
          child: _filteredTasks.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.task_alt,
                  size: 64,
                  color: widget.isDarkMode ? Colors.tealAccent : Colors.teal,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No tasks yet! Add one to start.',
                  style: TextStyle(fontSize: 18),
                ),
              ],
            ),
          )
              : ListView.builder(
            itemCount: _filteredTasks.length,
            itemBuilder: (BuildContext listContext, int index) {
              final task = _filteredTasks[index];
              return AnimatedOpacity(
                opacity: task.isCompleted ? 0.6 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Checkbox(
                      value: task.isCompleted,
                      onChanged: (value) => _toggleTaskCompletion(task),
                    ),
                    title: Text(
                      task.title,
                      style: TextStyle(
                        decoration: task.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (task.dueDate != null)
                          Text(
                            'Due: ${DateFormat.yMMMd().format(task.dueDate!)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        Text(
                          'Priority: ${task.priority.toString().split('.').last}',
                          style: TextStyle(
                            fontSize: 12,
                            color: task.priority == TaskPriority.high
                                ? Colors.red
                                : task.priority == TaskPriority.medium
                                ? Colors.orange
                                : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.teal),
                          onPressed: () => _showTaskDialog(task: task),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteTask(task.id!),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTaskDialog(),
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _dbHelper.close();
    super.dispose();
  }
}