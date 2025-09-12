import 'package:admin_vango/driver.dart';
import 'package:admin_vango/recurring_schedule_page.dart';
import 'package:admin_vango/route_management.dart';
import 'package:admin_vango/trip.dart';
import 'package:admin_vango/user.dart';
import 'package:admin_vango/van_management.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isSidebarCollapsed = false;
  String _selectedPage = 'Dashboard';
  int totalUsers = 0;
  int totalDrivers = 0;
  int totalBookings = 0;
  int totalRevenue = 0;

  // Add a ValueNotifier to manage hover state without full rebuilds
  final ValueNotifier<String> _hoveredItemNotifier = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    _loadSummaryData();
  }

  @override
  void dispose() {
    _hoveredItemNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadSummaryData() async {
    final firestore = FirebaseFirestore.instance;

    // Fetch total users
    final userSnapshot = await firestore.collection('users').get();
    final userCount = userSnapshot.size;

    // Fetch total drivers
    final driverSnapshot = await firestore
        .collection('drivers')
        .where('status', isEqualTo: 'approved')
        .get();
    final driverCount = driverSnapshot.size;

    // Fetch bookings and calculate total revenue
    final bookingsSnapshot = await firestore.collection('bookings').get();
    int revenue = 0;
    for (var doc in bookingsSnapshot.docs) {
      revenue += (doc.data()['totalPrice'] ?? 0) as int;
    }

    setState(() {
      totalUsers = userCount;
      totalDrivers = driverCount;
      totalBookings = bookingsSnapshot.size;
      totalRevenue = revenue;
    });
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      // Handle logout error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Stream<List<Map<String, dynamic>>> getRecentBookingsStream() {
    final firestore = FirebaseFirestore.instance;

    return firestore
        .collection('bookings')
        .orderBy('date', descending: true)
        .limit(20) // Get more records to sort properly
        .snapshots()
        .asyncMap((snapshot) async {
          List<Map<String, dynamic>> bookings = [];

          // Collect all unique user IDs first
          Set<String> userIds = {};
          for (var doc in snapshot.docs) {
            final data = doc.data();
            final userId = data['userId'];
            if (userId != null && userId.toString().isNotEmpty) {
              userIds.add(userId);
            }
          }

          // Batch fetch all user data at once
          Map<String, String> userNames = {};
          if (userIds.isNotEmpty) {
            try {
              // Split into chunks of 10 for Firestore 'in' query limit
              final chunks = <List<String>>[];
              final userIdsList = userIds.toList();
              for (int i = 0; i < userIdsList.length; i += 10) {
                chunks.add(userIdsList.sublist(
                  i, 
                  i + 10 > userIdsList.length ? userIdsList.length : i + 10
                ));
              }

              // Fetch users in batches
              for (final chunk in chunks) {
                final usersSnapshot = await firestore
                    .collection('users')
                    .where(FieldPath.documentId, whereIn: chunk)
                    .get();

                for (var userDoc in usersSnapshot.docs) {
                  final userData = userDoc.data();
                  userNames[userDoc.id] = userData['name'] ?? 'Unknown';
                }
              }
            } catch (e) {
              print('Error batch fetching users: $e');
            }
          }

          // Now process bookings with cached user names
          for (var doc in snapshot.docs) {
            final data = doc.data();
            final userId = data['userId'];
            
            String userName = 'Unknown';
            if (userId != null && userNames.containsKey(userId)) {
              userName = userNames[userId]!;
            }

            final seatList = data['selectedSeats'];
            String seatNumber = '';
            if (seatList is List) {
              seatNumber = seatList.join(', ');
            } else {
              seatNumber = 'N/A';
            }

            bookings.add({
              'userName': userName,
              'route': "${data['from']} → ${data['to']}",
              'date': data['date'] ?? '',
              'time': data['time'] ?? '',
              'seat_number': seatNumber,
              'status': _computeBookingStatus(data),
            });
          }

          // Sort by date (descending) and then by time (ascending)
          bookings.sort((a, b) {
            // First sort by date (descending - newest dates first)
            int dateComparison = b['date'].compareTo(a['date']);
            if (dateComparison != 0) {
              return dateComparison;
            }
            
            // If dates are the same, sort by time (ascending - earlier times first)
            return _compareTime(a['time'], b['time']);
          });

          // Return only the first 5 after sorting
          return bookings.take(5).toList();
        });
  }

  // Helper method to compare time strings (e.g., "7:00 AM" vs "9:00 AM")
  int _compareTime(String timeA, String timeB) {
    try {
      // Parse time strings to DateTime for proper comparison
      final DateTime dateTimeA = _parseTimeString(timeA);
      final DateTime dateTimeB = _parseTimeString(timeB);
      
      return dateTimeA.compareTo(dateTimeB);
    } catch (e) {
      // If parsing fails, fall back to string comparison
      return timeA.compareTo(timeB);
    }
  }

  // Helper method to parse time strings like "7:00 AM" to DateTime
  DateTime _parseTimeString(String timeStr) {
    if (timeStr.isEmpty) return DateTime(2000, 1, 1, 23, 59); // Default to end of day
    
    try {
      // Remove extra spaces and convert to uppercase
      final cleanTime = timeStr.trim().toUpperCase();
      
      // Split by space to separate time and AM/PM
      final parts = cleanTime.split(' ');
      if (parts.length != 2) throw FormatException('Invalid time format');
      
      final timePart = parts[0];
      final meridiem = parts[1];
      
      // Split time by colon
      final timeParts = timePart.split(':');
      if (timeParts.length != 2) throw FormatException('Invalid time format');
      
      int hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      
      // Convert to 24-hour format
      if (meridiem == 'PM' && hour != 12) {
        hour += 12;
      } else if (meridiem == 'AM' && hour == 12) {
        hour = 0;
      }
      
      // Return DateTime with today's date but the parsed time
      return DateTime(2000, 1, 1, hour, minute);
    } catch (e) {
      // If parsing fails, return a default time
      return DateTime(2000, 1, 1, 23, 59);
    }
  }

  String _computeBookingStatus(Map<String, dynamic> data) {
    final dateStr = data['date'];
    // Add your status computation logic here
    // For example:
    if (dateStr == null || dateStr.isEmpty) {
      return 'Invalid';
    }

    try {
      final bookingDate = DateTime.parse(dateStr);
      final now = DateTime.now();

      if (bookingDate.isBefore(now)) {
        return 'Completed';
      } else {
        return 'Upcoming';
      }
    } catch (e) {
      return 'Invalid Date';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Completed':
        return Colors.grey;
      case 'Upcoming':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget buildRecentBookingsTable() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: getRecentBookingsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF4E4E94)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading bookings',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.book_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No recent bookings found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }

        final rows = snapshot.data!
            .map(
              (booking) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      booking['userName'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                  ),
                  DataCell(SizedBox(width: 120, child: Text(booking['route']))),
                  DataCell(Text(booking['date'])),
                  DataCell(Text(booking['time'])),
                  DataCell(Text(booking['seat_number'])),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(
                          booking['status'],
                        ).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getStatusColor(
                            booking['status'],
                          ).withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        booking['status'] ?? 'Unknown',
                        style: TextStyle(
                          color: _getStatusColor(booking['status']),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
            .toList();

        return SingleChildScrollView(
          child: DataTable(
            columnSpacing: 20,
            headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
            headingTextStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D3748),
            ),
            dataTextStyle: TextStyle(color: Colors.grey.shade700),
            columns: const [
              DataColumn(label: Text("User")),
              DataColumn(label: Text("Route")),
              DataColumn(label: Text("Date")),
              DataColumn(label: Text("Time")),
              DataColumn(label: Text("Seat Number")),
              DataColumn(label: Text("Status")),
            ],
            rows: rows,
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    switch (_selectedPage) {
      case 'Dashboard':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Dashboard Overview",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                summaryCard("Total Users", totalUsers.toString()),
                const SizedBox(width: 16),
                summaryCard("Total Drivers", totalDrivers.toString()),
                const SizedBox(width: 16),
                summaryCard("Total Bookings", totalBookings.toString()),
                const SizedBox(width: 16),
                summaryCard("Total Revenue", "${totalRevenue}B"),
              ],
            ),
            const SizedBox(height: 40),
            const Text(
              "Recent Bookings",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: buildRecentBookingsTable(),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'Trips':
        return TripPage();
      case 'Users':
        return UserPage();
      case 'Drivers':
        return DriverPage();
      case 'Route Management':
        return RouteManagementPage();
      case 'Recurring Schedules':
        return RecurringScheduleManager();
      case 'Van Management':
        return VanManagementPage();
      default:
        return const Center(child: Text('Unknown page'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9FB),
      body: Row(
        children: [
          if (!_isSidebarCollapsed)
            Container(
              width: 220,
              color: const Color(0xFF4E4E94),
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 24),
                    child: Text(
                      "VanGo Admin",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  navItem(
                    "Dashboard",
                    Icons.dashboard,
                    _selectedPage == "Dashboard",
                    onTap: () {
                      setState(() => _selectedPage = "Dashboard");
                      // Navigate if needed
                    },
                  ),

                  navItem(
                    "Trips",
                    Icons.directions_car,
                    _selectedPage == "Trips",
                    onTap: () {
                      setState(() => _selectedPage = "Trips");
                    },
                  ),

                  navItem(
                    "Users",
                    Icons.people,
                    _selectedPage == "Users",
                    onTap: () {
                      setState(() => _selectedPage = "Users");
                    },
                  ),
                  navItem(
                    "Drivers",
                    Icons.person,
                    _selectedPage == "Drivers",
                    onTap: () {
                      setState(() => _selectedPage = "Drivers");
                    },
                  ),
                  navItem(
                    "Recurring Schedules",
                    Icons.repeat,
                    _selectedPage == "Recurring Schedules",
                    onTap: () {
                      setState(() => _selectedPage = "Recurring Schedules");
                    },
                  ),
                  navItem(
                    "Route Management",
                    Icons.map,
                    _selectedPage == "Route Management",
                    onTap: () {
                      setState(() => _selectedPage = "Route Management");
                    },
                  ),
                  navItem(
                    "Van Management",
                    Icons.directions_bus,
                    _selectedPage == "Van Management",
                    onTap: () {
                      setState(() => _selectedPage = "Van Management");
                    },
                  ),
                  const Spacer(),

                  navItem("Logout", Icons.logout, false, logout: true),
                ],
              ),
            ),

          // Main Content
          Expanded(
            child: Column(
              children: [
                // Header with collapse button outside sidebar
                Container(
                  height: 60,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () {
                      setState(() {
                        _isSidebarCollapsed = !_isSidebarCollapsed;
                      });
                    },
                  ),
                ),

                // Page content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: _buildContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget navItem(
    String label,
    IconData icon,
    bool isSelected, {
    VoidCallback? onTap,
    bool logout = false,
  }) {
    return ValueListenableBuilder<String>(
      valueListenable: _hoveredItemNotifier,
      builder: (context, hoveredItem, child) {
        return MouseRegion(
          onEnter: (_) => _hoveredItemNotifier.value = label,
          onExit: (_) => _hoveredItemNotifier.value = '',
          child: GestureDetector(
            onTap: logout ? _logout : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white
                    : logout
                    ? (hoveredItem == label
                          ? Colors.red.shade700
                          : Colors.red.shade600)
                    : (hoveredItem == label
                          ? Colors.white.withOpacity(0.1)
                          : Colors.transparent),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: isSelected
                        ? const Color(0xFF4E4E94)
                        : logout
                        ? Colors.white
                        : Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: logout
                            ? Colors.white
                            : isSelected
                            ? const Color(0xFF4E4E94)
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget summaryCard(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}