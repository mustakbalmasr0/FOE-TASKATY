import 'package:flutter/material.dart';

class ModernTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final bool isSelected;
  final Function(bool?) onSelectionChanged;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const ModernTaskCard({
    Key? key,
    required this.task,
    required this.isSelected,
    required this.onSelectionChanged,
    required this.onTap,
    required this.colorScheme,
    required this.theme,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final assignments = task['task_assignments'] as List<dynamic>?;
    final assignment = assignments?.isNotEmpty == true ? assignments?.elementAt(0) : null;
    final assigneeProfile = assignment?['assignee_profile'];
    final creatorProfile = task['creator_profile'];
    final status = assignment?['status'] ?? 'new';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);

    return Container(
      margin: const EdgeInsets.all(4),
      child: Material(
        elevation: 0,
        borderRadius: BorderRadius.circular(20),
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surface,
                colorScheme.surface.withOpacity(0.8),
              ],
            ),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withOpacity(0.5)
                  : colorScheme.outline.withOpacity(0.2),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
              if (isSelected)
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                splashColor: colorScheme.primary.withOpacity(0.1),
                highlightColor: colorScheme.primary.withOpacity(0.05),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  // This is the Column at line 78, causing vertical overflow.
                  // By wrapping its direct children in Expanded/Flexible, we manage space.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with checkbox and status
                      // This Row is generally well-constrained horizontally.
                      Row(
                        children: [
                          _buildModernCheckbox(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task['title'] ?? 'بدون عنوان',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(task['created_at']),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildModernStatusChip(status, statusColor, statusText),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Description (POTENTIAL CAUSE OF VERTICAL OVERFLOW)
                      // If the description can be long, it needs to be constrained.
                      if (task['description'] != null)
                        // Use Flexible instead of a fixed height Container for the description.
                        // This allows it to take available space but respects column limits.
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceVariant.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              task['description'],
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.8),
                                height: 1.4,
                              ),
                              maxLines: 2, // Keep maxLines to prevent excessive growth
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      // Add SizedBox only if description exists to avoid extra space
                      if (task['description'] != null) const SizedBox(height: 16),

                      // Spacer to push users to bottom (This is the culprit with fixed content!)
                      // Remove Spacer() if you want content to fill naturally.
                      // If you *must* use a Spacer, ensure the parent Column has enough space.
                      // For a grid-based card where cards have a fixed height, Spacer often causes issues.
                      // Consider removing it and letting content flow, or making the card taller.
                      // For now, let's remove it as it's the simplest fix for a small overflow.
                      // const Spacer(), // Removed this to resolve the 6.0 pixel overflow

                      // Users section (These are likely the source of the horizontal overflow if names are long)
                      // This Container and its internal Row should manage their children's width.
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.primaryContainer.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Wrap _buildModernUserInfo in Expanded to share horizontal space.
                            // Each _buildModernUserInfo is already correctly using Expanded internally.
                            Expanded(
                              child: _buildModernUserInfo(
                                'منشئ',
                                creatorProfile,
                                Icons.person_add,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: colorScheme.outline.withOpacity(0.3),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildModernUserInfo(
                                'معين إلى',
                                assigneeProfile,
                                Icons.assignment_ind,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets (No major changes needed here, as Expanded is already used) ---

  Widget _buildModernCheckbox() {
    return GestureDetector(
      onTap: () => onSelectionChanged(!isSelected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                color: colorScheme.onPrimary,
                size: 16,
              )
            : null,
      ),
    );
  }

  Widget _buildModernStatusChip(String status, Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // The _buildModernUserInfo method is well-structured regarding Expansions
  Widget _buildModernUserInfo(String label, Map<String, dynamic>? user, IconData icon) {
    final name = user?['name']?.toString() ?? 'غير محدد';
    final avatarUrl = user?['avatar_url']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.primaryContainer.withOpacity(0.7),
                  ],
                ),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildAvatarFallback(name);
                        },
                      ),
                    )
                  : _buildAvatarFallback(name),
            ),
            const SizedBox(width: 8),
            Expanded( // This Expanded is crucial for names that are too long
              child: Text(
                name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatarFallback(String name) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer,
            colorScheme.primaryContainer.withOpacity(0.7),
          ],
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'completed':
        return 'مكتملة';
      case 'in_progress':
        return 'قيد التنفيذ';
      default:
        return 'جديدة';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF4CAF50);
      case 'in_progress':
        return const Color(0xFF2196F3);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'غير محدد';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'تاريخ غير صالح';
    }
  }
}