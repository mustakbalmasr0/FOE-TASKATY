import 'package:flutter/material.dart';

class TaskDetailsPage extends StatelessWidget {
  final Map<String, dynamic> task;
  final Map<String, dynamic>? assignment;

  const TaskDetailsPage({
    super.key,
    required this.task,
    this.assignment,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = assignment?['status'] ?? 'new';
    final creatorProfile = task['creator_profile'];
    final assigneeProfile = assignment?['assignee_profile'];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primary,
                      colorScheme.secondary,
                    ],
                  ),
                ),
              ),
              title: Text(
                task['title'] ?? 'بدون عنوان',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _getStatusIcon(status),
                              color: _getStatusColor(status),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'حالة المهمة',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                _getStatusText(status),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: _getStatusColor(status),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Description Section
                  Text(
                    'الوصف',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      task['description'] ?? 'لا يوجد وصف',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Assignment Info
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          context,
                          'منشئ المهمة',
                          creatorProfile,
                          Icons.person_outline,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildInfoCard(
                          context,
                          'معين إلى',
                          assigneeProfile,
                          Icons.assignment_ind_outlined,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Timeline
                  _buildTimeline(context, task['created_at']),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String title,
      Map<String, dynamic>? user, IconData icon) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            if (user != null) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: user['avatar_url'] != null
                        ? NetworkImage(user['avatar_url'])
                        : null,
                    child: user['avatar_url'] == null
                        ? Text(user['name']?[0].toUpperCase() ?? '?')
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      user['name'] ?? 'غير معروف',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                'غير محدد',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, String? createdAt) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الجدول الزمني', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.calendar_today, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('تم الإنشاء في: ${_formatDate(createdAt ?? '')}'),
              ],
            ),
          ],
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
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'in_progress':
        return Icons.pending;
      default:
        return Icons.fiber_new;
    }
  }

  String _formatDate(String dateString) {
    final date = DateTime.parse(dateString).toLocal();
    return '${date.year}-${date.month}-${date.day}';
  }
}
