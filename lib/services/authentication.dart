// ignore_for_file: unnecessary_null_comparison, import_of_legacy_library_into_null_safe, avoid_print, use_build_context_synchronously, deprecated_member_use
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart';
import '../templates/accueill.dart';
import '../templates/home.dart';
import 'database.dart';

class AuthenticationService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn googleSignIn = GoogleSignIn();
  AppUser? _userFromFirebaseUser(User? user) {
    return user != null ? AppUser(uid: user.uid) : null;
  }

  Stream<AppUser?> get user {
    return _auth.authStateChanges().map(_userFromFirebaseUser);
  }

  // Connexion avec le compte gmail(Google Compte)
  Future signInWithGoogle(BuildContext context) async {
    try {
      GoogleSignInAccount? googleSignInAccount = kIsWeb
          ? await googleSignIn.signInSilently()
          : await googleSignIn.signIn();

      if (kIsWeb && googleSignInAccount == null) {
        googleSignInAccount = await googleSignIn.signIn();
      }

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      final GoogleSignInAuthentication googleAuth =
          await googleUser!.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Vérifier si l'email est déjà utilisé
      List<String> signInMethods =
          await _auth.fetchSignInMethodsForEmail(googleUser.email);

      if (signInMethods.isEmpty) {
        // L'email n'est pas déjà utilisé, procéder à l'authentification
        UserCredential result = await _auth.signInWithCredential(credential);
        User? user = result.user;

        // Sauvegarder l'utilisateur dans la base de données
        await DatabaseService(uid: user!.uid).saveUser(
          user.displayName,
          user.email,
          user.photoURL,
        );

        Navigator.pushReplacement(
            //Paypass
            context,
            MaterialPageRoute(builder: (context) => const Accueil()));

        return _userFromFirebaseUser(user);
      } else if (signInMethods.contains('google.com')) {
        // L'email est déjà utilisé avec une méthode de connexion Google, procéder à l'authentification
        UserCredential result = await _auth.signInWithCredential(credential);
        User? user = result.user;

        Navigator.pushReplacement(
            //Paypass
            context,
            MaterialPageRoute(builder: (context) => const Accueil()));

        return _userFromFirebaseUser(user);
      } else {
        // L'email est déjà utilisé avec une autre méthode
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text("Failed, an account already exists with this email")));
        return null;
      }
    } catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
      print(error.toString());
      return null;
    }
  }

// Méthode pour l'authentification GitHub
  Future signInWithGitHub(BuildContext context) async {
    try {
      UserCredential result = await _auth.signInWithPopup(
        GithubAuthProvider(),
      );
      User? user = result.user;

      List<String> signInMethods =
          await _auth.fetchSignInMethodsForEmail(user!.email!);

      if (signInMethods.isEmpty) {
        // L'email n'est pas déjà utilisé, procéder à l'authentification
        await DatabaseService(uid: user.uid).saveUser(
          user.displayName,
          user.email,
          user.photoURL,
        );

        Navigator.pushReplacement(
            //Paypass
            context,
            MaterialPageRoute(builder: (context) => const Accueil()));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Connected")));
        return _userFromFirebaseUser(user);
      } else {
        // L'email est déjà utilisé, mais l'utilisateur peut quand même se reconnecter
        Navigator.pushReplacement(
            //Paypass
            context,
            MaterialPageRoute(builder: (context) => const Accueil()));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Connected")));
        return _userFromFirebaseUser(user);
      }
    } catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
      print(error.toString());
      return null;
    }
  }

//Deconnexion
  Future signOut(BuildContext context) async {
    try {
      await googleSignIn.signOut();
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const Home()));
      return await _auth.signOut();
    } catch (exception) {
      print(exception.toString());
      return null;
    }
  }
}
