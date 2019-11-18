/// Copyright (c) 2019 - Èrik Campobadal Forés
library adonis_websok.io;

/// Imports @required
import 'package:meta/meta.dart';

/// Import the IO package.
import 'package:websok/html.dart';

/// Import the AdonisWebsok class.
import 'package:adonis_websok/adonis_websok.dart';

/// Represents an adonis websocket for IO.
class IOAdonisWebsok extends AdonisWebsok<HTMLWebsok> {
  /// Creates a new instance of the class.
  IOAdonisWebsok({
    @required String host,
    int port = -1,
    bool tls = false,
    String path = 'adonis-ws',
    Map<String, String> query = const <String, String>{},
  }) : super(
          host: host,
          port: port,
          tls: tls,
          path: path,
          query: query,
        );

  /// Sets up the connection using [S].
  HTMLWebsok connection() => HTMLWebsok(
        host: this.host,
        port: this.port,
        tls: this.tls,
        path: this.path,
        query: this.fullQuery(),
      );
}
