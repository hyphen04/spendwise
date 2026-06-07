import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/update_service.dart';

final pendingUpdateProvider = StateProvider<UpdateInfo?>((ref) => null);
