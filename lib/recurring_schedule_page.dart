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

  static const List<String> detailedTimes = [
    '5:00 AM',
    '5:30 AM',
    '6:00 AM',
    '6:30 AM',
    '7:00 AM',
    '7:30 AM',
    '8:00 AM',
    '8:30 AM',
    '9:00 AM',
    '9:30 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '11:30 AM',
    '12:00 PM',
    '12:30 PM',
    '1:00 PM',
    '1:30 PM',
    '2:00 PM',
    '2:30 PM',
    '3:00 PM',
    '3:30 PM',
    '4:00 PM',
    '4:30 PM',
    '5:00 PM',
    '5:30 PM',
    '6:00 PM',
    '6:30 PM',
    '7:00 PM',
    '7:30 PM',
    '8:00 PM',
    '8:30 PM',
    '9:00 PM',
    '9:30 PM',
    '10:00 PM',
  ];

  static const List<String> dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
}

class RecurringScheduleManager extends StatefulWidget {
  const RecurringScheduleManager({super.key});

  @override
  State<RecurringScheduleManager> createState() =>
      _RecurringScheduleManagerState();
}

class _RecurringScheduleManagerState extends State<RecurringScheduleManager> {
  final _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _vans = [];
  bool _isLoading = true;
  bool _isCreating = false;

  // Form fields
  String? _selectedRoute;
  String? _selectedVan;
  Map<String, dynamic>? _assignedDriver;
  bool _isLoadingDriver = false;
  final Set<String> _selectedTimes = {};
  String _repeatType = 'daily';
  final Set<String> _customDays = {};
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadRoutes(), _loadVans()]);
    setState(() {
      _isLoading = false;
    });
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
              'pricePerSeat': doc.data()['pricePerSeat'] ?? 0,
            },
          )
          .toList();
    } catch (e) {
      debugPrint('Error loading routes: $e');
    }
  }

  Future<void> _loadVans() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vans')
          .where('status', isEqualTo: 'Active')
          .get();
      _vans = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id,
              'vanId': doc.data()['vanId'] ?? '',
              'licensePlate': doc.data()['licensePlate'] ?? '',
              'capacity': doc.data()['capacity'] ?? 12,
              'driverId': doc.data()['driverId'] ?? '',
              'driverName': doc.data()['driverName'] ?? '',
            },
          )
          .toList();
    
      // Sort vans by vanId
      _vans.sort((a, b) {
        final vanIdA = a['vanId'].toString().toLowerCase();
        final vanIdB = b['vanId'].toString().toLowerCase();
        return vanIdA.compareTo(vanIdB);
      });
    } catch (e) {
      debugPrint('Error loading vans: $e');
    }
  }

  Future<void> _loadAssignedDriver(String vanId) async {
    setState(() => _isLoadingDriver = true);

    try {
      // Find the selected van
      final selectedVan = _vans.firstWhere(
        (van) => van['vanId'] == vanId,
        orElse: () => {},
      );

      if (selectedVan.isNotEmpty && selectedVan['driverId'].isNotEmpty) {
        // Get driver details
        final driverDoc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(selectedVan['driverId'])
            .get();

        if (driverDoc.exists) {
          setState(() {
            _assignedDriver = {
              'id': driverDoc.id,
              'name': driverDoc.data()?['name'] ?? selectedVan['driverName'],
              'email': driverDoc.data()?['email'] ?? '',
              'phone': driverDoc.data()?['phoneNumber'] ?? '',
            };
          });
        } else {
          // Fallback to stored driver name in van document
          setState(() {
            _assignedDriver = {
              'id': selectedVan['driverId'],
              'name': selectedVan['driverName'],
              'email': '',
              'phone': '',
            };
          });
        }
      } else {
        setState(() {
          _assignedDriver = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No driver assigned to this van'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading assigned driver: $e');
      setState(() {
        _assignedDriver = null;
      });
    } finally {
      setState(() => _isLoadingDriver = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        automaticallyImplyLeading: false, 
        title: const Text(
          'Create Bulking Schedule',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.repeat,
                                color: Colors.blue[600],
                                size: 32,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Create Recurring Schedule',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Set up automated trip generation based on your schedule pattern',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.blue[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Route Selection
                        _buildSectionTitle('Route'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedRoute,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            hintText: 'Select a route',
                          ),
                          items: _routes
                              .map<DropdownMenuItem<String>>(
                                (route) => DropdownMenuItem<String>(
                                  value: route['id'] as String,
                                  child: Text(route['name']),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedRoute = value),
                          validator: (value) =>
                              value == null ? 'Please select a route' : null,
                        ),

                        const SizedBox(height: 24),

                        // Van Selection
                        _buildSectionTitle('Van'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedVan,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            hintText: 'Select a van',
                          ),
                          items: _vans
                              .map<DropdownMenuItem<String>>(
                                (van) => DropdownMenuItem<String>(
                                  value: van['vanId'] as String,
                                  child: Row(
                                    mainAxisSize:
                                        MainAxisSize.min, // FIX: Add this line
                                    children: [
                                      Icon(
                                        Icons.directions_bus,
                                        size: 20,
                                        color: Colors.blue[600],
                                      ),
                                      const SizedBox(width: 12),
                                      // FIX: Remove Expanded and use Flexible with fit: FlexFit.loose
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: Text(
                                          '${van['vanId']} (${van['licensePlate']}) - ${van['capacity']} seats',
                                          overflow: TextOverflow
                                              .ellipsis, // Add ellipsis for long text
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => _selectedVan = value);
                            if (value != null) {
                              _loadAssignedDriver(value);
                            }
                          },
                          validator: (value) =>
                              value == null ? 'Please select a van' : null,
                        ),

                        const SizedBox(height: 24),

                        // Assigned Driver Display
                        _buildSectionTitle('Assigned Driver'),
                        const SizedBox(height: 8),

                        if (_isLoadingDriver)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Loading assigned driver...'),
                              ],
                            ),
                          )
                        else if (_assignedDriver != null)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.green[300]!),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.green[50],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  color: Colors.green[600],
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _assignedDriver!['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                      if (_assignedDriver!['email'].isNotEmpty)
                                        Text(
                                          _assignedDriver!['email'],
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green[600],
                                ),
                              ],
                            ),
                          )
                        else if (_selectedVan != null)
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
                                    'No driver assigned to this van. Please assign a driver in Van Management first.',
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
                              'Select a van to see assigned driver',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),

                        const SizedBox(height: 24),

                        // Time Selection
                        _buildSectionTitle('Times'),
                        const SizedBox(height: 8),
                        Container(
                          height: 200,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  childAspectRatio: 2.2,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: ScheduleConstants.detailedTimes.length,
                            itemBuilder: (context, index) {
                              final time =
                                  ScheduleConstants.detailedTimes[index];
                              final isSelected = _selectedTimes.contains(time);

                              return FilterChip(
                                label: Text(
                                  time,
                                  style: const TextStyle(fontSize: 11),
                                ),
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

                        const SizedBox(height: 24),

                        // Repeat Pattern
                        _buildSectionTitle('Repeat Pattern'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _repeatType,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'daily',
                              child: Text('Every Day'),
                            ),
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
                          onChanged: (value) =>
                              setState(() => _repeatType = value!),
                        ),

                        // Custom Days Selection
                        if (_repeatType == 'custom') ...[
                          const SizedBox(height: 16),
                          _buildSectionTitle('Select Days'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
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

                        const SizedBox(height: 24),

                        // Date Range
                        _buildSectionTitle('Date Range'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _startDate,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                                  if (date != null) {
                                    setState(() => _startDate = date);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Start Date',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat(
                                          'MMM dd, yyyy',
                                        ).format(_startDate),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        _endDate ??
                                        _startDate.add(
                                          const Duration(days: 30),
                                        ),
                                    firstDate: _startDate,
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                                  setState(() => _endDate = date);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'End Date',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          if (_endDate != null) ...[
                                            const Spacer(),
                                            GestureDetector(
                                              onTap: () => setState(
                                                () => _endDate = null,
                                              ),
                                              child: Icon(
                                                Icons.clear,
                                                size: 16,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _endDate != null
                                            ? DateFormat(
                                                'MMM dd, yyyy',
                                              ).format(_endDate!)
                                            : 'No end date',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: _endDate != null
                                              ? Colors.black
                                              : Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _resetForm,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Reset Form'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _canCreateSchedule()
                                    ? _createSchedule
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[600],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: _isCreating
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Text(
                                        'Create Recurring Schedule',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
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
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  bool _canCreateSchedule() {
    return _selectedRoute != null &&
        _selectedVan != null &&
        _assignedDriver != null &&
        _selectedTimes.isNotEmpty &&
        !_isCreating &&
        (_repeatType != 'custom' || _customDays.isNotEmpty);
  }

  void _resetForm() {
    setState(() {
      _selectedRoute = null;
      _selectedVan = null;
      _assignedDriver = null;
      _selectedTimes.clear();
      _repeatType = 'daily';
      _customDays.clear();
      _startDate = DateTime.now();
      _endDate = null;
    });
  }

  Future<void> _createSchedule() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final selectedVan = _vans.firstWhere(
        (van) => van['vanId'] == _selectedVan,
      );

      final scheduleData = {
        'routeId': _selectedRoute,
        'driverId': _assignedDriver!['id'],
        'driverName': _assignedDriver!['name'],
        'vanId': selectedVan['vanId'],
        'vanLicense': selectedVan['licensePlate'],
        'seatsTotal': selectedVan['capacity'],
        'times': _selectedTimes.toList(),
        'repeatType': _repeatType,
        'startDate': DateFormat('yyyy-MM-dd').format(_startDate),
        'endDate': _endDate != null
            ? DateFormat('yyyy-MM-dd').format(_endDate!)
            : null,
        'customDays': _repeatType == 'custom' ? _customDays.toList() : [],
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 1. Save the recurring schedule
      final recurringDoc = await FirebaseFirestore.instance
          .collection('recurring_schedules')
          .add(scheduleData);

      // 2. Generate individual trip schedules based on the pattern
      final generatedCount = await _generateIndividualSchedules({
        ...scheduleData,
        'id': recurringDoc.id,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Recurring schedule created successfully! Generated $generatedCount individual trips.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      _resetForm();
    } catch (e) {
      debugPrint('Error creating recurring schedule: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating schedule: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isCreating = false);
    }
  }

  // Add this new method to generate individual schedules
  Future<int> _generateIndividualSchedules(
    Map<String, dynamic> recurringSchedule,
  ) async {
    int generatedCount = 0;

    try {
      final startDate = DateTime.parse(recurringSchedule['startDate']);
      final endDate = recurringSchedule['endDate'] != null
          ? DateTime.parse(recurringSchedule['endDate'])
          : startDate.add(
              const Duration(days: 365),
            ); // Default to 1 year if no end date

      final times = List<String>.from(recurringSchedule['times']);
      final repeatType = recurringSchedule['repeatType'];
      final customDays = recurringSchedule['customDays'] != null
          ? List<String>.from(recurringSchedule['customDays'])
          : <String>[];

      // Get route details for price
      final routeDoc = await FirebaseFirestore.instance
          .collection('routes')
          .doc(recurringSchedule['routeId'])
          .get();

      final routeData = routeDoc.data() ?? {};

      DateTime currentDate = startDate;

      while (currentDate.isBefore(endDate) ||
          currentDate.isAtSameMomentAs(endDate)) {
        if (_shouldGenerateForDate(recurringSchedule, currentDate)) {
          for (String time in times) {
            // Check if schedule already exists
            final existing = await FirebaseFirestore.instance
                .collection('schedules')
                .where(
                  'date',
                  isEqualTo: DateFormat('yyyy-MM-dd').format(currentDate),
                )
                .where('time', isEqualTo: time)
                .where('routeId', isEqualTo: recurringSchedule['routeId'])
                .where('driverId', isEqualTo: recurringSchedule['driverId'])
                .limit(1)
                .get();

            if (existing.docs.isEmpty) {
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

              // Create individual schedule
              await FirebaseFirestore.instance.collection('schedules').add({
                'date': DateFormat('yyyy-MM-dd').format(currentDate),
                'time': time,
                'routeId': recurringSchedule['routeId'],
                'driverId': recurringSchedule['driverId'],
                'driverName': recurringSchedule['driverName'],
                'vanId': recurringSchedule['vanId'],
                'vanLicense': recurringSchedule['vanLicense'],
                'seatsTotal': recurringSchedule['seatsTotal'],
                'seatsAvailable': recurringSchedule['seatsTotal'],
                'seatsTaken': [],
                'status': initialStatus,
                'recurringScheduleId': recurringSchedule['id'],
                'from': routeData['from'] ?? '',
                'to': routeData['to'] ?? '',
                'price': routeData['pricePerSeat'] ?? 0,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });

              generatedCount++;
            }
          }
        }

        currentDate = currentDate.add(const Duration(days: 1));
      }
    } catch (e) {
      debugPrint('Error generating individual schedules: $e');
    }

    return generatedCount;
  }

  // Add this helper method to determine if a schedule should be generated for a specific date
  bool _shouldGenerateForDate(Map<String, dynamic> schedule, DateTime date) {
    final repeatType = schedule['repeatType'] ?? 'daily';
    final customDays = schedule['customDays'] != null
        ? List<String>.from(schedule['customDays'])
        : <String>[];

    switch (repeatType) {
      case 'daily':
        return true;
      case 'weekdays':
        return date.weekday >= 1 && date.weekday <= 5; // Monday-Friday
      case 'weekends':
        return date.weekday == 6 || date.weekday == 7; // Saturday-Sunday
      case 'weekly':
        final startDate = DateTime.parse(schedule['startDate']);
        return date.weekday == startDate.weekday;
      case 'custom':
        if (customDays.isEmpty) return false;
        final dayNames = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ];
        final dayName = dayNames[date.weekday - 1];
        return customDays.contains(dayName);
      default:
        return false;
    }
  }
}

