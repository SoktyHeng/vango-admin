import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TripPage extends StatefulWidget {
  const TripPage({super.key});

  @override
  State<TripPage> createState() => _TripPageState();
}

class _TripPageState extends State<TripPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';
  String _selectedDateFilter = 'All';
  String? _selectedRouteFilter;
  List<Map<String, dynamic>> _allRoutes = [];

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    try {
      final routesSnapshot = await _firestore.collection('routes').get();
      setState(() {
        _allRoutes = routesSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'routeId': data['routeId'] ?? doc.id,
            'from': data['from'] ?? '',
            'to': data['to'] ?? '',
            'name': '${data['from'] ?? ''} → ${data['to'] ?? ''}',
          };
        }).toList();
      });
    } catch (e) {
      // Handle error silently or show a snackbar
    }
  }

  Stream<List<Map<String, dynamic>>> getSchedulesStream() {
    return _firestore
        .collection('schedules')
        .orderBy('date', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'routeId': data['routeId'] ?? '',
              'date': data['date'] ?? '',
              'time': data['time'] ?? '',
              'seatsTotal': data['seatsTotal'] ?? 0,
              'seatsTaken': data['seatsTaken'] ?? [],
              'driverId': data['driverId'] ?? '',
              'driverName': data['driverName'] ?? '',
              'vanId': data['vanId'] ?? '',
              'vanLicense': data['vanLicense'] ?? '',
            };
          }).toList(),
        );
  }

  // Get available drivers from Firestore
  Future<List<Map<String, dynamic>>> _getDrivers() async {
    final snapshot = await _firestore.collection('drivers').get();
    return snapshot.docs
        .map(
          (doc) => {
            'id': doc.id,
            'name': doc.data()['name'] ?? 'Unknown Driver',
          },
        )
        .toList();
  }

  // Get available vans from Firestore
  Future<List<Map<String, dynamic>>> _getVans() async {
    final snapshot = await _firestore.collection('vans').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'vanId': data['vanId'] ?? doc.id,
        'licensePlate': data['licensePlate'] ?? 'Unknown License',
        'capacity': data['capacity'] ?? 12,
        'status': data['status'] ?? 'Active',
        'driverId': data['driverId'] ?? '',
        'driverName': data['driverName'] ?? '',
      };
    }).toList();
  }

  // Get available routes from Firestore
  Future<List<Map<String, dynamic>>> _getRoutes() async {
    final snapshot = await _firestore.collection('routes').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'routeId': data['routeId'] ?? doc.id,
        'from': data['from'] ?? '',
        'to': data['to'] ?? '',
        'pricePerSeat': data['pricePerSeat'] ?? 0,
        'name': '${data['from'] ?? ''} → ${data['to'] ?? ''}',
      };
    }).toList();
  }

  void _showAddScheduleDialog() {
    showDialog(
      context: context,
      builder: (context) => AddScheduleDialog(
        onScheduleAdded: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Schedule added successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _filterSchedules(
    List<Map<String, dynamic>> schedules,
  ) {
    var filteredSchedules = schedules;

    // Apply search query filter
    if (_searchQuery.isNotEmpty) {
      filteredSchedules = filteredSchedules.where((schedule) {
        final routeId = schedule['routeId'].toString().toLowerCase();
        final driverName = schedule['driverName'].toString().toLowerCase();
        final vanLicense = schedule['vanLicense'].toString().toLowerCase();
        final date = schedule['date'].toString().toLowerCase();
        final query = _searchQuery.toLowerCase();

        return routeId.contains(query) ||
            driverName.contains(query) ||
            vanLicense.contains(query) ||
            date.contains(query);
      }).toList();
    }

    // Apply date filter
    if (_selectedDateFilter != 'All') {
      filteredSchedules = filteredSchedules.where((schedule) {
        final dateStr = schedule['date'];
        if (dateStr == null || dateStr.isEmpty) return false;

        try {
          final scheduleDate = DateTime.parse(dateStr);
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final scheduleDay = DateTime(scheduleDate.year, scheduleDate.month, scheduleDate.day);

          switch (_selectedDateFilter) {
            case 'Today':
              return scheduleDay.isAtSameMomentAs(today);
            case 'This Week':
              final weekStart = today.subtract(Duration(days: today.weekday - 1));
              final weekEnd = weekStart.add(const Duration(days: 6));
              return scheduleDay.isAfter(weekStart.subtract(const Duration(days: 1))) &&
                     scheduleDay.isBefore(weekEnd.add(const Duration(days: 1)));
            case 'Future':
              return scheduleDay.isAfter(today);
            case 'Past':
              return scheduleDay.isBefore(today);
            default:
              return true;
          }
        } catch (e) {
          return false;
        }
      }).toList();
    }

    // Apply route filter
    if (_selectedRouteFilter != null && _selectedRouteFilter!.isNotEmpty) {
      filteredSchedules = filteredSchedules.where((schedule) {
        return schedule['routeId'] == _selectedRouteFilter;
      }).toList();
    }

    return filteredSchedules;
  }

  String _computeScheduleStatus(Map<String, dynamic> schedule) {
    final dateStr = schedule['date'];
    if (dateStr == null || dateStr.isEmpty) {
      return 'Invalid';
    }

    try {
      final scheduleDate = DateTime.parse(dateStr);
      final now = DateTime.now();

      if (scheduleDate.isBefore(DateTime(now.year, now.month, now.day))) {
        return 'Completed';
      } else if (scheduleDate.isAtSameMomentAs(
        DateTime(now.year, now.month, now.day),
      )) {
        return 'Today';
      } else {
        return 'Upcoming';
      }
    } catch (e) {
      return 'Invalid Date';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Completed':
        return Colors.green;
      case 'Today':
        return Colors.orange;
      case 'Upcoming':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatRoute(String routeId) {
    // Convert route ID to readable format
    // Example: "au_mega" -> "AU → MEGA"
    if (routeId.isEmpty) return 'Unknown Route';

    final parts = routeId.split('_');
    if (parts.length >= 2) {
      return '${parts[0].toUpperCase()} → ${parts[1].toUpperCase()}';
    }
    return routeId.toUpperCase();
  }

  void _showScheduleDetails(Map<String, dynamic> schedule) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Schedule Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('Route:', _formatRoute(schedule['routeId'])),
              _detailRow('Date:', schedule['date']),
              _detailRow('Time:', schedule['time']),
              _detailRow('Driver:', schedule['driverName']),
              _detailRow('Van License:', schedule['vanLicense']),
              _detailRow('Total Seats:', schedule['seatsTotal'].toString()),
              _detailRow(
                'Seats Taken:',
                (schedule['seatsTaken'] as List).length.toString(),
              ),
              _detailRow(
                'Available Seats:',
                (schedule['seatsTotal'] -
                        (schedule['seatsTaken'] as List).length)
                    .toString(),
              ),
              _detailRow('Status:', _computeScheduleStatus(schedule)),
              const SizedBox(height: 16),
              if ((schedule['seatsTaken'] as List).isNotEmpty) ...[
                const Text(
                  'Occupied Seats:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: (schedule['seatsTaken'] as List)
                      .map(
                        (seat) => Chip(
                          label: Text('Seat $seat'),
                          backgroundColor: Colors.red.shade100,
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _editSchedule(schedule);
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _editSchedule(Map<String, dynamic> schedule) {
    // Navigate to edit schedule form or show edit dialog
    // This would be implemented based on your edit requirements
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit functionality coming soon!')),
    );
  }

  Future<void> _deleteSchedule(String scheduleId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: const Text('Are you sure you want to delete this schedule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestore.collection('schedules').doc(scheduleId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Schedule deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting schedule: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedDateFilter = 'All';
      _selectedRouteFilter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Trip Management",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _showAddScheduleDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Schedule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Search Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText:
                    'Search schedules by route, driver, van license, or date...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                // Date Filter
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date Filter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: _selectedDateFilter,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'All', child: Text('All Dates')),
                          DropdownMenuItem(value: 'Today', child: Text('Today')),
                          DropdownMenuItem(value: 'This Week', child: Text('This Week')),
                          DropdownMenuItem(value: 'Future', child: Text('Future Trips')),
                          DropdownMenuItem(value: 'Past', child: Text('Past Trips')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedDateFilter = value ?? 'All';
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Route Filter
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route Filter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: _selectedRouteFilter,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        hint: const Text('All Routes'),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All Routes'),
                          ),
                          ..._allRoutes.map<DropdownMenuItem<String>>(
                            (route) => DropdownMenuItem<String>(
                              value: route['routeId'],
                              child: Text(route['name']),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedRouteFilter = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Clear Filters Button
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Actions',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _clearFilters,
                          icon: Icon(Icons.clear, size: 16),
                          label: const Text('Clear'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Data Table Container
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: getSchedulesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.schedule, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No scheduled trips found',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  final filteredSchedules = _filterSchedules(snapshot.data!);

                  if (filteredSchedules.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.filter_list_off, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'No trips match your filters',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear Filters'),
                          ),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dataTableTheme: DataTableThemeData(
                          headingRowColor: WidgetStateProperty.all(
                            Colors.grey.shade50,
                          ),
                          dataRowColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.hovered)) {
                              return Colors.grey.shade100;
                            }
                            return null;
                          }),
                        ),
                      ),
                      child: DataTable(
                        columnSpacing: 20,
                        horizontalMargin: 20,
                        headingRowHeight: 56,
                        dataRowHeight: 56,
                        columns: const [
                          DataColumn(
                            label: Text(
                              "Date",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              "Time",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              "Route",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              "Driver",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              "Van License",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              "Seats",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              "Status",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          DataColumn(
                            label: Text(
                              "Actions",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                        rows: filteredSchedules.map((schedule) {
                          final status = _computeScheduleStatus(schedule);
                          final seatsTaken =
                              (schedule['seatsTaken'] as List).length;
                          final seatsTotal = schedule['seatsTotal'];

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  schedule['date'],
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              DataCell(
                                Text(
                                  schedule['time'],
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              DataCell(
                                Text(
                                  _formatRoute(schedule['routeId']),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  schedule['driverName'],
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              DataCell(
                                Text(
                                  schedule['vanLicense'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '$seatsTaken/$seatsTotal',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: seatsTaken == seatsTotal
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(
                                      status,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: _getStatusColor(
                                        status,
                                      ).withOpacity(0.5),
                                    ),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: _getStatusColor(status),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.visibility,
                                        size: 18,
                                        color: Colors.blue.shade600,
                                      ),
                                      onPressed: () =>
                                          _showScheduleDetails(schedule),
                                      tooltip: 'View Details',
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit,
                                        size: 18,
                                        color: Colors.orange.shade600,
                                      ),
                                      onPressed: () => _editSchedule(schedule),
                                      tooltip: 'Edit',
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        size: 18,
                                        color: Colors.red.shade600,
                                      ),
                                      onPressed: () =>
                                          _deleteSchedule(schedule['id']),
                                      tooltip: 'Delete',
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ...existing AddScheduleDialog code remains the same...

// Add Schedule Dialog Widget
class AddScheduleDialog extends StatefulWidget {
  final VoidCallback onScheduleAdded;

  const AddScheduleDialog({super.key, required this.onScheduleAdded});

  @override
  State<AddScheduleDialog> createState() => _AddScheduleDialogState();
}

class _AddScheduleDialogState extends State<AddScheduleDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  String? _selectedRouteId;
  String? _selectedVanId;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  List<Map<String, dynamic>> _vans = [];
  List<Map<String, dynamic>> _routes = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final vansSnapshot = await _firestore.collection('vans').get();
      final routesSnapshot = await _firestore.collection('routes').get();

      _vans = vansSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'vanId': data['vanId'] ?? doc.id,
          'licensePlate': data['licensePlate'] ?? 'Unknown License',
          'capacity': data['capacity'] ?? 12,
          'status': data['status'] ?? 'Active',
          'driverId': data['driverId'] ?? '',
          'driverName': data['driverName'] ?? '',
        };
      }).toList();

      _routes = routesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'routeId': data['routeId'] ?? doc.id,
          'from': data['from'] ?? '',
          'to': data['to'] ?? '',
          'pricePerSeat': data['pricePerSeat'] ?? 0,
          'name': '${data['from'] ?? ''} → ${data['to'] ?? ''}',
        };
      }).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      setState(() => _selectedTime = time);
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour == 0
        ? 12
        : time.hour > 12
        ? time.hour - 12
        : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRouteId == null ||
        _selectedVanId == null ||
        _selectedDate == null ||
        _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get van details
      final vanDoc = await _firestore
          .collection('vans')
          .doc(_selectedVanId)
          .get();

      final vanData = vanDoc.data();

      if (vanData == null) {
        throw Exception('Van data not found');
      }

      // Check if van has an assigned driver
      final driverId = vanData['driverId'] ?? '';
      final driverName = vanData['driverName'] ?? '';

      if (driverId.isEmpty) {
        throw Exception('Selected van does not have an assigned driver');
      }

      // Create schedule data
      final scheduleData = {
        'routeId': _selectedRouteId,
        'date':
            '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}',
        'time': _formatTime(_selectedTime!),
        'seatsTotal': vanData['capacity'] ?? 12,
        'seatsTaken': [],
        'driverId': driverId,
        'driverName': driverName,
        'vanId': vanData['vanId'] ?? _selectedVanId,
        'vanLicense': vanData['licensePlate'] ?? 'Unknown License',
      };

      await _firestore.collection('schedules').add(scheduleData);

      if (mounted) {
        Navigator.pop(context);
        widget.onScheduleAdded();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating schedule: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add New Schedule'),
      content: SizedBox(
        width: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Route Selection
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Route',
                          border: OutlineInputBorder(),
                        ),
                        value: _selectedRouteId,
                        items: _routes
                            .map<DropdownMenuItem<String>>(
                              (route) => DropdownMenuItem<String>(
                                value: route['routeId'] as String,
                                child: Text(
                                  route['name'],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedRouteId = value),
                        validator: (value) =>
                            value == null ? 'Please select a route' : null,
                      ),
                      const SizedBox(height: 16),

                      // Date Selection
                      InkWell(
                        onTap: _selectDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _selectedDate == null
                                ? 'Select date'
                                : '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Time Selection
                      InkWell(
                        onTap: _selectTime,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Time',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _selectedTime == null
                                ? 'Select time'
                                : _formatTime(_selectedTime!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Van Selection with Driver Info
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Van (Driver will be auto-assigned)',
                          border: OutlineInputBorder(),
                          helperText: 'Driver is automatically assigned based on van selection',
                        ),
                        value: _selectedVanId,
                        items: _vans
                            .where((van) => van['status'] == 'Active' && van['driverId'].toString().isNotEmpty)
                            .map<DropdownMenuItem<String>>(
                              (van) => DropdownMenuItem<String>(
                                value: van['id'] as String,
                                child: Text(
                                  '${van['vanId']} - ${van['licensePlate']} (${van['capacity']} seats) - Driver: ${van['driverName']}',
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedVanId = value),
                        validator: (value) =>
                            value == null ? 'Please select a van' : null,
                      ),

                      // Show selected driver info
                      if (_selectedVanId != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Assigned Driver:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _vans.firstWhere(
                                  (van) => van['id'] == _selectedVanId,
                                  orElse: () => {'driverName': 'Unknown'},
                                )['driverName'],
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveSchedule,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}