// ignore_for_file: use_build_context_synchronously, depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:email_validator/email_validator.dart';
import 'package:http/http.dart' as http;
import 'package:sizer/sizer.dart';
import 'responsive.dart';

class ContactPage extends StatelessWidget {
  ContactPage({super.key});

  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final messageController = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.white,
        body: ResponsiveWidget(
          mobile: Center(
            child: Card(
              elevation: 5,
              color: Colors.white,
              child: SizedBox(
                height: 55.h,
                width: 90.w,
                child: Form(
                  key: _formKey,
                  child: Padding(
                    padding: EdgeInsets.only(left: 5.w, right: 5.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('Contact Us',
                            style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        TextFormField(
                          style:
                              TextStyle(color: Colors.black, fontSize: 10.sp),
                          controller: nameController,
                          decoration: InputDecoration(
                              hintText: 'Name',
                              hintStyle: TextStyle(
                                  color: Colors.black, fontSize: 10.sp)),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '*Required';
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                          style:
                              TextStyle(color: Colors.black, fontSize: 10.sp),
                          controller: emailController,
                          decoration: const InputDecoration(
                              hintText: 'Email',
                              hintStyle: TextStyle(color: Colors.black)),
                          validator: (email) {
                            if (email == null || email.isEmpty) {
                              return 'Required*';
                            } else if (!EmailValidator.validate(email)) {
                              return 'Please enter a valid Email';
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                         style:
                              TextStyle(color: Colors.black, fontSize: 10.sp),
                          controller: messageController,
                          decoration: InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(
                                  color: Colors.black, fontSize: 10.sp)),
                          maxLines: 5,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '*Required';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 3.h),
                        SizedBox(
                          height: 5.h,
                          width: 30.w,
                          child: TextButton(
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.black,
                                backgroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(60))),
                            onPressed: () async {
                              if (_formKey.currentState!.validate()) {
                                final response = await sendEmail(
                                    nameController.value.text,
                                    emailController.value.text,
                                    messageController.value.text);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  response == 200
                                      ? const SnackBar(
                                          content: Text('Message Sent!'),
                                          backgroundColor: Colors.deepPurple)
                                      : const SnackBar(
                                          content:
                                              Text('Failed to send message!'),
                                          backgroundColor: Colors.red),
                                );
                                nameController.clear();
                                emailController.clear();
                                messageController.clear();
                              }
                            },
                            child: Text('Send',
                                style: TextStyle(
                                    fontSize: 13.sp, color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          /////////////////////////////////////DESKTOP////////////////////////////////////////////////////////////////////////////////////////
          desktop: Center(
            child: Card(
              elevation: 5,
              color: Colors.white,
              child: Container(
                height: 450,
                width: 400,
                margin: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const Text('Contact',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                      TextFormField(
                        style: const TextStyle(color: Colors.black),
                        controller: nameController,
                        decoration: const InputDecoration(
                            hintText: 'Name',
                            hintStyle: TextStyle(color: Colors.black)),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '*Required';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        style: const TextStyle(color: Colors.black),
                        controller: emailController,
                        decoration: const InputDecoration(
                            hintText: 'Email',
                            hintStyle: TextStyle(color: Colors.black)),
                        validator: (email) {
                          if (email == null || email.isEmpty) {
                            return 'Required*';
                          } else if (!EmailValidator.validate(email)) {
                            return 'Please enter a valid Email';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        style: const TextStyle(color: Colors.black),
                        controller: messageController,
                        decoration: const InputDecoration(
                            hintText: 'Message',
                            hintStyle: TextStyle(color: Colors.black)),
                        maxLines: 5,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '*Required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(
                        height: 45,
                        width: 110,
                        child: TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(40))),
                          onPressed: () async {
                            if (_formKey.currentState!.validate()) {
                              final response = await sendEmail(
                                  nameController.value.text,
                                  emailController.value.text,
                                  messageController.value.text);
                              ScaffoldMessenger.of(context).showSnackBar(
                                response == 200
                                    ? const SnackBar(
                                        content: Text('Message Sent!'),
                                        backgroundColor: Colors.deepPurple)
                                    : const SnackBar(
                                        content:
                                            Text('Failed to send message!'),
                                        backgroundColor: Colors.red),
                              );
                              nameController.clear();
                              emailController.clear();
                              messageController.clear();
                            }
                          },
                          child: const Text('Send',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ));
  }
}

Future sendEmail(String name, String email, String message) async {
  final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
  final response = await http.post(url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'service_id': "service_ojwmi2p",
        'template_id': "template_stb08gw",
        'user_id': "DxdvgqsKz1QB0gKTK",
        'template_params': {
          'from_name': "Maxi-Activity: $name",
          'from_email': email,
          'message': message
        }
      }));
  return response.statusCode;
}
