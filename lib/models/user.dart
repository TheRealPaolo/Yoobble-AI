import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String? uid;
  AppUser({this.uid});
  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUser(uid: doc.data()!['uid']);
  }
}

class AppUserData {
  String? uid;
  String? name;
  String? email;
  String? photoUrl;

  AppUserData({this.uid, this.name, this.email, this.photoUrl});
  factory AppUserData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUserData(
      uid: doc.data()!['uid'],
      name: doc.data()!['name'],
      email: doc.data()!['email'],
      photoUrl: doc.data()!["photoUrl"],
    );
  }
  AppUserData.fromJson(Map<String, dynamic>? json) {
    uid = json!['uid'];
    name = json['name'];
    email = json['email'];
    photoUrl = json['photoUrl'];
  }
  Map<String, dynamic> toJson() =>
      {"name": name, "uid": uid, "email": email, "photoUrl": photoUrl};
}
