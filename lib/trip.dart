import 'package:flutter/material.dart';

class TripPage extends StatelessWidget {
  const TripPage({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> mockTrips = [
      {
        "date": "2025-07-04",
        "time": "1:00 PM",
        "route": "Mega → AU",
        "driver": "Mr. Chen",
        "plate": "AU-8812",
        "seatsTotal": 12,
        "seatsTaken": 10,
        "status": "Upcoming",
      },
      {
        "date": "2025-07-03",
        "time": "3:00 PM",
        "route": "AU → Mega",
        "driver": "Ms. Lin",
        "plate": "AU-2288",
        "seatsTotal": 12,
        "seatsTaken": 12,
        "status": "Completed",
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Scheduled Trips",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text("Date")),
                  DataColumn(label: Text("Time")),
                  DataColumn(label: Text("Route")),
                  DataColumn(label: Text("Driver")),
                  DataColumn(label: Text("Van Plate")),
                  DataColumn(label: Text("Total Seats")),
                  DataColumn(label: Text("Seats Taken")),
                  DataColumn(label: Text("Status")),
                  DataColumn(label: Text("Actions")),
                ],
                rows: mockTrips.map((trip) {
                  return DataRow(cells: [
                    DataCell(Text(trip['date'])),
                    DataCell(Text(trip['time'])),
                    DataCell(Text(trip['route'])),
                    DataCell(Text(trip['driver'])),
                    DataCell(Text(trip['plate'])),
                    DataCell(Text("${trip['seatsTotal']}")),
                    DataCell(Text("${trip['seatsTaken']}")),
                    DataCell(Text(trip['status'])),
                    DataCell(Row(
                      children: const [
                        Icon(Icons.remove_red_eye, size: 18),
                        SizedBox(width: 8),
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Icon(Icons.delete, size: 18),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
