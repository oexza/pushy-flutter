import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Type definitions for helpers
typedef void NotificationCallback(Map<String, dynamic> data);
typedef CallbackHandle? _GetCallbackHandle(Function callback);

// Define channel names
const String _eventChannelName = 'me.pushy.sdk.flutter/events';
const String _methodChannelName = 'me.pushy.sdk.flutter/methods';
const String _backgroundChannelName = 'me.pushy.sdk.flutter/background';

class Pushy {
  static const MethodChannel _channel = const MethodChannel(_methodChannelName);
  static const EventChannel _eventChannel =
      const EventChannel(_eventChannelName);

  static NotificationCallback? _notificationListener;
  static NotificationCallback? _notificationClickListener;

  static var notificationQueue = [];
  static var notificationClickQueue = [];

  static Future<String> register() async {
    // Register for push notifications
    return (await (_channel.invokeMethod<String>('register')))!;
  }

  static void listen() {
    // Invoke native method
    _channel.invokeMethod('listen');

    // Listen for notifications published on event channel
    _eventChannel.receiveBroadcastStream().listen((dynamic data) {
      // Decode JSON string into map
      Map<String, dynamic> result = json.decode(data);

      // Notification clicked?
      if (result['_pushyNotificationClicked'] != null) {
        // Print debug log
        print('Pushy notification click: $result');

        // Notification click listener defined?
        if (_notificationClickListener != null) {
          _notificationClickListener!(result);
        } else {
          // Queue for later
          notificationClickQueue.add(result);
        }
      } else {
        // Print debug log
        print('Pushy notification received: $result');

        // Notification received (not clicked)
        if (_notificationListener != null) {
          _notificationListener!(result);
        } else {
          // Queue for later
          notificationQueue.add(result);
        }
      }
    }, onError: (dynamic error) {
      // Print error
      print('Error: ${error.message}');
    });
  }

  static void requestStoragePermission() {
    // No longer needed (leave for backward compatibility)
  }

  static Future<bool> isRegistered() async {
    // Query for registration status
    String result = (await _channel.invokeMethod<String>('isRegistered'))!;

    // Convert string result to bool
    return result == "true" ? true : false;
  }

  static void setNotificationListener(NotificationCallback fn) {
    // Save listener for later (iOS invocation)
    _notificationListener = fn;

    // Retrieve callback handle for _isolate() method
    // and app-defined notification handler callback method
    CallbackHandle? isolateCallback = _getCallbackHandle(_isolate);
    CallbackHandle? notificationHandlerCallback = _getCallbackHandle(fn);

    // Ensure callbacks were located
    if (isolateCallback == null || notificationHandlerCallback == null) {
      print("Pushy: Error retrieving handle for Flutter callbacks");
      return;
    }

    // Register callback IDs with native app
    _channel.invokeMethod('setNotificationListener', <dynamic>[
      isolateCallback.toRawHandle(),
      notificationHandlerCallback.toRawHandle()
    ]);
  }

  static void setNotificationClickListener(NotificationCallback fn) {
    // Save listener for later
    _notificationClickListener = fn;

    // Any notifications pending?
    if (notificationClickQueue.length > 0) {
      notificationClickQueue
          .forEach((element) => {_notificationClickListener!(element)});

      // Empty queue
      notificationClickQueue = [];
    }
  }

  static Future<String?> subscribe(String topic) async {
    // Attempt to subscribe the device to topic
    return await _channel.invokeMethod<String>('subscribe', <dynamic>[topic]);
  }

  static Future<String?> unsubscribe(String topic) async {
    // Attempt to unsubscribe the device from topic
    return await _channel.invokeMethod<String>('unsubscribe', <dynamic>[topic]);
  }

  static void setEnterpriseConfig(String apiEndpoint, String mqttEndpoint) {
    // Invoke native method
    _channel.invokeMethod(
        'setEnterpriseConfig', <dynamic>[apiEndpoint, mqttEndpoint]);
  }

  static void toggleFCM(bool value) {
    // Invoke native method (Android only)
    if (Platform.isAndroid) {
      _channel.invokeMethod('toggleFCM', <dynamic>[value]);
    }
  }

  static void toggleMethodSwizzling(bool value) {
    // Invoke native method (iOS only)
    if (Platform.isIOS) {
      _channel.invokeMethod('toggleMethodSwizzling', <dynamic>[value]);
    }
  }

  static void toggleInAppBanner(bool value) {
    // Invoke native method (iOS only)
    if (Platform.isIOS) {
      _channel.invokeMethod('toggleInAppBanner', <dynamic>[value]);
    }
  }

  static void toggleNotifications(bool value) {
    // Invoke native method
    _channel.invokeMethod('toggleNotifications', <dynamic>[value]);
  }

  static void setNotificationIcon(String resourceName) {
    // Invoke native method
    _channel.invokeMethod('setNotificationIcon', <dynamic>[resourceName]);
  }

  static void setJobServiceInterval(int resourceName) {
    // Invoke native method
    _channel.invokeMethod('setJobServiceInterval', <dynamic>[resourceName]);
  }

  static void setHeartbeatInterval(int resourceName) {
    // Invoke native method
    _channel.invokeMethod('setHeartbeatInterval', <dynamic>[resourceName]);
  }

  static void clearBadge() {
    // Invoke native method (iOS only)
    if (Platform.isIOS) {
      _channel.invokeMethod('clearBadge');
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    // Android-only feature
    if (!Platform.isAndroid) {
      return true;
    }

    // Query for Android battery optimization status
    return (await _channel
        .invokeMethod<bool>('isIgnoringBatteryOptimizations'))!;
  }

  static void launchBatteryOptimizationsActivity() {
    // Invoke native method (Android only)
    if (Platform.isAndroid) {
      _channel.invokeMethod('launchBatteryOptimizationsActivity');
    }
  }

  static void notify(String title, String message, Map<String, dynamic> data) {
    // Attempt to display native notification
    _channel
        .invokeMethod('notify', <dynamic>[title, message, json.encode(data)]);
  }

  static Future<Object?> getDeviceCredentials() async {
    // Fetch device credentials as list
    List? result = await _channel.invokeMethod<List>('getDeviceCredentials');

    // Return null if device not registered yet
    if (result == null) {
      return result;
    }

    // Convert list to map of {token, authKey}
    return {'token': result[0], 'authKey': result[1]};
  }

  static Future<String?> setDeviceCredentials(Map credentials) async {
    // Attempt to assign device credentials
    return await _channel.invokeMethod<String>('setDeviceCredentials',
        <dynamic>[credentials['token'], credentials['authKey']]);
  }
}

// Background isolate entry point (for background handling of push notifications in Dart code)
@pragma('vm:entry-point')
void _isolate() {
  // Initialize state (necessary for MethodChannels)
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background method channel
  const MethodChannel _channel =
      MethodChannel(_backgroundChannelName, JSONMethodCodec());

  // Listen for push notifications sent via the channel
  _channel.setMethodCallHandler((MethodCall call) async {
    // Print isolate invocation (debug log)
    print('Pushy: _isolate() received notfication');

    // Extract arguments
    final dynamic args = call.arguments;

    // Convert notification handler callback ID to callback handle
    final CallbackHandle handle = CallbackHandle.fromRawHandle(args[0]);

    // Get the actual notification callback function from handle
    final Function? notificationCallback =
        PluginUtilities.getCallbackFromHandle(handle);

    // Failed?
    if (notificationCallback == null) {
      print('Pushy: Notification callback could not be located');
    }

    // Ensure we found the right one
    if (notificationCallback is NotificationCallback) {
      // Decode JSON string into map
      Map<String, dynamic> data = json.decode(args[1]);

      // Print debug log
      print('Pushy notification received: $data');

      // Invoke app-defined notification handler
      notificationCallback(data);
    }
  });

  // Ask for queued notifications to be sent over
  _channel.invokeMethod('notificationCallbackReady');
}

// Callback handle helper method
_GetCallbackHandle _getCallbackHandle =
    (Function callback) => PluginUtilities.getCallbackHandle(callback);
