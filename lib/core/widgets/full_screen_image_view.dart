import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class FullScreenImageView extends StatelessWidget {
  final String imageUrl;

  const FullScreenImageView({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.1,
          maxScale: 4.0,
          child: Hero(
            tag: imageUrl,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              placeholder: (context, url) =>
                  const DwellyOrbitingLoader(glowColor: Colors.white),
              errorWidget: (context, url, error) =>
                  const Icon(Icons.error, color: Colors.white, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}
