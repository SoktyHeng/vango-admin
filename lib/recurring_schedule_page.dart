import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Constants
class ScheduleConstants {
  static const Duration periodicGenerationInterval = Duration(hours: 1);
  static const int defaultCapacity = 12;
  static const int maxFutureBookingDays = 365;
  
  static const List<String> commonTimes = [
    '6:00 AM', '7:00 AM', '8:00 AM', '9:00 AM', '10:00 AM', '11:00 AM',
    '12:00 PM', '1:00 PM', '2:00 PM', '3:00 PM', '4:00 PM', '5:00 PM',
    '6:00 PM', '7:00 PM', '8:00 PM', '9:00 PM',
  ];
  
  static const List<String> detailedTimes = [
    '5:00 AM', '5:30 AM', '6:00 AM', '6:30 AM', '7:00 AM', '7:30 AM',
    '8:00 AM', '8:30 AM', '9:00 AM', '9:30 AM', '10:00 AM', '10:30 AM',
    '11:00 AM', '11:30 AM', '12:00 PM', '12:30 PM', '1:00 PM', '1:30 PM',
    '2:00 PM', '2:30 PM', '3:00 PM', '3:30 PM', '4:00 PM', '4:30 PM',
    '5:00 PM', '5:30 PM', '6:00 PM', '6:30 PM', '7:00 PM', '7:30 PM',
    '8:00 PM', '8:30 PM', '9:00 PM', '9:30 PM', '10:00 PM',
  ];
  
  static const List<String> dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 
    'Friday', 'Saturday', 'Sunday',
  ];
  
  // Collection names
  static const String recurringSchedulesCollection = 'recurring_schedules';
  static const String schedulesCollection = 'schedules';
  static const String routesCollection = 'routes';
  static const String driversCollection = 'drivers';
  static const String vansCollection = 'vans';
  
  // Status values
  static const String statusActive = 'active';
  static const String statusScheduled = 'scheduled';
  static const String statusCompleted = 'completed';
  static const String statusApproved = 'approved';
}

class RecurringScheduleManager extends StatefulWidget {
  const RecurringScheduleManager({super.key});

  @override
  State<RecurringScheduleManager> createState() =>
      _RecurringScheduleManagerState();
}

class _RecurringScheduleManagerState extends State<RecurringScheduleManager>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _recurringSchedules = [];
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _vans = [];
  bool _isLoading = true;
  Timer? _periodicTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();

    // Generate schedules for today when the page loads
    _generateSchedulesForToday();

    // Optional: Set up periodic generation
    _setupPeriodicGeneration();
  }

  void _setupPeriodicGeneration() {
    // Generate schedules every hour (you can adjust this)
    _periodicTimer = Timer.periodic(const Duration(hours: 1), (timer) {
      _generateSchedulesForToday();
      _generateSchedulesForTomorrow(); // Also generate for tomorrow
    });
  }

  Future<void> _generateSchedulesForTomorrow() async {
    try {
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      // Get all active recurring schedules
      final recurringSchedules = await FirebaseFirestore.instance
          .collection(ScheduleConstants.recurringSchedulesCollection)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in recurringSchedules.docs) {
        final schedule = doc.data();
        final scheduleId = doc.id;

        if (_shouldGenerateForDate(schedule, tomorrow)) {
          final times = List<String>.from(schedule['times'] ?? []);

          for (String time in times) {
            // Check if schedule already exists for tomorrow
            final existingSchedule = await FirebaseFirestore.instance
                .collection('schedules')
                .where('date', isEqualTo: DateFormat('yyyy-MM-dd').format(tomorrow))
                .where('time', isEqualTo: time)
                .where('routeId', isEqualTo: schedule['routeId'])
                .limit(1)
                .get();

            if (existingSchedule.docs.isEmpty) {
              // Create individual schedule
              await FirebaseFirestore.instance.collection('schedules').add({
                'date': DateFormat('yyyy-MM-dd').format(tomorrow),
                'time': time,
                'routeId': schedule['routeId'],
                'driverId': schedule['driverId'],
                'vanId': schedule['vanId'],
                'vanLicense': schedule['vanLicense'],
                'seatsTotal': schedule['seatsTotal'],
                'seatsAvailable': schedule['seatsTotal'],
                'status': 'scheduled',
                'recurringScheduleId': scheduleId,
                'from': schedule['from'],
                'to': schedule['to'],
                'price': schedule['price'] ?? 0,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error generating tomorrow schedules: $e');
    }
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadRecurringSchedules(),
      _loadRoutes(),
      _loadDrivers(),
      _loadVans(),
    ]);
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadRecurringSchedules() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('recurring_schedules')
          .orderBy('createdAt', descending: true)
          .get();

      _recurringSchedules = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      debugPrint('Error loading recurring schedules: $e');
    }
  }

  Future<void> _loadRoutes() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('routes')
          .get();
      _routes = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id,
              'name': '${doc.data()['from']} → ${doc.data()['to']}',
              'from': doc.data()['from'],
              'to': doc.data()['to'],
            },
          )
          .toList();
    } catch (e) {
      debugPrint('Error loading routes: $e');
    }
  }

  Future<void> _loadDrivers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where(
            'status',
            isEqualTo: 'approved',
          ) // Add this filter if you have status
          .get();

      _drivers = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id, // This should match the driverId in vans collection
              'name': doc.data()['name'] ?? 'Unknown Driver',
              'email': doc.data()['email'] ?? '',
            },
          )
          .toList();

      debugPrint('Loaded ${_drivers.length} drivers');
    } catch (e) {
      debugPrint('Error loading drivers: $e');
    }
  }

  Future<void> _loadVans() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vans')
          .get();
      _vans = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id,
              'name': doc.data()['vanId'] ?? doc.id,
              'license':
                  doc.data()['licensePlate'] ??
                  '', // FIXED: Use correct field name
              'seats':
                  doc.data()['capacity'] ?? 12, // FIXED: Use correct field name
              'vanId': doc.data()['vanId'] ?? '', // ADD: Include vanId
              'driverId': doc.data()['driverId'] ?? '', // ADD: Include driverId
              'driverName':
                  doc.data()['driverName'] ?? '', // ADD: Include driverName
            },
          )
          .toList();
    } catch (e) {
      debugPrint('Error loading vans: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Recurring Schedules',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active Schedules', icon: Icon(Icons.repeat)),
            Tab(text: 'Create New', icon: Icon(Icons.add_circle_outline)),
          ],
          labelColor: Colors.blue[600],
          unselectedLabelColor: Colors.grey[600],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildActiveSchedulesTab(), _buildCreateNewTab()],
            ),
    );
  }

  Widget _buildActiveSchedulesTab() {
    return _recurringSchedules.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.repeat, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No recurring schedules yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create recurring schedules to automatically generate trips',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _tabController.animateTo(1),
                  icon: const Icon(Icons.add),
                  label: const Text('Create First Schedule'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          )
        : Column(
            children: [
              // Button to generate schedules based on recurring schedule date ranges
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _generateSchedulesFromAllRecurringPatterns();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Generated schedules based on recurring patterns',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate Schedules from Patterns'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _recurringSchedules.length,
                  itemBuilder: (context, index) {
                    return _buildRecurringScheduleCard(
                      _recurringSchedules[index],
                    );
                  },
                ),
              ),
            ],
          );
  }

  Widget _buildRecurringScheduleCard(Map<String, dynamic> schedule) {
    final route = _routes.firstWhere(
      (r) => r['id'] == schedule['routeId'],
      orElse: () => {'name': 'Unknown Route'},
    );

    final driver = _drivers.firstWhere(
      (d) => d['id'] == schedule['driverId'],
      orElse: () => {'name': 'Unassigned Driver'},
    );

    // FIXED: Use vanId field instead of vanId as document ID
    final van = _vans.firstWhere(
      (v) =>
          v['vanId'] == schedule['vanId'], // Use vanId field, not document ID
      orElse: () => {
        'name': 'Unknown Van',
        'license': schedule['vanLicense'] ?? '', // Fallback to stored license
        'vanId': schedule['vanId'] ?? '',
      },
    );

    final isActive = schedule['isActive'] ?? true;
    final repeatType = schedule['repeatType'] ?? 'never';
    final times = List<String>.from(schedule['times'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: isActive ? null : Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // Header with status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isActive ? Colors.green[50] : Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isActive ? Icons.play_circle : Icons.pause_circle,
                  color: isActive ? Colors.green[600] : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isActive ? 'Active' : 'Paused',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.green[700] : Colors.grey[700],
                  ),
                ),
                const Spacer(),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(
                            isActive ? Icons.pause : Icons.play_arrow,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(isActive ? 'Pause' : 'Resume'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'generate',
                      child: Row(
                        children: const [
                          Icon(Icons.auto_awesome, size: 20),
                          SizedBox(width: 8),
                          Text('Generate Now'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) => _handleMenuAction(value, schedule),
                ),
              ],
            ),
          ),

          // Main content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Route
                Row(
                  children: [
                    Icon(Icons.route, size: 20, color: Colors.blue[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        route['name'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Driver & Van
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 18,
                            color: Colors.green[600],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              driver['name'],
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.directions_bus,
                            size: 18,
                            color: Colors.orange[600],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${van['vanId'] ?? van['name']} (${van['license']})',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Times
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 18,
                      color: Colors.purple[600],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: times
                            .map(
                              (time) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.purple[200]!,
                                  ),
                                ),
                                child: Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.purple[700],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Repeat pattern & dates
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.repeat, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            _getRepeatDisplayText(repeatType, schedule),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      if (schedule['startDate'] != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${DateFormat('MMM dd, yyyy').format(DateTime.parse(schedule['startDate']))} - ${schedule['endDate'] != null ? DateFormat('MMM dd, yyyy').format(DateTime.parse(schedule['endDate'])) : 'No end date'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getRepeatDisplayText(
    String repeatType,
    Map<String, dynamic> schedule,
  ) {
    switch (repeatType) {
      case 'daily':
        return 'Every day';
      case 'weekly':
        return 'Every week';
      case 'weekdays':
        return 'Weekdays only (Mon-Fri)';
      case 'weekends':
        return 'Weekends only (Sat-Sun)';
      case 'custom':
        final days = List<String>.from(schedule['customDays'] ?? []);
        return 'Custom: ${days.join(', ')}';
      default:
        return 'One time only';
    }
  }

  Widget _buildCreateNewTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Quick Templates
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.flash_on, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Quick Templates',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildQuickTemplateButton(
                      'Daily Service',
                      Icons.today,
                      () => _createQuickTemplate('daily'),
                    ),
                    _buildQuickTemplateButton(
                      'Weekdays Only',
                      Icons.business_center,
                      () => _createQuickTemplate('weekdays'),
                    ),
                    _buildQuickTemplateButton(
                      'Weekend Extra',
                      Icons.weekend,
                      () => _createQuickTemplate('weekends'),
                    ),
                    _buildQuickTemplateButton(
                      'Weekly',
                      Icons.calendar_view_week,
                      () => _createQuickTemplate('weekly'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Custom Creation Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showCreateCustomDialog(),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create Custom Recurring Schedule'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How it works:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '• Set up once: Choose route, driver, van, times, and repeat pattern\n'
                  '• Auto-generate: Schedules are created automatically based on your pattern\n'
                  '• Flexible: Pause, resume, or modify anytime\n'
                  '• Smart: Avoids conflicts and manages driver/van availability',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTemplateButton(
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.blue[600]),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.blue[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createQuickTemplate(String type) {
    showDialog(
      context: context,
      builder: (context) => QuickTemplateDialog(
        templateType: type,
        routes: _routes,
        drivers: _drivers,
        vans: _vans,
        onScheduleCreated: () {
          _loadRecurringSchedules();
        },
      ),
    );
  }

  void _showCreateCustomDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateRecurringScheduleDialog(
        routes: _routes,
        drivers: _drivers,
        vans: _vans,
        onScheduleCreated: () {
          _loadRecurringSchedules();
        },
      ),
    );
  }

  void _handleMenuAction(String action, Map<String, dynamic> schedule) async {
    switch (action) {
      case 'toggle':
        await _toggleScheduleStatus(schedule);
        break;
      case 'edit':
        _showEditDialog(schedule);
        break;
      case 'generate':
        await _generateNow(schedule);
        break;
      case 'delete':
        await _deleteSchedule(schedule);
        break;
    }
  }

  Future<void> _toggleScheduleStatus(Map<String, dynamic> schedule) async {
    try {
      final newStatus = !(schedule['isActive'] ?? true);
      await FirebaseFirestore.instance
          .collection('recurring_schedules')
          .doc(schedule['id'])
          .update({'isActive': newStatus});

      await _loadRecurringSchedules();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus ? 'Schedule resumed' : 'Schedule paused'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error updating schedule'))
        );
      }
    }
  }

  void _showEditDialog(Map<String, dynamic> schedule) {
    showDialog(
      context: context,
      builder: (context) => CreateRecurringScheduleDialog(
        routes: _routes,
        drivers: _drivers,
        vans: _vans,
        existingSchedule: schedule,
        onScheduleCreated: () {
          _loadRecurringSchedules();
        },
      ),
    );
  }

  Future<void> _generateNow(Map<String, dynamic> schedule) async {
    final startDate = DateTime.parse(schedule['startDate']);
    final endDate = schedule['endDate'] != null
        ? DateTime.parse(schedule['endDate'])
        : DateTime.now().add(const Duration(days: 365));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate Schedules'),
        content: Text(
          'Generate schedules from ${DateFormat('MMM dd, yyyy').format(startDate)} to ${DateFormat('MMM dd, yyyy').format(endDate)} based on this recurring pattern?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final generatedCount = await _generateSchedulesFromPattern(
          schedule,
          startDate,
          endDate,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generated $generatedCount schedules')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating schedules: $e')),
        );
      }
    }
  }

  Future<int> _generateSchedulesFromPattern(
    Map<String, dynamic> schedule,
    DateTime startDate,
    DateTime endDate,
  ) async {
    int generatedCount = 0;
    final times = List<String>.from(schedule['times'] ?? []);

    DateTime currentDate = startDate;

    while (currentDate.isBefore(endDate) ||
        currentDate.isAtSameMomentAs(endDate)) {
      if (_shouldGenerateForDate(schedule, currentDate)) {
        for (String time in times) {
          // Check if schedule already exists
          final existing = await FirebaseFirestore.instance
              .collection('schedules')
              .where(
                'date',
                isEqualTo: DateFormat('yyyy-MM-dd').format(currentDate),
              )
              .where('time', isEqualTo: time)
              .where('routeId', isEqualTo: schedule['routeId'])
              .where('driverId', isEqualTo: schedule['driverId'])
              .limit(1)
              .get();

          if (existing.docs.isEmpty) {
            try {
              // Get route details
              final routeDoc = await FirebaseFirestore.instance
                  .collection('routes')
                  .doc(schedule['routeId'])
                  .get();

              final routeData = routeDoc.data() ?? {};

              // Use stored data from recurring schedule
              final vanId = schedule['vanId'] ?? '';
              final driverId = schedule['driverId'] ?? '';
              final driverName = schedule['driverName'] ?? '';
              final vanLicense = schedule['vanLicense'] ?? '';
              final seatsTotal = schedule['seatsTotal'] ?? 12;

              if (vanId.isEmpty || driverId.isEmpty) {
                debugPrint(
                  'Missing van or driver info in recurring schedule: ${schedule['id']}',
                );
                continue;
              }

              // Determine initial status based on date
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final scheduleDay = DateTime(
                currentDate.year,
                currentDate.month,
                currentDate.day,
              );

              String initialStatus;
              if (scheduleDay.isAtSameMomentAs(today)) {
                initialStatus = 'active';
              } else if (scheduleDay.isAfter(today)) {
                initialStatus = 'scheduled';
              } else {
                initialStatus = 'completed';
              }

              await FirebaseFirestore.instance.collection('schedules').add({
                'date': DateFormat('yyyy-MM-dd').format(currentDate),
                'time': time,
                'routeId': schedule['routeId'],
                'driverId': driverId,
                'driverName': driverName,
                'vanId': vanId,
                'vanLicense': vanLicense,
                'seatsTotal': seatsTotal,
                'seatsAvailable': seatsTotal,
                'seatsTaken': [],
                'status': initialStatus,
                'recurringScheduleId': schedule['id'],
                'from': routeData['from'] ?? '',
                'to': routeData['to'] ?? '',
                'price': routeData['pricePerSeat'] ?? 0,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });

              generatedCount++;
            } catch (e) {
              debugPrint('Error generating individual schedule: $e');
            }
          }
        }
      }

      currentDate = currentDate.add(const Duration(days: 1));
    }

    return generatedCount;
  }

  Future<void> _deleteSchedule(Map<String, dynamic> schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recurring Schedule'),
        content: const Text(
          'Are you sure you want to delete this recurring schedule? This will not affect already generated individual schedules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('recurring_schedules')
            .doc(schedule['id'])
            .delete();

        await _loadRecurringSchedules();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recurring schedule deleted')),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting schedule: $e')));
      }
    }
  }

  Future<void> _generateSchedulesForToday() async {
    try {
      final today = DateTime.now();
      final todayString = DateFormat('yyyy-MM-dd').format(today);

      // Get all active recurring schedules
      final recurringSchedules = await FirebaseFirestore.instance
          .collection(ScheduleConstants.recurringSchedulesCollection)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in recurringSchedules.docs) {
        final schedule = doc.data();
        final scheduleId = doc.id;

        if (_shouldGenerateForDate(schedule, today)) {
          final times = List<String>.from(schedule['times'] ?? []);

          for (String time in times) {
            // Check if schedule already exists for today
            final existingSchedule = await FirebaseFirestore.instance
                .collection('schedules')
                .where('date', isEqualTo: todayString)
                .where('time', isEqualTo: time)
                .where('routeId', isEqualTo: schedule['routeId'])
                .limit(1)
                .get();

            if (existingSchedule.docs.isEmpty) {
              // Create individual schedule
              await FirebaseFirestore.instance.collection('schedules').add({
                'date': todayString,
                'time': time,
                'routeId': schedule['routeId'],
                'driverId': schedule['driverId'],
                'vanId': schedule['vanId'],
                'vanLicense': schedule['vanLicense'],
                'seatsTotal': schedule['seatsTotal'],
                'seatsAvailable': schedule['seatsTotal'],
                'status': 'active',
                'recurringScheduleId': scheduleId,
                'from': schedule['from'], // Add route details
                'to': schedule['to'], // Add route details
                'price': schedule['price'] ?? 0, // Add price if available
                'createdAt': FieldValue.serverTimestamp(),
              });

            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error generating schedules: $e');
    }
  }

  bool _shouldGenerateForDate(Map<String, dynamic> schedule, DateTime date) {
    final repeatType = schedule['repeatType'];
    final startDate = DateTime.parse(schedule['startDate']);
    final endDate = schedule['endDate'] != null
        ? DateTime.parse(schedule['endDate'])
        : null;

    // Check if date is within range
    if (date.isBefore(startDate) ||
        (endDate != null && date.isAfter(endDate))) {
      return false;
    }

    switch (repeatType) {
      case 'daily':
        return true;
      case 'weekly':
        return date.weekday == startDate.weekday;
      case 'weekdays':
        return date.weekday <= 5; // Mon-Fri
      case 'weekends':
        return date.weekday > 5; // Sat-Sun
      case 'custom':
        final customDays = List<String>.from(schedule['customDays'] ?? []);
        final dayNames = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ];
        return customDays.contains(dayNames[date.weekday - 1]);
      default:
        return false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _periodicTimer?.cancel();
    super.dispose();
  }

  Future<void> _generateSchedulesFromAllRecurringPatterns() async {
    try {
      final recurringSchedules = await FirebaseFirestore.instance
          .collection(ScheduleConstants.recurringSchedulesCollection)
          .where('isActive', isEqualTo: true)
          .get();

      int totalGenerated = 0;

      for (var doc in recurringSchedules.docs) {
        final schedule = doc.data();
        final startDate = DateTime.parse(schedule['startDate']);
        final endDate = schedule['endDate'] != null
            ? DateTime.parse(schedule['endDate'])
            : DateTime.now().add(
                const Duration(days: 365),
              ); // Default to 1 year if no end date

        final generated = await _generateSchedulesFromPattern(
          {'id': doc.id, ...schedule},
          startDate,
          endDate,
        );

        totalGenerated += generated;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Generated $totalGenerated schedules from recurring patterns',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generating schedules from patterns: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error generating schedules'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class QuickTemplateDialog extends StatefulWidget {
  final String templateType;
  final List<Map<String, dynamic>> routes;
  final List<Map<String, dynamic>> drivers;
  final List<Map<String, dynamic>> vans;
  final VoidCallback onScheduleCreated;

  const QuickTemplateDialog({
    super.key,
    required this.templateType,
    required this.routes,
    required this.drivers,
    required this.vans,
    required this.onScheduleCreated,
  });

  @override
  State<QuickTemplateDialog> createState() => _QuickTemplateDialogState();
}

class _QuickTemplateDialogState extends State<QuickTemplateDialog> {
  String? _selectedRoute;
  String? _selectedDriver;
  Map<String, dynamic>? _assignedVan;
  bool _isLoadingVan = false;
  final Set<String> _selectedTimes = {};
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _isCreating = false;

  String _repeatType = 'daily';
  final Set<String> _customDays = {};

  final List<String> _commonTimes = [
    '6:00 AM',
    '7:00 AM',
    '8:00 AM',
    '9:00 AM',
    '10:00 AM',
    '11:00 AM',
    '12:00 PM',
    '1:00 PM',
    '2:00 PM',
    '3:00 PM',
    '4:00 PM',
    '5:00 PM',
    '6:00 PM',
    '7:00 PM',
    '8:00 PM',
    '9:00 PM',
  ];

  String get _templateTitle {
    switch (widget.templateType) {
      case 'daily':
        return 'Daily Service';
      case 'weekdays':
        return 'Weekdays Only';
      case 'weekends':
        return 'Weekend Extra';
      case 'weekly':
        return 'Weekly Service';
      default:
        return 'Quick Template';
    }
  }

  // Add this method to fetch the assigned van for a driver
  Future<void> _loadAssignedVan(String driverId) async {
    setState(() => _isLoadingVan = true);

    try {
      // Query the van using the actual driver ID from your database
      final vanQuery = await FirebaseFirestore.instance
          .collection(ScheduleConstants.vansCollection)
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'Active')
          .limit(1)
          .get();

      if (vanQuery.docs.isNotEmpty) {
        final vanDoc = vanQuery.docs.first;
        final vanData = vanDoc.data();

        setState(() {
          _assignedVan = {
            'id': vanDoc.id,
            'vanId': vanData['vanId'] ?? '',
            'licensePlate': vanData['licensePlate'] ?? '',
            'capacity': vanData['capacity'] ?? ScheduleConstants.defaultCapacity,
            'driverId': vanData['driverId'] ?? '',
            'driverName': vanData['driverName'] ?? '',
          };
        });

      } else {
        setState(() {
          _assignedVan = null;
        });


        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No van assigned to this driver'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading assigned van: $e');
      setState(() {
        _assignedVan = null;
      });
    } finally {
      setState(() => _isLoadingVan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Create $_templateTitle'),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Route Selection
              const Text(
                'Route:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedRoute,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: widget.routes
                    .map(
                      (route) => DropdownMenuItem<String>(
                        value: route['id'] as String,
                        child: Text(route['name']),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedRoute = value),
              ),

              const SizedBox(height: 16),

              // Driver Selection
              const Text(
                'Driver:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedDriver,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: widget.drivers
                    .map<DropdownMenuItem<String>>(
                      (driver) => DropdownMenuItem<String>(
                        value: driver['id'] as String,
                        child: Text(driver['name']),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _selectedDriver = value);
                  if (value != null) {
                    _loadAssignedVan(value); // Auto-load assigned van
                  }
                },
              ),

              const SizedBox(height: 16),

              // Van Selection - Modified to show assigned van
              const Text(
                'Assigned Van:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),

              if (_isLoadingVan)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Loading assigned van...'),
                    ],
                  ),
                )
              else if (_assignedVan != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green[300]!),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.green[50],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.directions_bus, color: Colors.green[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_assignedVan!['vanId']} (${_assignedVan!['licensePlate']})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Capacity: ${_assignedVan!['capacity']} seats',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.check_circle, color: Colors.green[600]),
                    ],
                  ),
                )
              else if (_selectedDriver != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.orange[300]!),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.orange[50],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange[600]),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'No van assigned to this driver. Please assign a van in Van Management first.',
                          style: TextStyle(color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Select a driver to see assigned van',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),

              const SizedBox(height: 16),

              // Time Selection
              const Text(
                'Times:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: _commonTimes.length,
                  itemBuilder: (context, index) {
                    final time = _commonTimes[index];
                    final isSelected = _selectedTimes.contains(time);

                    return FilterChip(
                      label: Text(time, style: const TextStyle(fontSize: 10)),
                      selected: isSelected,
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) {
                            _selectedTimes.add(time);
                          } else {
                            _selectedTimes.remove(time);
                          }
                        });
                      },
                      selectedColor: Colors.blue[100],
                      checkmarkColor: Colors.blue[700],
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Repeat Pattern
              const Text(
                'Repeat Pattern:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _repeatType,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Every Day')),
                  DropdownMenuItem(
                    value: 'weekdays',
                    child: Text('Weekdays Only (Mon-Fri)'),
                  ),
                  DropdownMenuItem(
                    value: 'weekends',
                    child: Text('Weekends Only (Sat-Sun)'),
                  ),
                  DropdownMenuItem(
                    value: 'weekly',
                    child: Text('Every Week (same day)'),
                  ),
                  DropdownMenuItem(value: 'custom', child: Text('Custom Days')),
                ],
                onChanged: (value) => setState(() => _repeatType = value!),
              ),

              // Custom Days Selection (only show if custom is selected)
              if (_repeatType == 'custom') ...[
                const SizedBox(height: 12),
                const Text(
                  'Select Days:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: ScheduleConstants.dayNames.map((day) {
                    final isSelected = _customDays.contains(day);
                    return FilterChip(
                      label: Text(day.substring(0, 3)),
                      selected: isSelected,
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) {
                            _customDays.add(day);
                          } else {
                            _customDays.remove(day);
                          }
                        });
                      },
                      selectedColor: Colors.green[100],
                      checkmarkColor: Colors.green[700],
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 16),

              // Date Range
              const Text(
                'Date Range:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _startDate,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          setState(() => _startDate = date);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Start Date',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(DateFormat('MMM dd, yyyy').format(_startDate)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate:
                              _endDate ??
                              _startDate.add(const Duration(days: 30)),
                          firstDate: _startDate,
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        setState(() => _endDate = date);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'End Date',
                                  style: TextStyle(fontSize: 12),
                                ),
                                if (_endDate != null) ...[
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => _endDate = null),
                                    child: const Icon(Icons.clear, size: 16),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              _endDate != null
                                  ? DateFormat('MMM dd, yyyy').format(_endDate!)
                                  : 'No end date',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Info Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, size: 16, color: Colors.blue[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will create a recurring schedule that automatically generates individual trips based on your pattern.',
                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed:
              (_selectedRoute != null &&
                  _selectedDriver != null &&
                  _assignedVan != null &&
                  _selectedTimes.isNotEmpty &&
                  !_isCreating)
              ? _createSchedule
              : null,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _createSchedule() async {
    setState(() => _isCreating = true);

    try {
      // Use the assigned van data instead of searching in widget.vans
      if (_assignedVan == null) {
        throw Exception('No van assigned to this driver');
      }

      final scheduleData = {
        'routeId': _selectedRoute,
        'driverId': _selectedDriver,
        'driverName': _assignedVan!['driverName'],
        'vanId': _assignedVan!['vanId'], // Use actual vanId (like "van004")
        'vanLicense': _assignedVan!['licensePlate'], // Correct field name
        'seatsTotal': _assignedVan!['capacity'], // Correct field name
        'times': _selectedTimes.toList(),
        'repeatType': widget.templateType,
        'startDate': DateFormat('yyyy-MM-dd').format(_startDate),
        'endDate': _endDate != null
            ? DateFormat('yyyy-MM-dd').format(_endDate!)
            : null,
        'customDays': _repeatType == 'custom' ? _customDays.toList() : [],
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      };


      await FirebaseFirestore.instance
          .collection('recurring_schedules')
          .add(scheduleData);

      widget.onScheduleCreated();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_templateTitle created successfully!')),
      );
    } catch (e) {
      debugPrint('Error creating recurring schedule: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error creating schedule')));
    } finally {
      setState(() => _isCreating = false);
    }
  }
}

class CreateRecurringScheduleDialog extends StatefulWidget {
  final List<Map<String, dynamic>> routes;
  final List<Map<String, dynamic>> drivers;
  final List<Map<String, dynamic>> vans;
  final Map<String, dynamic>? existingSchedule;
  final VoidCallback onScheduleCreated;

  const CreateRecurringScheduleDialog({
    super.key,
    required this.routes,
    required this.drivers,
    required this.vans,
    this.existingSchedule,
    required this.onScheduleCreated,
  });

  @override
  State<CreateRecurringScheduleDialog> createState() =>
      _CreateRecurringScheduleDialogState();
}

class _CreateRecurringScheduleDialogState
    extends State<CreateRecurringScheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedRoute;
  String? _selectedDriver;
  final Set<String> _selectedTimes = {};
  String _repeatType = 'weekly';
  final Set<String> _customDays = {};
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _isCreating = false;

  // Add these variables
  Map<String, dynamic>? _assignedVan;
  bool _isLoadingVan = false;



  @override
  void initState() {
    super.initState();
    if (widget.existingSchedule != null) {
      final schedule = widget.existingSchedule!;
      _selectedRoute = schedule['routeId'];
      _selectedDriver = schedule['driverId'];
      _selectedTimes.clear();
      _selectedTimes.addAll(List<String>.from(schedule['times'] ?? []));
      _repeatType = schedule['repeatType'] ?? 'weekly';
      _customDays.clear();
      _customDays.addAll(List<String>.from(schedule['customDays'] ?? []));
      if (schedule['startDate'] != null) {
        _startDate = DateTime.parse(schedule['startDate']);
      }
      if (schedule['endDate'] != null) {
        _endDate = DateTime.parse(schedule['endDate']);
      }
    }
  }

  // Add this method to fetch the assigned van for a driver
  Future<void> _loadAssignedVan(String driverId) async {
    setState(() => _isLoadingVan = true);

    try {
      // Query the van using the actual driver ID from your database
      final vanQuery = await FirebaseFirestore.instance
          .collection(ScheduleConstants.vansCollection)
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'Active')
          .limit(1)
          .get();

      if (vanQuery.docs.isNotEmpty) {
        final vanDoc = vanQuery.docs.first;
        final vanData = vanDoc.data();

        setState(() {
          _assignedVan = {
            'id': vanDoc.id,
            'vanId': vanData['vanId'] ?? '',
            'licensePlate': vanData['licensePlate'] ?? '',
            'capacity': vanData['capacity'] ?? ScheduleConstants.defaultCapacity,
            'driverId': vanData['driverId'] ?? '',
            'driverName': vanData['driverName'] ?? '',
          };
        });

      } else {
        setState(() {
          _assignedVan = null;
        });


        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No van assigned to this driver'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading assigned van: $e');
      setState(() {
        _assignedVan = null;
      });
    } finally {
      setState(() => _isLoadingVan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingSchedule != null;

    return AlertDialog(
      title: Text(
        isEditing
            ? 'Edit Recurring Schedule'
            : 'Create Custom Recurring Schedule',
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Route Selection
                const Text(
                  'Route:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedRoute,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: widget.routes
                      .map<DropdownMenuItem<String>>(
                        (route) => DropdownMenuItem<String>(
                          value: route['id'] as String,
                          child: Text(route['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedRoute = value),
                  validator: (value) =>
                      value == null ? 'Please select a route' : null,
                ),

                const SizedBox(height: 16),

                // Driver Selection
                const Text(
                  'Driver:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedDriver,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: widget.drivers
                      .map<DropdownMenuItem<String>>(
                        (driver) => DropdownMenuItem<String>(
                          value: driver['id'] as String,
                          child: Text(driver['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedDriver = value);
                    if (value != null) {
                      _loadAssignedVan(value); // Auto-load assigned van
                    }
                  },
                  validator: (value) =>
                      value == null ? 'Please select a driver' : null,
                ),

                const SizedBox(height: 16),

                // Van Selection - Modified to show assigned van
                const Text(
                  'Assigned Van:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),

                if (_isLoadingVan)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Loading assigned van...'),
                      ],
                    ),
                  )
                else if (_assignedVan != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green[300]!),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.green[50],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.directions_bus, color: Colors.green[600]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_assignedVan!['vanId']} (${_assignedVan!['licensePlate']})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Capacity: ${_assignedVan!['capacity']} seats',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.check_circle, color: Colors.green[600]),
                      ],
                    ),
                  )
                else if (_selectedDriver != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange[300]!),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.orange[50],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange[600]),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'No van assigned to this driver. Please assign a van in Van Management first.',
                            style: TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Select a driver to see assigned van',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),

                const SizedBox(height: 16),

                // Time Selection
                const Text(
                  'Times:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          childAspectRatio: 2,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                    itemCount: ScheduleConstants.detailedTimes.length,
                    itemBuilder: (context, index) {
                      final time = ScheduleConstants.detailedTimes[index];
                      final isSelected = _selectedTimes.contains(time);

                      return FilterChip(
                        label: Text(time, style: const TextStyle(fontSize: 10)),
                        selected: isSelected,
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              _selectedTimes.add(time);
                            } else {
                              _selectedTimes.remove(time);
                            }
                          });
                        },
                        selectedColor: Colors.blue[100],
                        checkmarkColor: Colors.blue[700],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Repeat Pattern
                const Text(
                  'Repeat Pattern:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _repeatType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Every Day')),
                    DropdownMenuItem(
                      value: 'weekdays',
                      child: Text('Weekdays Only (Mon-Fri)'),
                    ),
                    DropdownMenuItem(
                      value: 'weekends',
                      child: Text('Weekends Only (Sat-Sun)'),
                    ),
                    DropdownMenuItem(
                      value: 'weekly',
                      child: Text('Every Week (same day)'),
                    ),
                    DropdownMenuItem(
                      value: 'custom',
                      child: Text('Custom Days'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _repeatType = value!),
                ),

                // Custom Days Selection (only show if custom is selected)
                if (_repeatType == 'custom') ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Select Days:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: ScheduleConstants.dayNames.map((day) {
                      final isSelected = _customDays.contains(day);
                      return FilterChip(
                        label: Text(day.substring(0, 3)),
                        selected: isSelected,
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              _customDays.add(day);
                            } else {
                              _customDays.remove(day);
                            }
                          });
                        },
                        selectedColor: Colors.green[100],
                        checkmarkColor: Colors.green[700],
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 16),

                // Date Range
                const Text(
                  'Date Range:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 1),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (date != null) {
                            setState(() => _startDate = date);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Start Date',
                                style: TextStyle(fontSize: 12),
                              ),
                              Text(
                                DateFormat('MMM dd, yyyy').format(_startDate),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate:
                                _endDate ??
                                _startDate.add(const Duration(days: 30)),
                            firstDate: _startDate,
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          setState(() => _endDate = date);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'End Date',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  if (_endDate != null) ...[
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () =>
                                          setState(() => _endDate = null),
                                      child: const Icon(Icons.clear, size: 16),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                _endDate != null
                                    ? DateFormat(
                                        'MMM dd, yyyy',
                                      ).format(_endDate!)
                                    : 'No end date',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Info Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, size: 16, color: Colors.blue[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This will create a recurring schedule that automatically generates individual trips based on your pattern.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_assignedVan != null && !_isCreating)
              ? _saveSchedule
              : null,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Update' : 'Create'),
        ),
      ],
    );
  }

  // Update the _saveSchedule method to use assigned van data
  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) return;

    if (_assignedVan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please ensure the selected driver has an assigned van',
          ),
        ),
      );
      return;
    }

    if (_selectedTimes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one time')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final scheduleData = {
        'routeId': _selectedRoute,
        'driverId': _selectedDriver,
        'driverName': _assignedVan!['driverName'],
        'vanId': _assignedVan!['vanId'],
        'vanLicense': _assignedVan!['licensePlate'],
        'seatsTotal': _assignedVan!['capacity'],
        'times': _selectedTimes.toList(),
        'repeatType': _repeatType,
        'startDate': DateFormat('yyyy-MM-dd').format(_startDate),
        'endDate': _endDate != null
            ? DateFormat('yyyy-MM-dd').format(_endDate!)
            : null,
        'customDays': _repeatType == 'custom' ? _customDays.toList() : [],
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.existingSchedule != null) {
        await FirebaseFirestore.instance
            .collection('recurring_schedules')
            .doc(widget.existingSchedule!['id'])
            .update(scheduleData);
      } else {
        scheduleData['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('recurring_schedules')
            .add(scheduleData);
      }

      widget.onScheduleCreated();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existingSchedule != null
                ? 'Recurring schedule updated successfully!'
                : 'Recurring schedule created successfully!',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error saving schedule')));
    } finally {
      setState(() => _isCreating = false);
    }
  }
}
