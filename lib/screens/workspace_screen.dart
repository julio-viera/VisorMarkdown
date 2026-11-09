import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../themes/app_theme.dart';
import '../widgets/document_scrollbar.dart';
import '../widgets/document_split_view.dart';
import '../widgets/app_logo.dart';
import '../widgets/window_chrome.dart';
import '../widgets/retained_preview.dart';
import '../widgets/deferred_document_text.dart';
import '../widgets/document_toolbar_fields.dart';
import '../widgets/safe_markdown_image.dart';
import '../widgets/numbered_editor.dart';
import '../widgets/anchored_preview.dart';
import '../widgets/document_tab_strip.dart';
import '../repositories/document_repository.dart';
import '../controllers/workspace_controller.dart';
import '../l10n/strings.dart';
import '../models/app_settings.dart';
import '../models/markdown_document.dart';
import '../services/markdown_service.dart';
import '../services/external_document_service.dart';
import '../services/desktop_file_open_service.dart';
import '../services/pdf_export_service.dart';
import '../services/document_limits.dart';
import 'settings_dialog.dart';
import 'diff_dialog.dart';
import 'about_dialog.dart' as app;

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.settings,
    this.arguments = const [],
    this.controller,
  });
  final AppSettings settings;
  final List<String> arguments;
  final WorkspaceController? controller;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final WorkspaceController workspace =
      widget.controller ??
      WorkspaceController(
        repository: DocumentRepository(settings: widget.settings),
      );
  late final AppLifecycleListener lifecycle;
  ExternalDocumentService? externalDocuments;
  DesktopFileOpenService? desktopFiles;
  final search = TextEditingController();
  final editorFocus = FocusNode();
  final searchFocus = FocusNode();
  bool dragging = false;
  bool busy = false;
  Strings get s => Strings(Localizations.localeOf(context).languageCode);
  @override
  void initState() {
    super.initState();
    widget.settings.confirmWindowClose = confirmExit;
    lifecycle = AppLifecycleListener(
      onExitRequested: () async =>
          await confirmExit() ? AppExitResponse.exit : AppExitResponse.cancel,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Platform.isAndroid) {
        externalDocuments = ExternalDocumentService();
        await externalDocuments!.start(
          onDocument: (file) {
            if (!mounted) return;
            workspace.importDocument(file);
            syncSearch();
          },
          onError: (error) {
            if (mounted) message('${s['error']}: $error');
          },
        );
      }
      for (final path in widget.arguments) {
        await guard(() => workspace.openPath(path));
        if (!mounted) return;
      }
      if (widget.settings.desktopFileEvents && mounted) {
        desktopFiles = DesktopFileOpenService();
        await desktopFiles!.start(
          onOpenPaths: (paths) async {
            for (final path in paths) {
              if (!mounted) return;
              await guard(() => workspace.openPath(path));
            }
            if (mounted) {
              syncSearch();
              editorFocus.requestFocus();
            }
          },
          onError: (error) {
            if (mounted) message('${s['error']}: $error');
          },
        );
      }
    });
  }

  @override
  void dispose() {
    widget.settings.confirmWindowClose = null;
    lifecycle.dispose();
    externalDocuments?.dispose();
    desktopFiles?.dispose();
    search.dispose();
    editorFocus.dispose();
    searchFocus.dispose();
    if (widget.controller == null) workspace.dispose();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) message('${s['error']}: $error');
    }
  }

  Future<bool> confirm(String title, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s['cancel']),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<bool> save(MarkdownDocument doc, {bool as = false}) async {
    if (doc.saving) return false;
    doc.saving = true;
    workspace.changed();
    try {
      if (!as && doc.path != null) {
        String? disk;
        try {
          disk = await workspace.repository.read(doc.path!);
        } on FileSystemException {
          /* Confirm recovery/overwrite below. */
        }
        if (!mounted) return false;
        if ((disk == null || disk != doc.savedText) &&
            !await confirm(
              disk == null ? s['missing'] : s['external'],
              s['overwrite'],
            )) {
          return false;
        }
      }
      final snapshot = doc.editor.text;
      if (as || doc.path == null) {
        final location = await workspace.repository.saveAs(
          doc.title.endsWith('.md') ? doc.title : '${doc.title}.md',
          snapshot,
          'md',
        );
        if (location == null) return false;
        // Mobile pickers return document URIs or copies, not writable OS paths.
        if (!Platform.isAndroid && !Platform.isIOS) doc.path = location;
      } else {
        await workspace.repository.write(doc.path!, snapshot);
      }
      if (!mounted || !workspace.documents.contains(doc)) return false;
      doc.savedText = snapshot;
      doc.externalText = null;
      doc.missing = false;
      message(s['saved']);
      return true;
    } catch (error) {
      if (mounted) message('${s['error']}: $error');
      return false;
    } finally {
      doc.saving = false;
      workspace.changed();
    }
  }

  Future<bool> mayClose(MarkdownDocument doc, {String? prompt}) async {
    if (doc.saving) return false;
    if (!doc.dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(prompt ?? s['unsaved']),
        content: Text(doc.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s['cancel']),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text(s['discard']),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(s['save']),
          ),
        ],
      ),
    );
    if (choice == 'save') return await save(doc) && !doc.dirty;
    return choice == 'discard';
  }

  Future<bool> confirmExit() async {
    if (busy) return false;
    for (final doc in List<MarkdownDocument>.of(workspace.documents)) {
      if (!await mayClose(doc, prompt: s['closeApp'])) return false;
    }
    await widget.settings.persistBeforeExit?.call();
    return true;
  }

  Future<void> close(MarkdownDocument doc) async {
    if (busy) return;
    if (await mayClose(doc) && mounted) {
      workspace.close(doc);
      syncSearch();
    }
  }

  void syncSearch() {
    search.text = workspace.active.query;
  }

  void select(int index) {
    workspace.select(index);
    syncSearch();
  }

  void navigateSearch(int direction) {
    workspace.nextMatch(direction);
    final doc = workspace.active;
    if (doc.matchIndex < 0) return;
    if (doc.mobilePreview) setState(() => doc.mobilePreview = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          workspace.active != doc ||
          !doc.editor.selection.isValid) {
        return;
      }
      editorFocus.context
          ?.findAncestorStateOfType<EditableTextState>()
          ?.bringIntoView(doc.editor.selection.extent);
    });
  }

  Future<void> open({String? path}) async {
    final target = workspace.active;
    if (busy || target.saving) return;
    setState(() => busy = true);
    try {
      await guard(() async {
        final files = path == null
            ? await workspace.repository.pick()
            : [
                OpenedFile(
                  p.basename(path),
                  await workspace.repository.read(path),
                  path,
                ),
              ];
        if (!mounted ||
            files.isEmpty ||
            !workspace.documents.contains(target)) {
          return;
        }
        if (!await mayClose(target, prompt: s['unsavedOpen']) || !mounted) {
          return;
        }
        workspace.replaceDocument(target, files.first);
        syncSearch();
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> copyMarkdown() => guard(() async {
    await Clipboard.setData(ClipboardData(text: workspace.active.editor.text));
  });

  Future<void> pasteMarkdown() => guard(() async {
    final target = workspace.active;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted ||
        data?.text == null ||
        !workspace.documents.contains(target)) {
      return;
    }
    final value = target.editor.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final pasted = data!.text!;
    final replacement = value.text.replaceRange(
      selection.start,
      selection.end,
      pasted,
    );
    try {
      DocumentLimits.validate(replacement);
    } on FormatException {
      message(s['documentLimit']);
      return;
    }
    target.editor.value = value.copyWith(
      text: replacement,
      selection: TextSelection.collapsed(
        offset: selection.start + pasted.length,
      ),
      composing: TextRange.empty,
    );
    if (target.mobilePreview) setState(() => target.mobilePreview = false);
    if (workspace.active == target) editorFocus.requestFocus();
  });

  Future<void> export(String format) async {
    if (busy) return;
    final doc = workspace.active;
    setState(() => busy = true);
    try {
      await guard(() async {
        final name = '${p.basenameWithoutExtension(doc.title)}.$format';
        String? location;
        if (format == 'pdf') {
          final bytes = await PdfExportService.render(
            doc.editor.text,
            doc.dialect,
            doc.title,
            baseDirectory: doc.path == null ? null : p.dirname(doc.path!),
            imageLoader: doc.images,
          );
          location = await workspace.repository.saveBytesAs(name, bytes, 'pdf');
        } else {
          final text = switch (format) {
            'html' => MarkdownService.html(
              doc.editor.text,
              doc.dialect,
              doc.title,
            ),
            'txt' => MarkdownService.plainText(doc.editor.text, doc.dialect),
            _ => doc.editor.text,
          };
          location = await workspace.repository.saveAs(name, text, format);
        }
        if (location != null && mounted) message(s['saved']);
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void insertTable(int columns) {
    final doc = workspace.active;
    if (!doc.dialect.supportsTables) return;
    final value = doc.editor.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final before = value.text.substring(0, selection.start);
    final after = value.text.substring(selection.end);
    final prefix = before.isEmpty || before.endsWith('\n\n')
        ? ''
        : before.endsWith('\n')
        ? '\n'
        : '\n\n';
    final suffix = after.isEmpty
        ? '\n'
        : after.startsWith('\n\n')
        ? ''
        : after.startsWith('\n')
        ? '\n'
        : '\n\n';
    final table = MarkdownService.exampleTable(
      columns,
      columnLabel: s['column'],
      cellLabel: s['example'],
    );
    final replacement = '$before$prefix$table$suffix$after';
    try {
      DocumentLimits.validate(replacement);
    } on FormatException {
      message(s['documentLimit']);
      return;
    }
    doc.editor.value = TextEditingValue(
      text: replacement,
      selection: TextSelection.collapsed(
        offset: before.length + prefix.length + table.length,
      ),
    );
    if (doc.mobilePreview) setState(() => doc.mobilePreview = false);
    editorFocus.requestFocus();
  }

  void compareDocuments() {
    if (workspace.documents.length < 2) {
      message(s['noComparison']);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => DiffDialog(
        documents: List.of(workspace.documents),
        active: workspace.active,
        strings: s,
      ),
    );
  }

  Future<void> reload(MarkdownDocument doc) async {
    if (doc.dirty && !await confirm(s['confirmReload'], s['reload'])) return;
    workspace.reload(doc);
  }

  Future<void> link(String url) async {
    await guard(() async {
      final uri = Uri.parse(url);
      if (!['http', 'https', 'mailto'].contains(uri.scheme)) return;
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError(url);
      }
    });
  }

  void about() => showDialog<void>(
    context: context,
    builder: (_) => app.AboutDialog(strings: s, onOpenLink: link),
  );

  Widget tool(
    String label,
    IconData icon,
    VoidCallback? action, {
    double extent = 36,
  }) => IconButton(
    tooltip: label,
    onPressed: action,
    icon: Icon(icon, size: extent <= 28 ? 18 : 20),
    padding: EdgeInsets.zero,
    constraints: BoxConstraints.tightFor(width: extent, height: extent),
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  void newTab() {
    workspace.add();
    syncSearch();
  }

  void settings() => showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(settings: widget.settings),
  );

  List<Widget> toolbarActions(MarkdownDocument doc, bool wide) => [
    if (wide)
      KeyedSubtree(
        key: const ValueKey('toggle-preview-action'),
        child: tool(
          s[doc.showPreview ? 'hidePreview' : 'showPreview'],
          doc.showPreview
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          () => setState(() => doc.showPreview = !doc.showPreview),
        ),
      ),
    KeyedSubtree(
      key: const ValueKey('new-tab-action'),
      child: tool(s['new'], Icons.add, newTab),
    ),
    PopupMenuButton<String>(
      key: const ValueKey('export-action'),
      tooltip: s['export'],
      icon: const Icon(Icons.ios_share, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 180),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(36, 36),
        maximumSize: const Size(36, 36),
      ),
      enabled: !busy,
      onSelected: export,
      itemBuilder: (_) => [
        for (final entry in {
          'md': 'markdown',
          'html': 'html',
          'txt': 'plainText',
          'pdf': 'pdf',
        }.entries)
          PopupMenuItem(
            value: entry.key,
            child: Text('${s['export']} · ${s[entry.value]}'),
          ),
      ],
    ),
    KeyedSubtree(
      key: const ValueKey('compare-action'),
      child: tool(s['compare'], Icons.compare_arrows, compareDocuments),
    ),
    KeyedSubtree(
      key: const ValueKey('settings-action'),
      child: tool(s['settings'], Icons.settings_outlined, settings),
    ),
  ];

  Widget toolbarContent(
    MarkdownDocument doc,
    List<Widget> children, {
    required bool wide,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final tools = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: children,
      );
      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: toolbarActions(doc, wide),
      );
      if (constraints.maxWidth < 440) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerRight, child: actions),
            const SizedBox(height: 6),
            tools,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: tools),
          const SizedBox(width: 12),
          Padding(padding: const EdgeInsets.only(top: 6), child: actions),
        ],
      );
    },
  );

  Widget tabsBar(bool wide) => ColoredBox(
    color: DocumentChromeColors(Theme.of(context).colorScheme).strip,
    child: wide
        ? DocumentTabStrip(
            documents: List.of(workspace.documents),
            activeIndex: workspace.activeIndex,
            strings: s,
            onSelect: select,
            onClose: close,
            actions: [
              if (widget.settings.customWindowChrome) ...[
                const WindowDragRegion(
                  key: ValueKey('window-drag-area'),
                  enabled: true,
                  child: SizedBox(width: 48, height: 42),
                ),
                WindowChromeControls(settings: widget.settings, strings: s),
              ],
            ],
            draggableBackground: widget.settings.customWindowChrome,
          )
        : SizedBox(
            height: 42,
            child: Row(
              children: [
                Builder(
                  builder: (context) => tool(
                    s['tabs'],
                    Icons.menu,
                    () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                Expanded(
                  child: WindowDragRegion(
                    enabled: widget.settings.customWindowChrome,
                    child: SizedBox(
                      height: 42,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${workspace.active.dirty ? '• ' : ''}${workspace.active.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.settings.customWindowChrome)
                  WindowChromeControls(settings: widget.settings, strings: s),
                const SizedBox(width: 4),
              ],
            ),
          ),
  );

  Widget tab(MarkdownDocument doc, int index, {bool vertical = false}) =>
      Material(
        color: index == workspace.activeIndex
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            select(index);
            if (vertical) Navigator.pop(context);
          },
          child: SizedBox(
            width: vertical ? null : 210,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${doc.dirty ? '• ' : ''}${doc.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  tool(
                    s['close'],
                    Icons.close,
                    doc.saving ? null : () => close(doc),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: workspace,
    builder: (context, _) {
      final doc = workspace.active;
      final wide = MediaQuery.sizeOf(context).width >= 800;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
            workspace.add();
            syncSearch();
          },
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): open,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              save(doc),
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () =>
              save(doc, as: true),
          const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
              close(doc),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              searchFocus.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.f3): () => navigateSearch(1),
          const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
              navigateSearch(-1),
        },
        child: PopScope(
          canPop: !busy && !workspace.documents.any((d) => d.dirty || d.saving),
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop && await confirmExit()) {
              await SystemNavigator.pop();
            }
          },
          child: Scaffold(
            drawer: wide
                ? null
                : Drawer(
                    child: SafeArea(
                      child: Column(
                        children: [
                          const ListTile(
                            leading: AppLogo(size: 28),
                            title: Text('Visor Markdown'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.add),
                            title: Text(s['new']),
                            onTap: () {
                              workspace.add();
                              syncSearch();
                              Navigator.pop(context);
                            },
                          ),
                          Expanded(
                            child: ListView(
                              children: [
                                for (
                                  var i = 0;
                                  i < workspace.documents.length;
                                  i++
                                )
                                  tab(
                                    workspace.documents[i],
                                    i,
                                    vertical: true,
                                  ),
                              ],
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.settings_outlined),
                            title: Text(s['settings']),
                            onTap: () {
                              Navigator.pop(context);
                              showDialog<void>(
                                context: context,
                                builder: (_) =>
                                    SettingsDialog(settings: widget.settings),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
            body: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tabsBar(wide),
                  DecoratedBox(
                    key: const ValueKey('document-toolbar'),
                    decoration: BoxDecoration(
                      color: DocumentChromeColors(Theme.of(context).colorScheme)
                          .active,
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant
                              .withValues(alpha: .45),
                          width: .5,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: toolbarContent(doc, [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            tool(
                              s['open'],
                              Icons.folder_open,
                              busy || doc.saving ? null : open,
                            ),
                            tool(
                              s['save'],
                              Icons.save_outlined,
                              busy || doc.saving ? null : () => save(doc),
                            ),
                            tool(
                              s['saveAs'],
                              Icons.save_as_outlined,
                              busy || doc.saving
                                  ? null
                                  : () => save(doc, as: true),
                            ),
                            const SizedBox(width: 8),
                            tool(s['copy'], Icons.copy_outlined, copyMarkdown),
                            tool(
                              s['paste'],
                              Icons.content_paste,
                              pasteMarkdown,
                            ),
                            PopupMenuButton<int>(
                              key: const ValueKey('insert-table'),
                              tooltip: s['insertTable'],
                              enabled: doc.dialect.supportsTables,
                              icon: const Icon(
                                Icons.table_chart_outlined,
                                size: 20,
                              ),
                              onSelected: insertTable,
                              itemBuilder: (_) => [
                                for (var columns = 2; columns <= 6; columns++)
                                  PopupMenuItem(
                                    value: columns,
                                    child: Text('$columns ${s['columns']}'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(
                          width: wide
                              ? 240
                              : MediaQuery.sizeOf(context).width - 24,
                          child: MarkdownStandardSelector(
                            value: doc.dialect,
                            strings: s,
                            onChanged: (value) {
                              doc.dialect = value;
                              workspace.changed();
                            },
                          ),
                        ),
                        SizedBox(
                          width: wide
                              ? 340
                              : MediaQuery.sizeOf(context).width - 24,
                          child: ListenableBuilder(
                            listenable: doc.editor,
                            builder: (context, _) => DocumentSearchField(
                              controller: search,
                              focusNode: searchFocus,
                              strings: s,
                              matchCount: doc.matches.length,
                              matchIndex: doc.matchIndex,
                              onChanged: workspace.search,
                              onNavigate: navigateSearch,
                            ),
                          ),
                        ),
                        if (!wide)
                          SizedBox(
                            width: MediaQuery.sizeOf(context).width - 24,
                            child: SegmentedButton<bool>(
                              expandedInsets: EdgeInsets.zero,
                              segments: [
                                ButtonSegment(
                                  value: false,
                                  label: Text(
                                    s['editor'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text(
                                    s['preview'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              selected: {doc.mobilePreview},
                              onSelectionChanged: (v) =>
                                  setState(() => doc.mobilePreview = v.first),
                            ),
                          ),
                      ], wide: wide),
                    ),
                  ),
                  if (doc.externalText != null || doc.missing)
                    Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        children: [
                          Text(s[doc.missing ? 'missing' : 'external']),
                          if (!doc.missing)
                            TextButton(
                              onPressed: () => reload(doc),
                              child: Text(s['reload']),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: DropTarget(
                      onDragEntered: (_) => setState(() => dragging = true),
                      onDragExited: (_) => setState(() => dragging = false),
                      onDragDone: (details) async {
                        setState(() => dragging = false);
                        if (details.files.isNotEmpty) {
                          await open(path: details.files.first.path);
                        }
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: dragging
                              ? Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 3,
                                )
                              : null,
                        ),
                        child: wide
                            ? DocumentSplitView(
                                editor: editor(doc),
                                editorFraction: doc.editorFraction,
                                preview: doc.showPreview
                                    ? previewPanels(doc)
                                    : null,
                                dividerLabel: s['resizePanels'],
                                onResizeEnd: doc.scrollSync.previewChanged,
                              )
                            : (doc.mobilePreview
                                  ? previewPanels(doc)
                                  : editor(doc)),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      key: const ValueKey('status-bar'),
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Row(
                        children: [
                          const AppLogo(size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${AppInfo.name} ${AppInfo.version}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * .25,
                            ),
                            child: Text(
                              s[doc.dirty ? 'modified' : 'ready'],
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          DeferredDocumentText(
                            controller: doc.editor,
                            builder: (source) => diagnostics(doc, source),
                          ),
                          tool(
                            s['about'],
                            Icons.info_outline,
                            about,
                            extent: 26,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  String? _diagnosedSource;
  MarkdownDialect? _diagnosedDialect;
  Set<String> _warnings = const {};

  Widget diagnostics(MarkdownDocument doc, String source) {
    if (source != _diagnosedSource || doc.dialect != _diagnosedDialect) {
      _diagnosedSource = source;
      _diagnosedDialect = doc.dialect;
      _warnings = MarkdownService.diagnostics(source, doc.dialect);
    }
    final warnings = _warnings;
    return tool(
      s['diagnostics'],
      warnings.isEmpty ? Icons.check_circle_outline : Icons.warning_amber,
      () => showDialog<void>(
        context: context,
        builder: (context) {
          final currentWarnings = MarkdownService.diagnostics(
            doc.editor.text,
            doc.dialect,
          );
          return AlertDialog(
            title: Text(s['diagnostics']),
            content: Text(
              currentWarnings.isEmpty
                  ? s['noIssues']
                  : currentWarnings.map((w) => s[w]).join('\n\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s['close']),
              ),
            ],
          );
        },
      ),
      extent: 26,
    );
  }

  Widget editor(MarkdownDocument doc) {
    EditableTextState? editable() {
      if (!doc.scroll.hasClients) return null;
      final state = editorFocus.context
          ?.findAncestorStateOfType<EditableTextState>();
      return state?.widget.controller == doc.editor ? state : null;
    }

    doc.scrollSync.readEditor = () {
      final render = editable()?.renderEditable;
      if (render == null || !render.attached || !render.hasSize) return null;
      final position = doc.scroll.position;
      if (position.hasContentDimensions &&
          position.pixels <= position.minScrollExtent) {
        return 0;
      }
      return render
          .getPositionForPoint(render.localToGlobal(Offset.zero))
          .offset;
    };
    doc.scrollSync.revealEditor = (offset) {
      final render = editable()?.renderEditable;
      if (render == null ||
          !render.attached ||
          !render.hasSize ||
          !doc.scroll.hasClients ||
          !doc.scroll.position.hasContentDimensions) {
        return;
      }
      final caret = render.getLocalRectForCaret(
        TextPosition(offset: offset.clamp(0, doc.editor.text.length)),
      );
      final position = doc.scroll.position;
      final target = offset == 0
          ? position.minScrollExtent
          : (position.pixels + caret.top).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            );
      if ((target - position.pixels).abs() > 1) doc.scroll.jumpTo(target);
    };
    return DocumentScrollbar.forDesktop(
      context,
      DocumentScrollbar(
        key: ObjectKey(doc),
        controller: doc.scroll,
        onThumbStart: doc.scrollSync.startThumbDrag,
        onThumbEnd: doc.scrollSync.endThumbDrag,
        child: NumberedEditor(
          key: ValueKey('numbered-editor-${doc.id}'),
          fieldKey: ValueKey('editor-${doc.id}'),
          onLimitExceeded: () => message(s['documentLimit']),
          controller: doc.editor,
          focusNode: editorFocus,
          scroll: doc.scroll,
          style: widget.settings.editor.style.copyWith(height: 1.5),
        ),
      ),
    );
  }

  Widget previewPanels(MarkdownDocument doc) => RetainedPreview(
    documents: List.of(workspace.documents),
    active: doc,
    builder: preview,
  );

  Widget preview(MarkdownDocument doc) => DeferredDocumentText(
    key: ValueKey('preview-${doc.id}'),
    controller: doc.editor,
    builder: (source) => AnchoredPreview(
      key: ValueKey((
        doc.path == null ? null : p.dirname(doc.path!),
        Localizations.localeOf(context),
      )),
      scrollSync: doc.scrollSync,
      data: source,
      editor: doc.editor,
      dialect: doc.dialect,
      blankLineHeight:
          MediaQuery.textScalerOf(context).scale(widget.settings.preview.size) *
          1.6,
      imageBuilder: (uri, title, alt) => SafeMarkdownImage(
        loader: doc.images,
        source: uri.toString(),
        alt: alt ?? title ?? '',
        strings: s,
      ),
      onTapLink: (_, href, _) {
        if (href != null) link(href);
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        blockSpacing: 0,
        p: widget.settings.preview.style.copyWith(height: 1.6),
        h1: widget.settings.preview.style.copyWith(
          fontSize: widget.settings.preview.size * 2,
          fontWeight: FontWeight.bold,
        ),
        h2: widget.settings.preview.style.copyWith(
          fontSize: widget.settings.preview.size * 1.5,
          fontWeight: FontWeight.bold,
        ),
        h3: widget.settings.preview.style.copyWith(
          fontSize: widget.settings.preview.size * 1.25,
          fontWeight: FontWeight.bold,
        ),
        h4: widget.settings.preview.style.copyWith(fontWeight: FontWeight.bold),
        h5: widget.settings.preview.style.copyWith(fontWeight: FontWeight.bold),
        h6: widget.settings.preview.style.copyWith(fontWeight: FontWeight.bold),
        blockquote: widget.settings.preview.style,
        listBullet: widget.settings.preview.style,
        tableHead: widget.settings.preview.style.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        tableBody: widget.settings.preview.style.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        code: widget.settings.preview.style.copyWith(fontFamily: 'monospace'),
      ),
    ),
  );
}
