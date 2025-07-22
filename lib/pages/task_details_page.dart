import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class TaskDetailsPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final Map<String, dynamic>? assignment;

  const TaskDetailsPage({
    super.key,
    required this.task,
    this.assignment,
  });

  @override
  State<TaskDetailsPage> createState() => _TaskDetailsState();
}

class _TaskDetailsState extends State<TaskDetailsPage> {
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingFile = false;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  late String _selectedStatus;
  late String _selectedPriority;
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;
  List<Map<String, dynamic>> _attachments = [];
  Map<String, dynamic> _taskData = {}; // Add this to store updated task data
  late RealtimeChannel _taskChannel; // Add this for real-time updates

  @override
  void initState() {
    super.initState();
    // Initialize date formatting for Arabic locale
    initializeDateFormatting('ar', null).then((_) {
      setState(() {
        // Defensive: Only set if not null and is String
        final createdAt = widget.task['created_at'];
        final endAt = widget.task['end_at'];
        _startDateController.text = _formatArabicDate(createdAt ?? '');
        _endDateController.text = _formatArabicDate(endAt ?? '');
      });
    });
    _initializeControllers();
    _loadAttachments();
    _fetchTaskData(); // Fetch complete task data including status
    _setupRealtimeListener(); // Add real-time listener
  }

  void _initializeControllers() {
    _titleController.text = widget.task['title'] ?? '';
    _descriptionController.text = widget.task['description'] ?? '';
    // Use task status from tasks table instead of assignment status
    _selectedStatus = _taskData['status'] ??
        widget.task['status'] ??
        widget.assignment?['status'] ??
        'new';
    _selectedPriority = widget.task['priority'] ?? 'عادي';

    // Safely parse dates, fallback to now if null or invalid
    final createdAt = widget.task['created_at'];
    final endAt = widget.task['end_at'];
    try {
      _startDate =
          (createdAt != null && createdAt is String && createdAt.isNotEmpty)
              ? DateTime.parse(createdAt)
              : DateTime.now();
    } catch (_) {
      _startDate = DateTime.now();
    }
    try {
      _endDate = (endAt != null && endAt is String && endAt.isNotEmpty)
          ? DateTime.parse(endAt)
          : DateTime.now();
    } catch (_) {
      _endDate = DateTime.now();
    }
    _startDateController.text = _formatArabicDate(createdAt ?? '');
    _endDateController.text = _formatArabicDate(endAt ?? '');
  }

  @override
  void dispose() {
    _taskChannel.unsubscribe(); // Clean up the channel
    _titleController.dispose();
    _descriptionController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  // Add method to setup real-time listener
  void _setupRealtimeListener() {
    _taskChannel = Supabase.instance.client
        .channel('task_${widget.task['id']}_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tasks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.task['id'],
          ),
          callback: (payload) {
            if (mounted) {
              // Update local task data when database changes
              final newData = payload.newRecord;
              setState(() {
                _taskData = {..._taskData, ...newData};
                _selectedStatus = newData['status'] ?? _selectedStatus;
                _selectedPriority = newData['priority'] ?? _selectedPriority;

                // Update controllers if not editing
                if (!_isEditing) {
                  _titleController.text =
                      newData['title'] ?? _titleController.text;
                  _descriptionController.text =
                      newData['description'] ?? _descriptionController.text;

                  // Update date controllers
                  if (newData['created_at'] != null) {
                    _startDateController.text =
                        _formatArabicDate(newData['created_at']);
                    try {
                      _startDate = DateTime.parse(newData['created_at']);
                    } catch (_) {}
                  }
                  if (newData['end_at'] != null) {
                    _endDateController.text =
                        _formatArabicDate(newData['end_at']);
                    try {
                      _endDate = DateTime.parse(newData['end_at']);
                    } catch (_) {}
                  }
                }
              });

              // Show a subtle notification about the update
              if (!_isEditing) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('تم تحديث المهمة'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.blue.shade600,
                  ),
                );
              }
            }
          },
        )
        .subscribe();
  }

  // Also listen to task assignments changes
  void _setupAssignmentRealtimeListener() {
    final assignmentChannel = Supabase.instance.client
        .channel('task_assignments_${widget.task['id']}_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'task_assignments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'task_id',
            value: widget.task['id'],
          ),
          callback: (payload) {
            if (mounted && !_isEditing) {
              // Refresh task data when assignments are updated
              _fetchTaskData();
            }
          },
        )
        .subscribe();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // Update task details including status
      final updatedData = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'priority': _selectedPriority,
        'status': _selectedStatus, // Update task status in tasks table
        'created_at': _startDate!.toIso8601String(),
        'end_at': _endDate!.toIso8601String(),
      };

      await Supabase.instance.client
          .from('tasks')
          .update(updatedData)
          .eq('id', widget.task['id']);

      // Update task assignment if it exists
      if (widget.assignment != null) {
        await Supabase.instance.client.from('task_assignments').update({
          'status': _selectedStatus, // Keep assignment status in sync
          'created_at': _startDate!.toIso8601String(),
          'end_at': _endDate!.toIso8601String(),
        }).eq('id', widget.assignment?['id']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التغييرات بنجاح')),
        );
        setState(() => _isEditing = false);
        // Refresh the task data
        await _fetchTaskData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _loadAttachments() async {
    try {
      final response = await Supabase.instance.client
          .from('task_attachments')
          .select()
          .eq('task_id', widget.task['id']);

      if (mounted) {
        setState(() {
          _attachments = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error loading attachments: $e');
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      setState(() => _isUploadingFile = true);

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      // Upload to Supabase Storage
      await Supabase.instance.client.storage
          .from('files')
          .uploadBinary(fileName, file.bytes!);

      // Get the public URL
      final fileUrl =
          Supabase.instance.client.storage.from('files').getPublicUrl(fileName);

      // Save attachment record
      final response = await Supabase.instance.client
          .from('task_attachments')
          .insert({
            'task_id': widget.task['id'],
            'file_name': file.name,
            'file_url': fileUrl,
            'file_type': file.extension,
            'uploaded_by': Supabase.instance.client.auth.currentUser!.id,
          })
          .select()
          .single();

      if (mounted) {
        setState(() {
          _attachments.add(response);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفع الملف بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في رفع الملف: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingFile = false);
    }
  }

  IconData _getFileIcon(String? fileType) {
    switch (fileType?.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Icons.image_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'zip':
      case 'rar':
        return Icons.archive_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _downloadFile(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في فتح الملف: ${e.toString()}')),
        );
      }
    }
  }

  // Add method to fetch complete task data including status
  Future<void> _fetchTaskData() async {
    try {
      final response = await Supabase.instance.client
          .from('tasks')
          .select('*')
          .eq('id', widget.task['id'])
          .single();

      if (mounted && response != null) {
        setState(() {
          _taskData = response;
          _selectedStatus = response['status'] ?? 'new';
          _selectedPriority = response['priority'] ?? 'عادي';

          // Update controllers with fresh data
          if (!_isEditing) {
            _titleController.text = response['title'] ?? '';
            _descriptionController.text = response['description'] ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching task data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get all assigned users
    final assignments = widget.task['task_assignments'] as List<dynamic>?;

    // Use current task data or fallback to widget data with real-time updates
    final currentTitle =
        _taskData['title'] ?? widget.task['title'] ?? 'بدون عنوان';
    final currentDescription =
        _taskData['description'] ?? widget.task['description'];
    final currentStatus = _taskData['status'] ?? widget.task['status'] ?? 'new';
    final currentPriority =
        _taskData['priority'] ?? widget.task['priority'] ?? 'عادي';

    return Scaffold(
      body: Form(
        key: _formKey,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              surfaceTintColor: colorScheme.surface,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Use the image as the background for the title section
                    Image.asset(
                      'assets/background.jpg',
                      fit: BoxFit.cover,
                    ),
                    // Add status indicator overlay on the title
                    Positioned(
                      top: 80,
                      right: 32,
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 300), // Add animation
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              _getStatusColor(currentStatus).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getStatusIcon(currentStatus),
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _getStatusText(currentStatus),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding:
                            const EdgeInsets.only(right: 32.0, bottom: 24.0),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            currentTitle,
                            key:
                                ValueKey(currentTitle), // Add key for animation
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (_isEditing)
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: Colors.white), // Rounded icon
                        onPressed: () {
                          setState(() {
                            _isEditing = false;
                            _initializeControllers(); // Revert changes
                          });
                        },
                      ),
                      _isSaving
                          ? Padding(
                              padding: const EdgeInsets.all(
                                  12.0), // Padding for loader
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5, // Slightly thicker stroke
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: Icon(Icons.save_rounded,
                                  color: Colors.white), // Rounded icon
                              onPressed: _saveChanges,
                            ),
                    ],
                  )
                else
                  IconButton(
                    icon: Icon(Icons.edit_rounded,
                        color: Colors.white), // Rounded icon
                    onPressed: () => setState(() => _isEditing = true),
                  ),
                const SizedBox(width: 8), // Spacing for actions
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title Field (only visible when editing)
                      if (_isEditing) ...[
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: 'عنوان المهمة',
                            filled: true,
                            fillColor:
                                colorScheme.surfaceVariant.withOpacity(0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: colorScheme.primary, width: 2),
                            ),
                            prefixIcon: Icon(Icons.title,
                                color: colorScheme.onSurfaceVariant),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'عنوان المهمة مطلوب';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Status Card - Always visible with current status (animated)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildStatusCard(context, theme, colorScheme),
                      ),
                      const SizedBox(height: 24),

                      // Priority Display - Always visible (animated)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _buildPriorityCard(context, theme, colorScheme),
                      ),
                      const SizedBox(height: 24),

                      // Priority Selection (only visible when editing)
                      if (_isEditing) ...[
                        _buildPrioritySelection(context, theme, colorScheme),
                        const SizedBox(height: 24),
                      ],

                      // Dates Selection (only visible when editing)
                      if (_isEditing) ...[
                        _buildDatesSelection(context, theme, colorScheme),
                        const SizedBox(height: 24),
                      ],

                      // Description Section with real-time updates
                      Text(
                        'الوصف',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (_isEditing)
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 5, // More lines for description
                          minLines: 3,
                          decoration: InputDecoration(
                            hintText: 'أدخل تفاصيل المهمة هنا...',
                            filled: true,
                            fillColor:
                                colorScheme.surfaceVariant.withOpacity(0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: colorScheme.primary, width: 2),
                            ),
                          ),
                        )
                      else
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            key: ValueKey(
                                currentDescription), // Add key for animation
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color:
                                  colorScheme.surfaceVariant.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: colorScheme.outlineVariant
                                      .withOpacity(0.5)),
                            ),
                            child: Text(
                              currentDescription ?? 'لا يوجد وصف لهذه المهمة.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.85),
                                height: 1.5,
                              ),
                              textAlign: TextAlign.justify,
                            ),
                          ),
                        ),

                      const SizedBox(height: 32), // More spacing

                      // Attachments Section
                      _buildAttachmentsList(context, theme, colorScheme),

                      const SizedBox(height: 32),

                      // Assignment Info
                      Row(children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.primary.withOpacity(0.18),
                                  colorScheme.primary.withOpacity(0.08),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withOpacity(0.10),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.primary.withOpacity(0.22),
                                    colorScheme.primary.withOpacity(0.08),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        colorScheme.primary.withOpacity(0.12),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: _buildInfoCard(
                                  context,
                                  'منشئ المهمة',
                                  widget.task['creator_profile'],
                                  Icons.person_outline_rounded,
                                  colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.secondary.withOpacity(0.18),
                                  colorScheme.secondary.withOpacity(0.08),
                                ],
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      colorScheme.secondary.withOpacity(0.10),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.secondary.withOpacity(0.22),
                                    colorScheme.secondary.withOpacity(0.08),
                                  ],
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        colorScheme.secondary.withOpacity(0.12),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                // --- Show all assigned users vertically here ---
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.assignment_ind_outlined,
                                            color: colorScheme.secondary,
                                            size: 28),
                                        const SizedBox(width: 12),
                                        Text(
                                          'معين إلى',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    assignments != null &&
                                            assignments.isNotEmpty
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: List.generate(
                                                assignments.length, (idx) {
                                              final assignee = assignments[idx]
                                                  ['assignee_profile'];
                                              final name = assignee?['name']
                                                      ?.toString() ??
                                                  'غير محدد';
                                              final avatarUrl =
                                                  assignee?['avatar_url']
                                                      ?.toString();
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 12.0),
                                                child: Row(
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 20,
                                                      backgroundColor:
                                                          colorScheme.secondary
                                                              .withOpacity(
                                                                  0.15),
                                                      backgroundImage:
                                                          avatarUrl != null &&
                                                                  avatarUrl
                                                                      .isNotEmpty
                                                              ? NetworkImage(
                                                                  avatarUrl)
                                                              : null,
                                                      child: avatarUrl ==
                                                                  null ||
                                                              avatarUrl.isEmpty
                                                          ? Text(
                                                              name.isNotEmpty
                                                                  ? name[0]
                                                                      .toUpperCase()
                                                                  : '?',
                                                              style: theme
                                                                  .textTheme
                                                                  .titleLarge
                                                                  ?.copyWith(
                                                                color: colorScheme
                                                                    .secondary,
                                                              ),
                                                            )
                                                          : null,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Text(
                                                        name,
                                                        style: theme
                                                            .textTheme.bodyLarge
                                                            ?.copyWith(
                                                          color: colorScheme
                                                              .onSurface,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }),
                                          )
                                        : Text(
                                            'غير محدد',
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                              color: theme
                                                  .textTheme.bodySmall?.color,
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),

                      const SizedBox(height: 32),

                      // Timeline (always visible)
                      _buildTimeline(context, theme, colorScheme,
                          widget.task['created_at']),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isEditing
          ? FloatingActionButton.extended(
              onPressed: _isSaving ? null : _saveChanges,
              icon: _isSaving
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colorScheme.onPrimary, // Match icon color
                      ),
                    )
                  : Icon(Icons.save_rounded,
                      color: colorScheme.onPrimary), // Use rounded icon
              label: Text(
                _isSaving ? 'جاري الحفظ...' : 'حفظ التغييرات',
                style: TextStyle(color: colorScheme.onPrimary),
              ),
              backgroundColor: colorScheme.primary, // Primary color for FAB
              elevation: 8, // More prominent shadow
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16), // Rounded FAB
              ),
            )
          : null,
    );
  }

  Widget _buildStatusCard(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final statusColor = _getStatusColor(_selectedStatus);
    return AnimatedContainer(
      key: ValueKey(_selectedStatus), // Add key for animation
      duration: const Duration(milliseconds: 300),
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 24, // Increased padding
            vertical: 20,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                statusColor.withOpacity(
                    0.9), // Slightly less opacity for the gradient effect
                statusColor.withOpacity(0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: statusColor.withOpacity(0.4), // More pronounced shadow
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'حالة المهمة',
                style: theme.textTheme.labelMedium?.copyWith(
                  // Smaller, clearer label
                  color: Colors.white.withOpacity(0.8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10), // Spacing
              Row(
                children: [
                  Icon(
                    _getStatusIcon(_selectedStatus),
                    color: Colors.white,
                    size: 32, // Larger icon
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    // Use Expanded to handle long text or dropdowns
                    child: _isEditing
                        ? DropdownButtonHideUnderline(
                            // Hide underline for cleaner look
                            child: DropdownButton<String>(
                              value: _selectedStatus,
                              isExpanded: true, // Take full width
                              icon: const Icon(Icons.arrow_drop_down_rounded,
                                  color: Colors.white70),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              dropdownColor: statusColor.withOpacity(
                                  0.9), // Match dropdown color to card
                              items:
                                  ['new', 'pending', 'in_progress', 'completed']
                                      .map((status) => DropdownMenuItem(
                                            value: status,
                                            child: Text(
                                              _getStatusText(status),
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _selectedStatus = value);
                                }
                              },
                            ),
                          )
                        : Text(
                            _getStatusText(_selectedStatus),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              // More prominent display text
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
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

  Widget _buildPrioritySelection(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الأولوية',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedPriority,
              decoration: InputDecoration(
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
                prefixIcon: Icon(Icons.priority_high_rounded,
                    color: _getPriorityColor(_selectedPriority)),
              ),
              items: ['عادي', 'هام', 'عاجل']
                  .map((priority) => DropdownMenuItem(
                        value: priority,
                        child: Text(priority, style: theme.textTheme.bodyLarge),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedPriority = value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityCard(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final currentPriority =
        _taskData['priority'] ?? widget.task['priority'] ?? 'عادي';
    final priorityColor = _getPriorityColor(currentPriority);

    return AnimatedContainer(
      key: ValueKey(currentPriority), // Add key for animation
      duration: const Duration(milliseconds: 300),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                priorityColor.withOpacity(0.1),
                priorityColor.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: priorityColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getPriorityIcon(currentPriority),
                  color: priorityColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الأولوية',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        currentPriority,
                        key: ValueKey(currentPriority),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: priorityColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatesSelection(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تواريخ المهمة',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startDateController,
                    readOnly: true,
                    onTap: () => _selectDate(context, true),
                    decoration: InputDecoration(
                      labelText: 'تاريخ البداية',
                      filled: true,
                      fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: colorScheme.primary, width: 2),
                      ),
                      suffixIcon: Icon(Icons.calendar_month_rounded,
                          color: colorScheme.primary),
                    ),
                    validator: (value) {
                      if (_startDate == null) {
                        return 'يرجى اختيار تاريخ البداية';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _endDateController,
                    readOnly: true,
                    onTap: () => _selectDate(context, false),
                    decoration: InputDecoration(
                      labelText: 'تاريخ الانتهاء',
                      filled: true,
                      fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: colorScheme.secondary, width: 2),
                      ),
                      suffixIcon: Icon(Icons.calendar_month_rounded,
                          color: colorScheme.secondary),
                    ),
                    validator: (value) {
                      if (_endDate == null) {
                        return 'يرجى اختيار تاريخ الانتهاء';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsList(
      BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'المرفقات',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (_isEditing)
              _isUploadingFile
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.primary,
                        ),
                      ),
                    )
                  : IconButton.filled(
                      // Use filled button for upload action
                      icon: const Icon(Icons.cloud_upload_rounded),
                      onPressed: _pickAndUploadFile,
                      tooltip: 'رفع ملف جديد',
                      color: colorScheme.primary,
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.primary.withOpacity(0.1),
                        foregroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
          ],
        ),
        const SizedBox(height: 12),
        if (_attachments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: Center(
              child: Text(
                'لا توجد مرفقات حاليًا. اضغط على أيقونة الرفع لإضافة ملف.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _attachments.length,
            itemBuilder: (context, index) {
              final attachment = _attachments[index];
              return Card(
                margin: const EdgeInsets.only(
                    bottom: 10), // Spacing between attachments
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: Icon(_getFileIcon(attachment['file_type']),
                      color: colorScheme.primary, size: 28),
                  title: Text(
                    attachment['file_name'],
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${attachment['file_type']?.toUpperCase() ?? 'FILE'} • ${_formatDate(attachment['created_at'] ?? DateTime.now().toIso8601String())}',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.download_rounded,
                        color: colorScheme.secondary),
                    onPressed: () => _downloadFile(attachment['file_url']),
                    tooltip: 'تنزيل الملف',
                  ),
                  onTap: () => _downloadFile(
                      attachment['file_url']), // Also download on tile tap
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context, String title,
      Map<String, dynamic>? user, IconData icon, Color accentColor) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20), // Consistent padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accentColor, size: 28), // Larger icon
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16), // Increased spacing
            if (user != null) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 24, // Larger avatar
                    backgroundColor: accentColor.withOpacity(0.15),
                    backgroundImage: user['avatar_url'] != null
                        ? NetworkImage(user['avatar_url'])
                        : null,
                    // Move 'child' to the end
                    child: user['avatar_url'] == null
                        ? Text(
                            user['name']?[0].toUpperCase() ?? '?',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(color: accentColor),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      user['name'] ?? 'غير معروف',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildTimeline(BuildContext context, ThemeData theme,
      ColorScheme colorScheme, String? createdAt) {
    final startDate = widget.task['created_at'];
    final endDate = widget.task['end_at'];

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.2),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_note_rounded,
                      color: colorScheme.primary, size: 30),
                  const SizedBox(width: 16),
                  Text(
                    'المواعيد',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildDateRectangle(
                    context,
                    'تاريخ البداية',
                    startDate ?? '',
                    Icons.play_circle_fill_rounded,
                    colorScheme.primary,
                  ),
                  const SizedBox(width: 14),
                  _buildDateRectangle(
                    context,
                    'تاريخ الانتهاء',
                    endDate ?? '',
                    Icons.flag_rounded,
                    colorScheme.secondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRectangle(BuildContext context, String label, String date,
      IconData icon, Color color) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.13),
              color.withOpacity(0.22),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: color.withOpacity(0.13), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(6),
                child:
                    Icon(icon, color: color, size: 24), // Slightly smaller icon
              ),
              const SizedBox(width: 14),
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.85),
                        fontWeight: FontWeight.bold,
                        fontSize: 14, // Slightly smaller label
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatArabicDate(date),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 15, // Reduced font size for date
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      locale: const Locale('ar'), // For Arabic date picker
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          _startDateController.text = _formatArabicDate(picked);
          // Ensure end date is not before start date
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = _startDate;
            _endDateController.text = _formatArabicDate(_startDate!);
          }
        } else {
          _endDate = picked;
          _endDateController.text = _formatArabicDate(picked);
          // Ensure start date is not after end date
          if (_startDate != null && _startDate!.isAfter(_endDate!)) {
            _startDate = _endDate;
            _startDateController.text = _formatArabicDate(_endDate!);
          }
        }
      });
    }
  }

  // Helper functions (unchanged functionally, but adjusted for consistency)
  String _formatArabicDate(dynamic dateString) {
    if (dateString == null || (dateString is String && dateString.isEmpty))
      return 'غير محدد';
    DateTime date;
    try {
      if (dateString is DateTime) {
        date = dateString;
      } else if (dateString is String && dateString.isNotEmpty) {
        date = DateTime.parse(dateString.toString()).toLocal();
      } else {
        return 'غير محدد';
      }
    } catch (_) {
      return 'غير محدد';
    }
    final DateFormat formatter = DateFormat(
        'EEEE، d MMMM y', 'ar'); // Specify Arabic locale if available

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
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد'
    ];
    final dayName = arabicDays[date.weekday - 1];
    final monthName = arabicMonths[date.month - 1];
    return '$dayName، ${date.day} $monthName ${date.year}';
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'تم التنفيذ';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'pending':
        return 'قيد الانتظار';
      default:
        return 'جديدة';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green.shade600; // Deeper green
      case 'in_progress':
        return Colors.blue.shade600; // Deeper blue
      case 'pending':
        return Colors.orange.shade600; // Orange for pending
      default:
        return Colors.grey.shade600; // Deeper grey
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle_rounded;
      case 'in_progress':
        return Icons.pending_actions_rounded; // More descriptive icon
      case 'pending':
        return Icons.schedule_rounded; // Clock icon for pending
      default:
        return Icons.fiber_new_rounded;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'عاجل':
        return Colors.red.shade700; // Stronger red
      case 'هام':
        return Colors.orange.shade700; // Stronger orange
      default:
        return Colors.blue.shade700; // Stronger blue
    }
  }

  String _formatDate(String dateString) {
    final date = DateTime.parse(dateString).toLocal();
    return DateFormat('yyyy-MM-dd')
        .format(date); // Use intl for consistent formatting
  }

  IconData _getPriorityIcon(String priority) {
    switch (priority) {
      case 'عاجل':
        return Icons.priority_high_rounded;
      case 'هام':
        return Icons.warning_rounded;
      default:
        return Icons.low_priority_rounded;
    }
  }
}
