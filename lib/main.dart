import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:audioplayers/audioplayers.dart';

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

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // Fonction pour lancer l'appel d'urgence
  Future<void> _launchCall() async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: '112',
    );

    if (!await launchUrl(launchUri)) {
      throw Exception('Impossible de lancer l\'appel vers $launchUri');
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
        _locationMessage = 
            'Latitude: ${position.latitude.toStringAsFixed(6)}\n'
            'Longitude: ${position.longitude.toStringAsFixed(6)}\n'
            'Précision: ${position.accuracy.toStringAsFixed(1)}m';
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
    
    // Optionnel: afficher une confirmation avant d'appeler
    _showCallConfirmation();
  }

  // Afficher une boîte de dialogue de confirmation pour l'appel
  void _showCallConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Appel d\'urgence'),
          content: const Text('Voulez-vous appeler le 112 maintenant ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _launchCall();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Appeler'),
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

              // Zone d'affichage de la localisation
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
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
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Ma position',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_isLoading)
                      const CircularProgressIndicator()
                    else
                      Text(
                        _locationMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                    const SizedBox(height: 12),
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