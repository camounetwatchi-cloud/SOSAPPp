import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SOS App Android',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const SOSHomePage(),
    );
  }
}

class SOSHomePage extends StatefulWidget {
  const SOSHomePage({super.key});

  @override
  State<SOSHomePage> createState() => _SOSHomePageState();
}

class _SOSHomePageState extends State<SOSHomePage> {
  String _locationMessage = "Localisation non disponible";
  bool _isLoading = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAlarm = false;
  
  // Variables pour la carte
  MapController? _mapController;
  double? _currentLat;
  double? _currentLng;
  Set<Marker> _markers = {};
  
  // Variables pour les paramètres
  bool _autoSOSEnabled = false;

  // Contacts d'urgence
  List<EmergencyContact> _emergencyContacts = [];

  // Variables pour l'enregistrement audio
  late final Record _audioRecorder;

  @override
  void initState() {
    super.initState();
    _audioRecorder = Record();
    _loadSettings();
    _getCurrentLocation();
    // Initialiser le MapController après un délai pour laisser le temps à Flutter de préparer la carte
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _mapController = MapController();
        });
      }
    });
  }
  
  // Charger les paramètres depuis SharedPreferences (avec fallback si indisponible)
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _autoSOSEnabled = prefs.getBool('autoSOSEnabled') ?? false;
      });
      // Charger les contacts d'urgence
      final contactsJson = prefs.getStringList('emergencyContacts') ?? [];
      _emergencyContacts = contactsJson.map((s) {
        try {
          return EmergencyContact.fromJson(jsonDecode(s));
        } catch (_) {
          return EmergencyContact(name: 'Unknown', phone: '');
        }
      }).toList();
      
      // Si auto-SOS est activé, déclencher après 2 secondes
      if (_autoSOSEnabled) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _handleSOSPress();
          }
        });
      }
    } catch (e) {
      print('SharedPreferences indisponible (normal sur émulateur): $e');
      // Sur l'émulateur, les prefs ne sont pas disponibles, on ignore simplement
      // Le paramètre restera faux (par défaut)
    }
  }
  
  // Sauvegarder les paramètres dans SharedPreferences (avec fallback si indisponible)
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('autoSOSEnabled', _autoSOSEnabled);
      // Sauvegarder les contacts d'urgence
      final contactsJson = _emergencyContacts.map((c) => jsonEncode(c.toJson())).toList();
      await prefs.setStringList('emergencyContacts', contactsJson);
    } catch (e) {
      print('Impossible de sauvegarder les paramètres: $e');
      // Sur l'émulateur, on ne peut pas sauvegarder, mais on ne plante pas
      // Le paramètre sera réinitialisé à chaque redémarrage
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // Demander la permission d'accès au microphone
  Future<bool> _requestMicrophonePermission() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.microphone.request();
        return status.isGranted;
      }
      // Sur web/windows/mac, la permission est gérée différemment ou pas requise
      return true;
    } catch (e) {
      print('Erreur lors de la demande de permission microphone: $e');
      return false;
    }
  }

  // Enregistrer 5 secondes d'audio
  Future<String?> _recordAudio() async {
    try {
      // Vérifier la permission
      final hasPermission = await _requestMicrophonePermission();
      if (!hasPermission) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission microphone refusée'),
            backgroundColor: Colors.orange,
          ),
        );
        return null;
      }

      // Obtenir le répertoire temporaire
      final dir = await getTemporaryDirectory();
      final audioPath = '${dir.path}/emergency_recording.m4a';

      // Démarrer l'enregistrement
      await _audioRecorder.start(
        path: audioPath,
        encoder: AudioEncoder.aacLc,
      );

      // Attendre 5 secondes
      await Future.delayed(const Duration(seconds: 5));

      // Arrêter l'enregistrement
      final result = await _audioRecorder.stop();

      if (result != null && result.isNotEmpty) {
        print('Audio enregistré: $audioPath');
        return audioPath;
      } else {
        print('Erreur: aucun audio enregistré');
        return null;
      }
    } catch (e) {
      print('Erreur lors de l\'enregistrement audio: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur enregistrement: ${e.toString()}'),
          backgroundColor: Colors.orange,
        ),
      );
      return null;
    }
  }

  // Fonction pour envoyer le SMS d'urgence avec audio en pièce jointe (MMS)
  Future<void> _sendSMS(String locationText, {String? audioPath}) async {
    try {
      String message = 'coucou ca va\n\nPosition:\n$locationText';
      // Si des contacts d'urgence sont configurés, envoyer au premier contact
      String phoneNumber = '+33781443413';
      if (_emergencyContacts.isNotEmpty) {
        phoneNumber = _emergencyContacts.first.phone;
      }

      // Construire l'URI SMS/MMS en fonction de la plateforme pour maximiser la compatibilité
      Uri smsUri;
      if (Platform.isAndroid && audioPath != null) {
        // Android: utiliser smsto: avec body pour MMS (si audio disponible)
        // Note: certaines apps Messages acceptent l'audio en paramètre supplémentaire
        smsUri = Uri(
          scheme: 'smsto',
          path: phoneNumber,
          queryParameters: {
            'body': message,
            'attachment': 'file://$audioPath', // Certaines apps reconnaissent ce paramètre
          },
        );
      } else if (Platform.isAndroid) {
        // Android sans audio: utiliser smsto: standard
        smsUri = Uri(
          scheme: 'smsto',
          path: phoneNumber,
          queryParameters: {'body': message},
        );
      } else if (Platform.isIOS && audioPath != null) {
        // iOS: sms: avec body et paramètre attachment (limité, mais essayer)
        smsUri = Uri(
          scheme: 'sms',
          path: phoneNumber,
          queryParameters: {
            'body': message,
          },
        );
      } else if (Platform.isIOS) {
        // iOS sans audio: sms: standard
        smsUri = Uri(
          scheme: 'sms',
          path: phoneNumber,
          queryParameters: {'body': message},
        );
      } else {
        // Fallback générique (web, windows, etc.)
        smsUri = Uri(
          scheme: 'sms',
          path: phoneNumber,
          queryParameters: {'body': message},
        );
      }

      // Sur émulateur Android, canLaunchUrl peut retourner false même si l'app SMS existe
      // On essaie de lancer l'URL directement en tant que fallback
      bool launched = false;
      try {
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
          launched = true;
        }
      } catch (e) {
        print('canLaunchUrl erreur: $e');
      }

      // Si canLaunchUrl a échoué, essayer quand même de lancer l'URL
      if (!launched) {
        try {
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
          launched = true;
        } catch (e) {
          print('launchUrl erreur: $e');
        }
      }

      if (launched) {
        String message2 = audioPath != null ? 'SMS avec audio prêt à être envoyé' : 'SMS prêt à être envoyé';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message2),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Impossible d\'ouvrir l\'application SMS. Vérifiez que l\'app SMS est installée.');
      }
    } catch (e) {
      print('Erreur lors de l\'envoi du SMS: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Fonction pour vérifier et demander les permissions de localisation
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Vérifier si le service de localisation est activé
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationMessage = 'Service de localisation désactivé';
      });
      return false;
    }

    // Vérifier les permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationMessage = 'Permission de localisation refusée';
        });
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationMessage = 'Permission de localisation refusée définitivement';
      });
      return false;
    }

    return true;
  }

  // Fonction pour récupérer la position actuelle
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _locationMessage = "Récupération de la position...";
    });

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLat = position.latitude;
        _currentLng = position.longitude;
        _locationMessage = 
            'Latitude: ${position.latitude.toStringAsFixed(6)}\n'
            'Longitude: ${position.longitude.toStringAsFixed(6)}';
        
        // Créer un marker pour la position actuelle
        _markers.clear();
        _markers.add(
          Marker(
            point: LatLng(position.latitude, position.longitude),
            width: 80.0,
            height: 80.0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 40,
                ),
              ],
            ),
          ),
        );
        
        // Centrer la carte sur la position (avec délai si nécessaire)
        Future.delayed(const Duration(milliseconds: 200), () {
          if (_mapController != null && mounted) {
            _mapController!.move(
              LatLng(position.latitude, position.longitude),
              15.0,
            );
          }
        });
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _locationMessage = 'Erreur: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // Fonction pour jouer le son d'alarme
  Future<void> _playAlarmSound() async {
    try {
      if (_isPlayingAlarm) {
        await _audioPlayer.stop();
        setState(() {
          _isPlayingAlarm = false;
        });
      } else {
        // Jouer le son en boucle à volume maximum
        await _audioPlayer.setVolume(1.0);
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(AssetSource('alarm_sound.mp3'));
        setState(() {
          _isPlayingAlarm = true;
        });
      }
    } catch (e) {
      print('Erreur lors de la lecture du son: $e');
      // Si le fichier audio n'existe pas, afficher un message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fichier audio non trouvé. Veuillez ajouter alarm_sound.mp3 dans assets/'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Fonction principale appelée au clic du bouton SOS
  Future<void> _handleSOSPress() async {
    // Jouer le son d'alarme
    await _playAlarmSound();
    
    // Récupérer la localisation
    await _getCurrentLocation();
    
    // Enregistrer 5 secondes d'audio
    final audioPath = await _recordAudio();
    
    // Afficher une confirmation avant d'envoyer le SMS
    _showSMSConfirmation(audioPath: audioPath);
  }

  // Afficher une boîte de dialogue de confirmation pour l'appel
  void _showSMSConfirmation({String? audioPath}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Envoi du SMS d\'urgence'),
          content: Text(audioPath != null 
            ? 'Voulez-vous envoyer le SMS avec le message vocal enregistré ?' 
            : 'Voulez-vous envoyer le SMS d\'urgence maintenant ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _sendSMS(_locationMessage, audioPath: audioPath);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Envoyer'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red,
        title: const Text(
          'SOS URGENCE',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'En cas d\'urgence,\nappuyez ci-dessous',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 30),

              // Bouton SOS principal
              ElevatedButton(
                onPressed: _handleSOSPress,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(40),
                  minimumSize: const Size(200, 200),
                  elevation: 10,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isPlayingAlarm ? Icons.volume_up : Icons.phone_in_talk,
                      size: 50,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isPlayingAlarm ? 'ALARME\nACTIVE' : 'APPUYER\nICI',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Bouton pour arrêter l'alarme
              if (_isPlayingAlarm)
                ElevatedButton.icon(
                  onPressed: _playAlarmSound,
                  icon: const Icon(Icons.stop),
                  label: const Text('Arrêter l\'alarme'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),

              const SizedBox(height: 20),

              // Zone d'affichage de la carte avec la localisation
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                height: 300,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _currentLat == null || _currentLng == null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isLoading)
                                const CircularProgressIndicator()
                              else
                                const Text(
                                  'Impossible de charger la carte',
                                  style: TextStyle(fontSize: 14),
                                ),
                            ],
                          ),
                        )
                      : _mapController != null
                          ? FlutterMap(
                              mapController: _mapController!,
                              options: MapOptions(
                                center: LatLng(_currentLat!, _currentLng!),
                                zoom: 15.0,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.example.sos_app',
                                ),
                                MarkerLayer(
                                  markers: _markers.toList(),
                                ),
                              ],
                            )
                          : const Center(
                              child: Text('Carte non disponible'),
                            ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Affichage simple des coordonnées sur une ligne
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Text(
                        _locationMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              
              // Bouton Paramètres
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsPage(
                        autoSOSEnabled: _autoSOSEnabled,
                        emergencyContacts: _emergencyContacts,
                        onAutoSOSChanged: (value) {
                          setState(() {
                            _autoSOSEnabled = value;
                          });
                          _saveSettings();
                        },
                        onEmergencyContactsChanged: (contacts) {
                          setState(() {
                            _emergencyContacts = contacts;
                          });
                          _saveSettings();
                        },
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.settings),
                label: const Text('Paramètres'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[600],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Page des paramètres
class SettingsPage extends StatefulWidget {
  final bool autoSOSEnabled;
  final Function(bool) onAutoSOSChanged;
  final List<EmergencyContact> emergencyContacts;
  final ValueChanged<List<EmergencyContact>> onEmergencyContactsChanged;

  const SettingsPage({
    super.key,
    required this.autoSOSEnabled,
    required this.onAutoSOSChanged,
    required this.emergencyContacts,
    required this.onEmergencyContactsChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _localAutoSOSEnabled;

  @override
  void initState() {
    super.initState();
    _localAutoSOSEnabled = widget.autoSOSEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red,
        title: const Text(
          'Paramètres',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text(
                'Déclenchement automatique du SOS',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Déclenche automatiquement le SOS au démarrage de l\'app',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              trailing: Switch(
                value: _localAutoSOSEnabled,
                activeColor: Colors.red,
                onChanged: (value) async {
                  setState(() {
                    _localAutoSOSEnabled = value;
                  });
                  try {
                    widget.onAutoSOSChanged(value);
                  } catch (e) {
                    print('Erreur lors du changement de paramètre: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Erreur: impossible de sauvegarder le paramètre'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              title: const Text(
                'Contacts d\'urgence',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Ajouter ou modifier les numéros d\'urgence',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_location_alt),
                onPressed: () async {
                  // Ouvrir la page de gestion des contacts d'urgence
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EmergencyContactsPage(
                        initialContacts: widget.emergencyContacts,
                        onChanged: (contacts) {
                          widget.onEmergencyContactsChanged(contacts);
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'À propos',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'SOS App v1.0.0',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Application d\'urgence pour alerter rapidement en cas de besoin.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Modèle simple pour un contact d'urgence
class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
      };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
        name: json['name'] ?? '',
        phone: json['phone'] ?? '',
      );
}

// Page pour gérer les contacts d'urgence
class EmergencyContactsPage extends StatefulWidget {
  final List<EmergencyContact> initialContacts;
  final ValueChanged<List<EmergencyContact>> onChanged;

  const EmergencyContactsPage({super.key, required this.initialContacts, required this.onChanged});

  @override
  State<EmergencyContactsPage> createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  late List<EmergencyContact> _contacts;

  @override
  void initState() {
    super.initState();
    _contacts = List.from(widget.initialContacts);
  }

  Future<void> _addOrEditContact({EmergencyContact? existing, int? index}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final phoneController = TextEditingController(text: existing?.phone ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existing == null ? 'Ajouter un contact' : 'Modifier le contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Téléphone'),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final phone = phoneController.text.trim();
                if (phone.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numéro requis'), backgroundColor: Colors.orange));
                  return;
                }
                final contact = EmergencyContact(name: name.isEmpty ? phone : name, phone: phone);
                if (index != null) {
                  _contacts[index] = contact;
                } else {
                  _contacts.add(contact);
                }
                widget.onChanged(_contacts);
                Navigator.of(context).pop(true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );

    if (result == true) setState(() {});
  }

  Future<void> _pickFromPhoneContacts() async {
    try {
      // Demander la permission
      if (!await FlutterContacts.requestPermission()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission contacts refusée'), backgroundColor: Colors.orange));
        return;
      }

      final contacts = await FlutterContacts.getContacts(withProperties: true);
      // Afficher une liste de sélection
      final selected = await showDialog<Contact?>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Choisir un contact'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: contacts.length,
                itemBuilder: (context, i) {
                  final c = contacts[i];
                  final display = c.displayName;
                  final phone = c.phones.isNotEmpty ? c.phones.first.number : '';
                  return ListTile(
                    title: Text(display),
                    subtitle: Text(phone),
                    onTap: () => Navigator.of(context).pop(c),
                  );
                },
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))],
          );
        },
      );

      if (selected != null) {
        final phone = selected.phones.isNotEmpty ? selected.phones.first.number : '';
        final name = selected.displayName;
        if (phone.isEmpty) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ce contact n\'a pas de numéro'), backgroundColor: Colors.orange));
          return;
        }
        _contacts.add(EmergencyContact(name: name, phone: phone));
        widget.onChanged(_contacts);
        setState(() {});
      }
    } catch (e) {
      print('Erreur import contacts: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'accéder aux contacts'), backgroundColor: Colors.orange));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts d\'urgence'),
        backgroundColor: Colors.red,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _addOrEditContact(),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter manuellement'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _pickFromPhoneContacts,
                  icon: const Icon(Icons.contacts),
                  label: const Text('Importer depuis le téléphone'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (context, i) {
                final c = _contacts[i];
                return Dismissible(
                  key: ValueKey(c.phone + i.toString()),
                  background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) {
                    _contacts.removeAt(i);
                    widget.onChanged(_contacts);
                    setState(() {});
                  },
                  child: ListTile(
                    title: Text(c.name),
                    subtitle: Text(c.phone),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _addOrEditContact(existing: c, index: i),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}