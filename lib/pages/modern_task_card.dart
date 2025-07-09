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
    final assignment =
        assignments?.isNotEmpty == true ? assignments?.elementAt(0) : null;
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with checkbox and status
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
                                    color:
                                        colorScheme.onSurface.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildModernStatusChip(
                              status, statusColor, statusText),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Description
                      if (task['description'] != null) ...[
                        Container(
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Users section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                colorScheme.primaryContainer.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.assignment_ind,
                                          size: 14, color: colorScheme.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'معين إلى',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (assignments != null &&
                                      assignments.isNotEmpty)
                                    assignments.length > 1
                                        ? SizedBox(
                                            height:
                                                56, // Adjust as needed for max visible users
                                            child: ListView.builder(
                                              itemCount: assignments.length,
                                              itemBuilder: (context, idx) {
                                                final assignee =
                                                    assignments[idx]
                                                        ['assignee_profile'];
                                                final name = assignee?['name']
                                                        ?.toString() ??
                                                    'غير محدد';
                                                final avatarUrl =
                                                    assignee?['avatar_url']
                                                        ?.toString();
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 8.0),
                                                  child: Row(
                                                    children: [
                                                      CircleAvatar(
                                                        radius: 16,
                                                        backgroundColor:
                                                            colorScheme
                                                                .primaryContainer
                                                                .withOpacity(
                                                                    0.7),
                                                        backgroundImage:
                                                            avatarUrl != null &&
                                                                    avatarUrl
                                                                        .isNotEmpty
                                                                ? NetworkImage(
                                                                    avatarUrl)
                                                                : null,
                                                        child: avatarUrl ==
                                                                    null ||
                                                                avatarUrl
                                                                    .isEmpty
                                                            ? Text(
                                                                name.isNotEmpty
                                                                    ? name[0]
                                                                        .toUpperCase()
                                                                    : '?',
                                                                style:
                                                                    TextStyle(
                                                                  color: colorScheme
                                                                      .onPrimaryContainer,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 12,
                                                                ),
                                                              )
                                                            : null,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          name,
                                                          style: theme.textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color: colorScheme
                                                                .onSurface,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                        : Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 16,
                                                backgroundColor: colorScheme
                                                    .primaryContainer
                                                    .withOpacity(0.7),
                                                backgroundImage: assignments[0][
                                                                    'assignee_profile']
                                                                ?[
                                                                'avatar_url'] !=
                                                            null &&
                                                        assignments[0][
                                                                    'assignee_profile']
                                                                ?['avatar_url']
                                                            .isNotEmpty
                                                    ? NetworkImage(assignments[
                                                                0]
                                                            ['assignee_profile']
                                                        ['avatar_url'])
                                                    : null,
                                                child: assignments[0][
                                                                    'assignee_profile']
                                                                ?[
                                                                'avatar_url'] ==
                                                            null ||
                                                        assignments[0][
                                                                    'assignee_profile']
                                                                ?['avatar_url']
                                                            .isEmpty
                                                    ? Text(
                                                        (assignments[0]['assignee_profile']
                                                                        ?[
                                                                        'name']
                                                                    ?.isNotEmpty ??
                                                                false)
                                                            ? assignments[0][
                                                                        'assignee_profile']
                                                                    ['name'][0]
                                                                .toUpperCase()
                                                            : '?',
                                                        style: TextStyle(
                                                          color: colorScheme
                                                              .onPrimaryContainer,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 12,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  assignments[0]['assignee_profile']
                                                              ?['name']
                                                          ?.toString() ??
                                                      'غير محدد',
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w500,
                                                    color:
                                                        colorScheme.onSurface,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          )
                                  else
                                    Text(
                                      'غير محدد',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurface
                                            .withOpacity(0.7),
                                      ),
                                    ),
                                ],
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

  Widget _buildModernUserInfo(
      String label, Map<String, dynamic>? user, IconData icon) {
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
            Expanded(
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
