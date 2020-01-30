/// Copyright (c) 2019 - Èrik Campobadal Forés
library adonis_websok;

/// For conversions to base64
import 'dart:convert';

/// For the periodic Timer (ping / pong).
import 'dart:async';

/// Imports @required
import 'package:meta/meta.dart';

/// Import the websok package.
import 'package:websok/websok.dart';

/// For channel subscriptions.
import 'package:adonis_websok/topic_subscription.dart';

/// Determines the different package types that can be sent.
enum PacketType {
  open,
  join,
  leave,
  join_ack,
  join_error,
  leave_ack,
  leave_error,
  event,
  ping,
  pong
}

/// Determines the structure of an action request.
class AWActionRequest {
  /// Determines if the action is complete.
  bool completed = false;

  /// Determines if the action has been accepted.
  bool accepted;

  /// Determines the reason of failure, if any.
  String reason;

  /// Store the callback to check for the action.
  final void Function(
    AWActionRequest action,
    PacketType type,
    dynamic data,
  ) checkCallback;

  /// Creates a new instance of the action.
  AWActionRequest(this.checkCallback);

  /// Marks the action as complete (accepter or denied)
  /// and sets a reason in case it's denied.
  void complete(bool accepted, [String reason = '']) {
    this.accepted = accepted;
    this.completed = true;
    this.reason = reason;
  }

  /// Marks the action as accepted.
  void accept() => this.complete(true);

  /// Marks the action as rejected, given a reason for it.
  void reject(String reason) => this.complete(false, reason);

  /// Check the action to see if it can be marked as complete.
  void check(PacketType type, dynamic data) => checkCallback(this, type, data);
}

abstract class AdonisWebsok<S extends Websok> {
  /// Represents the host used to connect.
  final String host;

  /// Represents the port used to connect.
  final int port;

  /// Determines if the websocket connection is on TLS.
  final bool tls;

  /// The path used to make the connection (only change if you changed it on the server).
  final String path;

  /// Base query parameters sent to the socket.
  final Map<String, String> query;

  /// Extended query that will be merged with the query.
  Map<String, dynamic> extendedQuery = <String, String>{};

  /// Stores the socket connection.
  S socket;

  /// Manages the subscriptions.
  Map<String, TopicSubscription> subscriptions = <String, TopicSubscription>{};

  /// Determines if the connection is correct.
  bool isActive = false;

  /// Manager actions requested on the websockets.
  List<AWActionRequest> actionRequests = [];

  /// Periodic timer used for ping / pong.
  Timer pingPong;

  /// Creates a new instance of AdonisWebsocket.
  AdonisWebsok({
    @required this.host,
    this.port = -1,
    this.tls = false,
    this.path = 'adonis-ws',
    this.query = const <String, String>{},
  });

  /// Sets up the connection using [S].
  S connection();

  /// Encodes a message given its type and the data to transmit using the
  /// protocol that adonisjs expects.
  static String encode(PacketType type, dynamic data) =>
      json.encode({'t': type.index, 'd': data});

  /// Decodes a string that comes forom an adonis websocket response.
  static Map<String, dynamic> decode(String data) => json.decode(data);

  /// Returns the full query used.
  /// { ...this.query, ...this.extendedQuery } // Supported in SDK >= 2.3.0
  Map<String, String> fullQuery() =>
      {}..addAll(this.query)..addAll(this.extendedQuery);

  /// Returns the full URL where the socket is connected.
  String url() => this.socket?.url();

  /// Connects to the web socket and sets it up for usage.
  Future<void> connect({
    bool sendRequest = true,
    void onError(error),
    void onDone(),
  }) async {
    if (this.isActive) return null;
    if (sendRequest) {
      this.socket = this.connection()..connect();
      this.socket.listen(
            onData: (dynamic d) {
              final decoded = AdonisWebsok.decode(d);
              final type = PacketType.values[decoded['t']];
              final data = decoded['d'];
              // Run the actions.
              this.actionRequests.forEach((a) => a.check(type, data));
              switch (type) {
                case PacketType.open:
                  {
                    // Set the websocket as active.
                    this.isActive = true;
                    // Send a ping every clientInterval
                    this.pingPong = Timer.periodic(
                      Duration(milliseconds: data['clientInterval']),
                      (timer) => this.send(PacketType.ping),
                    );
                    break;
                  }
                case PacketType.event:
                  {
                    final subscription = this.getSubscription(data['topic']);
                    if (subscription != null) {
                      subscription.onEventCallback(
                        data['event'],
                        data['data'],
                      );
                    }
                    break;
                  }
                default:
                  break;
              }
            },
            onError: onError,
            onDone: onDone,
          );
    }
    return Future(() =>
        this.connect(sendRequest: false, onError: onError, onDone: onDone));
  }

  /// Send some data to the raw socket connection. You should avoid using this
  /// function as its used internally.
  void send(PacketType type, [dynamic data = '']) =>
      this.socket.send(AdonisWebsok.encode(type, data));

  /// Adds JWT authentication to the connection.
  void withJwtToken(String token) => this.extendedQuery['token'] = token;

  /// Adds a personal token authentication to the connection.
  void withApiToken(String token) => this.extendedQuery['token'] = token;

  /// Adds basic authentication to the connection.
  void withBasicAuth(String username, String password) =>
      this.extendedQuery['basic'] = base64.encode(
        utf8.encode('$username:$password'),
      );

  /// Determines if the socket is subscribed to a given topic.
  bool hasSubcription(String topic) => this.subscriptions.containsKey(topic);

  /// Returns the subscription of a given topic or null if it does not exist.
  TopicSubscription getSubscription(String topic) =>
      this.hasSubcription(topic) ? this.subscriptions[topic] : null;

  /// Subscribes to a given topic. The future is completed when the server
  /// responds with the apropiate successful message and the returned value
  /// has the [TopicSubscription] where you can send messages. If [actionRequest]
  /// is set, it won't send another action request to the server and instead
  /// for [actionRequest] to complete, weather as accepted or rejected. If the
  /// subscription is already active, the current subscroption is returned as the
  /// future value.
  Future<TopicSubscription> subscribe(
    String topic, [
    AWActionRequest actionRequest,
  ]) async {
    // Check if already subscribed.
    if (this.hasSubcription(topic)) return this.getSubscription(topic);
    // Check if there's the need to send the request to the socket.
    if (actionRequest != null) {
      if (actionRequest.completed) {
        // Remove it from the actions list.
        this.actionRequests.removeWhere((a) => identical(a, actionRequest));
        return actionRequest.accepted
            ? this.subscriptions[topic] = TopicSubscription(topic, this)
            : Future.error(actionRequest.reason);
      }
      return Future(() => this.subscribe(topic, actionRequest));
    }
    // Send an action request.
    final action = AWActionRequest((action, type, data) {
      if (action.completed) {
        return;
      } else if (type == PacketType.join_ack && data['topic'] == topic) {
        action.accept();
      } else if (type == PacketType.join_error && data['topic'] == topic) {
        action.reject(data['message']);
      }
    });
    this.actionRequests.add(action);
    this.send(PacketType.join, {'topic': topic});
    // Return a future to wait till the subscription succeed.
    return Future(() => this.subscribe(topic, action));
  }

  /// Subscribes to a given topic. The future is completed when the server
  /// responds with the apropiate successful message. If [actionRequest]
  /// is set, it won't send another action request to the server and instead
  /// for [actionRequest] to complete, weather as accepted or rejected. If the
  /// subscroption is not active, the returned value is false, otherwise the returned
  /// value is true.
  Future<bool> unsubscribe(
    String topic, [
    AWActionRequest actionRequest,
  ]) async {
    // Check if already subscribed.
    if (!this.hasSubcription(topic)) return false;
    // Check if there's the need to send the request to the socket.
    if (actionRequest != null) {
      if (actionRequest.completed) {
        // Remove it from the actions list.
        this.actionRequests.removeWhere((a) => identical(a, actionRequest));
        if (actionRequest.accepted) {
          // Get the subscription and mark it as closed.
          final sub = this.getSubscription(topic);
          sub.isActive = false;
          // Remove it from the active subscriptions.
          this.subscriptions.remove(topic);
          return true;
        }
        return Future.error(actionRequest.reason);
      }
      return Future(() => this.unsubscribe(topic, actionRequest));
    }
    // Send an action request.
    final action = AWActionRequest((action, type, data) {
      if (action.completed) {
        return;
      }
      else if (type == PacketType.leave_ack && data['topic'] == topic) {
        action.accept();
      } else if (type == PacketType.leave_error && data['topic'] == topic) {
        action.reject(data['message']);
      }
    });
    this.actionRequests.add(action);
    this.send(PacketType.leave, {'topic': topic});
    // Return a future to wait till the subscription succeed.
    return Future(() => this.unsubscribe(topic, action));
  }

  /// Closes the conexion with the socket.
  void close() {
    this.isActive = false;
    this.pingPong.cancel();
    this.socket.close();
  }
}
