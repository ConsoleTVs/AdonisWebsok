import 'package:adonis_websok/adonis_websok.dart';

/// Represents a topic subscription.
class TopicSubscription {
  /// Stores the channel name.
  final String name;

  /// Stores the adonis websocket instance.
  final AdonisWebsok socket;

  /// Determines if the subscription to the given topic is active.
  bool isActive = true;

  /// Stores the listeners to the topic events.
  Map<String, void Function(dynamic data)> listeners = {};

  /// Stores the callback than runs when a new event is received.
  void onEventCallback(String event, dynamic data) =>
      this.listeners[event] != null ? this.listeners[event](data) : null;

  /// Creates a new channel subscription.
  TopicSubscription(this.name, this.socket);

  /// Sets the callback fired when a new event is received.
  void on(String event, void callback(dynamic data)) =>
      this.listeners[event] = callback;

  /// Remove the callback of the given event if exists.
  void off(String event) => this.listeners.remove(event);

  /// Emits an event to the server.
  void emit(String event, [dynamic data = '']) => this.isActive
      ? this.socket.send(
          PacketType.event,
          {'topic': this.name, 'event': event, 'data': data},
        )
      : null;

  /// Unsubscribes to the topic.
  Future<bool> close() async => this.socket.unsubscribe(this.name);
}
