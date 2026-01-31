import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

// --- CONFIG PATH PINTAR ---
String get rootPath {
  if (Platform.isAndroid) {
    return '/storage/emulated/0/MilkyNote_Sync';
  } else if (Platform.isWindows) {
    final userProfile = Platform.environment['USERPROFILE'];
    return '$userProfile\\Documents\\Note';
  } else {
    final home = Platform.environment['HOME'];
    return '$home/Documents/Note';
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MilkyNote Ultimate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
        fontFamily: 'Monospace',
      ),
      home: const HalamanUtama(),
    );
  }
}

class HalamanUtama extends StatefulWidget {
  const HalamanUtama({super.key});

  @override
  State<HalamanUtama> createState() => _HalamanUtamaState();
}

class _HalamanUtamaState extends State<HalamanUtama>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _textController = TextEditingController();

  String currentPath = "";
  List<FileSystemEntity> sidebarFiles = [];
  File? activeFile;

  bool _hasUnsavedChanges = false;
  String _originalContent = "";
  int _jumlahKata = 0;
  int _jumlahKarakter = 0;

  bool _showDesktopSidebar = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _textController.addListener(() {
      _hitungStatistik();
      _cekPerubahan();
    });
    currentPath = rootPath;
    _inisialisasiAwal();
  }

  void _hitungStatistik() {
    String teks = _textController.text;
    setState(() {
      _jumlahKarakter = teks.length;
      if (teks.trim().isEmpty) {
        _jumlahKata = 0;
      } else {
        _jumlahKata = teks.trim().split(RegExp(r'\s+')).length;
      }
    });
  }

  void _cekPerubahan() {
    bool beda = _textController.text != _originalContent;
    if (beda != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = beda;
      });
    }
  }

  Future<void> _inisialisasiAwal() async {
    if (Platform.isAndroid) {
      if (await Permission.storage.status.isDenied) {
        await Permission.storage.request();
      }
      if (await Permission.manageExternalStorage.status.isDenied) {
        await Permission.manageExternalStorage.request();
      }
    }

    final path = rootPath;
    setState(() {
      currentPath = path;
    });

    final dir = Directory(path);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        debugPrint("Gagal buat folder: $e");
      }
    }
    _bacaFolder(path);
  }

  Future<void> _bacaFolder(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        return;
      }

      List<FileSystemEntity> entities = dir.listSync();

      entities.sort((a, b) {
        bool aIsDir = FileSystemEntity.isDirectorySync(a.path);
        bool bIsDir = FileSystemEntity.isDirectorySync(b.path);
        if (aIsDir && !bIsDir) {
          return -1;
        }
        if (!aIsDir && bIsDir) {
          return 1;
        }
        return a.path.compareTo(b.path);
      });

      setState(() {
        currentPath = folderPath;
        sidebarFiles = entities;
      });
    } catch (e) {
      debugPrint("Gagal baca folder: $e");
    }
  }

  void _onItemClicked(FileSystemEntity entity) async {
    if (FileSystemEntity.isDirectorySync(entity.path)) {
      _bacaFolder(entity.path);
    } else {
      File file = File(entity.path);
      if (file.path.endsWith('.md') || file.path.endsWith('.txt')) {
        String isi = await file.readAsString();

        if (!mounted) {
          return;
        }
        setState(() {
          activeFile = file;
          _textController.text = isi;
          _originalContent = isi;
          _hasUnsavedChanges = false;
        });

        bool isMobile = MediaQuery.of(context).size.width < 700;
        if (Platform.isAndroid || isMobile) {
          if (Scaffold.of(context).isDrawerOpen) {
            Navigator.pop(context);
          }
        }
      }
    }
  }

  void _goBack() {
    if (currentPath == rootPath) {
      return;
    }
    final parentDir = Directory(currentPath).parent;
    _bacaFolder(parentDir.path);
  }

  Future<void> _simpanFile() async {
    if (activeFile == null) {
      _tampilkanDialogBaru(isFolder: false);
      return;
    }

    setState(() => _isLoading = true);

    await activeFile!.writeAsString(_textController.text);

    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _originalContent = _textController.text;
      _hasUnsavedChanges = false;
    });

    _bacaFolder(currentPath);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tersimpan! (Ctrl+S)'),
        duration: Duration(milliseconds: 800),
      ),
    );
  }

  // --- PDF ENGINE ---
  Future<pw.Font> _loadFont() async {
    try {
      final fontData = await rootBundle.load(
        "assets/fonts/SpecialElite-Regular.ttf",
      );
      return pw.Font.ttf(fontData);
    } catch (e) {
      return pw.Font.courier();
    }
  }

  Future<void> _exportSinglePdf() async {
    if (_textController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Naskah kosong!")));
      return;
    }

    setState(() => _isLoading = true);

    final ttf = await _loadFont();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: ttf),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              activeFile?.path.split(Platform.pathSeparator).last ?? "Dokumen",
            ),
          ),
          pw.Paragraph(text: _textController.text),
        ],
      ),
    );
    await _prosesSimpanPdf(
      pdf,
      activeFile?.path.split(Platform.pathSeparator).last ?? 'doc.pdf',
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportProjectPdf() async {
    setState(() => _isLoading = true);

    List<File> babNaskah = _scanFolderAman(Directory(currentPath));
    babNaskah.sort((a, b) => a.path.compareTo(b.path));

    if (babNaskah.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada naskah .md/.txt!")),
      );
      return;
    }

    final ttf = await _loadFont();
    final pdf = pw.Document();
    String judulProject = currentPath
        .split(Platform.pathSeparator)
        .last
        .toUpperCase();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: ttf),
        build: (context) {
          List<pw.Widget> content = [];

          content.add(
            pw.Center(
              child: pw.Text(
                judulProject,
                style: pw.TextStyle(
                  fontSize: 40,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          );
          content.add(pw.SizedBox(height: 100));
          content.add(
            pw.Center(
              child: pw.Text(
                "Total Bab: ${babNaskah.length}",
                style: const pw.TextStyle(fontSize: 18, color: PdfColors.grey),
              ),
            ),
          );
          content.add(pw.NewPage());

          for (var file in babNaskah) {
            String namaBab = file.path
                .split(Platform.pathSeparator)
                .last
                .replaceAll('.md', '');
            try {
              String isiBab = file.readAsStringSync();
              content.add(
                pw.Header(
                  level: 1,
                  child: pw.Text(
                    namaBab,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              );
              content.add(pw.SizedBox(height: 10));
              content.add(pw.Paragraph(text: isiBab));
              content.add(pw.NewPage());
            } catch (e) {
              debugPrint("Error: $e");
            }
          }
          return content;
        },
      ),
    );
    await _prosesSimpanPdf(pdf, '${judulProject}_FULL.pdf');

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  List<File> _scanFolderAman(Directory dir) {
    List<File> files = [];
    try {
      List<FileSystemEntity> entities = dir.listSync(recursive: false);
      for (var entity in entities) {
        if (entity.path.split(Platform.pathSeparator).last.startsWith('.')) {
          continue;
        }

        if (entity is File) {
          if (entity.path.endsWith('.md') || entity.path.endsWith('.txt')) {
            files.add(entity);
          }
        } else if (entity is Directory) {
          files.addAll(_scanFolderAman(entity));
        }
      }
    } catch (e) {
      debugPrint("Skip folder: ${dir.path}");
    }
    return files;
  }

  Future<void> _prosesSimpanPdf(pw.Document pdf, String namaDefault) async {
    String? outputFile;
    String cleanName = namaDefault.replaceAll('.md', '.pdf');

    if (Platform.isAndroid) {
      final path = '$rootPath/$cleanName';
      final file = File(path);
      await file.writeAsBytes(await pdf.save());
      outputFile = path;
    } else {
      outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export PDF',
        fileName: cleanName,
        allowedExtensions: ['pdf'],
        type: FileType.custom,
      );
      if (outputFile != null) {
        if (!outputFile.endsWith('.pdf')) {
          outputFile += '.pdf';
        }
        final file = File(outputFile);
        await file.writeAsBytes(await pdf.save());
      }
    }

    if (outputFile != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF Disimpan: $outputFile'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // --- UI ---
  void _tampilkanDialogBaru({required bool isFolder}) {
    TextEditingController c = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isFolder ? "Folder Baru" : "File Baru"),
        content: TextField(
          controller: c,
          decoration: InputDecoration(hintText: "Nama..."),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (c.text.isEmpty) {
                return;
              }
              String p = '$currentPath/${c.text}';
              if (!isFolder && !p.endsWith('.md')) {
                p += '.md';
              }
              isFolder
                  ? await Directory(p).create()
                  : await File(p).writeAsString("");
              _bacaFolder(currentPath);
              if (!isFolder && mounted) {
                setState(() {
                  activeFile = File(p);
                  _textController.text = "";
                });
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text("Buat"),
          ),
        ],
      ),
    );
  }

  void _renameItem(FileSystemEntity item) {
    String oldName = item.path.split(Platform.pathSeparator).last;
    TextEditingController c = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Ganti Nama"),
        content: TextField(controller: c),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () async {
              String newName = c.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                String newPath = '${item.parent.path}/$newName';
                await item.rename(newPath);
                if (activeFile?.path == item.path && mounted) {
                  setState(() => activeFile = File(newPath));
                }
                _bacaFolder(currentPath);
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  void _deleteItem(FileSystemEntity item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus?"),
        content: Text(
          "Yakin hapus '${item.path.split(Platform.pathSeparator).last}'?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await item.delete(recursive: true);
                if (activeFile?.path == item.path && mounted) {
                  setState(() {
                    activeFile = null;
                    _textController.clear();
                  });
                }
                _bacaFolder(currentPath);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (e) {
                debugPrint("Error: $e");
              }
            },
            child: const Text("Hapus"),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: Colors.grey[100],
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blueGrey[50],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: const Icon(Icons.create_new_folder),
                  onPressed: () => _tampilkanDialogBaru(isFolder: true),
                ),
                IconButton(
                  icon: const Icon(Icons.note_add),
                  onPressed: () => _tampilkanDialogBaru(isFolder: false),
                ),
              ],
            ),
          ),
          if (currentPath != rootPath)
            ListTile(
              leading: const Icon(Icons.arrow_back),
              title: const Text("Kembali.."),
              onTap: _goBack,
              tileColor: Colors.grey[200],
            ),
          Expanded(
            child: ListView.builder(
              itemCount: sidebarFiles.length,
              itemBuilder: (context, index) {
                final item = sidebarFiles[index];
                final name = item.path.split(Platform.pathSeparator).last;
                if (name.startsWith('.')) {
                  return const SizedBox.shrink();
                }

                bool isDir = FileSystemEntity.isDirectorySync(item.path);
                return ListTile(
                  leading: Icon(
                    isDir ? Icons.folder : Icons.description,
                    color: isDir ? Colors.amber : Colors.grey,
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: activeFile?.path == item.path,
                  onTap: () => _onItemClicked(item),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (val) {
                      if (val == 'rename') {
                        _renameItem(item);
                      }
                      if (val == 'delete') {
                        _deleteItem(item);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text("Ganti Nama"),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          "Hapus",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorArea() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.blueGrey,
            tabs: const [
              Tab(text: "Editor"),
              Tab(text: "Preview"),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: "Mulai menulis...",
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MarkdownBody(data: _textController.text),
              ),
            ],
          ),
        ),
        Container(
          height: 35,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$_jumlahKata KATA  •  $_jumlahKarakter KARAKTER",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                "V4.5 FINAL",
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isMobile = MediaQuery.of(context).size.width < 700;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _simpanFile,
      },
      child: Scaffold(
        appBar: AppBar(
          leading: isMobile
              ? null
              : IconButton(
                  icon: Icon(
                    _showDesktopSidebar ? Icons.menu_open : Icons.menu,
                  ),
                  onPressed: () => setState(
                    () => _showDesktopSidebar = !_showDesktopSidebar,
                  ),
                  tooltip: "Toggle Sidebar",
                ),
          title: Text(
            activeFile?.path.split(Platform.pathSeparator).last ?? "MilkyNote",
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.picture_as_pdf),
              onSelected: (val) {
                if (val == 'single') {
                  _exportSinglePdf();
                }
                if (val == 'project') {
                  _exportProjectPdf();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'single',
                  child: Text("Export File Ini"),
                ),
                const PopupMenuItem(
                  value: 'project',
                  child: Text("Export Full Folder (Buku)"),
                ),
              ],
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: Icon(
                Icons.save,
                color: _hasUnsavedChanges ? Colors.amber[900] : Colors.black87,
              ),
              onPressed: _simpanFile,
            ),
          ],
        ),

        drawer: isMobile ? Drawer(child: _buildSidebar()) : null,

        body: Stack(
          children: [
            Row(
              children: [
                if (!isMobile && _showDesktopSidebar) _buildSidebar(),
                if (!isMobile && _showDesktopSidebar)
                  VerticalDivider(width: 1, color: Colors.grey[300]),
                Expanded(child: _buildEditorArea()),
              ],
            ),
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 20),
                      Text(
                        "Sedang Memproses PDF...",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
