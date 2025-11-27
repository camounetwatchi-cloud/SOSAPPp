import 'package:flutter/material.dart';
// 1. Import nécessaire pour lancer l'appel
import 'package:url_launcher/url_launcher.dart'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // 2. Fonction qui gère l'appel téléphonique
  Future<void> _launchCall() async {
    // Création de l'URI pour le numéro d'urgence (112)
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: '112',
    );
    
    // Tentative de lancement
    // Sur simulateur, cela ouvre l'appli Téléphone.
    // Sur un vrai mobile, cela compose le numéro.
    if (!await launchUrl(launchUri)) {
      throw Exception('Impossible de lancer l\'appel vers $launchUri');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Enlève le bandeau "Debug"
      title: 'SOS App Android',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.red,
          title: const Text(
            'SOS URGENCE',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'En cas d\'urgence,\nappuyez ci-dessous',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              
              // 3. Le Bouton d'action
              ElevatedButton(
                onPressed: _launchCall, // Appelle la fonction créée plus haut
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, // Couleur de fond rouge
                  foregroundColor: Colors.white, // Couleur du texte blanc
                  shape: const CircleBorder(), // Forme ronde
                  padding: const EdgeInsets.all(40), // Espace intérieur
                  minimumSize: const Size(200, 200), // Taille du bouton
                  elevation: 10, // Effet d'ombre
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.phone_in_talk, size: 50), // Icône de téléphone
                    SizedBox(height: 10),
                    Text(
                      'APPELER\n112',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
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