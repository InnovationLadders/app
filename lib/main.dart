import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request necessary permissions for WebViews (e.g., camera, microphone)
  await _requestPermissions();

  // For Android, ensure Hybrid Composition is enabled
  if (Platform.isAndroid) {
    await AndroidInAppWebViewController.setWebContentsDebuggingEnabled(true);
    var swAvailable = await AndroidWebViewFeature.isFeatureSupported(AndroidWebViewFeature.SERVICE_WORKER_BASIC_USAGE);
    var swReady = await AndroidWebViewFeature.isFeatureSupported(AndroidWebViewFeature.SERVICE_WORKER_CACHE_MODE);
    if (swAvailable && swReady) {
      AndroidServiceWorkerController.instance().setServiceWorkerClient(AndroidServiceWorkerClient(
        shouldInterceptRequest: (request) async {
          return null;
        },
      ));
    }
  }

  runApp(const MyApp());
}

Future<void> _requestPermissions() async {
  await [Permission.camera, Permission.microphone, Permission.location].request();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebViewApp2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: const MaterialColor(0xFF2196F3, <int, Color>{
          50: Color(0xFFE3F2FD),
          100: Color(0xFFBBDEFB),
          200: Color(0xFF90CAF9),
          300: Color(0xFF64B5F6),
          400: Color(0xFF42A5F5),
          500: Color(0xFF2196F3),
          600: Color(0xFF1E88E5),
          700: Color(0xFF1976D2),
          800: Color(0xFF1565C0),
          900: Color(0xFF0D47A1),
        }),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  final String targetUrl = "https://myprojectplatform.com/";
  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  double progress = 0;
  bool _isConnected = true;
  late StreamSubscription<InternetConnectionStatus> _listener;
  DateTime? currentBackPressTime;

  @override
  void initState() {
    super.initState();
    _initConnectivityListener();
    _initPullToRefreshController();
  }

  void _initConnectivityListener() {
    InternetConnectionChecker().hasConnection.then((hasConnection) {
      setState(() {
        _isConnected = hasConnection;
      });
    });
    _listener = InternetConnectionChecker().onStatusChange.listen((status) {
      setState(() {
        _isConnected = status != InternetConnectionStatus.disconnected;
        if (_isConnected && webViewController != null) {
          webViewController!.reload(); // Reload if connection is restored
        }
      });
    });
  }

  void _initPullToRefreshController() {
    pullToRefreshController = PullToRefreshController(
      options: PullToRefreshOptions(
        color: Theme.of(context).primaryColor,
      ),
      onRefresh: () async {
        if (Platform.isAndroid) {
          webViewController?.reload();
        } else if (Platform.isIOS) {
          webViewController?.loadUrl(urlRequest: URLRequest(url: await webViewController?.getUrl()));
        }
        pullToRefreshController?.endRefreshing();
      },
    );
  }

  @override
  void dispose() {
    _listener.cancel();
    webViewController = null; // Clean up webViewController reference
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (webViewController != null) {
      final canGoBack = await webViewController!.canGoBack();
      if (canGoBack) {
        webViewController!.goBack();
        return false; // Prevent default back button behavior
      }
    }
    // If can't go back in webview, check for double back to exit app
    DateTime now = DateTime.now();
    if (currentBackPressTime == null || now.difference(currentBackPressTime!) > const Duration(seconds: 2)) {
      currentBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Press back again to exit')),
      );
      return false; // Stay in app
    }
    return true; // Exit app
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('WebViewApp2'),
          centerTitle: true,
          backgroundColor: Theme.of(context).primaryColor,
        ),
        body: SafeArea(
          child: _isConnected
              ? Stack(
                  children: [ 
                    InAppWebView(
                      initialUrlRequest: URLRequest(url: Uri.parse(targetUrl)),
                      initialOptions: InAppWebViewGroupOptions(
                        crossPlatform: InAppWebViewOptions(
                          useShouldOverrideUrlLoading: true,
                          mediaPlaybackRequiresUserGesture: false,
                          cacheEnabled: true,
                          javaScriptCanOpenWindowsAutomatically: true,
                          preferredContentMode: UserPreferredContentMode.RECOMMENDED,
                          clearCache: false, // Maintain cache
                        ),
                        android: AndroidInAppWebViewOptions(
                          useHybridComposition: true, // Crucial for performance on Android
                          hardwareAcceleration: true,
                          allowFileAccess: true,
                          domStorageEnabled: true,
                          databaseEnabled: true,
                        ),
                        ios: IOSInAppWebViewOptions(
                          allowsInlineMediaPlayback: true,
                          automaticallyAdjustsScrollIndicatorInsets: true,
                        ),
                      ),
                      pullToRefreshController: pullToRefreshController,
                      onWebViewCreated: (controller) {
                        webViewController = controller;
                      },
                      onLoadStart: (controller, url) {
                        setState(() {
                          progress = 0; // Reset progress on new load start
                        });
                      },
                      onLoadStop: (controller, url) async {
                        pullToRefreshController?.endRefreshing();
                        setState(() {
                          progress = 1.0;
                        });
                      },
                      onProgressChanged: (controller, p) {
                        if (p == 100) {
                          pullToRefreshController?.endRefreshing();
                        }
                        setState(() {
                          progress = p / 100;
                        });
                      },
                      onLoadError: (controller, url, code, message) {
                        pullToRefreshController?.endRefreshing();
                        // Handle specific error types, e.g., show a dedicated error page
                        // For now, if no internet, the _isConnected check handles it.
                        // For other errors, a reload might be attempted.
                      },
                      androidOnPermissionRequest: (controller, origin, resources) async {
                        return PermissionRequestResponse(
                          resources: resources,
                          action: PermissionRequestResponseAction.GRANT,
                        );
                      },
                      onTitleChanged: (controller, title) {},
                    ),
                    if (progress < 1.0) // Show loading indicator until page is fully loaded
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                      ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.signal_wifi_off,
                        size: 80,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No Internet Connection',
                        style: TextStyle(fontSize: 18, color: Colors.black54),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () async {
                          setState(() {
                            _isConnected = true; // Assume connected for a moment
                          });
                          // Trigger a recheck and reload
                          bool hasConnection = await InternetConnectionChecker().hasConnection;
                          setState(() {
                            _isConnected = hasConnection;
                          });
                          if (hasConnection && webViewController != null) {
                            webViewController!.reload();
                          }
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
