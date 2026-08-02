import 'package:permission_handler/permission_handler.dart';

enum MicrophonePermissionResult {
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

abstract interface class MicrophonePermissionGate {
  Future<MicrophonePermissionResult> request();

  Future<bool> openSettings();
}

class PermissionHandlerMicrophoneGate implements MicrophonePermissionGate {
  @override
  Future<MicrophonePermissionResult> request() async {
    var status = await Permission.microphone.status;
    if (status.isDenied) status = await Permission.microphone.request();
    if (status.isGranted) return MicrophonePermissionResult.granted;
    if (status.isPermanentlyDenied) {
      return MicrophonePermissionResult.permanentlyDenied;
    }
    if (status.isRestricted) return MicrophonePermissionResult.restricted;
    return MicrophonePermissionResult.denied;
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
