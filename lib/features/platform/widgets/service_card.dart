/// Карточка одного из 9 сервисов Platform API.
library;

import 'package:flutter/material.dart';

/// Статус сервиса.
enum ServiceStatus { live, demo, blocked }

class ServiceCard extends StatelessWidget {
  final int number;
  final String title;
  final String subtitle;
  final IconData icon;
  final ServiceStatus status;
  final bool enabled;
  final VoidCallback? onTap;

  const ServiceCard({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final isEnabled = enabled && onTap != null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isEnabled ? color.withOpacity(0.4) : Colors.grey.shade300,
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isEnabled ? color.withOpacity(0.12) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon,
                        color: isEnabled ? color : Colors.grey, size: 20),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$number. $title',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isEnabled ? Colors.black87 : Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isEnabled ? Colors.grey[700] : Colors.grey[400],
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              if (isEnabled)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    'Попробовать →',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(ServiceStatus s) {
    switch (s) {
      case ServiceStatus.live:    return const Color(0xFF22C55E);
      case ServiceStatus.demo:    return const Color(0xFFF59E0B);
      case ServiceStatus.blocked: return const Color(0xFFEF4444);
    }
  }

  String _statusLabel(ServiceStatus s) {
    switch (s) {
      case ServiceStatus.live:    return 'БОЕВОЙ';
      case ServiceStatus.demo:    return 'DEMO';
      case ServiceStatus.blocked: return 'БЛОКЕР';
    }
  }
}
