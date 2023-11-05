import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart'; // Import the logging package
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
  const MyApp({super.key});
}

class _MyAppState extends State<MyApp> {
  final Logger _logger = Logger('MyApp'); // Create a logger instance
  String nine = 'today';
  String transribetext = '';
  String translated = 'Translation';
  String url = 'http://192.168.68.101:5000/upload_audio';
  int curtindex = 0;
  bool isVisible = true;
  bool isRecording = false;
  late FlutterSoundRecorder _audioRecorder;
  bool shouldHideSizedBox = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = FlutterSoundRecorder();
    _audioRecorder.openRecorder();

    requestPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Add a listener to check the keyboard status after the build is completed
      checkKeyboardVisibility();
    });
  }

  void checkKeyboardVisibility() {
    final mediaQueryData = MediaQuery.of(context);
    final keyboardHeight = mediaQueryData.viewInsets.bottom;
    setState(() {
      isVisible = keyboardHeight <= 0;
    });
  }

  Future<void> requestPermissions() async {
    // Request both RECORD_AUDIO and WRITE_EXTERNAL_STORAGE permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.storage,
    ].request();

    // Check the status for each permission
    if (statuses[Permission.microphone]!.isGranted &&
        statuses[Permission.storage]!.isGranted) {
      // Permissions granted, you can proceed with audio recording or other tasks.
    } else if (statuses[Permission.microphone]!.isDenied ||
        statuses[Permission.storage]!.isDenied) {
      // Permissions denied on the first request, show a message or explanation to the user.
      _showPermissionDeniedDialog();
    } else if (statuses[Permission.microphone]!.isPermanentlyDenied ||
        statuses[Permission.storage]!.isPermanentlyDenied) {
      // Permissions permanently denied, open app settings so the user can enable them manually.
      openAppSettings();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permission Denied'),
          content: const Text(
              'Please grant the required permissions to use this feature.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> toggleRecording() async {
    try {
      if (!isRecording) {
        final tempDir = await getTemporaryDirectory();
        final recordingPath = '${tempDir.path}/my_audio.wav';

        await _audioRecorder.startRecorder(
          toFile: recordingPath,
          codec: Codec.pcm16WAV,
        );

        Fluttertoast.showToast(
          msg: 'Recording!',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.SNACKBAR,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );

        setState(() {
          isRecording = true; // Update the state when recording starts
        });
      } else {
        await _audioRecorder.stopRecorder();

        Fluttertoast.showToast(
          msg: 'Recording stopped',
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.SNACKBAR,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );

        // Send the recorded audio to the server
        await sendAudioToServer();

        setState(() {
          isRecording = false; // Update the state when recording stops
        });
      }
    } catch (e) {
      _logger.severe('Error toggling recording: $e');
    }
  }

  Future<void> sendAudioToServer() async {
    try {
      final tempDir =
          await getTemporaryDirectory(); // Get the temporary directory
      final recordingPath = '${tempDir.path}/my_audio.wav';

      var uri = Uri.parse(url); // Replace with your Flask backend URL
      var request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('audio', recordingPath));

      var response = await request.send();
      if (response.statusCode == 200) {
        // Successfully uploaded audio, handle the response
        String responseBody = await response.stream.bytesToString();
        Map<String, dynamic> jsonResponse = json.decode(responseBody);

        // Extract recognized and translated text
        String recognizedText = jsonResponse['recognized_text'];
        String translatedText = jsonResponse['translated_text'];

        // Update the UI with the transcription and translation
        setState(() {
          transribetext = recognizedText.replaceAll('"', '');
          translated = translatedText.replaceAll('"', '');
        });
      } else {
        // Handle errors
        _logger.warning(
            'Error: ${response.reasonPhrase}'); // Use the logger for warnings
      }
    } catch (e) {
      _logger.severe(
          'Error sending audio to server: $e'); // Use the logger for errors
    }
  }

  Future<void> sendTextToServer(String text) async {
    try {
      var uri = Uri.parse(url); // Replace with your Flask backend URL
      var response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        // Successfully received the translated text from the server
        String translatedText = jsonDecode(response.body)['translated_text'];

        // Update the UI with the translated text
        setState(() {
          transribetext = translatedText.replaceAll('"', '');
        });
      } else {
        // Handle errors from the server
        _logger.warning('Error: ${response.reasonPhrase}');
      }
    } catch (e) {
      _logger.severe('Error sending text to server: $e');
    }
  }

  @override
  void dispose() {
    _audioRecorder.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool showfab = MediaQuery.of(context).viewInsets.bottom != 0;

    final ButtonStyle style = ElevatedButton.styleFrom(
      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      foregroundColor: Colors.white70,
      backgroundColor: Colors.lightBlue.shade500,
      fixedSize: const Size(150, 50),
    );

    final TextStyle inputStyle = TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.bold,
      color: Colors.black,
    );

    return MaterialApp(
      home: Scaffold(
          appBar: AppBar(
            leading: const Icon(Icons.translate),
            title: const Text('Translation'),
            backgroundColor: Colors.lightBlue.shade800,
          ),
          body: Column(
            children: [
              Container(
                decoration: const BoxDecoration(color: Colors.white10),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  height: 400,
                  decoration: BoxDecoration(
                      color: Colors.lightBlue.shade800,
                      borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(40),
                        bottomLeft: Radius.circular(40),
                      )),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: TextField(
                          decoration: const InputDecoration(
                              hintText: 'Enter Text ',
                              border: InputBorder.none),
                          style: inputStyle,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: TextField(
                          decoration: const InputDecoration(
                              hintText: 'Enter Text ',
                              border: InputBorder.none),
                          style: inputStyle,
                          enabled: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 100,
                decoration: const BoxDecoration(color: Colors.white10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      style: style,
                      onPressed: () {
                        // ignore: avoid_print
                        print('Button Pressed2');
                      },
                      child: const Text("Conyo"),
                    ),
                    const Icon(
                      Icons.arrow_forward,
                      size: 35,
                    ),
                    ElevatedButton(
                      onPressed: () {
                        // ignore: avoid_print
                        print('Button Pressed1');
                      },
                      style: style,
                      child: const Text("Bisaya"),
                    ),
                  ],
                ),
              ),
              Visibility(
                visible: !showfab,
                child: SizedBox(
                  height: 80,
                  width: 80,
                  child: GestureDetector(
                    onTap: toggleRecording,
                    child: FloatingActionButton(
                      backgroundColor: isRecording ? Colors.red : null,
                      child: Icon(
                        isRecording ? Icons.stop : Icons.mic,
                        size: 42,
                      ),
                      onPressed: () {
                        // Handle microphone button press
                        toggleRecording();
                      },
                    ),
                  ),
                ),
              )
            ],
          )),
    );
  }
}
