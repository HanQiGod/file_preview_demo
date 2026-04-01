import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';
import 'package:mini_pdf_epub_viewer/mini_pdf_epub_viewer.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view.dart';
import 'package:universal_file_viewer/universal_file_viewer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FilePreviewDemoApp());
}

class FilePreviewDemoApp extends StatelessWidget {
  const FilePreviewDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'File Preview Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF6F1E8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const FilePreviewDemoPage(),
    );
  }
}

enum PreviewStrategy { universal, composable }

enum PreviewKind { image, pdf, text, markdown, csv, office, video, unsupported }

const String kSamplePdfUrl = 'https://pdfobject.com/pdf/sample.pdf';

class FilePreviewDemoPage extends StatefulWidget {
  const FilePreviewDemoPage({super.key});

  @override
  State<FilePreviewDemoPage> createState() => _FilePreviewDemoPageState();
}

class _FilePreviewDemoPageState extends State<FilePreviewDemoPage> {
  final DemoSeedRepository _demoSeedRepository = DemoSeedRepository();
  final TextEditingController _remoteUrlController = TextEditingController(
    text: kSamplePdfUrl,
  );

  PreviewStrategy _strategy = PreviewStrategy.universal;
  DemoSeedFiles? _demoSeedFiles;
  PreviewSelection? _selection;
  Map<String, PermissionStatus> _androidPermissionStates = const {};
  bool _isPreparing = true;
  bool _isPicking = false;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _bootstrapDemo();
  }

  @override
  void dispose() {
    _remoteUrlController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapDemo() async {
    try {
      final demoSeedFiles = await _demoSeedRepository.prepare();
      final permissionStates = await _loadAndroidPermissionStates();
      if (!mounted) {
        return;
      }

      setState(() {
        _demoSeedFiles = demoSeedFiles;
        _selection = PreviewSelection.local(
          title: '演示图片',
          source: demoSeedFiles.imagePath,
          description: '运行时生成的本地 PNG，用来测试图片预览与手势缩放。',
        );
        _androidPermissionStates = permissionStates;
        _isPreparing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isPreparing = false;
      });
      _showMessage('初始化演示文件失败：$error');
    }
  }

  List<PreviewSelection> get _presetSelections {
    final demoSeedFiles = _demoSeedFiles;
    if (demoSeedFiles == null) {
      return const [];
    }

    return [
      PreviewSelection.local(
        title: '演示图片',
        source: demoSeedFiles.imagePath,
        description: '本地 PNG 文件，适合测试图片缩放和清晰度。',
      ),
      PreviewSelection.local(
        title: '演示 Markdown',
        source: demoSeedFiles.markdownPath,
        description: '本地 Markdown 文件，用来展示长文档滚动和文本预览。',
      ),
      PreviewSelection.local(
        title: '演示 CSV',
        source: demoSeedFiles.csvPath,
        description: '本地 CSV 文件，组合方案会把它渲染成表格。',
      ),
      PreviewSelection.local(
        title: '演示 TXT',
        source: demoSeedFiles.textPath,
        description: '本地纯文本文件，适合最轻量的内容预览。',
      ),
      PreviewSelection.remote(
        title: '远程 PDF',
        source: kSamplePdfUrl,
        description: '公开 PDF 示例地址，可直接测试远程文档预览。',
      ),
    ];
  }

  Future<Map<String, PermissionStatus>> _loadAndroidPermissionStates() async {
    if (!Platform.isAndroid) {
      return const {};
    }

    return {
      'storage': await Permission.storage.status,
      'photos': await Permission.photos.status,
      'videos': await Permission.videos.status,
      'audio': await Permission.audio.status,
    };
  }

  Future<void> _requestAndroidPermissions() async {
    if (!Platform.isAndroid) {
      _showMessage('当前平台通常通过系统文档选择器即可读取文件，无需额外申请存储权限。');
      return;
    }

    setState(() {
      _isRequestingPermission = true;
    });

    try {
      final results = await <Permission>[
        Permission.storage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();

      if (!mounted) {
        return;
      }

      setState(() {
        _androidPermissionStates = {
          'storage': results[Permission.storage] ?? PermissionStatus.denied,
          'photos': results[Permission.photos] ?? PermissionStatus.denied,
          'videos': results[Permission.videos] ?? PermissionStatus.denied,
          'audio': results[Permission.audio] ?? PermissionStatus.denied,
        };
      });

      final statuses = results.values.toList();
      final hasGrant = statuses.any(
        (status) => status.isGranted || status.isLimited,
      );
      final hasPermanentlyDenied = statuses.any(
        (status) => status.isPermanentlyDenied,
      );

      if (hasGrant) {
        _showMessage('已完成权限申请。系统文件选择器通常也可以在未授权时继续工作。');
      } else if (hasPermanentlyDenied) {
        _showMessage('权限被永久拒绝，可前往系统设置手动开启。');
      } else {
        _showMessage('权限未授予。你仍然可以尝试使用系统文件选择器选取文档。');
      }

      final refreshed = await _loadAndroidPermissionStates();
      if (!mounted) {
        return;
      }
      setState(() {
        _androidPermissionStates = refreshed;
      });
    } catch (error) {
      _showMessage('权限申请失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingPermission = false;
        });
      }
    }
  }

  Future<void> _pickLocalFile() async {
    setState(() {
      _isPicking = true;
    });

    try {
      final result = await file_picker.FilePicker.platform.pickFiles(
        type: file_picker.FileType.any,
        allowMultiple: false,
      );

      if (!mounted) {
        return;
      }

      if (result == null) {
        _showMessage('已取消文件选择。');
        return;
      }

      final picked = result.files.single;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        _showMessage('当前结果没有本地路径，demo 只处理有绝对路径的文件。');
        return;
      }

      setState(() {
        _selection = PreviewSelection.local(
          title: picked.name,
          source: path,
          description: '来自系统文件选择器的本地文件。',
        );
      });

      _showMessage('已加载 ${picked.name}');
    } catch (error) {
      _showMessage('选择文件失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  void _loadRemoteUrl() {
    final raw = _remoteUrlController.text.trim();
    final uri = Uri.tryParse(raw);

    if (raw.isEmpty || uri == null || !uri.hasScheme) {
      _showMessage('请输入完整的远程 URL，例如 https://pdfobject.com/pdf/sample.pdf');
      return;
    }

    setState(() {
      _selection = PreviewSelection.remote(
        title: uri.pathSegments.isEmpty ? raw : uri.pathSegments.last,
        source: raw,
        description: '来自远程地址的预览资源。',
      );
    });
  }

  Future<void> _openExternally() async {
    final selection = _selection;
    if (selection == null || selection.isRemote) {
      _showMessage('远程资源无法直接交给外部应用，建议切换到全能型插件预览。');
      return;
    }

    final result = await OpenFilex.open(selection.source);
    if (!mounted) {
      return;
    }

    if (result.type == ResultType.done) {
      _showMessage('已交给外部应用处理。');
      return;
    }

    final message = result.message.trim();
    _showMessage(
      message.isEmpty ? '外部打开失败。' : '外部打开失败：$message',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF7F1E8),
              Color(0xFFF4F8F3),
              Color(0xFFEAF4F8),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final previewHeight = math.max(
                480.0,
                constraints.maxHeight * 0.72,
              );

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: [
                  _buildHeroCard(context),
                  const SizedBox(height: 16),
                  _buildStrategyCard(context),
                  const SizedBox(height: 16),
                  _buildPermissionCard(context),
                  const SizedBox(height: 16),
                  _buildSampleCard(context),
                  const SizedBox(height: 16),
                  _buildCurrentSelectionCard(context),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: previewHeight,
                    child: _buildPreviewCard(context),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF143642), Color(0xFF0F766E), Color(0xFFF59E0B)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260F172A),
            blurRadius: 24,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Flutter 文件预览 Demo',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '同一份文件可以在两种策略之间切换：'
            '一边是 universal_file_viewer 的一站式预览，一边是图片 / PDF / 文本按类型分发的组合方案。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _HeroTag(label: 'Image / PDF / TXT / CSV'),
              _HeroTag(label: '本地文件 + 远程资源'),
              _HeroTag(label: 'Android 权限演示'),
              _HeroTag(label: 'Office 兜底策略'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStrategyCard(BuildContext context) {
    final theme = Theme.of(context);
    final strategyNote = _strategy == PreviewStrategy.universal
        ? '全能型插件模式：由 universal_file_viewer 负责扩展名识别与兜底，适合快速上线。'
        : '自由组合模式：图片走 PhotoView，PDF 走 mini_pdf_epub_viewer，文本与 CSV 由业务代码接管，适合精细化控制。';

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '预览策略',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<PreviewStrategy>(
            multiSelectionEnabled: false,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: PreviewStrategy.universal,
                icon: Icon(Icons.widgets_outlined),
                label: Text('全能型插件'),
              ),
              ButtonSegment(
                value: PreviewStrategy.composable,
                icon: Icon(Icons.account_tree_outlined),
                label: Text('自由组合'),
              ),
            ],
            selected: {_strategy},
            onSelectionChanged: (selection) {
              setState(() {
                _strategy = selection.first;
              });
            },
          ),
          const SizedBox(height: 14),
          Text(
            strategyNote,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard(BuildContext context) {
    final theme = Theme.of(context);
    final hasPermanentlyDenied = _androidPermissionStates.values.any(
      (status) => status.isPermanentlyDenied,
    );

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '权限与文件选择',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            Platform.isAndroid
                ? 'Android 13+ 需要细粒度媒体权限。文档类文件通常仍通过系统文件选择器处理，因此这个 demo 把权限申请做成了显式动作。'
                : '当前平台使用系统文档选择器即可完成文件选择，本 demo 不额外申请存储权限。',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _androidPermissionStates.entries.map((entry) {
                final label = switch (entry.key) {
                  'storage' => 'Storage',
                  'photos' => 'Images',
                  'videos' => 'Videos',
                  'audio' => 'Audio',
                  _ => entry.key,
                };
                return Chip(
                  avatar: Icon(
                    _iconForPermission(entry.value),
                    size: 18,
                    color: _colorForPermission(entry.value),
                  ),
                  label: Text('$label · ${_labelForPermission(entry.value)}'),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _isRequestingPermission
                      ? null
                      : _requestAndroidPermissions,
                  icon: Icon(
                    _isRequestingPermission
                        ? Icons.hourglass_top_rounded
                        : Icons.verified_user_outlined,
                  ),
                  label: Text(
                    _isRequestingPermission ? '申请中...' : '申请读取权限',
                  ),
                ),
                if (hasPermanentlyDenied)
                  OutlinedButton.icon(
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('打开系统设置'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSampleCard(BuildContext context) {
    final theme = Theme.of(context);
    final selection = _selection;

    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '演示样例',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '先用预置文件快速体验，再用系统文件选择器加载你自己的附件或文档。',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _presetSelections.map((sample) {
              final isSelected =
                  selection?.source == sample.source &&
                  selection?.isRemote == sample.isRemote;
              return ChoiceChip(
                selected: isSelected,
                label: Text(sample.title),
                avatar: Icon(_iconForKind(sample.kind), size: 18),
                onSelected: (_) {
                  setState(() {
                    _selection = sample;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _isPicking ? null : _pickLocalFile,
                icon: Icon(
                  _isPicking
                      ? Icons.hourglass_top_rounded
                      : Icons.folder_open_outlined,
                ),
                label: Text(_isPicking ? '选择中...' : '选择本地文件'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _remoteUrlController.text = kSamplePdfUrl;
                  _loadRemoteUrl();
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('加载远程 PDF'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _remoteUrlController,
            decoration: InputDecoration(
              labelText: '远程资源 URL',
              hintText: 'https://example.com/sample.pdf',
              filled: true,
              fillColor: const Color(0xFFF8F5EF),
              suffixIcon: IconButton(
                onPressed: _loadRemoteUrl,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _loadRemoteUrl(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentSelectionCard(BuildContext context) {
    final theme = Theme.of(context);
    final selection = _selection;

    return _SurfaceCard(
      child: selection == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('请选择一个文件或远程资源。'),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前文件',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  selection.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  selection.description,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text(selection.isRemote ? '远程资源' : '本地文件')),
                    Chip(label: Text(_labelForKind(selection.kind))),
                    Chip(label: Text(selection.extensionLabel)),
                    Chip(label: Text(_labelForStrategy(_strategy))),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  selection.source,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _supportNoteForSelection(selection),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
                if (!selection.isRemote) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openExternally,
                    icon: const Icon(Icons.open_in_new_outlined),
                    label: const Text('使用外部应用打开'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildPreviewCard(BuildContext context) {
    final theme = Theme.of(context);

    return _SurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '预览区域',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                avatar: Icon(
                  _strategy == PreviewStrategy.universal
                      ? Icons.widgets_outlined
                      : Icons.account_tree_outlined,
                  size: 18,
                ),
                label: Text(_labelForStrategy(_strategy)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _strategy == PreviewStrategy.universal
                ? '当前由 universal_file_viewer 接管文件渲染，适合快速覆盖多格式。'
                : '当前按类型分发到专业组件。Office 与视频保留为业务兜底入口。',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ColoredBox(
                color: const Color(0xFFFBFAF7),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: _buildPreviewContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewContent() {
    if (_isPreparing) {
      return const Center(child: CircularProgressIndicator());
    }

    final selection = _selection;
    if (selection == null) {
      return const _EmptyPreview(
        icon: Icons.file_open_outlined,
        title: '还没有选中文件',
        message: '从上方样例中选择一个文件，或者直接打开系统文件选择器。',
      );
    }

    if (_strategy == PreviewStrategy.universal) {
      return KeyedSubtree(
        key: ValueKey('universal-${selection.cacheKey}'),
        child: selection.isRemote
            ? UniversalFileViewer.remote(fileUrl: selection.source)
            : UniversalFileViewer(file: File(selection.source)),
      );
    }

    return KeyedSubtree(
      key: ValueKey('composable-${selection.cacheKey}'),
      child: _buildComposablePreview(selection),
    );
  }

  Widget _buildComposablePreview(PreviewSelection selection) {
    switch (selection.kind) {
      case PreviewKind.image:
        return _buildImagePreview(selection);
      case PreviewKind.pdf:
        return _buildPdfPreview(selection);
      case PreviewKind.text:
      case PreviewKind.markdown:
        if (selection.isRemote) {
          return _FallbackPreview(
            icon: Icons.download_for_offline_outlined,
            title: '远程文本未内置读取',
            message: '文章里提到，网络文件通常会先下载到本地再预览。这个 demo 的组合方案只直接处理本地 text / md 文件。',
          );
        }
        return TextFilePreview(path: selection.source);
      case PreviewKind.csv:
        if (selection.isRemote) {
          return _FallbackPreview(
            icon: Icons.download_for_offline_outlined,
            title: '远程 CSV 未内置读取',
            message: '如果业务里需要预览远程 CSV，建议先下载到临时目录，再走统一的类型分发逻辑。',
          );
        }
        return CsvFilePreview(path: selection.source);
      case PreviewKind.office:
        return _FallbackPreview(
          icon: Icons.description_outlined,
          title: 'Office 文档需要专用内核',
          message: '组合方案里，Office 预览通常要接 flutter_office_viewer 或 Android 的 X5 内核。这个 demo 保留了外部打开入口，避免引入平台专属实现。',
          actionLabel: selection.isRemote ? null : '外部打开',
          onAction: selection.isRemote ? null : _openExternally,
        );
      case PreviewKind.video:
        return _FallbackPreview(
          icon: Icons.ondemand_video_outlined,
          title: '视频预览未在组合方案内实现',
          message: '文章中的一站式方案可以覆盖视频。若你要在组合方案里做视频播放，建议引入专门的视频播放器组件。',
          actionLabel: selection.isRemote ? null : '外部打开',
          onAction: selection.isRemote ? null : _openExternally,
        );
      case PreviewKind.unsupported:
        return _FallbackPreview(
          icon: Icons.help_outline_rounded,
          title: '暂不支持的格式',
          message: '这个示例没有为当前扩展名接入专门组件。你可以切换到全能型插件，或直接使用外部应用兜底。',
          actionLabel: selection.isRemote ? null : '外部打开',
          onAction: selection.isRemote ? null : _openExternally,
        );
    }
  }

  Widget _buildImagePreview(PreviewSelection selection) {
    final ImageProvider<Object> provider = selection.isRemote
        ? NetworkImage(selection.source)
        : FileImage(File(selection.source));

    return PhotoView(
      imageProvider: provider,
      minScale: PhotoViewComputedScale.contained,
      initialScale: PhotoViewComputedScale.contained,
      backgroundDecoration: const BoxDecoration(color: Color(0xFF101828)),
    );
  }

  Widget _buildPdfPreview(PreviewSelection selection) {
    return DocumentViewer(
      source: selection.isRemote
          ? DocumentSource.network(selection.source)
          : DocumentSource.file(selection.source),
      type: DocumentType.pdf,
      showThumbnails: true,
      thumbnailWidth: 120,
      selectedThumbnailColor: Theme.of(context).colorScheme.primary,
    );
  }

  String _supportNoteForSelection(PreviewSelection selection) {
    if (_strategy == PreviewStrategy.universal) {
      return '当前演示使用一站式插件；遇到图片、PDF、Office、视频、文本等类型时，会优先交给内部渲染器处理，不支持的格式再回退到外部应用。';
    }

    return switch (selection.kind) {
      PreviewKind.image => '组合方案会把图片交给 PhotoView，获得更细的手势缩放控制。',
      PreviewKind.pdf => '组合方案会把 PDF 交给 mini_pdf_epub_viewer，并保留缩略图侧栏。',
      PreviewKind.text || PreviewKind.markdown => '组合方案会直接读取本地文本内容，适合接入自己的高亮或业务标注。',
      PreviewKind.csv => '组合方案会把 CSV 解析成表格，便于继续叠加排序、筛选和复制能力。',
      PreviewKind.office => 'Office 文档在组合方案里通常要接专用内核；这个 demo 只保留了预留位和兜底入口。',
      PreviewKind.video => '视频更适合接入专门播放器组件；这里用说明卡片代替。',
      PreviewKind.unsupported => '当前扩展名没有接入自定义组件，建议切到全能型插件或外部打开。',
    };
  }
}

class PreviewSelection {
  const PreviewSelection({
    required this.title,
    required this.source,
    required this.isRemote,
    required this.description,
  });

  factory PreviewSelection.local({
    required String title,
    required String source,
    required String description,
  }) {
    return PreviewSelection(
      title: title,
      source: source,
      isRemote: false,
      description: description,
    );
  }

  factory PreviewSelection.remote({
    required String title,
    required String source,
    required String description,
  }) {
    return PreviewSelection(
      title: title,
      source: source,
      isRemote: true,
      description: description,
    );
  }

  final String title;
  final String source;
  final bool isRemote;
  final String description;

  PreviewKind get kind => detectPreviewKind(source);

  String get extensionLabel {
    final extension = extractExtension(source);
    return extension.isEmpty ? '无扩展名' : extension;
  }

  String get cacheKey => '${isRemote ? 'remote' : 'local'}-$source';
}

PreviewKind detectPreviewKind(String source) {
  final extension = extractExtension(source);
  switch (extension) {
    case '.jpg':
    case '.jpeg':
    case '.png':
    case '.gif':
    case '.bmp':
    case '.webp':
      return PreviewKind.image;
    case '.pdf':
      return PreviewKind.pdf;
    case '.txt':
      return PreviewKind.text;
    case '.md':
      return PreviewKind.markdown;
    case '.csv':
      return PreviewKind.csv;
    case '.doc':
    case '.docx':
    case '.xls':
    case '.xlsx':
    case '.ppt':
    case '.pptx':
      return PreviewKind.office;
    case '.mp4':
    case '.mov':
    case '.avi':
    case '.mkv':
      return PreviewKind.video;
    default:
      return PreviewKind.unsupported;
  }
}

String extractExtension(String source) {
  final uri = Uri.tryParse(source);
  final pathValue = uri != null && uri.hasScheme ? uri.path : source;
  return p.extension(pathValue).toLowerCase();
}

String _labelForKind(PreviewKind kind) {
  return switch (kind) {
    PreviewKind.image => '图片',
    PreviewKind.pdf => 'PDF',
    PreviewKind.text => '文本',
    PreviewKind.markdown => 'Markdown',
    PreviewKind.csv => 'CSV',
    PreviewKind.office => 'Office',
    PreviewKind.video => '视频',
    PreviewKind.unsupported => '未知格式',
  };
}

String _labelForStrategy(PreviewStrategy strategy) {
  return switch (strategy) {
    PreviewStrategy.universal => '全能型插件',
    PreviewStrategy.composable => '自由组合',
  };
}

IconData _iconForKind(PreviewKind kind) {
  return switch (kind) {
    PreviewKind.image => Icons.image_outlined,
    PreviewKind.pdf => Icons.picture_as_pdf_outlined,
    PreviewKind.text => Icons.notes_outlined,
    PreviewKind.markdown => Icons.article_outlined,
    PreviewKind.csv => Icons.table_chart_outlined,
    PreviewKind.office => Icons.description_outlined,
    PreviewKind.video => Icons.movie_outlined,
    PreviewKind.unsupported => Icons.help_outline_rounded,
  };
}

IconData _iconForPermission(PermissionStatus status) {
  if (status.isGranted || status.isLimited) {
    return Icons.check_circle_outline_rounded;
  }
  if (status.isPermanentlyDenied) {
    return Icons.error_outline_rounded;
  }
  return Icons.remove_circle_outline_rounded;
}

Color _colorForPermission(PermissionStatus status) {
  if (status.isGranted || status.isLimited) {
    return const Color(0xFF0F766E);
  }
  if (status.isPermanentlyDenied) {
    return const Color(0xFFB91C1C);
  }
  return const Color(0xFFB45309);
}

String _labelForPermission(PermissionStatus status) {
  if (status.isGranted) {
    return '已授权';
  }
  if (status.isLimited) {
    return '部分授权';
  }
  if (status.isPermanentlyDenied) {
    return '永久拒绝';
  }
  if (status.isRestricted) {
    return '受限';
  }
  if (status.isProvisional) {
    return '临时授权';
  }
  return '未授权';
}

class DemoSeedFiles {
  const DemoSeedFiles({
    required this.imagePath,
    required this.markdownPath,
    required this.csvPath,
    required this.textPath,
  });

  final String imagePath;
  final String markdownPath;
  final String csvPath;
  final String textPath;
}

class DemoSeedRepository {
  static const String _folderName = 'file_preview_demo_samples';

  Future<DemoSeedFiles> prepare() async {
    final tempDir = await getTemporaryDirectory();
    final demoDir = Directory(p.join(tempDir.path, _folderName));
    if (!await demoDir.exists()) {
      await demoDir.create(recursive: true);
    }

    final imageFile = File(p.join(demoDir.path, 'preview_card.png'));
    final markdownFile = File(p.join(demoDir.path, 'preview_notes.md'));
    final csvFile = File(p.join(demoDir.path, 'plugin_matrix.csv'));
    final textFile = File(p.join(demoDir.path, 'readme.txt'));

    await _writeDemoImage(imageFile);
    await markdownFile.writeAsString(_markdownSample, flush: true);
    await csvFile.writeAsString(_csvSample, flush: true);
    await textFile.writeAsString(_textSample, flush: true);

    return DemoSeedFiles(
      imagePath: imageFile.path,
      markdownPath: markdownFile.path,
      csvPath: csvFile.path,
      textPath: textFile.path,
    );
  }

  Future<void> _writeDemoImage(File file) async {
    const width = 1200;
    const height = 720;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());

    final backgroundPaint = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        const [
          Color(0xFF143642),
          Color(0xFF0F766E),
          Color(0xFFF59E0B),
        ],
      );
    canvas.drawRect(rect, backgroundPaint);

    final circlePaint = Paint()..color = const Color(0x22FFFFFF);
    canvas.drawCircle(const Offset(980, 140), 220, circlePaint);
    canvas.drawCircle(const Offset(170, 590), 180, circlePaint);

    final boardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(88, 90, 1024, 540),
      const Radius.circular(42),
    );
    final boardPaint = Paint()..color = const Color(0xEAF8FAF7);
    canvas.drawRRect(boardRect, boardPaint);

    final shadowPaint = Paint()..color = const Color(0x180F172A);
    canvas.drawRRect(
      boardRect.shift(const Offset(0, 16)),
      shadowPaint,
    );
    canvas.drawRRect(boardRect, boardPaint);

    _paintText(
      canvas,
      text: 'Flutter 文件预览',
      offset: const Offset(148, 152),
      style: const TextStyle(
        fontSize: 68,
        fontWeight: FontWeight.w800,
        color: Color(0xFF143642),
        letterSpacing: 0.4,
      ),
      maxWidth: 760,
    );

    _paintText(
      canvas,
      text: '一站式插件 + 自由组合',
      offset: const Offset(148, 236),
      style: const TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0F766E),
      ),
      maxWidth: 760,
    );

    _paintText(
      canvas,
      text: 'Image  PDF  Markdown  CSV  Office Fallback',
      offset: const Offset(148, 304),
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        color: Color(0xFF475569),
      ),
      maxWidth: 780,
    );

    final highlightRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(148, 392, 420, 92),
      const Radius.circular(28),
    );
    canvas.drawRRect(
      highlightRect,
      Paint()..color = const Color(0xFF143642),
    );

    _paintText(
      canvas,
      text: 'Pick, Detect, Preview',
      offset: const Offset(188, 420),
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 0.3,
      ),
      maxWidth: 340,
    );

    final noteRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(720, 188, 256, 256),
      const Radius.circular(36),
    );
    canvas.drawRRect(
      noteRect,
      Paint()..color = const Color(0xFFFDF2D0),
    );
    _paintText(
      canvas,
      text: 'Preview\nAnywhere',
      offset: const Offset(776, 252),
      style: const TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        color: Color(0xFF92400E),
        height: 1.2,
      ),
      maxWidth: 160,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final bytes = byteData?.buffer.asUint8List();
    if (bytes == null) {
      throw StateError('生成 PNG 字节失败。');
    }

    await file.writeAsBytes(bytes, flush: true);
  }

  void _paintText(
    Canvas canvas, {
    required String text,
    required Offset offset,
    required TextStyle style,
    required double maxWidth,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    textPainter.paint(canvas, offset);
  }
}

class TextFilePreview extends StatelessWidget {
  const TextFilePreview({super.key, required this.path});

  final String path;

  Future<String> _loadText() async {
    return File(path).readAsString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<String>(
      future: _loadText(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _FallbackPreview(
            icon: Icons.error_outline_rounded,
            title: '文本读取失败',
            message: '${snapshot.error}',
          );
        }

        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: SelectableText(
              snapshot.data ?? '',
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.7,
                color: const Color(0xFF1F2937),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CsvFilePreview extends StatelessWidget {
  const CsvFilePreview({super.key, required this.path});

  final String path;

  Future<List<List<String>>> _loadRows() async {
    final content = await File(path).readAsString();
    final lines = content
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return const [];
    }

    final rows = lines
        .map(
          (line) => line
              .split(',')
              .map((cell) => cell.trim())
              .toList(growable: false),
        )
        .toList(growable: false);
    final maxColumns = rows.fold<int>(
      0,
      (previous, row) => math.max(previous, row.length),
    );

    return rows
        .map((row) {
          if (row.length == maxColumns) {
            return row;
          }
          return [
            ...row,
            ...List<String>.filled(maxColumns - row.length, ''),
          ];
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<String>>>(
      future: _loadRows(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _FallbackPreview(
            icon: Icons.error_outline_rounded,
            title: 'CSV 读取失败',
            message: '${snapshot.error}',
          );
        }

        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) {
          return const _EmptyPreview(
            icon: Icons.table_chart_outlined,
            title: 'CSV 内容为空',
            message: '请换一个包含表格数据的文件再试。',
          );
        }

        final header = rows.first;
        final body = rows.skip(1).toList(growable: false);

        return Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 28,
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFE2E8F0),
                ),
                columns: header
                    .map((cell) => DataColumn(label: Text(cell)))
                    .toList(growable: false),
                rows: body
                    .map(
                      (row) => DataRow(
                        cells: row
                            .map((cell) => DataCell(Text(cell)))
                            .toList(growable: false),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x140F172A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: const Color(0xFF64748B)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackPreview extends StatelessWidget {
  const _FallbackPreview({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 58, color: const Color(0xFF475569)),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const String _markdownSample = '''
# Flutter 文件预览 Demo

这个 Markdown 文件来自运行时生成的本地示例，用来模拟聊天附件或云盘文档。

## 两条实现路线

1. 全能型插件：用 `universal_file_viewer` 统一接管不同格式。
2. 自由组合型：按扩展名分发给图片、PDF、文本等专用组件。

## 实战建议

- 先做格式识别，再做组件分发。
- Android 13+ 重点关注细粒度媒体权限。
- Office 文档最好单独评估内核兼容性。
- 大文件优先考虑分页、缓存和降内存策略。
''';

const String _csvSample = '''
插件,支持格式,特点,适用场景
universal_file_viewer,图片 PDF Office 视频 文本,一站式接入,快速开发
mini_pdf_epub_viewer,PDF EPUB,缩略图侧栏,精细化 PDF 阅读
photo_view,图片,支持缩放与拖拽,图片详情页
open_filex,未知格式兜底,交给系统外部应用,兜底打开
''';

const String _textSample = '''
文件预览通常不是单一组件问题，而是“格式兼容 + 体验一致性”的组合题。

这个示例做了三件事：
1. 用系统文件选择器拿到真实路径。
2. 用统一的扩展名识别逻辑做路由。
3. 在全能型与自由组合型之间来回切换，比较效果和接入成本。
''';
