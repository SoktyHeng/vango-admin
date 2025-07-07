import 'package:flutter/material.dart';

class VanManagementPage extends StatefulWidget {
  const VanManagementPage({super.key});

  @override
  State<VanManagementPage> createState() => _VanManagementPageState();
}

class _VanManagementPageState extends State<VanManagementPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Van Management",
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
            child: Center(
              child: const Text("Van Management features coming soon!"),
            ),
          ),
        ),
      ],
    );
  }
}