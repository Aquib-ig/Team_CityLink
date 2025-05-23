import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:cloudinary/cloudinary.dart';

// Cloudinary Initialization
const String cloudName = "dtlmvwa2q";
const String uploadPreset = "unsigned-preset";
final cloudinary = Cloudinary.unsignedConfig(cloudName: cloudName);

class ComplaintBoxScreen extends StatefulWidget {
  final String municipalityId;

  const ComplaintBoxScreen({super.key, required this.municipalityId});

  @override
  _ComplaintBoxScreenState createState() => _ComplaintBoxScreenState();
}

class _ComplaintBoxScreenState extends State<ComplaintBoxScreen> {
  String selectedType = "Hospital"; // Default complaint type
  final TextEditingController messageController = TextEditingController();
  File? selectedImage;
  File? selectedVideo;
  String? recordedAudioPath;
  GeoPoint? userLocation;
  bool isRecording = false;
  bool isSubmitting = false;
  bool isAnonymous = false;
  late FlutterSoundRecorder _recorder;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
    _initializeRecorder();
  }

  Future<void> _fetchLocation() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        Position position = await Geolocator.getCurrentPosition();
        setState(() {
          userLocation = GeoPoint(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      print("Error fetching location: $e");
    }
  }

  Future<void> _initializeRecorder() async {
    _recorder = FlutterSoundRecorder();
    await _recorder.openRecorder();
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      print("Microphone permission not granted");
    }
  }

  Future<void> _startRecording() async {
    Directory tempDir = await getTemporaryDirectory();
    String path = "${tempDir.path}/voice_note.aac";
    try {
      setState(() {
        isRecording = true;
      });
      await _recorder.startRecorder(toFile: path);
      recordedAudioPath = path;
    } catch (e) {
      print("Error starting recorder: $e");
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recorder.stopRecorder();
      setState(() {
        isRecording = false;
      });
    } catch (e) {
      print("Error stopping recorder: $e");
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedImage = await ImagePicker().pickImage(source: source);
    if (pickedImage != null) {
      setState(() {
        selectedImage = File(pickedImage.path);
      });
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    final pickedVideo = await ImagePicker().pickVideo(source: source);
    if (pickedVideo != null) {
      setState(() {
        selectedVideo = File(pickedVideo.path);
      });
    }
  }

  Future<String?> _uploadToCloudinary(File file, String resourceType) async {
    try {
      final response = await cloudinary.unsignedUpload(
        file: file.path,
        uploadPreset: uploadPreset,
        resourceType: CloudinaryResourceType.values.byName(resourceType),
      );

      if (response.isSuccessful && response.secureUrl != null) {
        return response.secureUrl;
      } else {
        print("Error uploading to Cloudinary: ${response.error}");
        return null;
      }
    } catch (e) {
      print("Error uploading file: $e");
      return null;
    }
  }

  Future<void> submitComplaint() async {
    if (messageController.text.trim().isEmpty || selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Message and Photo are required.")),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null && !isAnonymous) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User not logged in")),
      );
      return;
    }

    setState(() => isSubmitting = true);

    List<Future<String?>> uploadFutures = [];
    if (selectedImage != null) {
      uploadFutures.add(_uploadToCloudinary(selectedImage!, "image"));
    }
    if (selectedVideo != null) {
      uploadFutures.add(_uploadToCloudinary(selectedVideo!, "video"));
    }
    if (recordedAudioPath != null) {
      uploadFutures.add(_uploadToCloudinary(File(recordedAudioPath!), "raw"));
    }

    try {
      final results = await Future.wait(uploadFutures);
      final photoUrl = results.isNotEmpty ? results[0] : null;
      final videoUrl = results.length > 1 ? results[1] : null;
      final voiceUrl = results.length > 2 ? results[2] : null;

      final complaint = {
        "user_id": isAnonymous ? null : user?.uid,
        "anonymous": isAnonymous,
        "complaint_type": selectedType,
        "message": messageController.text.trim(),
        "photo_url": photoUrl,
        "video_url": videoUrl,
        "voice_url": voiceUrl,
        "location": userLocation ?? GeoPoint(0, 0),
        "status": "",
        "submitted_at": Timestamp.now(),
        "updated_at": Timestamp.now(),
      };

      await FirebaseFirestore.instance
          .collection('Municipalities')
          .doc(widget.municipalityId)
          .collection('Complaints')
          .add(complaint);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Complaint Submitted Successfully")),
      );
      Navigator.pop(context);
    } catch (e) {
      log(e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error submitting complaint: $e")),
      );
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Complaint Box',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green.shade700,
      ),
      body: Container(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Anonymous Submission'),
                  Switch(
                    value: isAnonymous,
                    onChanged: (value) {
                      setState(() {
                        isAnonymous = value;
                      });
                    },
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                value: selectedType,
                items: [
                  "Hospital",
                  "Police",
                  "Public Complaint",
                  "Sanitation Issue",
                  "Infrastructure Damage"
                ]
                    .map((type) =>
                        DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (value) => setState(() => selectedType = value!),
                decoration: const InputDecoration(
                  labelText: "Complaint Type",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: "Message",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera),
                label: const Text("Capture Photo"),
              ),
              ElevatedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.image),
                label: const Text("Select Photo from Gallery"),
              ),
              if (selectedImage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Image.file(selectedImage!,
                      height: 150, width: 150, fit: BoxFit.cover),
                ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => _pickVideo(ImageSource.gallery),
                icon: const Icon(Icons.video_library),
                label: const Text("Select Video from Gallery (Optional)"),
              ),
              ElevatedButton.icon(
                onPressed: () => _pickVideo(ImageSource.camera),
                icon: const Icon(Icons.videocam),
                label: const Text("Capture Video (Optional)"),
              ),
              if (selectedVideo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      "Video Selected: ${selectedVideo!.path.split('/').last}"),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: isRecording ? _stopRecording : _startRecording,
                    icon: Icon(isRecording ? Icons.stop : Icons.mic),
                    label:
                        Text(isRecording ? "Stop Recording" : "Record Voice"),
                  ),
                  if (recordedAudioPath != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text(
                        "Audio Recorded: ${recordedAudioPath!.split('/').last}",
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: submitComplaint,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.green.shade700,
                ),
                child: const Text(
                  "Submit Complaint",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
