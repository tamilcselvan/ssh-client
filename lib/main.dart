import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:sqflite/sqflite.dart' hide Database;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart' as xml;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite_common_ffi for desktop platforms
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    ffi.sqfliteFfiInit();
    databaseFactory = ffi.databaseFactoryFfi;
  }

  final database = openDatabase(
    p.join(await getDatabasesPath(), 'ssh_config.db'),
    onCreate: (db, version) {
      return db.execute(
        "CREATE TABLE configs(id INTEGER PRIMARY KEY, siteName TEXT, hostname TEXT, username TEXT, port TEXT, usePassword INTEGER, password TEXT, keyPath TEXT, groupName TEXT, filename TEXT)",
      );
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute("ALTER TABLE configs ADD COLUMN filename TEXT");
      }
    },
    version: 2,
  );
  runApp(SSHConfigGeneratorApp(database: database));
}

class SSHConfigGeneratorApp extends StatefulWidget {
  final Future<Database> database;

  const SSHConfigGeneratorApp({super.key, required this.database});

  @override
  _SSHConfigGeneratorAppState createState() => _SSHConfigGeneratorAppState();
}

class _SSHConfigGeneratorAppState extends State<SSHConfigGeneratorApp> {
  Future<List<Map<String, dynamic>>> _listConfigs() async {
    final db = await widget.database;
    return db.query('configs');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SSH Config Generator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('SSH Config Generator'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'SSH Config Generator'),
                Tab(text: 'Sites'),
                Tab(text: 'Settings'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              SSHConfigGenerator(database: widget.database),
              SSHConfigList(database: widget.database),
              SettingsTab(database: widget.database),
            ],
          ),
        ),
      ),
    );
  }
}

class SSHConfigGenerator extends StatefulWidget {
  final Future<Database> database;

  const SSHConfigGenerator({super.key, required this.database});

  @override
  _SSHConfigGeneratorState createState() => _SSHConfigGeneratorState();
}

class _SSHConfigGeneratorState extends State<SSHConfigGenerator> {
  final TextEditingController siteNameController = TextEditingController();
  final TextEditingController hostnameController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController portController =
      TextEditingController(text: '22');
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController keyPathController = TextEditingController();
  final TextEditingController groupController = TextEditingController();

  bool usePassword = true;
  List<String> groupNames = [];
  int? editingId;
  late Future<List<Map<String, dynamic>>> _configs;

  @override
  void initState() {
    super.initState();
    _loadGroupNames();
    _configs = _listConfigs();
  }

  Future<void> _loadGroupNames() async {
    final db = await widget.database;
    final List<Map<String, dynamic>> configs = await db.query('configs');
    final Set<String> groups =
        configs.map((config) => config['groupName'] as String).toSet();
    setState(() {
      groupNames = groups.toList();
    });
  }

  Future<List<Map<String, dynamic>>> _listConfigs() async {
    final db = await widget.database;
    return db.query('configs');
  }

  @override
  void dispose() {
    siteNameController.dispose();
    hostnameController.dispose();
    usernameController.dispose();
    portController.dispose();
    passwordController.dispose();
    keyPathController.dispose();
    groupController.dispose();
    super.dispose();
  }

  Future<void> insertConfig(Map<String, dynamic> config) async {
    final db = await widget.database;
    try {
      await db.insert(
        'configs',
        config,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('Error inserting config: $e');
    }
  }

  Future<void> updateConfig(int id, Map<String, dynamic> config) async {
    final db = await widget.database;
    try {
      await db.update(
        'configs',
        config,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print('Error updating config: $e');
    }
  }

  Future<void> deleteConfig(int id) async {
    final db = await widget.database;
    try {
      await db.delete(
        'configs',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print('Error deleting config: $e');
    }
  }

  void generateScript() async {
    if (_validateInputs()) {
      String command;
      if (usePassword) {
        command =
            "sshpass -p '${passwordController.text}' ssh ${usernameController.text}@${hostnameController.text} -p ${portController.text} -o ServerAliveInterval=60 -o ServerAliveCountMax=60\n";
      } else {
        command =
            "ssh -i '${keyPathController.text}' ${usernameController.text}@${hostnameController.text} -p ${portController.text} -o ServerAliveInterval=60 -o ServerAliveCountMax=60\n";
      }

      String filename;
      if (groupController.text.isNotEmpty) {
        filename =
            "${groupController.text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}_${siteNameController.text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}.sh";
      } else {
        filename =
            "${siteNameController.text.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}_${Uuid().v4()}.sh";
      }

      // For simplicity, we'll just print the script for now
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Script Generated"),
          content: SelectableText("Filename: $filename\n\nCommand:\n$command"),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: command));
                Navigator.pop(context);
              },
              child: const Text("Copy"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );

      final config = {
        'siteName': siteNameController.text,
        'hostname': hostnameController.text,
        'username': usernameController.text,
        'port': portController.text,
        'usePassword': usePassword ? 1 : 0,
        'password': passwordController.text,
        'keyPath': keyPathController.text,
        'groupName': groupController.text,
        'filename': filename,
      };

      if (editingId != null) {
        await updateConfig(editingId!, config);
      } else {
        await insertConfig(config);
      }

      // Clear fields
      siteNameController.clear();
      hostnameController.clear();
      usernameController.clear();
      portController.text = '22';
      passwordController.clear();
      keyPathController.clear();
      groupController.clear();
      setState(() {
        usePassword = true;
        editingId = null;
      });

      // Get the current home directory
      final homeDir = Platform.environment['HOME'] ?? '/home/tamilselvan';

      // save to file to home directory (for now)
      // $homeDir/ACS/sites/filename.sh
      File file = File('$homeDir/ACS/sites/$filename');
      await file.writeAsString(command);

      // Set execute permission
      await Process.run('chmod', ['+x', file.path]);

      // Append to FileZilla config
      await _appendToFileZillaConfig(config);
    }
  }

  Future<void> _appendToFileZillaConfig(Map<String, dynamic> config) async {
    final homeDir = Platform.environment['HOME'] ?? '/home/tamilselvan';
    final filezillaConfigPath = '$homeDir/.config/filezilla/sitemanager.xml';
    final file = File(filezillaConfigPath);

    if (await file.exists()) {
      final document = xml.XmlDocument.parse(await file.readAsString());
      final serversNode = document.findAllElements('Servers').first;

      final serverNode = xml.XmlElement(xml.XmlName('Server'), [], [
        xml.XmlElement(
            xml.XmlName('Host'), [], [xml.XmlText(config['hostname'])]),
        xml.XmlElement(xml.XmlName('Port'), [], [xml.XmlText(config['port'])]),
        xml.XmlElement(xml.XmlName('Protocol'), [], [xml.XmlText('1')]),
        xml.XmlElement(xml.XmlName('Type'), [], [xml.XmlText('0')]),
        xml.XmlElement(
            xml.XmlName('User'), [], [xml.XmlText(config['username'])]),
        if (config['usePassword'] == 1)
          xml.XmlElement(
              xml.XmlName('Pass'), [], [xml.XmlText(config['password'])])
        else
          xml.XmlElement(
              xml.XmlName('Keyfile'), [], [xml.XmlText(config['keyPath'])]),
        xml.XmlElement(xml.XmlName('Logontype'), [],
            [xml.XmlText(config['usePassword'] == 1 ? '1' : '5')]),
        xml.XmlElement(xml.XmlName('EncodingType'), [], [xml.XmlText('Auto')]),
        xml.XmlElement(xml.XmlName('BypassProxy'), [], [xml.XmlText('0')]),
        xml.XmlElement(
            xml.XmlName('Name'), [], [xml.XmlText(config['siteName'])]),
        xml.XmlElement(xml.XmlName('SyncBrowsing'), [], [xml.XmlText('0')]),
        xml.XmlElement(
            xml.XmlName('DirectoryComparison'), [], [xml.XmlText('0')]),
      ]);

      if (config['groupName'].isNotEmpty) {
        final groupNode = serversNode.findElements('Folder').firstWhere(
          (folder) =>
              folder.getAttribute('expanded') == '1' &&
              folder.text.trim() == config['groupName'],
          orElse: () {
            final newGroupNode = xml.XmlElement(
                xml.XmlName('Folder'),
                [xml.XmlAttribute(xml.XmlName('expanded'), '1')],
                [xml.XmlText(config['groupName'])]);
            serversNode.children.add(newGroupNode);
            return newGroupNode;
          },
        );
        groupNode.children.add(serverNode);
      } else {
        serversNode.children.add(serverNode);
      }

      await file
          .writeAsString(document.toXmlString(pretty: true, indent: '  '));
    } else {
      print('FileZilla config file not found.');
    }
  }

  bool _validateInputs() {
    if (siteNameController.text.isEmpty ||
        hostnameController.text.isEmpty ||
        usernameController.text.isEmpty ||
        portController.text.isEmpty ||
        (usePassword && passwordController.text.isEmpty) ||
        (!usePassword && keyPathController.text.isEmpty)) {
      showDialog(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text("Error"),
          content: Text("Please fill in all required fields."),
          actions: [
            TextButton(
              onPressed: null,
              child: Text("OK"),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        keyPathController.text = result.files.single.path ?? '';
      });
    }
  }

  void _editConfig(Map<String, dynamic> config) {
    setState(() {
      editingId = config['id'];
      siteNameController.text = config['siteName'];
      hostnameController.text = config['hostname'];
      usernameController.text = config['username'];
      portController.text = config['port'];
      usePassword = config['usePassword'] == 1;
      passwordController.text = config['password'];
      keyPathController.text = config['keyPath'];
      groupController.text = config['groupName'];
    });
    DefaultTabController.of(context).animateTo(0);
  }

  void _confirmDeleteConfig(int id, String siteName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text(
            "Are you sure you want to delete the configuration for $siteName?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              await deleteConfig(id);
              Navigator.pop(context);
              setState(() {
                _configs = _listConfigs();
              });
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Config Generator'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField("Site Name", siteNameController),
            _buildTextField("Hostname", hostnameController),
            _buildTextField("Username", usernameController),
            _buildTextField("Port", portController,
                keyboardType: TextInputType.number),
            _buildGroupField("Group", groupController),
            const SizedBox(height: 10),
            Row(
              children: [
                Radio(
                  value: true,
                  groupValue: usePassword,
                  onChanged: (value) {
                    setState(() {
                      usePassword = value as bool;
                    });
                  },
                ),
                const Text("Password"),
                Radio(
                  value: false,
                  groupValue: usePassword,
                  onChanged: (value) {
                    setState(() {
                      usePassword = value as bool;
                    });
                  },
                ),
                const Text("Key File"),
              ],
            ),
            if (usePassword)
              _buildTextField("Password", passwordController, obscureText: true)
            else
              Row(
                children: [
                  Expanded(
                      child: _buildTextField("Key Path", keyPathController)),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _pickFile,
                    child: const Text("Browse"),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: generateScript,
                child: Text(editingId != null
                    ? "Update SSH Script"
                    : "Generate SSH Script"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {bool obscureText = false,
      TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildGroupField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8.0),
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<String>.empty();
              }
              return groupNames.where((String option) {
                return option.contains(textEditingValue.text.toLowerCase());
              });
            },
            onSelected: (String selection) {
              controller.text = selection;
            },
            fieldViewBuilder: (BuildContext context,
                TextEditingController fieldTextEditingController,
                FocusNode fieldFocusNode,
                VoidCallback onFieldSubmitted) {
              fieldTextEditingController.text = controller.text;
              return TextField(
                controller: fieldTextEditingController,
                focusNode: fieldFocusNode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                onChanged: (text) {
                  controller.text = text;
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class SSHConfigList extends StatefulWidget {
  final Future<Database> database;

  const SSHConfigList({super.key, required this.database});

  @override
  _SSHConfigListState createState() => _SSHConfigListState();
}

class _SSHConfigListState extends State<SSHConfigList> {
  late Future<List<Map<String, dynamic>>> _configs;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController hostnameController = TextEditingController();
  final TextEditingController siteNameController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController portController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController keyPathController = TextEditingController();
  final TextEditingController groupController = TextEditingController();
  String _searchText = '';
  int? editingId;
  bool usePassword = true;

  @override
  void initState() {
    super.initState();
    _configs = _listConfigs();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchText = _searchController.text;
      _configs = _listConfigs();
    });
  }

  Future<List<Map<String, dynamic>>> _listConfigs() async {
    final db = await widget.database;
    if (_searchText.isEmpty) {
      return db.query('configs');
    } else {
      return db.query(
        'configs',
        where:
            'siteName LIKE ? OR hostname LIKE ? OR username LIKE ? OR groupName LIKE ?',
        whereArgs: [
          '%$_searchText%',
          '%$_searchText%',
          '%$_searchText%',
          '%$_searchText%'
        ],
      );
    }
  }

  Future<void> _truncateTable() async {
    final db = await widget.database;
    await db.delete('configs');
    setState(() {
      _configs = _listConfigs();
    });
  }

  Future<void> _dropAndRecreateTable() async {
    final db = await widget.database;
    await db.execute("DROP TABLE IF EXISTS configs");
    await db.execute(
      "CREATE TABLE configs(id INTEGER PRIMARY KEY, siteName TEXT, hostname TEXT, username TEXT, port TEXT, usePassword INTEGER, password TEXT, keyPath TEXT, groupName TEXT, filename TEXT)",
    );
    setState(() {
      _configs = _listConfigs();
    });
  }

  Future<void> deleteConfig(int id) async {
    final db = await widget.database;
    try {
      await db.delete(
        'configs',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print('Error deleting config: $e');
    }
  }

  void _runScript(String filePath) async {
    ProcessResult result;
    if (Platform.isLinux) {
      result = await Process.run('x-terminal-emulator', ['-e', filePath]);
    } else if (Platform.isMacOS) {
      result = await Process.run(
          'osascript', ['-e', 'tell app "Terminal" to do script "$filePath"']);
    } else {
      result = ProcessResult(1, 1, '', 'Unsupported OS');
    }

    if (result.exitCode != 0) {
      // showDialog(
      //   context: context,
      //   builder: (context) => AlertDialog(
      //     title: const Text("Error"),
      //     content: Text("Failed to run script: ${result.stderr}"),
      //     actions: [
      //       TextButton(
      //         onPressed: () => Navigator.pop(context),
      //         child: const Text("OK"),
      //       ),
      //     ],
      //   ),
      // );
    }
  }

  void _confirmDeleteConfig(int id, String siteName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text(
            "Are you sure you want to delete the configuration for $siteName?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              await deleteConfig(id);
              Navigator.pop(context);
              setState(() {
                _configs = _listConfigs();
              });
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _editConfig(Map<String, dynamic> config) {
    setState(() {
      editingId = config['id'];
      siteNameController.text = config['siteName'];
      hostnameController.text = config['hostname'];
      usernameController.text = config['username'];
      portController.text = config['port'];
      usePassword = config['usePassword'] == 1;
      passwordController.text = config['password'];
      keyPathController.text = config['keyPath'];
      groupController.text = config['groupName'];
    });
    DefaultTabController.of(context).animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Container(
          alignment: Alignment.centerRight,
          margin: const EdgeInsets.all(8.0),
          child: ElevatedButton(
            onPressed: _truncateTable,
            child: const Text("Truncate Table"),
          ),
        ),
        // Container(
        //   alignment: Alignment.centerRight,
        //   margin: const EdgeInsets.all(8.0),
        //   child: ElevatedButton(
        //     onPressed: _dropAndRecreateTable,
        //     child: const Text("Drop and Recreate Table"),
        //   ),
        // ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _configs,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return const Center(child: Text('Error loading configs'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No SSH configs found'));
              } else {
                final groupedConfigs = <String, List<Map<String, dynamic>>>{};
                for (var config in snapshot.data!) {
                  final groupName = config['groupName'] ?? 'Ungrouped';
                  if (!groupedConfigs.containsKey(groupName)) {
                    groupedConfigs[groupName] = [];
                  }
                  groupedConfigs[groupName]!.add(config);
                }

                return ListView(
                  children: groupedConfigs.entries.map((entry) {
                    final groupName = entry.key;
                    final configs = entry.value;

                    return ExpansionTile(
                      title: Text(groupName),
                      children: configs.map((config) {
                        return ListTile(
                          title: Text(config['siteName'] ?? 'No Name'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Hostname: ${config['hostname'] ?? 'No Hostname'}'),
                              Text(
                                  'Username: ${config['username'] ?? 'No Username'}'),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () {
                                  final filePath =
                                      '${Platform.environment['HOME']}/ACS/sites/${config['filename']}';
                                  _runScript(filePath);
                                },
                                child: const Text("Connect"),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  _editConfig(config);
                                },
                                child: const Text("Edit"),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () {
                                  _confirmDeleteConfig(
                                      config['id'], config['siteName']);
                                },
                                child: const Text("Delete"),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  }).toList(),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

class SettingsTab extends StatelessWidget {
  final Future<Database> database;

  const SettingsTab({super.key, required this.database});

  Future<void> _exportToCSV() async {
    final db = await database;
    final List<Map<String, dynamic>> configs = await db.query('configs');

    List<List<dynamic>> rows = [
      [
        "id",
        "siteName",
        "hostname",
        "username",
        "port",
        "usePassword",
        "password",
        "keyPath",
        "groupName",
        "filename"
      ]
    ];

    for (var config in configs) {
      List<dynamic> row = [];
      row.add(config['id']);
      row.add(config['siteName']);
      row.add(config['hostname']);
      row.add(config['username']);
      row.add(config['port']);
      row.add(config['usePassword']);
      row.add(config['password']);
      row.add(config['keyPath']);
      row.add(config['groupName']);
      row.add(config['filename']);
      rows.add(row);
    }

    String csv = const ListToCsvConverter().convert(rows);
    final directory = await getApplicationDocumentsDirectory();
    final path = "${directory.path}/configs.csv";
    final file = File(path);
    await file.writeAsString(csv);

    // Show success message
    print("Exported to $path");
  }

  Future<void> _importFromCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      final csv = await file.readAsString();
      List<List<dynamic>> rows = const CsvToListConverter().convert(csv);

      final db = await database;
      await db.transaction((txn) async {
        for (int i = 1; i < rows.length; i++) {
          List<dynamic> row = rows[i];
          await txn.insert(
            'configs',
            {
              'id': row[0],
              'siteName': row[1],
              'hostname': row[2],
              'username': row[3],
              'port': row[4],
              'usePassword': row[5],
              'password': row[6],
              'keyPath': row[7],
              'groupName': row[8],
              'filename': row[9],
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      // Show success message
      print("Imported from CSV");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: _exportToCSV,
            child: const Text("Export to CSV"),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              if (Platform.isLinux) {
                // Use FilePicker for Linux
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.any,
                  allowedExtensions: ['csv'],
                );

                if (result != null) {
                  final file = File(result.files.single.path!);
                  final csv = await file.readAsString();
                  List<List<dynamic>> rows =
                      const CsvToListConverter().convert(csv);

                  final db = await database;
                  await db.transaction((txn) async {
                    for (int i = 1; i < rows.length; i++) {
                      List<dynamic> row = rows[i];
                      await txn.insert(
                        'configs',
                        {
                          'id': row[0],
                          'siteName': row[1],
                          'hostname': row[2],
                          'username': row[3],
                          'port': row[4],
                          'usePassword': row[5],
                          'password': row[6],
                          'keyPath': row[7],
                          'groupName': row[8],
                          'filename': row[9],
                        },
                        conflictAlgorithm: ConflictAlgorithm.replace,
                      );
                    }
                  });

                  // Show success message
                  print("Imported from CSV");
                }
              } else {
                // Use FilePicker for other platforms
                await _importFromCSV();
              }
            },
            child: const Text("Import from CSV"),
          ),
        ],
      ),
    );
  }
}
