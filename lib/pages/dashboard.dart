import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskaty/pages/admin_page.dart';
import 'package:taskaty/pages/task_details_page.dart';

class DashboardPage extends StatefulWidget {
  static const route = '/admin/dashboard';
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, dynamic>> _allTasks = [];
  Map<String, Map<String, dynamic>> _usersCache = {};
  bool _isLoading = false;
  String _selectedFilter = 'الكل';

  @override
  void initState() {
    super.initState();
    _fetchAllTasks();
  }

  Future<void> _fetchAllTasks() async {
    setState(() => _isLoading = true);
    try {
      // Step 1: Fetch all tasks
      final tasksResponse = await Supabase.instance.client
          .from('tasks')
          .select('*')
          .order('created_at', ascending: false);

      if (tasksResponse == null) {
        setState(() {
          _allTasks = [];
          _isLoading = false;
        });
        return;
      }

      final tasks = List<Map<String, dynamic>>.from(tasksResponse);

      // Step 2: Fetch all task assignments
      final assignmentsResponse = await Supabase.instance.client
          .from('task_assignments')
          .select('*');

      final assignments = assignmentsResponse != null 
          ? List<Map<String, dynamic>>.from(assignmentsResponse)
          : <Map<String, dynamic>>[];

      // Step 3: Collect all unique user IDs
      Set<String> userIds = {};
      
      // Add creator IDs from tasks
      for (final task in tasks) {
        if (task['created_by'] != null) {
          userIds.add(task['created_by'].toString());
        }
      }
      
      // Add assignee IDs from assignments
      for (final assignment in assignments) {
        if (assignment['user_id'] != null) {
          userIds.add(assignment['user_id'].toString());
        }
      }

      // Step 4: Fetch all user profiles - Fixed column name from 'name' to 'full_name'
      _usersCache.clear();
      if (userIds.isNotEmpty) {
        final usersResponse = await Supabase.instance.client
            .from('profiles')
            .select('id, name, avatar_url')
            .inFilter('id', userIds.toList());

        if (usersResponse != null) {
          final users = List<Map<String, dynamic>>.from(usersResponse);
          for (final user in users) {
            _usersCache[user['id'].toString()] = user;
          }
        }
      }

      // Step 5: Match assignments to tasks and enrich with user data
      final enrichedTasks = tasks.map((task) {
        final taskId = task['id'];
        
        // Find assignments for this task
        final taskAssignments = assignments
            .where((assignment) => assignment['task_id'] == taskId)
            .map((assignment) {
              // Add user profile to assignment
              if (assignment['user_id'] != null) {
                assignment['assignee_profile'] = _usersCache[assignment['user_id'].toString()];
              }
              return assignment;
            }).toList();

        // Add assignments to task
        task['task_assignments'] = taskAssignments;

        // Add creator profile to task
        if (task['created_by'] != null) {
          task['creator_profile'] = _usersCache[task['created_by'].toString()];
        }

        return task;
      }).toList();

      if (mounted) {
        setState(() {
          _allTasks = enrichedTasks;
          debugPrint('Fetched Tasks with Users: ${_allTasks.length} tasks');
          debugPrint('Users Cache: ${_usersCache.keys.toList()}');
        });
      }
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب المهام: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateTaskStatus(int taskId, String status) async {
    try {
      // Find the assignment for this task
      final assignmentResponse = await Supabase.instance.client
          .from('task_assignments')
          .select()
          .eq('task_id', taskId)
          .single();

      if (assignmentResponse != null) {
        // Update the assignment status
        await Supabase.instance.client
            .from('task_assignments')
            .update({'status': status})
            .eq('id', assignmentResponse['id']);

        if (mounted) {
          _fetchAllTasks(); // Refresh tasks after update
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('تم تحديث حالة المهمة إلى: ${_getStatusText(status)}'),
              backgroundColor: _getStatusColor(status),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating task status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث حالة المهمة: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة المتابعة'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchAllTasks,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.of(context).pushNamed(AdminDashboard.route).then((_) {
              // Refresh tasks when returning from create task page
              _fetchAllTasks();
            });
          },
          icon: const Icon(Icons.add_task),
          label: const Text('إنشاء مهمة'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _allTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          size: 64,
                          color: colorScheme.primary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد مهام حالياً',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'قم بإنشاء مهمة جديدة باستخدام زر إنشاء مهمة',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildStatsCard(colorScheme, theme),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 400,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            mainAxisExtent: 200,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index >= _allTasks.length) return null;
                              return _buildTaskCard(
                                  _allTasks[index], colorScheme, theme);
                            },
                            childCount: _allTasks.length,
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildStatsCard(ColorScheme colorScheme, ThemeData theme) {
    // Update stats calculation to use task_assignments
    final completedTasks = _allTasks.where((task) {
      final assignments = task['task_assignments'] as List<dynamic>?;
      return assignments?.any((a) => a['status'] == 'completed') ?? false;
    }).length;

    final inProgressTasks = _allTasks.where((task) {
      final assignments = task['task_assignments'] as List<dynamic>?;
      return assignments?.any((a) => a['status'] == 'in_progress') ?? false;
    }).length;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              'إجمالي المهام',
              _allTasks.length.toString(),
              Icons.assignment,
              colorScheme.primary,
              theme,
            ),
            _buildStatItem(
              'قيد التنفيذ',
              inProgressTasks.toString(),
              Icons.pending_actions,
              colorScheme.secondary,
              theme,
            ),
            _buildStatItem(
              'مكتملة',
              completedTasks.toString(),
              Icons.task_alt,
              Colors.green,
              theme,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineSmall,
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildTaskCard(
      Map<String, dynamic> task, ColorScheme colorScheme, ThemeData theme) {
    final assignments = task['task_assignments'] as List<dynamic>?;
    final assignment =
        assignments?.isNotEmpty == true ? assignments?.elementAt(0) : null;
    final assigneeProfile = assignment?['assignee_profile'];
    final creatorProfile = task['creator_profile'];
    final status = assignment?['status'] ?? 'new';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TaskDetailsPage(
                task: task,
                assignment: assignment,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task['title'] ?? 'بدون عنوان',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildStatusChip(status, colorScheme),
                ],
              ),
              const SizedBox(height: 8),
              if (task['description'] != null) ...[
                Text(
                  task['description'],
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.8),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],
              const Spacer(),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _buildUserInfo(
                      'منشئ',
                      creatorProfile,
                      colorScheme,
                      theme,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildUserInfo(
                      'معين إلى',
                      assigneeProfile,
                      colorScheme,
                      theme,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTaskDetails(
      Map<String, dynamic> task, Map<String, dynamic>? assignment) {
    final currentStatus = assignment?['status'] ?? 'new';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Task Info Section
              Text(
                task['title'] ?? 'بدون عنوان',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                task['description'] ?? '',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),

              // Status Update Section
              Text(
                'تحديث الحالة',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final status in ['new', 'in_progress', 'completed'])
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        label: Text(_getStatusText(status)),
                        selected: currentStatus == status,
                        onSelected: (_) {
                          Navigator.pop(context);
                          _updateTaskStatus(task['id'], status);
                        },
                        labelStyle: TextStyle(
                          color: currentStatus == status
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        selectedColor: _getStatusColor(status).withOpacity(0.2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildUserInfo('منشئ', task['creator_profile'],
                      Theme.of(context).colorScheme, Theme.of(context)),
                  _buildUserInfo(
                      'معين إلى',
                      task['task_assignments']?[0]?['assignee_profile'],
                      Theme.of(context).colorScheme,
                      Theme.of(context)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'تاريخ الإنشاء: ${_formatDate(task['created_at'])}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      default:
        return Colors.grey;
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

  Widget _buildStatusChip(String? status, ColorScheme colorScheme) {
    Color color;
    String label;

    switch (status) {
      case 'completed':
        color = Colors.green;
        label = 'مكتملة';
        break;
      case 'in_progress':
        color = colorScheme.primary;
        label = 'قيد التنفيذ';
        break;
      default:
        color = Colors.grey;
        label = 'جديدة';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildUserInfo(String label, Map<String, dynamic>? user,
      ColorScheme colorScheme, ThemeData theme) {
    if (user == null) {
      return Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              color: colorScheme.onPrimaryContainer,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              Text(
                'غير محدد',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Fixed: Use _name' instead of 'name' to match the database schema
    final name = user['name']?.toString() ?? 'غير معروف';
    final avatarUrl = user['avatar_url']?.toString();

    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: colorScheme.primaryContainer,
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              Text(
                name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}