import 'package:flutter/material.dart';

class EntityTile extends StatelessWidget {
  const EntityTile({
    super.key,
    required this.icon,
    required this.name,
    this.colorHex,
    this.subtitle,
    this.isDefault = false,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
    this.onSetDefault,
    this.onClearDefault,
  });

  final String icon;
  final String name;
  final String? colorHex;
  final String? subtitle;
  final bool isDefault;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onSetDefault;
  final VoidCallback? onClearDefault;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 20)),
            ),
          ),
          if (colorHex != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _hexToColor(colorHex!),
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(name, style: Theme.of(context).textTheme.bodyLarge),
          ),
          if (isDefault) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Default',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: Theme.of(context).textTheme.bodySmall)
          : null,
      trailing: PopupMenuButton<_Action>(
        icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
        onSelected: (action) {
          switch (action) {
            case _Action.edit:
              onEdit();
            case _Action.setDefault:
              onSetDefault?.call();
            case _Action.clearDefault:
              onClearDefault?.call();
            case _Action.archive:
              onArchive();
            case _Action.delete:
              onDelete();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: _Action.edit, child: Text('Edit')),
          if (!isDefault && onSetDefault != null)
            const PopupMenuItem(
                value: _Action.setDefault, child: Text('Set as default')),
          if (isDefault && onClearDefault != null)
            const PopupMenuItem(
                value: _Action.clearDefault, child: Text('Remove default')),
          const PopupMenuItem(value: _Action.archive, child: Text('Archive')),
          PopupMenuItem(
            value: _Action.delete,
            child: Text('Delete', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
    );
  }
}

enum _Action { edit, setDefault, clearDefault, archive, delete }

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}
