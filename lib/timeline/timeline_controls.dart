import 'package:flutter/material.dart';

import 'timeline_controller.dart';

class TimelineControls extends StatelessWidget {
  const TimelineControls({super.key, required this.controller});

  final TimelineController controller;

  Future<void> _pickDate(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: controller.selection.ist,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selected != null) {
      await controller.select(controller.selection.withDate(selected));
    }
  }

  Future<void> _pickTime(BuildContext context) async {
    final selected = await showModalBottomSheet<_Slot>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: 360,
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.8,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: 96,
            itemBuilder: (context, index) {
              final slot = _Slot(index ~/ 4, (index % 4) * 15);
              return TextButton(
                onPressed: () => Navigator.pop(context, slot),
                child: Text(slot.label),
              );
            },
          ),
        ),
      ),
    );
    if (selected != null) {
      await controller.select(
        controller.selection.withTime(
          hour: selected.hour,
          minute: selected.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xE6111827),
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: () => _pickDate(context),
            icon: const Icon(Icons.calendar_month, size: 18),
            label: Text(controller.selection.displayDate),
          ),
          Container(width: 1, height: 26, color: Colors.white12),
          TextButton.icon(
            onPressed: () => _pickTime(context),
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(controller.selection.displayTime),
          ),
          IconButton(
            tooltip: 'Refresh timeline',
            onPressed: controller.isLoading ? null : controller.load,
            icon: controller.isLoading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 19),
          ),
        ],
      ),
    );
  }
}

class _Slot {
  const _Slot(this.hour, this.minute);
  final int hour;
  final int minute;

  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
