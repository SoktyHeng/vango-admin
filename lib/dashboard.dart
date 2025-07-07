import 'package:admin_vango/driver.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSummaryData();
  }

  Future<void> _loadSummaryData() async {
    final firestore = FirebaseFirestore.instance;

    // Fetch total users
    final userSnapshot = await firestore.collection('users').get();
    final userCount = userSnapshot.size;

    // Fetch total drivers

    // Fetch bookings and calculate total revenue
    final bookingsSnapshot = await firestore.collection('bookings').get();
    int revenue = 0;
    for (var doc in bookingsSnapshot.docs) {
      revenue += (doc.data()['totalPrice'] ?? 0) as int;
    }

    setState(() {
      totalUsers = userCount;
      totalDrivers = 0;
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
        .limit(5)
        .snapshots()
        .asyncMap((snapshot) async {
          List<Map<String, dynamic>> bookings = [];

          for (var doc in snapshot.docs) {
            final data = doc.data();

            // Fetch user data
            String userName = 'Unknown';
            try {
              final userDoc = await firestore
                  .collection('users')
                  .doc(data['userId'])
                  .get();
              userName = userDoc.exists && userDoc.data() != null
                  ? userDoc.data()!['name'] ?? 'Unknown'
                  : 'Unknown';
            } catch (_) {}

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

          return bookings;
        });
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

  Widget buildRecentBookingsTable() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: getRecentBookingsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rows = snapshot.data!
            .map(
              (booking) => DataRow(
                cells: [
                  DataCell(Text(booking['userName'])),
                  DataCell(SizedBox(width: 80, child: Text(booking['route']))),
                  DataCell(Text(booking['date'])),
                  DataCell(Text(booking['time'])),
                  DataCell(Text(booking['seat_number'])),
                  DataCell(Text(booking['status'])),
                ],
              ),
            )
            .toList();

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
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
                    "Route Management",
                    Icons.route,
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
    return GestureDetector(
      onTap: logout ? _logout : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white
              : logout
              ? Colors.red.shade600
              : Colors.transparent,
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
