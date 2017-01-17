import 'dart:async' show Future;
import '../client.dart';

abstract class ConnectionHandle {
  Future<WCClient> get client;
}
