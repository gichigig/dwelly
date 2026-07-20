import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:image_cropper/image_cropper.dart';

import '../services/native_app_picker.dart';

class WhatsappGallerySheet extends StatefulWidget {
  const WhatsappGallerySheet({super.key});

  @override
  State<WhatsappGallerySheet> createState() => _WhatsappGallerySheetState();
}

class _WhatsappGallerySheetState extends State<WhatsappGallerySheet> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _currentAlbum;
  List<AssetEntity> _assets = [];
  List<Map<String, dynamic>> _nativeApps = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  
  AssetEntity? _selectedAsset;
  final TextEditingController _captionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestPermissionAndFetch();
    _fetchNativeApps();
  }

  Future<void> _fetchNativeApps() async {
    final apps = await NativeAppPicker.getApps();
    if (mounted) {
      setState(() {
        _nativeApps = apps;
      });
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissionAndFetch() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps == PermissionState.limited) {
      setState(() {
        _hasPermission = true;
      });
      await _fetchMedia();
    } else {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
      PhotoManager.openSetting();
    }
  }

  Future<void> _fetchMedia() async {
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      hasAll: true,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(
            type: OrderOptionType.createDate,
            asc: false,
          ),
        ],
      ),
    );
    
    if (albums.isNotEmpty) {
      // The first album when hasAll: true is the aggregate of all images.
      // We can explicitly name it "Recents" in the UI by modifying how we display it.
      setState(() {
        _albums = albums;
        _currentAlbum = albums[0];
      });
      await _loadAssetsForCurrentAlbum();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAssetsForCurrentAlbum() async {
    if (_currentAlbum == null) return;
    setState(() => _isLoading = true);
    
    final List<AssetEntity> assets = await _currentAlbum!.getAssetListPaged(
      page: 0,
      size: 80,
    );
    
    setState(() {
      _assets = assets;
      _isLoading = false;
    });
  }

  Widget _buildAlbumTile(AssetPathEntity album) {
    return ListTile(
      onTap: () => Navigator.pop(context, album),
      leading: FutureBuilder<List<AssetEntity>>(
        future: album.getAssetListRange(start: 0, end: 1),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: AssetEntityImage(
                  snapshot.data![0],
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(100),
                  fit: BoxFit.cover,
                ),
              ),
            );
          }
          return Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.folder, color: Colors.white54),
          );
        },
      ),
      title: Text(album.isAll ? 'Recents' : album.name, style: const TextStyle(color: Colors.white)),
      subtitle: FutureBuilder<int>(
        future: album.assetCountAsync,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Text('${snapshot.data} items', style: const TextStyle(color: Colors.white54));
          }
          return const Text('Loading...', style: TextStyle(color: Colors.white54));
        },
      ),
      trailing: _currentAlbum == album ? const Icon(Icons.check, color: Colors.green) : null,
    );
  }

  Future<void> _showAlbumSelector() async {
    if (_albums.isEmpty) return;

    final selected = await showDialog<dynamic>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Select Album',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _albums.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildAlbumTile(_albums[0]);
                    }
                    
                    if (index == 1) {
                      if (_nativeApps.isEmpty) return const SizedBox.shrink();
                      return ListTile(
                        onTap: () => Navigator.pop(context, 'open_more_apps'),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.apps, color: Colors.white),
                        ),
                        title: const Text('More apps', style: TextStyle(color: Colors.white)),
                        subtitle: const Text('Google Photos, Drive, etc.', style: TextStyle(color: Colors.white54)),
                      );
                    }

                    if (index <= _albums.length) {
                      return _buildAlbumTile(_albums[index - 1]);
                    }

                    return ListTile(
                      onTap: () => Navigator.pop(context, 'see_more'),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.folder_open, color: Colors.white),
                      ),
                      title: const Text('Browse system', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Open system file picker', style: TextStyle(color: Colors.white54)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      if (selected == 'see_more') {
        Navigator.pop(context, {'action': 'see_more'});
      } else if (selected == 'open_more_apps') {
        await _showMoreAppsSelector();
      } else if (selected is Map) {
        Navigator.pop(context, selected);
      } else if (selected is AssetPathEntity && selected != _currentAlbum) {
        setState(() {
          _currentAlbum = selected;
        });
        await _loadAssetsForCurrentAlbum();
      }
    }
  }

  Future<void> _showMoreAppsSelector() async {
    final selected = await showDialog<dynamic>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'More Apps',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _nativeApps.length,
                  itemBuilder: (context, index) {
                    final app = _nativeApps[index];
                    return ListTile(
                      onTap: () => Navigator.pop(context, {'type': 'native_app', 'packageName': app['packageName'], 'className': app['className']}),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Image.memory(
                            base64Decode(app['icon'].replaceAll(RegExp(r'\s+'), '')),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      title: Text(app['name'], style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null && selected is Map) {
      Navigator.pop(context, selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Drag Handle & Header
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white, size: 28),
                    ),
                    GestureDetector(
                      onTap: _showAlbumSelector,
                      child: Row(
                        children: [
                          Text(
                            (_currentAlbum != null && _currentAlbum!.isAll) ? 'Recents' : (_currentAlbum?.name ?? 'Recents'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Colors.white),
                        ],
                      ),
                    ),
                    const SizedBox(width: 28),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              
              // Grid Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : !_hasPermission
                        ? const Center(
                            child: Text('Permission Denied', style: TextStyle(color: Colors.white)))
                        : GridView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.all(2),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                            itemCount: _assets.length,
                            itemBuilder: (context, index) {
                              final asset = _assets[index];
                              final isSelected = _selectedAsset == asset;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedAsset = null;
                                    } else {
                                      _selectedAsset = asset;
                                    }
                                  });
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    AssetEntityImage(
                                      asset,
                                      isOriginal: false,
                                      thumbnailSize: const ThumbnailSize.square(200),
                                      fit: BoxFit.cover,
                                    ),
                                    if (isSelected)
                                      Container(
                                        color: Colors.black.withOpacity(0.5),
                                        child: const Center(
                                          child: Icon(Icons.check_circle, color: Colors.green, size: 36),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              
              // Bottom Action Bar
              if (_selectedAsset != null)
                Container(
                  color: const Color(0xFF2B2B2B),
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final file = await _selectedAsset!.file;
                          if (file == null) return;
                          final croppedFile = await ImageCropper().cropImage(
                            sourcePath: file.path,
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
                            Navigator.pop(context, {
                              'file': File(croppedFile.path),
                              'caption': _captionController.text,
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
                            hintStyle: TextStyle(color: Colors.white54),
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
                        onTap: () async {
                          final file = await _selectedAsset!.file;
                          if (file != null) {
                            Navigator.pop(context, {
                              'file': file,
                              'caption': _captionController.text,
                            });
                          }
                        },
                        child: CircleAvatar(
                          backgroundColor: const Color(0xFF00A884),
                          radius: 24,
                          child: const Icon(Icons.send, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
