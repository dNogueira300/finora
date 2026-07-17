import 'package:flutter/material.dart';
import '../../../core/money.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.label, required this.cents, required this.color, required this.icon});
  final String label;
  final int cents;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 16, backgroundColor: color.withValues(alpha: .1),
              child: Icon(icon, size: 18, color: color)),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(formatMoney(cents),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
