import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  late String _selectedStatus;
  late String _selectedPriority;
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _titleController.text = widget.task['title'] ?? '';
    _descriptionController.text = widget.task['description'] ?? '';
    _selectedStatus = widget.assignment?['status'] ?? 'new';
    _selectedPriority = widget.task['priority'] ?? 'عادي';
    _startDate = DateTime.parse(widget.task['created_at']);
    _endDate = DateTime.parse(widget.task['end_at']);
    _startDateController.text = _formatArabicDate(widget.task['created_at']);
    _endDateController.text = _formatArabicDate(widget.task['end_at']);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          isStart ? _startDate ?? DateTime.now() : _endDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme.apply(
                  bodyColor: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          _startDateController.text =
              _formatArabicDate(picked.toIso8601String());
        } else {
          _endDate = picked;
          _endDateController.text = _formatArabicDate(picked.toIso8601String());
        }
      });
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      // Update task details
      await Supabase.instance.client.from('tasks').update({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'priority': _selectedPriority,
        'created_at': _startDate!.toIso8601String(),
        'end_at': _endDate!.toIso8601String(),
      }).eq('id', widget.task['id']);

      // Update task assignment
      await Supabase.instance.client.from('task_assignments').update({
        'status': _selectedStatus,
        'created_at': _startDate!.toIso8601String(),
        'end_at': _endDate!.toIso8601String(),
      }).eq('id', widget.assignment?['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التغييرات بنجاح')),
        );
        setState(() => _isEditing = false);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Form(
        key: _formKey,
        child: CustomScrollView(
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
                  widget.task['title'] ?? 'بدون عنوان',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              actions: [
                if (_isEditing)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _isEditing = false;
                            _initializeControllers();
                          });
                        },
                      ),
                      IconButton(
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        onPressed: _isSaving ? null : _saveChanges,
                      ),
                    ],
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => setState(() => _isEditing = true),
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title Field
                    if (_isEditing) ...[
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'عنوان المهمة',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'عنوان المهمة مطلوب';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Status Card
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getStatusColor(_selectedStatus),
                            _getStatusColor(_selectedStatus).withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _getStatusColor(_selectedStatus)
                                .withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                _getStatusIcon(_selectedStatus),
                                color: Colors.white,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'حالة المهمة',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (_isEditing)
                                    DropdownButton<String>(
                                      value: _selectedStatus,
                                      dropdownColor:
                                          _getStatusColor(_selectedStatus),
                                      items: ['new', 'in_progress', 'completed']
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
                                          setState(
                                              () => _selectedStatus = value);
                                        }
                                      },
                                    )
                                  else
                                    Text(
                                      _getStatusText(_selectedStatus),
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Priority Selection
                    if (_isEditing)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الأولوية',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedPriority,
                              items: ['عادي', 'هام', 'عاجل']
                                  .map((priority) => DropdownMenuItem(
                                        value: priority,
                                        child: Text(priority),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _selectedPriority = value);
                                }
                              },
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Dates Selection
                    if (_isEditing) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'تواريخ المهمة',
                              style: theme.textTheme.titleMedium,
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
                                      suffixIcon: Icon(Icons.calendar_today,
                                          color: colorScheme.primary),
                                      border: const OutlineInputBorder(),
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
                                      suffixIcon: Icon(Icons.calendar_today,
                                          color: colorScheme.secondary),
                                      border: const OutlineInputBorder(),
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
                    ],

                    // Description
                    Text(
                      'الوصف',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_isEditing)
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.task['description'] ?? 'لا يوجد وصف',
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
                            widget.task['creator_profile'],
                            Icons.person_outline,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildInfoCard(
                            context,
                            'معين إلى',
                            widget.assignment?['assignee_profile'],
                            Icons.assignment_ind_outlined,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Timeline
                    _buildTimeline(context, widget.task['created_at']),
                  ],
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
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ التغييرات'),
              backgroundColor: colorScheme.primary,
            )
          : null,
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
    final colorScheme = theme.colorScheme;
    final startDate = widget.task['created_at'];
    final endDate = widget.task['end_at'];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.event, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'المواعيد',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildDateRow(
                  context,
                  'تاريخ البداية',
                  startDate ?? '',
                  Icons.play_circle_outline,
                  colorScheme.primary,
                ),
                const SizedBox(height: 16),
                _buildDateRow(
                  context,
                  'تاريخ الانتهاء',
                  endDate ?? '',
                  Icons.flag_circle_outlined,
                  colorScheme.secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow(BuildContext context, String label, String date,
      IconData icon, Color color) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
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
                const SizedBox(height: 4),
                Text(
                  _formatArabicDate(date),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatArabicDate(String dateString) {
    if (dateString.isEmpty) return 'غير محدد';

    final date = DateTime.parse(dateString).toLocal();
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

    final dayName = arabicDays[date.weekday % 7];
    final monthName = arabicMonths[date.month - 1];

    return '$dayName، ${date.day} $monthName ${date.year}';
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

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'عاجل':
        return Colors.red;
      case 'هام':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _formatDate(String dateString) {
    final date = DateTime.parse(dateString).toLocal();
    return '${date.year}-${date.month}-${date.day}';
  }
}
