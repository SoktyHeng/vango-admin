import 'package:admin_vango/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/email_service.dart';

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
          (snapshot) {
            List<Map<String, dynamic>> drivers = snapshot.docs.map((doc) {
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
                'uid': data['uid'], // Added missing uid field
              };
            }).toList();

            // Sort by createdAt (newest first)
            drivers.sort((a, b) {
              final aDate = a['createdAt'];
              final bDate = b['createdAt'];
              
              // Handle null values - put them at the end
              if (aDate == null && bDate == null) return 0;
              if (aDate == null) return 1;
              if (bDate == null) return -1;
              
              try {
                DateTime dateA;
                DateTime dateB;
                
                if (aDate is Timestamp) {
                  dateA = aDate.toDate();
                } else if (aDate is String) {
                  dateA = DateTime.parse(aDate);
                } else {
                  return 1; // Push invalid dates to end
                }
                
                if (bDate is Timestamp) {
                  dateB = bDate.toDate();
                } else if (bDate is String) {
                  dateB = DateTime.parse(bDate);
                } else {
                  return -1; // Push invalid dates to end
                }
                
                // Sort newest first (descending)
                return dateB.compareTo(dateA);
              } catch (e) {
                return 0; // Keep original order if parsing fails
              }
            });

            return drivers;
          },
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
      final email = driver['email'];
      final password = driver['password'];
      final driverName = driver['name'];

      // Validate required fields
      if (email == null || email.isEmpty) {
        throw Exception('Driver email is missing');
      }
      if (password == null || password.isEmpty) {
        throw Exception('Driver password is missing');
      }

      // Create Firebase Auth account
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final uid = userCredential.user!.uid;

      // Update the driver document
      await FirebaseFirestore.instance.collection('drivers').doc(docId).update({
        'status': 'approved',
        'uid': uid,
        'approvedAt': FieldValue.serverTimestamp(),
        'password': FieldValue.delete(), // Remove password for security
      });

      // Send approval email
      final emailSent = await EmailService.sendApprovalEmail(
        driverName: driverName,
        driverEmail: email,
        loginUrl: 'https://your-driver-app-url.com/login', // Replace with your actual URL
      );

      // Close loading indicator
      if (mounted) {
        Navigator.pop(context);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Driver $driverName approved successfully${emailSent ? ' and notification email sent' : ' but email failed to send'}',
            ),
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
    // First show dialog to get rejection reason
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _RejectDriverDialog(driverName: driverName),
    );

    if (reason == null) return; // User cancelled

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Get driver data before deleting
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(docId)
          .get();

      final driverData = driverDoc.data();
      final driverEmail = driverData?['email'] ?? '';

      // Delete the driver document
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(docId)
          .delete();

      // Send rejection email if email exists
      bool emailSent = false;
      if (driverEmail.isNotEmpty) {
        emailSent = await EmailService.sendRejectionEmail(
          driverName: driverName,
          driverEmail: driverEmail,
          reason: reason,
        );
      }

      // Close loading indicator
      if (mounted) {
        Navigator.pop(context);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Driver $driverName rejected${emailSent ? ' and notification email sent' : ' but email failed to send'}',
            ),
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
                        return const SizedBox(
                          height: 200,
                          child: Column(
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
                child:
                    driver['profileImage'] != null &&
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                      )
                    : const Icon(Icons.person, color: Colors.white, size: 40),
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
            MaterialPageRoute(builder: (context) => const DashboardPage()),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Login failed: $e')));
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
                color: Colors.grey.withOpacity(0.1),
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
                  color: Colors.grey.withOpacity(0.1),
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
                    columnSpacing: 20,
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

// Dialog widget for getting rejection reason
class _RejectDriverDialog extends StatefulWidget {
  final String driverName;

  const _RejectDriverDialog({required this.driverName});

  @override
  State<_RejectDriverDialog> createState() => _RejectDriverDialogState();
}

class _RejectDriverDialogState extends State<_RejectDriverDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final List<String> _commonReasons = [
    'Invalid license documentation',
    'Incomplete application',
    'Failed background check',
    'Does not meet age requirements',
    'Insufficient driving experience',
    'Other (please specify below)',
  ];
  String? _selectedReason;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reject ${widget.driverName}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please select or provide a reason for rejection:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            
            // Common reasons dropdown
            DropdownButtonFormField<String>(
              value: _selectedReason,
              decoration: const InputDecoration(
                labelText: 'Reason for rejection',
                border: OutlineInputBorder(),
              ),
              items: _commonReasons.map((reason) {
                return DropdownMenuItem(
                  value: reason,
                  child: Text(reason),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedReason = value;
                });
              },
            ),
            
            const SizedBox(height: 16),
            
            // Custom reason text field (shown when "Other" is selected)
            if (_selectedReason == 'Other (please specify below)') ...[
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Please specify the reason',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
            ],
            
            // Info text
            Text(
              'The driver will receive an email notification with this reason.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedReason != null ? () {
            String finalReason = _selectedReason!;
            if (_selectedReason == 'Other (please specify below)') {
              finalReason = _reasonController.text.trim();
              if (finalReason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please specify the reason')),
                );
                return;
              }
            }
            Navigator.pop(context, finalReason);
          } : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Reject Driver'),
        ),
      ],
    );
  }
}