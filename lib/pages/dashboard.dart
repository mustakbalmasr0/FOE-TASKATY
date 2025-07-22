import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taskaty/pages/admin_page.dart';
import 'package:taskaty/pages/pdf_report_generator.dart';
import 'package:taskaty/pages/task_details_page.dart';
import 'package:taskaty/pages/modern_task_card.dart' as task_card;
import 'package:table_calendar/table_calendar.dart'; // Keep this import for isSameDay
import 'package:taskaty/pages/task_calendar.dart'; // Import your new calendar widget
import 'package:collection/collection.dart'; // **ADD THIS IMPORT**
import 'package:taskaty/pages/appbar_sidebar.dart'; // Import the new Sidebar widget

class DashboardPage extends StatefulWidget {
  static const route = '/admin/dashboard';
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _allTasks = [];
  Map<String, Map<String, dynamic>> _usersCache = {};
  bool _isLoading = false;
  String _selectedFilter = 'الكل';

  // Calendar related variables
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  late AnimationController _calendarAnimationController;
  late Animation<double> _calendarAnimation;

  // Task selection
  Set<int> _selectedTaskIds = {};

  List<Map<String, dynamic>> _filteredTasks = [];

  @override
  void initState() {
    super.initState();
    _fetchAllTasks();

    _calendarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _calendarAnimation = CurvedAnimation(
      parent: _calendarAnimationController,
      curve: Curves.easeInOut,
    );
    _calendarAnimationController.forward();
  }

  @override
  void dispose() {
    _calendarAnimationController.dispose();
    super.dispose();
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      if (isSameDay(_selectedDay, selectedDay)) {
        // If the same day is selected again, deselect it
        _selectedDay = null;
        _filteredTasks = _allTasks; // Show all tasks
      } else {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _filterTasksByDate(selectedDay);
      }
    });
  }

  void _filterTasksByDate(DateTime selectedDate) {
    final startOfDay =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    setState(() {
      _filteredTasks = _allTasks.where((task) {
        // Ensure 'created_at' is not null before parsing
        if (task['created_at'] == null) return false;
        final createdAt = DateTime.parse(task['created_at']);
        return createdAt.isAfter(startOfDay) && createdAt.isBefore(endOfDay);
      }).toList();
    });
  }

  List<Map<String, dynamic>> _getTasksForDay(DateTime day) {
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return _allTasks.where((task) {
      // Ensure 'created_at' is not null before parsing
      if (task['created_at'] == null) return false;
      final createdAt = DateTime.parse(task['created_at']);
      return createdAt.isAfter(startOfDay) && createdAt.isBefore(endOfDay);
    }).toList();
  }

  Future<void> _fetchAllTasks() async {
    setState(() => _isLoading = true);
    try {
      final tasksResponse = await Supabase.instance.client
          .from('tasks')
          .select('*')
          .order('created_at', ascending: false);

      if (tasksResponse == null) {
        setState(() {
          _allTasks = [];
          _filteredTasks = [];
          _isLoading = false;
        });
        return;
      }

      final tasks = List<Map<String, dynamic>>.from(tasksResponse);

      final assignmentsResponse =
          await Supabase.instance.client.from('task_assignments').select('*');

      final assignments = assignmentsResponse != null
          ? List<Map<String, dynamic>>.from(assignmentsResponse)
          : <Map<String, dynamic>>[];

      Set<String> userIds = {};
      for (final task in tasks) {
        if (task['created_by'] != null) {
          userIds.add(task['created_by'].toString());
        }
      }
      for (final assignment in assignments) {
        if (assignment['user_id'] != null) {
          userIds.add(assignment['user_id'].toString());
        }
      }

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

      final enrichedTasks = tasks.map((task) {
        final taskId = task['id'];
        final taskAssignments = assignments
            .where((assignment) => assignment['task_id'] == taskId)
            .map((assignment) {
          if (assignment['user_id'] != null) {
            assignment['assignee_profile'] =
                _usersCache[assignment['user_id'].toString()];
          }
          return assignment;
        }).toList();

        // Remove duplicate assignments for the same user
        final Map<String, Map<String, dynamic>> uniqueAssignments = {};
        for (final assignment in taskAssignments) {
          final userId = assignment['user_id']?.toString();
          if (userId != null) {
            if (!uniqueAssignments.containsKey(userId)) {
              uniqueAssignments[userId] = assignment;
            } else {
              // Keep the most recent assignment status
              final existingDate = DateTime.tryParse(
                  uniqueAssignments[userId]!['created_at'] ?? '');
              final currentDate =
                  DateTime.tryParse(assignment['created_at'] ?? '');

              if (currentDate != null &&
                  existingDate != null &&
                  currentDate.isAfter(existingDate)) {
                uniqueAssignments[userId] = assignment;
              }
            }
          }
        }

        task['task_assignments'] = uniqueAssignments.values.toList();
        if (task['created_by'] != null) {
          task['creator_profile'] = _usersCache[task['created_by'].toString()];
        }
        return task;
      }).toList();

      if (mounted) {
        setState(() {
          _allTasks = enrichedTasks;
          // Apply initial filter if a day is selected when refetching
          if (_selectedDay != null) {
            _filterTasksByDate(_selectedDay!);
          } else {
            _filteredTasks = enrichedTasks;
          }
          debugPrint('Fetched Tasks: ${_allTasks.length}');
        });
      }
    } catch (e) {
      debugPrint('Error fetching tasks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب المهام: $e'),
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
      final assignmentResponse = await Supabase.instance.client
          .from('task_assignments')
          .select()
          .eq('task_id', taskId)
          .single();

      if (assignmentResponse != null) {
        await Supabase.instance.client
            .from('task_assignments')
            .update({'status': status}).eq('id', assignmentResponse['id']);

        if (mounted) {
          _fetchAllTasks();
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
            content: Text('خطأ في تحديث حالة المهمة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _generatePdfReport() async {
    final selectedTasks = (_selectedDay != null ? _filteredTasks : _allTasks)
        .where((t) => _selectedTaskIds.contains(t['id']))
        .toList();

    if (selectedTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد المهام التي تريد تصديرها إلى PDF.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // `WidgetsFlutterBinding.ensureInitialized()` is typically called once at the very start of main()
    // and is not needed here.
    final pdfGenerator = PdfReportGenerator();
    await pdfGenerator.generateAndOpenPdf(selectedTasks);
  }

  // New method to show the calendar as a bottom sheet
  void _showCalendarBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows the bottom sheet to be full height
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8, // Start with 80% of the screen height
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false, // Set to false to allow initialChildSize to work
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'اختر تاريخًا',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: TaskCalendar(
                        focusedDay: _focusedDay,
                        selectedDay: _selectedDay,
                        calendarFormat: _calendarFormat,
                        onDaySelected: (day, focusedDay) {
                          _onDaySelected(day, focusedDay);
                          Navigator.pop(
                              context); // Close bottom sheet after selection
                        },
                        onFormatChanged: (format) {
                          setState(() {
                            _calendarFormat = format;
                          });
                        },
                        onPageChanged: (focusedDay) {
                          _focusedDay = focusedDay;
                        },
                        eventLoader: _getTasksForDay,
                        animation: _calendarAnimation,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // New method to handle select all functionality
  void _handleSelectAll() {
    final displayTasks = _selectedDay != null ? _filteredTasks : _allTasks;
    setState(() {
      if (_selectedTaskIds.length == displayTasks.length &&
          displayTasks.isNotEmpty) {
        _selectedTaskIds.clear();
      } else {
        _selectedTaskIds = displayTasks.map((t) => t['id'] as int).toSet();
      }
    });
  }

  // New method to handle show all tasks
  void _handleShowAllTasks() {
    setState(() {
      _selectedDay = null; // Clear the selected day
      _filteredTasks = _allTasks; // Show all tasks from the main list
    });
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    try {
      // Delete task assignments first (foreign key constraint)
      await Supabase.instance.client
          .from('task_assignments')
          .delete()
          .eq('task_id', task['id']);

      // Delete the task
      await Supabase.instance.client
          .from('tasks')
          .delete()
          .eq('id', task['id']);

      // Remove from local lists
      setState(() {
        _allTasks.removeWhere((t) => t['id'] == task['id']);
        _filteredTasks.removeWhere((t) => t['id'] == task['id']);
        _selectedTaskIds.remove(task['id']);
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف المهمة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting task: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في حذف المهمة: $e'),
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
    final displayTasks = _selectedDay != null ? _filteredTasks : _allTasks;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).pushNamed(AdminDashboard.route).then((_) {
                  _fetchAllTasks();
                });
              },
              icon: const Icon(Icons.add_task),
              label: const Text('إنشاء مهمة'),
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : CustomScrollView(
                    // Changed to CustomScrollView for overall scrolling
                    slivers: [
                      SliverToBoxAdapter(
                        child:
                            _buildStatsCard(colorScheme, theme, displayTasks),
                      ),
                      // The TaskCalendar widget is now opened via a button, so it's removed from here
                      if (displayTasks.isEmpty)
                        SliverToBoxAdapter(
                          child: Center(
                            child: Container(
                              margin: const EdgeInsets.all(32),
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _selectedDay != null
                                        ? Icons.event_busy
                                        : Icons.assignment_outlined,
                                    size: 64,
                                    color: colorScheme.primary.withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _selectedDay != null
                                        ? 'لا توجد مهام في هذا اليوم'
                                        : 'لا توجد مهام حالياً',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _selectedDay != null
                                        ? 'جرب اختيار يوم آخر من التقويم'
                                        : 'قم بإنشاء مهمة جديدة باستخدام زر إنشاء مهمة',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.textTheme.bodySmall?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 400,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              mainAxisExtent: 280,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index >= displayTasks.length) return null;
                                final task = displayTasks[index];
                                final isSelected =
                                    _selectedTaskIds.contains(task['id']);
                                return task_card.ModernTaskCard(
                                  task: task,
                                  isSelected: isSelected,
                                  onSelectionChanged: (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        _selectedTaskIds.add(task['id']);
                                      } else {
                                        _selectedTaskIds.remove(task['id']);
                                      }
                                    });
                                  },
                                  onTap: () {
                                    final assignments =
                                        task['task_assignments'];
                                    Map<String, dynamic>? assignment;

                                    if (assignments is List &&
                                        assignments.isNotEmpty) {
                                      // Explicitly cast to List<Map<String, dynamic>> for firstWhereOrNull
                                      final List<Map<String, dynamic>>
                                          typedAssignments =
                                          List<Map<String, dynamic>>.from(
                                              assignments);

                                      // Use firstWhereOrNull to find an 'in_progress' assignment
                                      assignment = typedAssignments
                                          .firstWhereOrNull((a) =>
                                              a['status'] == 'in_progress');

                                      // If no 'in_progress' assignment was found, use the first one
                                      if (assignment == null) {
                                        assignment = typedAssignments
                                            .firstOrNull; // Use firstOrNull for safety
                                      }
                                    }

                                    // Now, pass `assignment` (which can be null) to the details page
                                    Navigator.of(context)
                                        .push(
                                      MaterialPageRoute(
                                        builder: (context) => TaskDetailsPage(
                                          task: task,
                                          assignment:
                                              assignment, // This is now correctly typed as Map<String, dynamic>?
                                        ),
                                      ),
                                    )
                                        .then((_) {
                                      _fetchAllTasks();
                                    });
                                  },
                                  onDelete: _deleteTask,
                                  colorScheme: colorScheme,
                                  theme: theme,
                                );
                              },
                              childCount: displayTasks.length,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          // Add the sidebar overlay
          DashboardSidebar(
            onCalendarPressed: _showCalendarBottomSheet,
            onShowAllTasks: _handleShowAllTasks,
            onGeneratePdf: _generatePdfReport,
            onRefresh: _fetchAllTasks,
            onSelectAll: _handleSelectAll,
            isAllSelected: _selectedTaskIds.length == displayTasks.length,
            selectedCount: _selectedTaskIds.length,
            totalTasks: displayTasks.length,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color, ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCard(ColorScheme colorScheme, ThemeData theme,
      List<Map<String, dynamic>> tasks) {
    final completedTasks = tasks.where((task) {
      final assignments = task['task_assignments'] as List<dynamic>?;
      return assignments?.any(
              (a) => (a as Map<String, dynamic>)['status'] == 'completed') ??
          false;
    }).length;

    final inProgressTasks = tasks.where((task) {
      final assignments = task['task_assignments'] as List<dynamic>?;
      return assignments?.any(
              (a) => (a as Map<String, dynamic>)['status'] == 'in_progress') ??
          false;
    }).length;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.surface,
              colorScheme.surface.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Show date if a day is selected (now that calendar is always visible)
              if (_selectedDay != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'مهام يوم ${_formatDate(_selectedDay.toString())}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    'إجمالي المهام',
                    tasks.length.toString(),
                    Icons.assignment,
                    colorScheme.primary,
                    theme,
                  ),
                  _buildStatItem(
                    'جاري التنفيذ',
                    inProgressTasks.toString(),
                    Icons.pending_actions,
                    colorScheme.secondary,
                    theme,
                  ),
                  _buildStatItem(
                    'تم التنفيذ',
                    completedTasks.toString(),
                    Icons.task_alt,
                    Colors.green,
                    theme,
                  ),
                ],
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
        return 'تم التنفيذ';
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

