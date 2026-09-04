import 'package:flutter/material.dart';
import 'package:hydrowin/core/media/media_url.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';
import 'package:hydrowin/features/fleet/widgets/machine_status_chip.dart';
import 'package:intl/intl.dart';

class MachineListTile extends StatelessWidget {
  const MachineListTile({
    required this.machine,
    required this.onTap,
    super.key,
  });

  final MachineSummary machine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = machineStatusColor(machine.status, scheme);
    final lastSeen = machine.lastSeenAt != null
        ? DateFormat('dd.MM HH:mm').format(machine.lastSeenAt!.toLocal())
        : '—';
    final photoUrl = resolveMediaUrl(context, machine.photoUrl);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 64,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(2),
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photoUrl.isNotEmpty
                      ? AuthNetworkImage(
                          url: photoUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _photoPlaceholder(scheme),
                        )
                      : _photoPlaceholder(scheme),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            machine.code,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            machineStatusLabel(machine.status),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          if (machine.gps != null) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message:
                                  '${machine.gps!.lat.toStringAsFixed(5)}, '
                                  '${machine.gps!.lon.toStringAsFixed(5)}',
                              child: Icon(
                                Icons.location_on,
                                size: 18,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                          if (machine.isReadOnlyForCurrentUser) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Продано клиенту — только просмотр',
                              child: Icon(
                                Icons.visibility_outlined,
                                size: 18,
                                color: scheme.outline,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(machine.name),
                      Text(
                        '${machine.model} · ${machine.locationLabel}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (machine.description.trim().isNotEmpty)
                        Text(
                          machine.description.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      if (machine.isReadOnlyForCurrentUser &&
                          machine.ownerOrgName != null &&
                          machine.ownerOrgName!.isNotEmpty)
                        Text(
                          'Клиент: ${machine.ownerOrgName}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                  ),
                        ),
                      if (machine.ipAddress != null &&
                          machine.ipAddress!.isNotEmpty)
                        Text(
                          'IP: ${machine.ipAddress}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (machine.headlineAlert != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          machine.headlineAlert!,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Оператор: ${machine.operatorName} · $lastSeen',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoPlaceholder(ColorScheme scheme) {
    return Container(
      width: 56,
      height: 56,
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.precision_manufacturing_outlined,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
