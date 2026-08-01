import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'place_search_controller.dart';
import 'place_search_result.dart';

class ExpandablePlaceSearch extends StatefulWidget {
  const ExpandablePlaceSearch({
    required this.controller,
    required this.onSelected,
    super.key,
  });

  final PlaceSearchController controller;
  final ValueChanged<PlaceSearchResult> onSelected;

  @override
  State<ExpandablePlaceSearch> createState() => ExpandablePlaceSearchState();
}

class ExpandablePlaceSearchState extends State<ExpandablePlaceSearch> {
  static const _animationDuration = Duration(milliseconds: 240);
  static const _searchDebounce = Duration(milliseconds: 420);

  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  final Object _tapRegionGroup = Object();

  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  Timer? _debounceTimer;
  Timer? _focusTimer;
  OverlayEntry? _suggestionOverlay;
  List<PlaceSearchResult> _suggestions = const [];
  double _overlayWidth = 0;
  bool _wasExpanded = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _wasExpanded = widget.controller.expanded;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ExpandablePlaceSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onControllerChanged);
    widget.controller.addListener(_onControllerChanged);
    _wasExpanded = widget.controller.expanded;
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final expanded = widget.controller.expanded;
    if (expanded && !_wasExpanded) {
      _focusTimer?.cancel();
      _focusTimer = Timer(const Duration(milliseconds: 90), () {
        if (mounted && widget.controller.expanded) {
          _focusNode.requestFocus();
        }
      });
    } else if (!expanded && _wasExpanded) {
      _debounceTimer?.cancel();
      _focusTimer?.cancel();
      _suggestions = const [];
      _removeSuggestionOverlay();
      _focusNode.unfocus();
    }
    _wasExpanded = expanded;
    setState(() {});
  }

  void _open() {
    if (!widget.controller.expanded) widget.controller.toggle();
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    _setSuggestions(const []);
    final query = value.trim();
    if (query.length < 2) return;
    _debounceTimer = Timer(_searchDebounce, () {
      unawaited(_performSearch(query));
    });
  }

  Future<void> _submit(String value) async {
    _debounceTimer?.cancel();
    await _performSearch(value, showFailure: true);
  }

  Future<void> _performSearch(String value, {bool showFailure = false}) async {
    final query = value.trim();
    if (!mounted || !widget.controller.expanded || query.length < 2) {
      _setSuggestions(const []);
      return;
    }

    final result = await widget.controller.submit(query);
    if (!mounted ||
        !widget.controller.expanded ||
        _textController.text.trim() != query) {
      return;
    }

    if (result == null) {
      _setSuggestions(const []);
      final message = widget.controller.message;
      if (showFailure && message != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _setSuggestions([result]);
  }

  void _setSuggestions(List<PlaceSearchResult> suggestions) {
    if (!mounted) return;
    setState(() => _suggestions = suggestions);
    if (suggestions.isEmpty) {
      _removeSuggestionOverlay();
    } else {
      _showSuggestionOverlay();
    }
  }

  void _showSuggestionOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.expanded || _suggestions.isEmpty) {
        return;
      }
      _refreshOverlayGeometry();
      if (_overlayWidth <= 0) return;
      if (_suggestionOverlay == null) {
        _suggestionOverlay = OverlayEntry(builder: _buildSuggestionOverlay);
        Overlay.of(context).insert(_suggestionOverlay!);
      } else {
        _suggestionOverlay!.markNeedsBuild();
      }
    });
  }

  void _refreshOverlayGeometry() {
    final renderObject = _fieldKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final width = renderObject.size.width;
    if ((width - _overlayWidth).abs() < 0.5) return;
    _overlayWidth = width;
    _suggestionOverlay?.markNeedsBuild();
  }

  Widget _buildSuggestionOverlay(BuildContext overlayContext) {
    return Positioned.fill(
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 8),
        child: Align(
          alignment: Alignment.topLeft,
          child: TapRegion(
            groupId: _tapRegionGroup,
            child: SizedBox(
              key: const Key('place-suggestion-overlay'),
              width: _overlayWidth,
              child: _SuggestionPanel(
                suggestions: _suggestions,
                onSelected: _selectSuggestion,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectSuggestion(PlaceSearchResult result) {
    _debounceTimer?.cancel();
    _textController.value = TextEditingValue(
      text: result.name,
      selection: TextSelection.collapsed(offset: result.name.length),
    );
    _setSuggestions(const []);
    _focusNode.unfocus();
    widget.onSelected(result);
  }

  void _closeAndClear() {
    _debounceTimer?.cancel();
    _focusTimer?.cancel();
    _textController.clear();
    _suggestions = const [];
    _removeSuggestionOverlay();
    _focusNode.unfocus();
    widget.controller.collapse();
  }

  void _collapsePreservingQuery() {
    _debounceTimer?.cancel();
    _suggestions = const [];
    _removeSuggestionOverlay();
    _focusNode.unfocus();
    widget.controller.collapse();
  }

  bool handleBack() {
    if (_suggestions.isNotEmpty || _suggestionOverlay != null) {
      _setSuggestions(const []);
      return true;
    }
    if (widget.controller.expanded) {
      _collapsePreservingQuery();
      return true;
    }
    return false;
  }

  void handleMapTap() {
    if (!widget.controller.expanded) return;
    _setSuggestions(const []);
    _focusNode.unfocus();
    if (_textController.text.trim().isEmpty) widget.controller.collapse();
  }

  void dismissForBackground() {
    if (!widget.controller.expanded && _suggestionOverlay == null) return;
    _collapsePreservingQuery();
  }

  void _handleTapOutside(PointerDownEvent event) {
    handleMapTap();
  }

  void _removeSuggestionOverlay() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
    _overlayWidth = 0;
  }

  @override
  void deactivate() {
    _removeSuggestionOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _debounceTimer?.cancel();
    _focusTimer?.cancel();
    _removeSuggestionOverlay();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expanded = widget.controller.expanded;
    if (_suggestionOverlay != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshOverlayGeometry();
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 480.0;
        final expandedWidth = math.min(480.0, availableWidth);
        final collapsedWidth = math.min(52.0, availableWidth);

        return TapRegion(
          groupId: _tapRegionGroup,
          onTapOutside: _handleTapOutside,
          child: CompositedTransformTarget(
            key: _fieldKey,
            link: _layerLink,
            child: AnimatedContainer(
              key: const Key('place-search-container'),
              duration: _animationDuration,
              curve: Curves.easeOutCubic,
              width: expanded ? expandedWidth : collapsedWidth,
              height: 52,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: expanded
                    ? const Color(0xF0101827)
                    : const Color(0xE6101827),
                borderRadius: BorderRadius.circular(expanded ? 26 : 18),
                border: Border.all(
                  color: expanded
                      ? const Color(0xCC2D4168)
                      : const Color(0x992D4168),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: _SearchFieldContent(
                  expanded: expanded,
                  controller: _textController,
                  focusNode: _focusNode,
                  loading: widget.controller.loading,
                  onOpen: _open,
                  onChanged: _onQueryChanged,
                  onSubmitted: _submit,
                  onClose: _closeAndClear,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchFieldContent extends StatelessWidget {
  const _SearchFieldContent({
    required this.expanded,
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onOpen,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClose,
  });

  final bool expanded;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final VoidCallback onOpen;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedAlign(
          duration: ExpandablePlaceSearchState._animationDuration,
          curve: Curves.easeOutCubic,
          alignment: expanded ? Alignment.centerLeft : Alignment.center,
          child: AnimatedPadding(
            duration: ExpandablePlaceSearchState._animationDuration,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(left: expanded ? 14 : 0),
            child: const Icon(
              Icons.search_rounded,
              size: 22,
              color: Color(0xFF8EC5FF),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: expanded,
            child: Semantics(
              button: true,
              label: 'Open location search',
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onOpen),
              ),
            ),
          ),
        ),
        Positioned(
          left: 50,
          right: 48,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !expanded,
            child: ExcludeSemantics(
              excluding: !expanded,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: expanded ? 1 : 0,
                child: Center(
                  child: TextField(
                    key: const Key('place-search-field'),
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.search,
                    textAlignVertical: TextAlignVertical.center,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFFF1F5FF),
                      fontSize: 17,
                    ),
                    cursorColor: const Color(0xFF8EC5FF),
                    autocorrect: false,
                    enableSuggestions: true,
                    maxLength: 256,
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    decoration: const InputDecoration(
                      hintText: 'Search a place',
                      hintStyle: TextStyle(
                        color: Color(0xFFAAB7D4),
                        fontSize: 17,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 2,
          top: 2,
          bottom: 2,
          width: 48,
          child: IgnorePointer(
            ignoring: !expanded,
            child: ExcludeSemantics(
              excluding: !expanded,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: expanded ? 1 : 0,
                child: loading
                    ? Semantics(
                        label: 'Searching',
                        liveRegion: true,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF8EC5FF),
                            ),
                          ),
                        ),
                      )
                    : Semantics(
                        button: true,
                        label: 'Close location search',
                        child: IconButton(
                          key: const Key('close-place-search'),
                          tooltip: 'Close location search',
                          onPressed: onClose,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 21,
                            color: Color(0xFFC5CEE2),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({required this.suggestions, required this.onSelected});

  final List<PlaceSearchResult> suggestions;
  final ValueChanged<PlaceSearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('place-suggestion-panel'),
        constraints: const BoxConstraints(maxHeight: 240),
        decoration: BoxDecoration(
          color: const Color(0xF7101827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xCC2D4168)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: suggestions.length,
          separatorBuilder: (_, _) => const Divider(
            height: 1,
            thickness: 1,
            indent: 58,
            color: Color(0x332D4168),
          ),
          itemBuilder: (context, index) {
            final result = suggestions[index];
            return _SuggestionRow(
              key: Key('place-suggestion-$index'),
              result: result,
              onTap: () => onSelected(result),
            );
          },
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.result, required this.onTap, super.key});

  final PlaceSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      splashColor: const Color(0x1A8EC5FF),
      highlightColor: const Color(0x142D4168),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x262D6AA3),
                ),
                child: const Icon(
                  Icons.location_on_outlined,
                  size: 19,
                  color: Color(0xFF8EC5FF),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF1F5FF),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (result.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        result.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFAAB7D4),
                          fontSize: 13.5,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
