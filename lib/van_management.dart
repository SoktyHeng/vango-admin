import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VanManagementPage extends StatefulWidget {
  const VanManagementPage({super.key});

  @override
  State<VanManagementPage> createState() => _VanManagementPageState();
}

class _VanManagementPageState extends State<VanManagementPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Generate next van ID
  Future<String> _generateVanId() async {
    try {
      final QuerySnapshot vansSnapshot = await _firestore.collection('vans').get();
      
      // Extract existing van numbers
      List<int> existingNumbers = [];
      for (var doc in vansSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final vanId = data['vanId'] as String?;
        if (vanId != null && vanId.startsWith('van')) {
          final numberStr = vanId.substring(3);
          final number = int.tryParse(numberStr);
          if (number != null) {
            existingNumbers.add(number);
          }
        }
      }
      
      // Find next available number
      int nextNumber = 1;
      existingNumbers.sort();
      for (int number in existingNumbers) {
        if (number == nextNumber) {
          nextNumber++;
        } else {
          break;
        }
      }
      
      return 'van${nextNumber.toString().padLeft(3, '0')}';
    } catch (e) {
      // Fallback to timestamp-based ID if error occurs
      return 'van${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    }
  }

  // Stream with sorting applied
  Stream<List<Map<String, dynamic>>> getVansStream() {
    return _firestore.collection('vans').snapshots().map((snapshot) {
      List<Map<String, dynamic>> vans = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'docId': doc.id,
          ...data,
        };
      }).toList();

      // Sort by createdAt (newest first)
      vans.sort((a, b) {
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

      return vans;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Van Management",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddVanDialog(),
              icon: const Icon(Icons.add),
              label: const Text("Add New Van"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
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
              stream: getVansStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_bus, size: 80, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No vans found',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        Text(
                          'Click "Add New Van" to get started',
                          style: TextStyle(color: Colors.grey),
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
                    columns: const [
                      DataColumn(label: Text('Van ID')),
                      DataColumn(label: Text('License Plate')),
                      DataColumn(label: Text('Driver')),
                      DataColumn(label: Text('Capacity')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: snapshot.data!.map((data) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              data['vanId'] ?? data['docId'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D3748),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              data['licensePlate'] ?? 'N/A',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              data['driverName'] ?? 'Unassigned',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${data['capacity'] ?? 0}',
                              style: TextStyle(
                                color: Colors.grey.shade700,
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
                                color: _getStatusColor(data['status']).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _getStatusColor(data['status']).withOpacity(0.5),
                                ),
                              ),
                              child: Text(
                                data['status'] ?? 'Unknown',
                                style: TextStyle(
                                  color: _getStatusColor(data['status']),
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
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                  onPressed: () => _showEditVanDialog(data['docId'], data),
                                  tooltip: 'Edit Van',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  onPressed: () => _showDeleteConfirmation(data['docId']),
                                  tooltip: 'Delete Van',
                                ),
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

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.red;
      case 'maintenance':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  void _showAddVanDialog() {
    showDialog(
      context: context,
      builder: (context) => VanFormDialog(
        title: 'Add New Van',
        onSave: (vanData) async {
          try {
            // Generate custom van ID
            final vanId = await _generateVanId();
            vanData['vanId'] = vanId;
            
            await _firestore.collection('vans').add(vanData);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Van $vanId added successfully!')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error adding van: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _showEditVanDialog(String docId, Map<String, dynamic> vanData) {
    showDialog(
      context: context,
      builder: (context) => VanFormDialog(
        title: 'Edit Van',
        initialData: vanData,
        currentVanDocId: docId,
        onSave: (updatedData) async {
          try {
            await _firestore.collection('vans').doc(docId).update(updatedData);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Van ${vanData['vanId'] ?? docId} updated successfully!')),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error updating van: $e')),
              );
            }
          }
        },
      ),
    );
  }

  void _showDeleteConfirmation(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Van'),
        content: const Text('Are you sure you want to delete this van? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await _firestore.collection('vans').doc(docId).delete();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Van deleted successfully!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting van: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class VanFormDialog extends StatefulWidget {
  final String title;
  final Map<String, dynamic>? initialData;
  final String? currentVanDocId;
  final Function(Map<String, dynamic>) onSave;

  const VanFormDialog({
    super.key,
    required this.title,
    this.initialData,
    this.currentVanDocId,
    required this.onSave,
  });

  @override
  State<VanFormDialog> createState() => _VanFormDialogState();
}

class _VanFormDialogState extends State<VanFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late TextEditingController _licensePlateController;
  late TextEditingController _capacityController;
  
  String? _selectedDriverId;
  String _selectedStatus = 'Active';
  List<Map<String, dynamic>> _drivers = [];
  Set<String> _assignedDriverIds = {};
  bool _loadingDrivers = true;

  final List<String> _statusOptions = ['Active', 'Inactive', 'Maintenance'];

  @override
  void initState() {
    super.initState();
    _licensePlateController = TextEditingController(
      text: widget.initialData?['licensePlate'] ?? '',
    );
    _capacityController = TextEditingController(
      text: widget.initialData?['capacity']?.toString() ?? '',
    );
    _selectedStatus = widget.initialData?['status'] ?? 'Active';
    _selectedDriverId = widget.initialData?['driverId'];
    
    _loadDriversAndAssignments();
  }

  Future<void> _loadDriversAndAssignments() async {
    try {
      // Load all drivers
      final QuerySnapshot driversSnapshot = await _firestore.collection('drivers').get();
      
      // Load all vans to check driver assignments
      final QuerySnapshot vansSnapshot = await _firestore.collection('vans').get();
      
      Set<String> assignedDriverIds = {};
      for (var vanDoc in vansSnapshot.docs) {
        final vanData = vanDoc.data() as Map<String, dynamic>;
        final driverId = vanData['driverId'] as String?;
        
        // Exclude current van's driver if editing
        if (driverId != null && vanDoc.id != widget.currentVanDocId) {
          assignedDriverIds.add(driverId);
        }
      }
      
      setState(() {
        _drivers = driversSnapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['name'] ?? 'Unknown Driver',
            'email': data['email'] ?? '',
            'phone': data['phone'] ?? '',
          };
        }).toList();
        _assignedDriverIds = assignedDriverIds;
        _loadingDrivers = false;
      });
    } catch (e) {
      setState(() {
        _loadingDrivers = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading drivers: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _licensePlateController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _licensePlateController,
                decoration: const InputDecoration(
                  labelText: 'License Plate',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter license plate';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _loadingDrivers
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      value: _selectedDriverId,
                      decoration: const InputDecoration(
                        labelText: 'Driver',
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Select a driver'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Unassigned'),
                        ),
                        ..._drivers.map((driver) {
                          final isAssigned = _assignedDriverIds.contains(driver['id']);
                          final isCurrentlySelected = driver['id'] == _selectedDriverId;
                          
                          return DropdownMenuItem<String>(
                            value: driver['id'],
                            enabled: !isAssigned || isCurrentlySelected,
                            child: Row(
                              children: [
                                Text(
                                  driver['name'],
                                  style: TextStyle(
                                    color: isAssigned && !isCurrentlySelected
                                        ? Colors.grey
                                        : null,
                                  ),
                                ),
                                if (isAssigned && !isCurrentlySelected)
                                  const Text(
                                    ' (Already Assigned)',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedDriverId = value;
                        });
                      },
                    ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _capacityController,
                decoration: const InputDecoration(
                  labelText: 'Capacity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter capacity';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: _statusOptions.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(status),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedStatus = value!;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loadingDrivers ? null : () {
            if (_formKey.currentState!.validate()) {
              // Check if selected driver is already assigned (additional validation)
              if (_selectedDriverId != null && 
                  _assignedDriverIds.contains(_selectedDriverId) &&
                  _selectedDriverId != widget.initialData?['driverId']) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This driver is already assigned to another van!'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Find the selected driver's name
              String? driverName;
              if (_selectedDriverId != null) {
                final selectedDriver = _drivers.firstWhere(
                  (driver) => driver['id'] == _selectedDriverId,
                  orElse: () => {'name': 'Unknown Driver'},
                );
                driverName = selectedDriver['name'];
              }

              final vanData = {
                'licensePlate': _licensePlateController.text.trim(),
                'driverId': _selectedDriverId,
                'driverName': driverName ?? 'Unassigned',
                'capacity': int.parse(_capacityController.text.trim()),
                'status': _selectedStatus,
                'updatedAt': FieldValue.serverTimestamp(),
              };

              if (widget.initialData == null) {
                vanData['createdAt'] = FieldValue.serverTimestamp();
              }

              widget.onSave(vanData);
              Navigator.of(context).pop();
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}