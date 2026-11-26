import 'package:hive_ce/hive.dart';

Future<bool> boxExists(String name) => Hive.boxExists(name);
