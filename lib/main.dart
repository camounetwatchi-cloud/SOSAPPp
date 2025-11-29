import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  late MapController _mapController;
  double? _currentLat;
  double? _currentLng;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // Fonction pour envoyer le SMS d'urgence (choisit le scheme selon la plateforme)
  Future<void> _sendSMS(String locationText) async {
    try {
      String message = 'coucou ca va\n\nPosition:\n$locationText';
      String phoneNumber = '0781443413';

      // Construire l'URI SMS en fonction de la plateforme pour maximiser la compatibilité
      Uri smsUri;
      if (Platform.isAndroid) {
        // Android: utiliser smsto: pour préremplir le corps dans la plupart des apps
        smsUri = Uri(
          scheme: 'smsto',
          path: phoneNumber,
          queryParameters: {'body': message},
        );
      } else if (Platform.isIOS) {
        // iOS: sms: avec body query param
        smsUri = Uri(
          scheme: 'sms',
          path: phoneNumber,
          queryParameters: {'body': message},
        );
      } else {
        // Fallback générique
        smsUri = Uri(
          scheme: 'sms',
          path: phoneNumber,
          queryParameters: {'body': message},
        );
      }

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS prêt à être envoyé'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Impossible d\'ouvrir l\'application SMS');
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
            'Longitude: ${position.longitude.toStringAsFixed(6)}\n'
            'Précision: ${position.accuracy.toStringAsFixed(1)}m';
        
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
        
        // Centrer la carte sur la position
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          15.0,
        );
        
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
    
    // Afficher une confirmation avant d'envoyer le SMS
    _showSMSConfirmation();
  }

  // Afficher une boîte de dialogue de confirmation pour l'appel
  void _showSMSConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Envoi du SMS d\'urgence'),
          content: const Text('Voulez-vous envoyer le SMS d\'urgence maintenant ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _sendSMS(_locationMessage);
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
                      : FlutterMap(
                          mapController: _mapController,
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
                        ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Affichage des coordonnées texte
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on,
                          color: Colors.red[700],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Coordonnées',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isLoading)
                      const CircularProgressIndicator()
                    else
                      Text(
                        _locationMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _getCurrentLocation,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualiser'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}