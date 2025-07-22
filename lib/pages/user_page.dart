import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = false;
  String _selectedFilter = 'الكل';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _taskAttachments = [];

  final List<String> _filterOptions = [
    'الكل',
    'جديدة',
    'قيد التنفيذ',
    'تم التفيذ'
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    // Call fetchTasks after the widget is properly mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTasks();
      _fetchUserProfile();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchTasks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      // Use DISTINCT to prevent duplicate tasks and group by task_id
      final response =
          await Supabase.instance.client.from('task_assignments').select('''
            id,
            status,
            created_at,
            end_at,
            task_id,
            task:tasks (
              id,
              title,
              description,
              priority,
              created_at,
              end_at,
              creator:profiles!created_by (
                name,
                avatar_url
              )
            )
          ''').eq('user_id', userId).order('created_at', ascending: false);

      if (!mounted) return;

      // Process the response to remove duplicate tasks
      final Map<int, Map<String, dynamic>> uniqueTasks = {};

      for (final assignment in response) {
        final taskData = assignment['task'] as Map<String, dynamic>?;
        if (taskData != null) {
          final taskId = taskData['id'] as int;

          // If we haven't seen this task before, or if this assignment has a more recent status
          if (!uniqueTasks.containsKey(taskId)) {
            uniqueTasks[taskId] = assignment;
          } else {
            // Keep the assignment with the most recent status update
            final existingAssignment = uniqueTasks[taskId]!;
            final existingDate =
                DateTime.tryParse(existingAssignment['created_at'] ?? '');
            final currentDate =
                DateTime.tryParse(assignment['created_at'] ?? '');

            if (currentDate != null &&
                existingDate != null &&
                currentDate.isAfter(existingDate)) {
              uniqueTasks[taskId] = assignment;
            }
          }
        }
      }

      setState(() {
        _tasks = uniqueTasks.values.toList();
      });
      _animationController.forward();
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      if (!mounted) return;
      if (_tasks.isNotEmpty) {
        _showSnackBar('خطأ في جلب المهام: ${e.toString()}', isError: true);
      }
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchUserProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final response = await Supabase.instance.client
          .from('profiles')
          .select('name, avatar_url')
          .eq('id', userId)
          .single();

      if (mounted && response != null) {
        setState(() {
          _userProfile = response;
        });
      }
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
    }
  }

  Future<void> _fetchTaskAttachments(dynamic taskId) async {
    try {
      // Convert taskId to integer since that's what the database expects
      final int parsedTaskId =
          taskId is String ? int.parse(taskId) : taskId as int;

      final response = await Supabase.instance.client
          .from('task_attachments')
          .select()
          .eq('task_id', parsedTaskId);

      if (mounted) {
        setState(() {
          _taskAttachments = List<Map<String, dynamic>>.from(response);
        });
      }

      debugPrint('Fetched attachments: $_taskAttachments'); // Debug log
    } catch (e) {
      debugPrint('Error loading attachments: $e');
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          textDirection: TextDirection.rtl,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _getTaskPriority(int index) {
    final priorities = ['عالية', 'متوسطة', 'منخفضة'];
    return priorities[index % 3];
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'عالية':
        return Colors.red;
      case 'متوسطة':
        return Colors.orange;
      case 'منخفضة':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority) {
      case 'عالية':
        return Icons.priority_high;
      case 'متوسطة':
        return Icons.remove;
      case 'منخفضة':
        return Icons.keyboard_arrow_down;
      default:
        return Icons.help_outline;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return 'قيد الانتظار';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'completed':
        return 'تم التنفيذ';
      default:
        return 'جديدة';
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Icons.pending_actions;
      case 'in_progress':
        return Icons.running_with_errors;
      case 'completed':
        return Icons.task_alt;
      default:
        return Icons.fiber_new;
    }
  }

  String _formatArabicDate(String? dateStr) {
    if (dateStr == null) return 'تاريخ غير معروف';
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final difference = now.difference(date);

    final List<String> arabicMonths = [
      'يناير',
      'فبراير',
      'مارس',
      'إبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];

    final List<String> arabicDays = [
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت'
    ];

    if (difference.inDays == 0) {
      return 'اليوم';
    } else if (difference.inDays == 1) {
      return 'أمس';
    } else if (difference.inDays < 7) {
      return 'قبل ${difference.inDays} أيام';
    } else {
      final dayName = arabicDays[date.weekday % 7];
      final monthName = arabicMonths[date.month - 1];
      return '$dayName، ${date.day} $monthName ${date.year}';
    }
  }

  IconData _getFileIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      case 'doc':
      case 'docx':
        return Icons.document_scanner;
      default:
        return Icons.insert_drive_file;
    }
  }

  Future<void> _downloadFile(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url))) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('خطأ في فتح الملف: ${e.toString()}', isError: true);
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
        backgroundColor: colorScheme.surface,
        body: CustomScrollView(
          slivers: [
            // Modern App Bar
            SliverAppBar(
              expandedHeight: 200,
              floating: false,
              pinned: true,
              elevation: 0,
              backgroundColor: colorScheme.primary,
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (mounted) {
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/', (route) => false);
                    }
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background image (same as in task_details_page.dart)
                    Image.asset(
                      'assets/background.jpg',
                      fit: BoxFit.cover,
                    ),
                    // Gradient overlay and content
                    /*
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colorScheme.primary.withOpacity(0.85),
                            colorScheme.primary.withOpacity(0.7),
                            colorScheme.secondary.withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),
                    */
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor:
                                      Colors.white.withOpacity(0.2),
                                  backgroundImage:
                                      _userProfile?['avatar_url'] != null
                                          ? NetworkImage(
                                              _userProfile!['avatar_url'])
                                          : null,
                                  child: _userProfile?['avatar_url'] == null
                                      ? Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: 28,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'مرحباً${_userProfile?['name'] != null ? ' ${_userProfile!['name']}' : ''}',
                                        style:
                                            theme.textTheme.bodyLarge?.copyWith(
                                          color: Colors.white.withOpacity(0.9),
                                        ),
                                      ),
                                      Text(
                                        'مهامك المعيّنة',
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    _fetchTasks();
                                    _fetchUserProfile();
                                  },
                                  icon: const Icon(
                                    Icons.refresh,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Stats Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildStatsSection(colorScheme, theme),
              ),
            ),

            // Filter Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildFilterSection(colorScheme, theme),
              ),
            ),

            // Tasks List
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('جاري تحميل المهام...'),
                        ],
                      ),
                    ),
                  )
                : _tasks.isEmpty
                    ? SliverFillRemaining(
                        child: _buildEmptyState(colorScheme, theme),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final task = _tasks[index];
                            return FadeTransition(
                              opacity: _fadeAnimation,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 8.0,
                                ),
                                child: _buildTaskCard(
                                  task,
                                  index,
                                  colorScheme,
                                  theme,
                                ),
                              ),
                            );
                          },
                          childCount: _tasks.length,
                        ),
                      ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _fetchTasks,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          icon: const Icon(Icons.refresh),
          label: const Text('تحديث'),
        ),
      ),
    );
  }

  Widget _buildStatsSection(ColorScheme colorScheme, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'إجمالي المهام',
            value: '${_tasks.length}',
            icon: Icons.assignment,
            color: colorScheme.primary,
            colorScheme: colorScheme,
            theme: theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'قيد التنفيذ',
            value: '${(_tasks.length * 0.6).round()}',
            icon: Icons.schedule,
            color: colorScheme.secondary,
            colorScheme: colorScheme,
            theme: theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'تم التفيذ',
            value: '${(_tasks.length * 0.3).round()}',
            icon: Icons.check_circle,
            color: Colors.green,
            colorScheme: colorScheme,
            theme: theme,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(
            _filterOptions.length,
            (index) {
              final filter = _filterOptions[index];
              final isSelected = _selectedFilter == filter;

              return Container(
                margin: const EdgeInsets.only(left: 8),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(filter),
                  onSelected: (selected) {
                    setState(() {
                      _selectedFilter = selected ? filter : 'الكل';
                    });
                  },
                  backgroundColor: colorScheme.surfaceContainer,
                  selectedColor: colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(
    Map<String, dynamic> assignment,
    int index,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final task = assignment['task'] as Map<String, dynamic>;
    final status = assignment['status'] ?? 'new';
    final statusColor = _getStatusColor(status);
    final creator = task['creator'] as Map<String, dynamic>;
    final priority = task['priority'] ?? 'عادي';

    // Filter tasks based on selected filter
    if (_selectedFilter != 'الكل') {
      final arabicStatus = _getStatusText(status);
      if (arabicStatus != _selectedFilter) {
        return const SizedBox.shrink();
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shadowColor: statusColor.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showTaskDetails(
              assignment, status, priority, colorScheme, theme),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.surface,
                  colorScheme.surface,
                  statusColor.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getStatusIcon(status),
                          color: statusColor,
                          size: 24,
                        ),
                      ),
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
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'بواسطة: ${creator['name'] ?? 'غير معروف'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getPriorityColor(priority).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          priority,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _getPriorityColor(priority),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (task['description'] != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        task['description'],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.8),
                          height: 1.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  // --- Timer and End Date Section ---
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      DateTime? endDate;
                      if (task['end_at'] != null) {
                        endDate = DateTime.tryParse(task['end_at']);
                      }
                      String timerText = 'غير محدد';
                      if (endDate != null) {
                        final now = DateTime.now();
                        final diff = endDate.difference(now);
                        if (diff.isNegative) {
                          timerText = 'انتهت المهمة';
                        } else if (diff.inDays > 0) {
                          timerText = 'متبقي ${diff.inDays} يوم';
                        } else if (diff.inHours > 0) {
                          timerText = 'متبقي ${diff.inHours} ساعة';
                        } else if (diff.inMinutes > 0) {
                          timerText = 'متبقي ${diff.inMinutes} دقيقة';
                        } else {
                          timerText = 'ينتهي قريباً';
                        }
                      }
                      return Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              color: colorScheme.primary, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            timerText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.event, color: colorScheme.error, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'تاريخ الانتهاء: ${_formatArabicDate(task['end_at'])}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  // --- End Timer and Date Section ---
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainer
                                    .withOpacity(0.5),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.outline.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    size: 14,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatArabicDate(task['created_at']),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            fit: FlexFit.loose,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    colorScheme.errorContainer.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: colorScheme.error.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.event_busy_outlined,
                                    size: 14,
                                    color: colorScheme.error,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'ينتهي: ${_formatArabicDate(task['end_at'])}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.error,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'تاريخ غير معروف';
    final date = DateTime.parse(dateStr);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'اليوم';
    } else if (difference.inDays == 1) {
      return 'البارحة';
    } else if (difference.inDays < 7) {
      return 'قبل ${difference.inDays} أيام';
    } else {
      return '${date.year}-${date.month}-${date.day}';
    }
  }

  Widget _buildEmptyState(ColorScheme colorScheme, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 80,
            color: colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'لا توجد مهام معيّنة',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ستظهر المهام المعيّنة إليك هنا',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _fetchTasks,
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTaskDetails(
    Map<String, dynamic> assignment,
    String status,
    String priority,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    // Clear previous attachments
    setState(() => _taskAttachments.clear());

    // Access task data from the assignment
    final task = assignment['task'] as Map<String, dynamic>;
    final taskId = task['id'];

    if (taskId != null) {
      _fetchTaskAttachments(taskId).then((_) {
        if (!mounted) return;

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => StatefulBuilder(
            builder: (context, setModalState) => Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                padding: EdgeInsets.only(
                  top: 24,
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colorScheme.onSurface.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Title and Priority
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color:
                                  _getPriorityColor(priority).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _getPriorityIcon(priority),
                              color: _getPriorityColor(priority),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  task['title'] ?? r'مهمة بدون عنوان',
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getPriorityColor(priority)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    r'أولوية $priority',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _getPriorityColor(priority),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Description
                      if (assignment['task']['description'] != null &&
                          assignment['task']['description'].isNotEmpty) ...[
                        Text(
                          r'الوصف',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            assignment['task']['description'],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Attachments
                      Text(
                        r'المرفقات',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Display attachments
                      if (_taskAttachments.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(r'لا توجد مرفقات'),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _taskAttachments.length,
                          itemBuilder: (context, index) {
                            final attachment = _taskAttachments[index];
                            return Card(
                              child: ListTile(
                                leading:
                                    Icon(_getFileIcon(attachment['file_type'])),
                                title: Text(attachment['file_name']),
                                trailing: IconButton(
                                  icon: const Icon(Icons.download),
                                  onPressed: () =>
                                      _downloadFile(attachment['file_url']),
                                ),
                              ),
                            );
                          },
                        ),

                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text(r'إغلاق'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _showSnackBar(r'تم تحديث حالة المهمة',
                                    isError: false);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                              ),
                              child: const Text(r'تحديث الحالة'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      });
    }
  }
}
