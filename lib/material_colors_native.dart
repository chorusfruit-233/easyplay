import 'package:flutter/services.dart';

Future<List<dynamic>> generateMaterialColors(
  Map<String, Object> request,
) async => (await const MethodChannel(
  'easyplay/material_colors',
).invokeListMethod<dynamic>('generate', request))!;
