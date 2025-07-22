import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class UserTaskDetailsSheet extends StatefulWidget {
  final Map<String, dynamic> assignment;
  final Function(int taskId, int assignmentId, String newStatus) onStatusUpdate;
  final Function(String message, {required bool isError}) onShowSnackBar;

  const UserTaskDetailsSheet({
    super.key,
    required this.assignment,
    required this.onStatusUpdate,
    required this.onShowSnackBar,
  });

  @override
  State<UserTaskDetailsSheet> createState() => _UserTaskDetailsSheetState();
}

class _UserTaskDetailsSheetState extends State<UserTaskDetailsSheet> {
  List<Map<String, dynamic>> _taskAttachments = [];
  bool _isLoadingAttachments = false;

  @override
  void initState() {
    super.initState();
    _fetchTaskAttachments();
  }

  Future<void> _fetchTaskAttachments() async {
    setState(() => _isLoadingAttachments = true);
    try {
      final task = widget.assignment['task'] as Map<String, dynamic>;
      final taskId = task['id'];

      if (taskId != null) {
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
      }
    } catch (e) {
      debugPrint('Error loading attachments: $e');
      if (mounted) {
        widget.onShowSnackBar('خطأ في تحميل المرفقات: ${e.toString()}',
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAttachments = false);
      }
    }
  }

  String _getPriorityText(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return 'عالية';
      case 'medium':
        return 'متوسطة';
      case 'low':
        return 'منخفضة';
      default:
        return priority;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
      case 'عالية':
        return Colors.red;
      case 'medium':
      case 'متوسطة':
        return Colors.orange;
      case 'low':
      case 'منخفضة':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
      case 'عالية':
        return Icons.priority_high;
      case 'medium':
      case 'متوسطة':
        return Icons.remove;
      case 'low':
      case 'منخفضة':
        return Icons.keyboard_arrow_down;
      default:
        return Icons.help_outline;
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
        widget.onShowSnackBar('خطأ في فتح الملف: ${e.toString()}',
            isError: true);
      }
    }
  }

  void _showStatusUpdateDialog() {
    final task = widget.assignment['task'] as Map<String, dynamic>;
    final currentStatus = widget.assignment['status'] ?? 'new';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.update,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'تحديث حالة المهمة',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    task['title'] ?? 'بدون عنوان',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'اختر الحالة الجديدة:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                _buildStatusOption('pending', 'قيد الانتظار',
                    Icons.pending_actions, Colors.orange, currentStatus),
                const SizedBox(height: 8),
                _buildStatusOption('in_progress', 'قيد التنفيذ',
                    Icons.running_with_errors, Colors.blue, currentStatus),
                const SizedBox(height: 8),
                _buildStatusOption('completed', 'تم التنفيذ', Icons.task_alt,
                    Colors.green, currentStatus),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'إلغاء',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusOption(String statusValue, String statusText,
      IconData icon, Color color, String currentStatus) {
    final isSelected = currentStatus == statusValue;

    return GestureDetector(
      onTap: () {
        final task = widget.assignment['task'] as Map<String, dynamic>;
        widget.onStatusUpdate(task['id'], widget.assignment['id'], statusValue);
        Navigator.of(context).pop();
        Navigator.of(context).pop(); // Close the sheet as well
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.1)
              : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? color
                : Theme.of(context).colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                statusText,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? color
                          : Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final task = widget.assignment['task'] as Map<String, dynamic>;
    final priority = task['priority'] ?? 'عادي';

    return Directionality(
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
                      color: _getPriorityColor(priority).withOpacity(0.1),
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
                          task['title'] ?? 'مهمة بدون عنوان',
                          style: theme.textTheme.headlineSmall?.copyWith(
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
                            color: _getPriorityColor(priority).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'أولوية ${_getPriorityText(priority)}',
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
              if (task['description'] != null &&
                  task['description'].isNotEmpty) ...[
                Text(
                  'الوصف',
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
                    task['description'],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Attachments
              Text(
                'المرفقات',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              if (_isLoadingAttachments)
                const Center(child: CircularProgressIndicator())
              else if (_taskAttachments.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('لا توجد مرفقات'),
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
                        leading: Icon(_getFileIcon(attachment['file_type'])),
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
                      child: const Text('إغلاق'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _showStatusUpdateDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                      ),
                      child: const Text('تحديث الحالة'),
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

  static void show({
    required BuildContext context,
    required Map<String, dynamic> assignment,
    required Function(int taskId, int assignmentId, String newStatus)
        onStatusUpdate,
    required Function(String message, {required bool isError}) onShowSnackBar,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UserTaskDetailsSheet(
        assignment: assignment,
        onStatusUpdate: onStatusUpdate,
        onShowSnackBar: onShowSnackBar,
      ),
    );
  }
}
