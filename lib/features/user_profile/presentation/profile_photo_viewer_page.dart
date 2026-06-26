import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';

class ProfilePhotoViewerPage extends StatefulWidget {
  final String imageUrl;
  final String tag;

  const ProfilePhotoViewerPage({
    Key? key,
    required this.imageUrl,
    required this.tag,
  }) : super(key: key);

  @override
  State<ProfilePhotoViewerPage> createState() => _ProfilePhotoViewerPageState();
}

class _ProfilePhotoViewerPageState extends State<ProfilePhotoViewerPage> {
  @override
  void initState() {
    super.initState();
    _preventScreenshots();
  }

  Future<void> _preventScreenshots() async {
    await ScreenProtector.preventScreenshotOn();
    await ScreenProtector.protectDataLeakageWithColor(Colors.black);
  }

  @override
  void dispose() {
    ScreenProtector.preventScreenshotOff();
    ScreenProtector.protectDataLeakageWithColorOff();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Hero(
            tag: widget.tag,
            child: Image.network(
              widget.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.error, color: Colors.white, size: 50),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
