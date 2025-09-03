import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TripPage extends StatefulWidget {
  final bool isRecurring;
  const TripPage({super.key, this.isRecurring = false});

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

  // Add this helper method to parse time strings to comparable values
  int _parseTimeToMinutes(String timeString) {
    try {
      // Handle formats like "7:00 AM", "9:00 AM", "12:30 PM", etc.
      final parts = timeString.split(' ');
      if (parts.length != 2) return 0;

      final timePart = parts[0];
      final amPm = parts[1].toUpperCase();

      final timeSplit = timePart.split(':');
      if (timeSplit.length != 2) return 0;

      int hour = int.tryParse(timeSplit[0]) ?? 0;
      final minute = int.tryParse(timeSplit[1]) ?? 0;

      // Convert to 24-hour format
      if (amPm == 'PM' && hour != 12) {
        hour += 12;
      } else if (amPm == 'AM' && hour == 12) {
        hour = 0;
      }

      return hour * 60 + minute;
    } catch (e) {
      print('Error parsing time: $timeString - $e');
      return 0;
    }
  }

  Stream<List<Map<String, dynamic>>> getSchedulesStream() {
    return _firestore
        .collection('schedules')
        .orderBy('date', descending: false)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) {
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
                  'status': data['status'] ?? 'active',
                  'createdAt': data['createdAt'],
                  'updatedAt': data['updatedAt'],
                };
              }).toList()..sort((a, b) {
                // First sort by date
                final dateCompare = a['date'].compareTo(b['date']);
                if (dateCompare != 0) return dateCompare;

                // If dates are the same, sort by time using proper time parsing
                final aTime = a['time'] ?? '';
                final bTime = b['time'] ?? '';
                final aTimeMinutes = _parseTimeToMinutes(aTime);
                final bTimeMinutes = _parseTimeToMinutes(bTime);

                return aTimeMinutes.compareTo(bTimeMinutes);
              }),
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

  // SOLUTION 1: Bulk Driver Update Feature
  Future<void> _showBulkDriverUpdateDialog() async {
    showDialog(
      context: context,
      builder: (context) => BulkDriverUpdateDialog(
        onUpdateComplete: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Driver assignments updated successfully!'),
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
          final scheduleDay = DateTime(
            scheduleDate.year,
            scheduleDate.month,
            scheduleDate.day,
          );

          switch (_selectedDateFilter) {
            case 'Today':
              return scheduleDay.isAtSameMomentAs(today);
            case 'This Week':
              final weekStart = today.subtract(
                Duration(days: today.weekday - 1),
              );
              final weekEnd = weekStart.add(const Duration(days: 6));
              return scheduleDay.isAfter(
                    weekStart.subtract(const Duration(days: 1)),
                  ) &&
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
    // First check if there's a stored status
    final storedStatus = schedule['status'];
    if (storedStatus != null && storedStatus.isNotEmpty) {
      return storedStatus;
    }

    // Fallback to date-based computation for backward compatibility
    final dateStr = schedule['date'];
    if (dateStr == null || dateStr.isEmpty) {
      return 'invalid';
    }

    try {
      final scheduleDate = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final scheduleDay = DateTime(
        scheduleDate.year,
        scheduleDate.month,
        scheduleDate.day,
      );

      if (scheduleDay.isBefore(today)) {
        return 'completed';
      } else if (scheduleDay.isAtSameMomentAs(today)) {
        return 'active';
      } else {
        return 'scheduled';
      }
    } catch (e) {
      return 'invalid';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'scheduled':
        return Colors.blue;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      case 'delayed':
        return Colors.orange;
      case 'invalid':
        return Colors.red.shade300;
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
    showDialog(
      context: context,
      builder: (context) => EditScheduleDialog(
        schedule: schedule,
        onScheduleUpdated: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Schedule updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
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

  Future<void> _updateScheduleStatus(
    String scheduleId,
    String newStatus,
  ) async {
    try {
      await _firestore.collection('schedules').doc(scheduleId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schedule status updated to "$newStatus"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - UPDATED with Bulk Update Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Trip Management",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _showBulkDriverUpdateDialog,
                    icon: const Icon(Icons.sync),
                    label: const Text('Update Drivers'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
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
                  const SizedBox(width: 12),
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
                          DropdownMenuItem(
                            value: 'All',
                            child: Text('All Dates'),
                          ),
                          DropdownMenuItem(
                            value: 'Today',
                            child: Text('Today'),
                          ),
                          DropdownMenuItem(
                            value: 'This Week',
                            child: Text('This Week'),
                          ),
                          DropdownMenuItem(
                            value: 'Future',
                            child: Text('Future Trips'),
                          ),
                          DropdownMenuItem(
                            value: 'Past',
                            child: Text('Past Trips'),
                          ),
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
                          Icon(
                            Icons.filter_list_off,
                            size: 64,
                            color: Colors.grey,
                          ),
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
                                    PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert,
                                        size: 18,
                                        color: Colors.grey.shade600,
                                      ),
                                      tooltip: 'More Actions',
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'edit':
                                            _editSchedule(schedule);
                                            break;
                                          case 'complete':
                                            _updateScheduleStatus(
                                              schedule['id'],
                                              'completed',
                                            );
                                            break;
                                          case 'cancel':
                                            _updateScheduleStatus(
                                              schedule['id'],
                                              'cancelled',
                                            );
                                            break;
                                          case 'activate':
                                            _updateScheduleStatus(
                                              schedule['id'],
                                              'active',
                                            );
                                            break;
                                          case 'delete':
                                            _deleteSchedule(schedule['id']);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) {
                                        final currentStatus =
                                            schedule['status'] ?? 'active';

                                        return [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.edit,
                                                  size: 16,
                                                  color: Colors.orange,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Edit'),
                                              ],
                                            ),
                                          ),
                                          // Show "Mark Complete" for active trips only
                                          if (currentStatus == 'active')
                                            const PopupMenuItem(
                                              value: 'complete',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.check_circle,
                                                    size: 16,
                                                    color: Colors.green,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Mark Complete'),
                                                ],
                                              ),
                                            ),
                                          // Show "Cancel" for both active AND scheduled trips
                                          if (currentStatus == 'active' ||
                                              currentStatus == 'scheduled')
                                            const PopupMenuItem(
                                              value: 'cancel',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.cancel,
                                                    size: 16,
                                                    color: Colors.red,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text('Cancel'),
                                                ],
                                              ),
                                            ),
                                          const PopupMenuDivider(),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.delete,
                                                  size: 16,
                                                  color: Colors.red,
                                                ),
                                                SizedBox(width: 8),
                                                Text('Delete'),
                                              ],
                                            ),
                                          ),
                                        ];
                                      },
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

// NEW: Edit Schedule Dialog
class EditScheduleDialog extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final VoidCallback onScheduleUpdated;

  const EditScheduleDialog({
    super.key,
    required this.schedule,
    required this.onScheduleUpdated,
  });

  @override
  State<EditScheduleDialog> createState() => _EditScheduleDialogState();
}

class _EditScheduleDialogState extends State<EditScheduleDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  String? _selectedRouteId;
  String? _selectedVanId;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  List<Map<String, dynamic>> _vans = [];
  List<Map<String, dynamic>> _routes = [];
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initializeFields();
    _loadData();
  }

  void _initializeFields() {
    // Initialize with existing schedule data
    _selectedRouteId = widget.schedule['routeId'];

    // Parse date
    final dateStr = widget.schedule['date'];
    try {
      _selectedDate = DateTime.parse(dateStr);
    } catch (e) {
      _selectedDate = DateTime.now();
    }

    // Parse time
    final timeStr = widget.schedule['time'];
    _selectedTime = _parseTimeOfDay(timeStr);

    // Van will be set after loading vans data
    _selectedVanId = widget.schedule['vanId'];
  }

  TimeOfDay _parseTimeOfDay(String timeString) {
    try {
      // Handle formats like "7:00 AM", "9:00 AM", "12:30 PM", etc.
      final parts = timeString.split(' ');
      if (parts.length != 2) return TimeOfDay.now();

      final timePart = parts[0];
      final amPm = parts[1].toUpperCase();

      final timeSplit = timePart.split(':');
      if (timeSplit.length != 2) return TimeOfDay.now();

      int hour = int.tryParse(timeSplit[0]) ?? 0;
      final minute = int.tryParse(timeSplit[1]) ?? 0;

      // Convert to 24-hour format
      if (amPm == 'PM' && hour != 12) {
        hour += 12;
      } else if (amPm == 'AM' && hour == 12) {
        hour = 0;
      }

      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return TimeOfDay.now();
    }
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

      // Find the van document ID based on vanId
      final currentVan = _vans.firstWhere(
        (van) => van['vanId'] == widget.schedule['vanId'],
        orElse: () => {},
      );
      if (currentVan.isNotEmpty) {
        _selectedVanId = currentVan['id'];
      }
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
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
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

  Future<void> _updateSchedule() async {
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

    setState(() => _isSaving = true);

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

      // Determine status based on date
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final scheduleDay = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
      );

      String status;
      if (scheduleDay.isAtSameMomentAs(today)) {
        status = 'active'; // Today's trips are active
      } else if (scheduleDay.isAfter(today)) {
        status = 'scheduled'; // Future trips are scheduled
      } else {
        status = 'completed'; // Past trips are considered completed
      }

      // Update schedule data
      final updatedData = {
        'routeId': _selectedRouteId,
        'date':
            '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}',
        'time': _formatTime(_selectedTime!),
        'seatsTotal': vanData['capacity'] ?? 12,
        'driverId': driverId,
        'driverName': driverName,
        'vanId': vanData['vanId'] ?? _selectedVanId,
        'vanLicense': vanData['licensePlate'] ?? 'Unknown License',
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection('schedules')
          .doc(widget.schedule['id'])
          .update(updatedData);

      if (mounted) {
        Navigator.pop(context);
        widget.onScheduleUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating schedule: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Schedule'),
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
                      // Current Schedule Info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Schedule:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.schedule['date']} at ${widget.schedule['time']}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            Text(
                              'Route: ${widget.schedule['routeId']} | Van: ${widget.schedule['vanId']} | Driver: ${widget.schedule['driverName']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),

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
                                child: Text(route['name']),
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
                          helperText:
                              'Driver is automatically assigned based on van selection',
                        ),
                        value: _selectedVanId,
                        items: _vans
                            .where(
                              (van) =>
                                  van['status'] == 'Active' &&
                                  van['driverId'].toString().isNotEmpty,
                            )
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
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Updated Driver Assignment:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.green.shade700,
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
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Seats warning if there are existing bookings
                      if ((widget.schedule['seatsTaken'] as List)
                          .isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.warning,
                                    size: 16,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Existing Bookings Warning',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'This schedule has ${(widget.schedule['seatsTaken'] as List).length} booked seats. Changes may affect passenger bookings.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade600,
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
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _updateSchedule,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update Schedule'),
        ),
      ],
    );
  }
}

// SOLUTION 1: Bulk Driver Update Dialog
class BulkDriverUpdateDialog extends StatefulWidget {
  final VoidCallback onUpdateComplete;

  const BulkDriverUpdateDialog({super.key, required this.onUpdateComplete});

  @override
  State<BulkDriverUpdateDialog> createState() => _BulkDriverUpdateDialogState();
}

class _BulkDriverUpdateDialogState extends State<BulkDriverUpdateDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isUpdating = false;
  String _updateMode = 'future_only'; // 'all', 'future_only', 'date_range'
  DateTimeRange? _dateRange;
  List<String> _updateLog = [];

  Future<void> _performBulkUpdate() async {
    setState(() {
      _isUpdating = true;
      _updateLog.clear();
    });

    try {
      // Get current van-driver mappings
      final vansSnapshot = await _firestore.collection('vans').get();
      final Map<String, Map<String, dynamic>> vanDriverMap = {};

      for (var vanDoc in vansSnapshot.docs) {
        final vanData = vanDoc.data();
        final vanId = vanData['vanId'];
        if (vanId != null) {
          vanDriverMap[vanId] = {
            'driverId': vanData['driverId'] ?? '',
            'driverName': vanData['driverName'] ?? '',
            'licensePlate': vanData['licensePlate'] ?? '',
          };
        }
      }

      // Get schedules to update based on mode
      Query scheduleQuery = _firestore.collection('schedules');

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      if (_updateMode == 'future_only') {
        final todayStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        scheduleQuery = scheduleQuery.where(
          'date',
          isGreaterThanOrEqualTo: todayStr,
        );
      } else if (_updateMode == 'date_range' && _dateRange != null) {
        final startStr =
            '${_dateRange!.start.year}-${_dateRange!.start.month.toString().padLeft(2, '0')}-${_dateRange!.start.day.toString().padLeft(2, '0')}';
        final endStr =
            '${_dateRange!.end.year}-${_dateRange!.end.month.toString().padLeft(2, '0')}-${_dateRange!.end.day.toString().padLeft(2, '0')}';
        scheduleQuery = scheduleQuery
            .where('date', isGreaterThanOrEqualTo: startStr)
            .where('date', isLessThanOrEqualTo: endStr);
      }

      final schedulesSnapshot = await scheduleQuery.get();
      int updatedCount = 0;
      int skippedCount = 0;

      // Update each schedule
      for (var scheduleDoc in schedulesSnapshot.docs) {
        final scheduleData = scheduleDoc.data() as Map<String, dynamic>;
        final vanId = scheduleData['vanId'];

        if (vanId != null && vanDriverMap.containsKey(vanId)) {
          final newDriverInfo = vanDriverMap[vanId]!;
          final currentDriverId = scheduleData['driverId'];

          // Only update if driver has changed
          if (currentDriverId != newDriverInfo['driverId']) {
            await scheduleDoc.reference.update({
              'driverId': newDriverInfo['driverId'],
              'driverName': newDriverInfo['driverName'],
              'vanLicense': newDriverInfo['licensePlate'],
              'updatedAt': FieldValue.serverTimestamp(),
            });

            updatedCount++;
            setState(() {
              _updateLog.add(
                'Updated ${scheduleData['date']} ${scheduleData['time']}: ${currentDriverId} → ${newDriverInfo['driverId']}',
              );
            });
          } else {
            skippedCount++;
          }
        }
      }

      setState(() {
        _updateLog.add('\n✅ Update complete:');
        _updateLog.add('- Updated: $updatedCount schedules');
        _updateLog.add('- Skipped: $skippedCount schedules (no change needed)');
      });
    } catch (e) {
      setState(() {
        _updateLog.add('❌ Error: $e');
      });
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  Future<void> _selectDateRange() async {
    final dateRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );

    if (dateRange != null) {
      setState(() => _dateRange = dateRange);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bulk Update Driver Assignments'),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will sync driver assignments from the current van-driver mappings to existing schedules.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            const Text(
              'Update Mode:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            RadioListTile<String>(
              title: const Text('Future trips only (recommended)'),
              subtitle: const Text('Only update today and future schedules'),
              value: 'future_only',
              groupValue: _updateMode,
              onChanged: (value) => setState(() => _updateMode = value!),
            ),

            RadioListTile<String>(
              title: const Text('All trips'),
              subtitle: const Text(
                'Update all schedules (including past ones)',
              ),
              value: 'all',
              groupValue: _updateMode,
              onChanged: (value) => setState(() => _updateMode = value!),
            ),

            RadioListTile<String>(
              title: const Text('Date range'),
              subtitle: Text(
                _dateRange != null
                    ? 'From ${_dateRange!.start.day}/${_dateRange!.start.month} to ${_dateRange!.end.day}/${_dateRange!.end.month}'
                    : 'Select date range',
              ),
              value: 'date_range',
              groupValue: _updateMode,
              onChanged: (value) => setState(() => _updateMode = value!),
            ),

            if (_updateMode == 'date_range')
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: ElevatedButton(
                  onPressed: _selectDateRange,
                  child: Text(
                    _dateRange != null
                        ? 'Change Date Range'
                        : 'Select Date Range',
                  ),
                ),
              ),

            const SizedBox(height: 20),

            if (_updateLog.isNotEmpty) ...[
              const Text(
                'Update Log:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _updateLog
                          .map(
                            (log) => Text(
                              log,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ] else
              const Expanded(child: SizedBox()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        ElevatedButton(
          onPressed:
              (_isUpdating ||
                  (_updateMode == 'date_range' && _dateRange == null))
              ? null
              : () async {
                  await _performBulkUpdate();
                  if (_updateLog.any((log) => log.contains('✅'))) {
                    widget.onUpdateComplete();
                  }
                },
          child: _isUpdating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update Driver Assignments'),
        ),
      ],
    );
  }
}

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

      // Determine initial status based on date
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final scheduleDay = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
      );

      String initialStatus;
      if (scheduleDay.isAtSameMomentAs(today)) {
        initialStatus = 'active'; // Today's trips are active
      } else if (scheduleDay.isAfter(today)) {
        initialStatus = 'scheduled'; // Future trips are scheduled
      } else {
        initialStatus =
            'active'; // Past dates (shouldn't happen with date picker restrictions)
      }

      // Create schedule data with status
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
        'status': initialStatus, // Add status field
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
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
                                child: Text(route['name']),
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
                          helperText:
                              'Driver is automatically assigned based on van selection',
                        ),
                        value: _selectedVanId,
                        items: _vans
                            .where(
                              (van) =>
                                  van['status'] == 'Active' &&
                                  van['driverId'].toString().isNotEmpty,
                            )
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
