import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:scribble/scribble.dart';
import 'package:path/path.dart' as p;

class HalamanCanvas extends StatefulWidget {
  final String rootPath;
  final String? fileToEditBaseName;
  final bool isStandalone;

  const HalamanCanvas({
    super.key,
    required this.rootPath,
    this.fileToEditBaseName,
    this.isStandalone = false,
  });

  @override
  State<HalamanCanvas> createState() => _HalamanCanvasState();
}

class _HalamanCanvasState extends State<HalamanCanvas> {
  late ScribbleNotifier notifier;
  bool _isLoaded = false;

  // STATE MANUAL
  bool _isPanningMode = false;
  bool _isEraser = false;
  double _strokeWidth = 5.0; // Default ketebalan

  final TransformationController _transformationController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    notifier = ScribbleNotifier();
    _loadExistingData();
  }

  Future<void> _loadExistingData() async {
    if (widget.fileToEditBaseName == null) {
      setState(() => _isLoaded = true);
      return;
    }

    try {
      String filePath;
      if (widget.isStandalone) {
        filePath = p.join(widget.rootPath, '${widget.fileToEditBaseName}.draw');
      } else {
        filePath = p.join(
          widget.rootPath,
          'assets_gambar',
          '${widget.fileToEditBaseName}.json',
        );
      }

      final file = File(filePath);
      if (await file.exists()) {
        String jsonString = await file.readAsString();
        Map<String, dynamic> jsonData = jsonDecode(jsonString);
        notifier.setSketch(sketch: Sketch.fromJson(jsonData));
      }
    } catch (e) {
      debugPrint("Gagal memuat: $e");
    } finally {
      setState(() => _isLoaded = true);
    }
  }

  Future<void> _simpanGambar(BuildContext context) async {
    try {
      final sketchData = notifier.currentSketch;
      String jsonString = jsonEncode(sketchData.toJson());

      String baseName =
          widget.fileToEditBaseName ??
          'canvas_${DateTime.now().millisecondsSinceEpoch}';

      if (widget.isStandalone) {
        final savePath = p.join(widget.rootPath, '$baseName.draw');
        await File(savePath).writeAsString(jsonString);

        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Kanvas Tersimpan!')));
      } else {
        final ByteData imageBytes = await notifier.renderImage();
        final Uint8List pngBytes = imageBytes.buffer.asUint8List();

        final imagesDir = Directory(p.join(widget.rootPath, 'assets_gambar'));
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }

        await File(
          p.join(imagesDir.path, '$baseName.png'),
        ).writeAsBytes(pngBytes);
        await File(
          p.join(imagesDir.path, '$baseName.json'),
        ).writeAsString(jsonString);

        if (!context.mounted) return;
        final markdownCode = '![](assets_gambar/$baseName.png)';
        Navigator.pop(context, markdownCode);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal simpan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isStandalone ? "Kanvas Vektor" : "Edit Gambar"),
        actions: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isPanningMode ? Colors.orange[100] : Colors.blue[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _isPanningMode ? "Mode: GESER ✋" : "Mode: GAMBAR ✏️",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => notifier.clear(),
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () => _simpanGambar(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                // BARIS 1: ALAT & WARNA
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildToolButton(
                        icon: Icons.pan_tool,
                        isActive: _isPanningMode,
                        onTap: () {
                          setState(() => _isPanningMode = true);
                        },
                        tooltip: "Geser Layar",
                      ),
                      const VerticalDivider(),
                      _buildToolButton(
                        icon: Icons.edit,
                        isActive: !_isPanningMode && !_isEraser,
                        onTap: () {
                          setState(() {
                            _isPanningMode = false;
                            _isEraser = false;
                          });
                          notifier.setColor(Colors.black);
                        },
                        tooltip: "Pen",
                      ),
                      _buildToolButton(
                        icon: Icons.cleaning_services,
                        isActive: !_isPanningMode && _isEraser,
                        onTap: () {
                          setState(() {
                            _isPanningMode = false;
                            _isEraser = true;
                          });
                          notifier.setEraser();
                        },
                        tooltip: "Penghapus",
                      ),
                      const VerticalDivider(),
                      _buildColorDot(Colors.black),
                      _buildColorDot(Colors.red),
                      _buildColorDot(Colors.blue),
                      _buildColorDot(Colors.green),
                    ],
                  ),
                ),

                // BARIS 2: SLIDER UKURAN (TEBAL / TIPIS)
                if (!_isPanningMode) // Sembunyikan kalau lagi mode geser
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 8, color: Colors.grey),
                        Expanded(
                          child: Slider(
                            value: _strokeWidth,
                            min: 1.0,
                            max: 50.0, // Bisa tebal banget sampai 50
                            activeColor: Colors.blueGrey,
                            onChanged: (val) {
                              setState(() {
                                _strokeWidth = val;
                              });
                              // Update ukuran Pen atau Eraser
                              notifier.setStrokeWidth(val);
                            },
                          ),
                        ),
                        const Icon(Icons.circle, size: 20, color: Colors.grey),
                        Text(
                          "${_strokeWidth.toInt()}px",
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // AREA KANVAS
          Expanded(
            child: InteractiveViewer(
              transformationController: _transformationController,
              panEnabled: _isPanningMode,
              scaleEnabled: _isPanningMode,
              minScale: 0.05,
              maxScale: 5.0,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              constrained: false,
              child: SizedBox(
                width: 9000,
                height: 9000,
                child: Stack(
                  children: [
                    Container(color: Colors.white, width: 9000, height: 9000),
                    GridPaper(
                      color: Colors.blueGrey.withValues(alpha: 0.1),
                      interval: 100,
                    ),
                    AbsorbPointer(
                      absorbing: _isPanningMode,
                      child: Scribble(notifier: notifier, drawPen: true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.blueGrey : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isActive ? null : Border.all(color: Colors.grey),
      ),
      child: IconButton(
        icon: Icon(icon, color: isActive ? Colors.white : Colors.black87),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildColorDot(Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isPanningMode = false;
            _isEraser = false;
          });
          notifier.setColor(color);
        },
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey),
          ),
        ),
      ),
    );
  }
}
