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
  State<ExpandablePlaceSearch> createState() => _ExpandablePlaceSearchState();
}

class _ExpandablePlaceSearchState extends State<ExpandablePlaceSearch> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ExpandablePlaceSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onControllerChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.controller.expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else {
      _focusNode.unfocus();
    }
  }

  Future<void> _submit(String value) async {
    final result = await widget.controller.submit(value);
    if (!mounted || result == null) return;
    _focusNode.unfocus();
    widget.onSelected(result);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expanded = widget.controller.expanded;
    final availableWidth = MediaQuery.sizeOf(context).width - 24;
    final expandedWidth = availableWidth.clamp(220.0, 310.0);
    return AnimatedContainer(
      key: const Key('place-search-container'),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      width: expanded ? expandedWidth : 48,
      constraints: const BoxConstraints(maxWidth: 340),
      decoration: BoxDecoration(
        color: const Color(0xE6141B2B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x526B8CC7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: expanded ? _expandedContent() : _searchButton(),
      ),
    );
  }

  Widget _searchButton() {
    return IconButton(
      key: const Key('open-place-search'),
      tooltip: 'Search for a place',
      onPressed: widget.controller.toggle,
      icon: const Icon(Icons.search_rounded, color: Color(0xFFE7EEFF)),
    );
  }

  Widget _expandedContent() {
    final message = widget.controller.message;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 48,
          child: Stack(
            children: [
              const Positioned(
                left: 14,
                top: 0,
                bottom: 0,
                child: Icon(
                  Icons.travel_explore_rounded,
                  size: 20,
                  color: Color(0xFF93C5FD),
                ),
              ),
              Positioned(
                left: 44,
                right: 46,
                top: 0,
                bottom: 0,
                child: TextField(
                  key: const Key('place-search-field'),
                  controller: _textController,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.search,
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
                  onSubmitted: _submit,
                  decoration: const InputDecoration(
                    hintText: 'Search a place',
                    hintStyle: TextStyle(color: Color(0xFF8D99AE)),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 46,
                child: widget.controller.loading
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        key: const Key('close-place-search'),
                        tooltip: 'Close search',
                        onPressed: widget.controller.toggle,
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
              ),
            ],
          ),
        ),
        if (message != null)
          Container(
            key: const Key('place-search-message'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 11),
            decoration: const BoxDecoration(
              color: Color(0x99101927),
              border: Border(top: BorderSide(color: Color(0x334B6B9C))),
            ),
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFFC7D2E8)),
            ),
          ),
      ],
    );
  }
}
