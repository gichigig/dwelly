import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

class FilePreviewSheet extends StatefulWidget {
  final File file;

  const FilePreviewSheet({super.key, required this.file});

  @override
  State<FilePreviewSheet> createState() => _FilePreviewSheetState();
}

class _FilePreviewSheetState extends State<FilePreviewSheet> {
  final TextEditingController _captionController = TextEditingController();
  late File _currentFile;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.file;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Image Preview
            Center(
              child: InteractiveViewer(
                child: Image.file(_currentFile, fit: BoxFit.contain),
              ),
            ),
            
            // Top Bar
            Positioned(
              top: 16,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),

            // Bottom Action Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: const Color(0xFF2B2B2B),
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final croppedFile = await ImageCropper().cropImage(
                          sourcePath: _currentFile.path,
                          uiSettings: [
                            AndroidUiSettings(
                              toolbarTitle: 'Edit Photo',
                              toolbarColor: Colors.black,
                              toolbarWidgetColor: Colors.white,
                              initAspectRatio: CropAspectRatioPreset.original,
                              lockAspectRatio: false,
                            ),
                            IOSUiSettings(title: 'Edit Photo'),
                          ],
                        );
                        if (croppedFile != null) {
                          setState(() {
                            _currentFile = File(croppedFile.path);
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.edit, color: Colors.white, size: 24),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Add a caption...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.grey[800],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        maxLines: 4,
                        minLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context, {
                          'file': _currentFile,
                          'caption': _captionController.text,
                        });
                      },
                      child: const CircleAvatar(
                        backgroundColor: Color(0xFF00A884),
                        radius: 24,
                        child: Icon(Icons.send, color: Colors.white),
                      ),
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
