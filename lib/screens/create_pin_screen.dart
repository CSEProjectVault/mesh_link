import 'package:flutter/material.dart';
import '../models/pin_models.dart';

/// Screen for composing a new emergency report Pin.
///
/// UI-prototype sprint: state is held locally in this widget. On submit
/// we build a hardcoded [Pin] (fake GPS coords, fake author) and pop it
/// back to the caller. Once local storage + CRDT are wired up, submit
/// will instead write through the merge engine and let sync layers
/// propagate it.
class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({super.key});

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  Severity? _selectedSeverity;
  PinCategory? _selectedCategory;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selectedSeverity != null &&
      _selectedCategory != null &&
      _titleController.text.trim().isNotEmpty;

  void _handleSubmit() {
    if (!_formKey.currentState!.validate() || !_canSubmit) {
      if (_selectedSeverity == null || _selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a severity and category to continue.'),
          ),
        );
      }
      return;
    }

    setState(() => _submitting = true);

    // Hardcoded placeholder — real GPS + device identity land with the
    // storage/CRDT milestone.
    final pin = Pin(
      id: 'pin_${DateTime.now().millisecondsSinceEpoch}',
      lat: 46.8523,
      lng: -121.7603,
      severity: _selectedSeverity!,
      category: _selectedCategory!,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      authorName: 'You',
      createdAt: DateTime.now(),
    );

    // Simulate a brief local-write delay so the submit state is visible.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      Navigator.of(context).pop(pin);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Report'),
        actions: [
          TextButton(
            onPressed: _canSubmit && !_submitting ? _handleSubmit : null,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Post'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _SectionLabel('Severity'),
            const SizedBox(height: 10),
            _SeverityPicker(
              selected: _selectedSeverity,
              onSelected: (s) => setState(() => _selectedSeverity = s),
            ),
            const SizedBox(height: 28),
            _SectionLabel('Category'),
            const SizedBox(height: 10),
            _CategorySelector(
              selected: _selectedCategory,
              onSelected: (c) => setState(() => _selectedCategory = c),
            ),
            const SizedBox(height: 28),
            _SectionLabel('Details'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Short summary, e.g. "Blocked trail, fallen tree"',
                border: OutlineInputBorder(),
              ),
              maxLength: 80,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'A title is required'
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What is happening, exact location details, '
                    'who is affected, what help is needed…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              minLines: 4,
              maxLines: 8,
              maxLength: 500,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Current location will be attached automatically',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _canSubmit && !_submitting ? _handleSubmit : null,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Post Report'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            letterSpacing: 1.1,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

/// Row of severity cards. Deliberately larger tap targets than a plain
/// chip row — severity is the single most important field on a report
/// and should be hard to misselect under stress.
class _SeverityPicker extends StatelessWidget {
  final Severity? selected;
  final ValueChanged<Severity> onSelected;

  const _SeverityPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: Severity.values.map((s) {
        final isSelected = selected == s;
        return _SelectableCard(
          isSelected: isSelected,
          accentColor: s.color,
          onTap: () => onSelected(s),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(s.icon, size: 20, color: s.color),
              const SizedBox(width: 8),
              Text(
                s.label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Grid of category cards with icon + label.
class _CategorySelector extends StatelessWidget {
  final PinCategory? selected;
  final ValueChanged<PinCategory> onSelected;

  const _CategorySelector({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: PinCategory.values.map((c) {
        final isSelected = selected == c;
        return _SelectableCard(
          isSelected: isSelected,
          accentColor: theme.colorScheme.primary,
          onTap: () => onSelected(c),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                c.icon,
                size: 20,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                c.label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Shared selectable-card visual used by both pickers: outlined by
/// default, filled + accent-colored border when selected.
class _SelectableCard extends StatelessWidget {
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;
  final Widget child;

  const _SelectableCard({
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isSelected
          ? accentColor.withValues(alpha: 0.14)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : theme.colorScheme.outlineVariant,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}
