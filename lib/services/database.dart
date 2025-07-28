// ignore_for_file: unused_local_variable, avoid_function_literals_in_foreach_calls, avoid_print, non_constant_identifier_names
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';

class DatabaseService {
  final String? uid;

  DatabaseService({this.uid});

//Collection des users
  final CollectionReference<Map<String, dynamic>> userCollection =
      FirebaseFirestore.instance.collection("users");

//query de users
  final queryUser = FirebaseFirestore.instance
      .collection('users')
      .orderBy('timestamp', descending: true);

//Enregister un utilisateur dans la BDD
  Future<void> saveUser(name, email, photUrl) async {
    DocumentReference<Map<String, dynamic>> documentReference =
        userCollection.doc(uid);
    documentReference.snapshots().listen((doc) async {
      if (doc.exists) {
        return;
      } else {
        return await userCollection.doc(uid).set({
          'uid': uid,
          'name': name,
          'email': email,
          "photoUrl": photUrl,
          'timestamp': FieldValue.serverTimestamp()
        });
      }
    });
  }

//Fetching les données del'utilisateur
  AppUserData _userFromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    var data = snapshot.data();
    if (data == null) throw Exception("user not found");
    return AppUserData(
      uid: data['uid'],
      name: data['name'],
      email: data['email'],
    );
  }

// données en stream
  Stream<AppUserData> get user {
    return userCollection.doc(uid).snapshots().map(_userFromSnapshot);
  }

//Fetching liste des utilisateurs
  List<AppUserData> _userListFromSnapshot(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map((doc) {
      return _userFromSnapshot(doc);
    }).toList();
  }

//liste des utilisateurs en stream
  Stream<List<AppUserData>> get users {
    return queryUser.snapshots().map(_userListFromSnapshot);
  }

  //Recherche des utilisateurs
  Future<QuerySnapshot> searchUsers(String name) async {
    Future<QuerySnapshot> users = userCollection
        .where('name', isGreaterThanOrEqualTo: name)
        .where('name', isLessThan: '${name}z')
        .get();
    return users;
  }

//Mise à jour des données de l'utilisateur
  void updateUserData(AppUserData user) {
    userCollection.doc(user.uid).update({'name': user.name});
  }
}
