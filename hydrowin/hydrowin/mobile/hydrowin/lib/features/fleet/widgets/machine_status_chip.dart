import 'package:flutter/material.dart';
import 'package:hydrowin/core/theme/hw_colors.dart';
import 'package:hydrowin/domain/models/machine_summary.dart';

Color machineStatusColor(MachineStatus status, ColorScheme scheme) {
  return switch (status) {
    MachineStatus.ok => HwColors.ok,
    MachineStatus.warning => HwColors.warn,
    MachineStatus.critical => HwColors.critical,
    MachineStatus.offline => HwColors.offline,
  };
}

String machineStatusLabel(MachineStatus status) {
  return switch (status) {
    MachineStatus.ok => 'OK',
    MachineStatus.warning => 'Внимание',
    MachineStatus.critical => 'Критично',
    MachineStatus.offline => 'Оффлайн',
  };
}
