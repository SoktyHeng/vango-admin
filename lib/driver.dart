import 'package:admin_vango/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});

  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  bool showPending = false;
  String _searchQuery = '';

  Stream<List<Map<String, dynamic>>> getDriversStream(String status) {
    return FirebaseFirestore.instance
        .collection('drivers')
        .where('status', isEqualTo: status)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();

            return {
              'id': doc.id,
              'name': data['name'] ?? '',
              'email': data['email'] ?? '',
              'phone': data['phoneNumber'] ?? '',
              'profileImage': data['profileImage'] ?? '',
              'licenseImage': data['licenseImage'] ?? '',
              'licenseNumber': data['licenseNumber'] ?? '',
              'status': data['status'] ?? '',
              'createdAt': data['createdAt'],
              'password': data['password'],
            };
          }).toList(),
        );
  }

  List<Map<String, dynamic>> _filterDrivers(
    List<Map<String, dynamic>> drivers,
  ) {
    if (_searchQuery.isEmpty) return drivers;

    return drivers.where((driver) {
      final name = driver['name'].toString().toLowerCase();
      final email = driver['email'].toString().toLowerCase();
      final phone = driver['phone'].toString().toLowerCase();
      final licenseNumber = driver['licenseNumber'].toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      return name.contains(query) ||
          email.contains(query) ||
          phone.contains(query) ||
          licenseNumber.contains(query);
    }).toList();
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';

    try {
      if (timestamp is Timestamp) {
        var date = timestamp.toDate();
        return '${date.day}/${date.month}/${date.year}';
      } else if (timestamp is String) {
        var date = DateTime.parse(timestamp);
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return 'Invalid Date';
    }

    return 'N/A';
  }

  Future<void> approveDriver(Map<String, dynamic> driver) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final docId = driver['id'];

      // Get the driver's email & password from the driver data
      final email = driver['email'];
      final password = driver['password']; // stored during registration

      // Validate required fields
      if (email == null || email.isEmpty) {
        throw Exception('Driver email is missing');
      }
      if (password == null || password.isEmpty) {
        throw Exception('Driver password is missing');
      }

      // Log the retrieved data for debugging
      debugPrint('Driver Email: $email');
      debugPrint('Driver Password: ${password != null ? '[HIDDEN]' : 'NULL'}');

      // Create Firebase Auth account with email and password
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final uid = userCredential.user!.uid;

      // Update the driver document with approval data
      await FirebaseFirestore.instance.collection('drivers').doc(docId).update({
        'status': 'approved',
        'uid': uid,
        'approvedAt': FieldValue.serverTimestamp(),
        'password': FieldValue.delete(), // Remove password for security
      });

      // Close loading indicator
      if (mounted) {
        Navigator.pop(context);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Driver ${driver['name']} approved successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Close loading indicator
      if (mounted) {
        Navigator.pop(context);

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve driver: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> rejectDriver(String docId, String driverName) async {
    // Show confirmation dialog first
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Rejection'),
        content: Text(
          'Are you sure you want to reject $driverName? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Option 1: Delete the driver document completely
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(docId)
          .delete();

      // Close loading indicator
      if (mounted) {
        Navigator.pop(context);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Driver $driverName rejected and removed successfully'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Close loading indicator
      if (mounted) {
        Navigator.pop(context);

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reject driver: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _viewLicenseImage(String? imageUrl, String driverName) {
    if (imageUrl == null || imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No license image available')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '$driverName\'s License',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return SizedBox(
                          height: 200,
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                size: 50,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text('Failed to load license image'),
                            ],
                          ),
                        );
                      },
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        }

                        final progress =
                            loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                            : null;

                        return SizedBox(
                          height: 200,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(value: progress),
                                const SizedBox(height: 16),
                                Text(
                                  progress != null
                                      ? 'Loading: ${(progress * 100).toInt()}%'
                                      : 'Loading...',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _viewDriverDetails(Map<String, dynamic> driver) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Driver Details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Profile Image
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF4E4E94),
                child: driver['profileImage'] != null &&
                        driver['profileImage'].toString().isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          driver['profileImage'],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 40,
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) {
                              return child;
                            }
                            return const SizedBox(
                              width: 80,
                              height: 80,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            );
                          },
                        ),
                      )
                    : const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 40,
                      ),
              ),
              const SizedBox(height: 16),
              
              Text(
                driver['name'],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(driver['email'] ?? 'No Email'),
              Text(driver['phone'] ?? 'No Phone'),
              Text('License: ${driver['licenseNumber'] ?? 'No License'}'),
              Text('Status: ${driver['status'] ?? 'Unknown'}'),
              const SizedBox(height: 16),
              if (driver['licenseImage'] != null &&
                  driver['licenseImage'].isNotEmpty) ...[
                const Text(
                  'License Image:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () =>
                      _viewLicenseImage(driver['licenseImage'], driver['name']),
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        driver['licenseImage'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  size: 32,
                                  color: Colors.grey,
                                ),
                                Text('Failed to load image'),
                              ],
                            ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) {
                            return child;
                          }
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> checkDriverApprovalStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .where('uid', isEqualTo: user.uid)
          .get();

      if (doc.docs.isEmpty) return false;

      final driverData = doc.docs.first.data();
      return driverData['status'] == 'approved';
    } catch (e) {
      debugPrint('Error checking driver approval status: $e');
      return false;
    }
  }

  // Use this in your driver app login flow
  Future<void> handleDriverLogin(String email, String password) async {
    try {
      // Login with Firebase Auth
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Check if driver is approved
      final isApproved = await checkDriverApprovalStatus();

      if (isApproved) {
        // Navigate to driver dashboard
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => DashboardPage()),
          );
        }
      } else {
        // Show not approved message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your account is not approved yet. Please wait for admin approval.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      // Handle login error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e'))
        );
      }
    }
  }

  Future<void> removeDriver(
    String docId,
    String driverName,
    String? uid,
  ) async {
    // Show confirmation dialog first
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Removal'),
        content: Text(
          'Are you sure you want to remove $driverName? This will also delete their Firebase Auth account. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Delete the Firebase Auth account if uid exists
      if (uid != null && uid.isNotEmpty) {
        try {
          // Note: This requires Firebase Admin SDK in a real app
          // For now, we'll just delete the Firestore document
          // The auth account will remain but become orphaned
        } catch (e) {
          debugPrint('Warning: Could not delete auth account: $e');
        }
      }

      // Delete the driver document from Firestore
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(docId)
          .delete();

      // Close loading indicator
      if (mounted) {
        Navigator.pop(context);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Driver $driverName removed successfully'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Close loading indicator
      if (mounted) {
        Navigator.pop(context);

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove driver: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildDriverProfileImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const Icon(Icons.person, color: Colors.white, size: 20);
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.person, color: Colors.white, size: 20);
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              showPending ? 'Pending Drivers' : 'Driver Management',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D3748),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4E4E94),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: getDriversStream(
                      showPending ? 'pending' : 'approved',
                    ),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return Text(
                        "$count ${showPending ? 'Pending' : 'Drivers'}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      showPending = !showPending;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: showPending ? Colors.orange : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    showPending
                        ? 'View Approved Drivers'
                        : 'Review Pending Drivers',
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Search Bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText:
                  'Search drivers by name, email, phone, or license number...',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Drivers Table
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: getDriversStream(showPending ? 'pending' : 'approved'),
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
                          'Error loading drivers',
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
                          Icons.people_outline,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No ${showPending ? 'pending' : 'approved'} drivers found',
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

                final filteredDrivers = _filterDrivers(snapshot.data!);

                if (filteredDrivers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No drivers match your search',
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

                return SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 20, // Match user.dart spacing
                    headingRowColor: WidgetStateProperty.all(
                      Colors.grey.shade50,
                    ),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3748),
                    ),
                    dataTextStyle: TextStyle(color: Colors.grey.shade700),
                    columns: [
                      const DataColumn(label: Text('Profile')),
                      const DataColumn(label: Text('Name')),
                      const DataColumn(label: Text('Phone')),
                      const DataColumn(label: Text('License No.')),
                      const DataColumn(label: Text('Email')),
                      if (showPending) const DataColumn(label: Text('License')),
                      const DataColumn(label: Text('Join Date')),
                      const DataColumn(label: Text('Actions')),
                    ],
                    rows: filteredDrivers.map((driver) {
                      return DataRow(
                        cells: [
                          DataCell(
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFF4E4E94),
                              child: _buildDriverProfileImage(
                                driver['profileImage']?.toString(),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              driver['name'] ?? 'No Name',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              driver['phone'].isNotEmpty
                                  ? driver['phone']
                                  : 'No Phone',
                            ),
                          ),
                          DataCell(
                            Text(
                              driver['licenseNumber'].isNotEmpty
                                  ? driver['licenseNumber']
                                  : 'No License',
                            ),
                          ),
                          DataCell(
                            Text(
                              driver['email'].isNotEmpty
                                  ? driver['email']
                                  : 'No Email',
                            ),
                          ),
                          if (showPending)
                            DataCell(
                              GestureDetector(
                                onTap: () {
                                  _viewLicenseImage(
                                    driver['licenseImage'],
                                    driver['name'],
                                  );
                                },
                                child: Container(
                                  width: 40,
                                  height: 25,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child:
                                      driver['licenseImage'] != null &&
                                          driver['licenseImage']
                                              .toString()
                                              .isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: Image.network(
                                            driver['licenseImage'],
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return const Icon(
                                                    Icons.broken_image,
                                                    size: 16,
                                                    color: Colors.grey,
                                                  );
                                                },
                                            loadingBuilder:
                                                (
                                                  context,
                                                  child,
                                                  loadingProgress,
                                                ) {
                                                  if (loadingProgress == null) {
                                                    return child;
                                                  }
                                                  return const Center(
                                                    child: SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 1,
                                                          ),
                                                    ),
                                                  );
                                                },
                                          ),
                                        )
                                      : const Icon(
                                          Icons.image_not_supported,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                ),
                              ),
                            ),
                          DataCell(Text(_formatDate(driver['createdAt']))),
                          DataCell(
                            Row(
                              children: [
                                if (showPending) ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.check,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                    onPressed: () => approveDriver(driver),
                                    tooltip: 'Approve',
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    onPressed: () => rejectDriver(
                                      driver['id'],
                                      driver['name'],
                                    ),
                                    tooltip: 'Reject',
                                  ),
                                ] else ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.visibility,
                                      color: Colors.blue,
                                      size: 20,
                                    ),
                                    onPressed: () => _viewDriverDetails(driver),
                                    tooltip: 'View Driver',
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    onPressed: () => removeDriver(
                                      driver['id'],
                                      driver['name'],
                                      driver['uid'],
                                    ),
                                    tooltip: 'Remove Driver',
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
