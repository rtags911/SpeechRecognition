import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Translation App',
      home: TranslationPage(),
    );
  }
}

class TranslationPage extends StatefulWidget {
  const TranslationPage({Key? key}) : super(key: key);

  @override
  _TranslationPageState createState() => _TranslationPageState();
}

class _TranslationPageState extends State<TranslationPage> {
  final Logger _logger = Logger('TranslationPage');
TextEditingController textEditingController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  String enteredText = '';
  Timer? _timer;
  String transcribedText = '';
  String TextChoose = 'Conyo';
  String translatedText = ' ';
  int currentIndex = 0;
  bool isVisible = true;
  bool isRecording = false;
  late FlutterSoundRecorder _audioRecorder;

  @override
  void initState() {
    super.initState();
    _audioRecorder = FlutterSoundRecorder();
    _audioRecorder.openRecorder();
    requestPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkKeyboardVisibility();
    });
  }

void updateHintText(String translatedWord) {
    setState(() {
      textEditingController.text =
          translatedWord; // Update text in the controller
    });
  }
  void checkKeyboardVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mediaQueryData = MediaQuery.of(context);
      final keyboardHeight = mediaQueryData.viewInsets.bottom;
      if (mounted) {
        setState(() {
          isVisible = keyboardHeight <= 0;
        });
      }
    });
  }

  Future<void> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      Permission.storage,
    ].request();
    if (statuses[Permission.microphone]!.isGranted &&
        statuses[Permission.storage]!.isGranted) {
      // Permissions granted
    } else if (statuses[Permission.microphone]!.isDenied ||
        statuses[Permission.storage]!.isDenied) {
      _showPermissionDeniedDialog();
    } else if (statuses[Permission.microphone]!.isPermanentlyDenied ||
        statuses[Permission.storage]!.isPermanentlyDenied) {
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
          isRecording = true;
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
        await sendAudioToServer();
        setState(() {
          isRecording = false;
        });
      }
    } catch (e) {
      _logger.severe('Error toggling recording: $e');
    }
  }

  Future<void> sendAudioToServer() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final recordingPath = '${tempDir.path}/my_audio.wav';
      var uri = Uri.parse('http://192.168.31.29:5000/upload_audio/$TextChoose');
      var request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('audio', recordingPath));

      var response = await request.send();

      if (response.statusCode == 200) {
        String responseBody = await response.stream.bytesToString();
        Map<String, dynamic> jsonResponse = json.decode(responseBody);
        String recognizedText = jsonResponse['recognized_text'];
        String translatedText = jsonResponse['translated_text'];
        setState(() {
          transcribedText = recognizedText.replaceAll('"', '');
          print(transcribedText);
          translatedText = translatedText.replaceAll('"', '');
          print(translatedText);
        });
      } else {
        _logger.warning('Error: ${response.reasonPhrase}');
      }
    } catch (e) {
      _logger.severe('Error sending audio to server: $e');
    }
  }

  Future<void> sendTextToServer(String text) async {
    try {
      // Replace the URL with your server endpoint
      // ignore: prefer_interpolation_to_compose_strings
      var uri = Uri.parse('http://192.168.68.101:5000/$TextChoose');

      var request = http.MultipartRequest('POST', uri)
        ..fields['text'] =
            enteredText; // Sending text as a field in the request

      var response = await request.send();

      if (response.statusCode == 200) {
        String responseBody = await response.stream.bytesToString();
        Map<String, dynamic> jsonResponse = json.decode(responseBody);
        String recognizedText = jsonResponse['recognized_text'];
        String translatedText = jsonResponse['translated_text'];

        setState(() {
          transcribedText = recognizedText.replaceAll('"', '');
          translatedText = translatedText.replaceAll('"', '');
        });
      } else {
        _logger.warning('Error: ${response.reasonPhrase}');
      }
    } catch (e) {
      _logger.severe('Error sending text to server: $e');
    }
  }

  void updateTranslatedText(String newText) {
    setState(() {
      translatedText = newText; // Update translatedText with new text
    });
  }

  @override
  void dispose() {
    _textController
        .dispose(); // Dispose the TextEditingController to avoid memory leaks
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel(); // Cancel the timer on dispose
    }

    _audioRecorder.closeRecorder(); // Dispose the audio recorder
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
updateHintText(translatedText);
    return Scaffold(
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
                ),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: TextField(
                      controller: TextEditingController(text: transcribedText),
                      onChanged: (text) {
                        if (_timer != null && _timer!.isActive) {
                          _timer!.cancel(); // Cancel the previous timer
                        }
                        _timer = Timer(const Duration(milliseconds: 800), () {
                          setState(() {
                            enteredText = transcribedText;
                            print(
                                enteredText); // Capture the text after a delay
                          });
                        });
                        //sendTextToServer(text);
                      },
                      decoration: const InputDecoration(
                        hintText: 'Enter Text',
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                 Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: translatedText,
                        border: InputBorder.none,
                        enabled: false,
                      ),
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                      
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
                    showModalBottomSheet(
                      context: context,
                      builder: (BuildContext builder) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ListTile(
                              title: const Text('Conyo'),
                              onTap: () {
                                Navigator.pop(context, 'Conyo');
                              },
                            ),
                            ListTile(
                              title: const Text('English'),
                              onTap: () {
                                Navigator.pop(context, 'English');
                              },
                            ),
                          ],
                        );
                      },
                    ).then((value) {
                      if (value != null) {
                        setState(() {
                          TextChoose = value;
                          print('Press : ' + TextChoose);
                        });
                      }
                    });
                  },
                  child: Text(TextChoose),
                ),
                const Icon(
                  Icons.arrow_forward,
                  size: 35,
                ),
                ElevatedButton(
                  onPressed: () {},
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
                    toggleRecording();
                  },
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
