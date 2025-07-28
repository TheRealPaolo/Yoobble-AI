import 'dart:async';
import 'package:flutter/material.dart';

class GeminiLoading extends StatefulWidget {
  final Color? circleColor;
  final Color? textColor;

  const GeminiLoading({
    super.key,
    this.circleColor,
    this.textColor,
  });

  @override
  _GeminiLoadingState createState() => _GeminiLoadingState();
}

class _GeminiLoadingState extends State<GeminiLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _currentMessageIndex = 0;
  Timer? _messageTimer; // Timer can be null

  final List<String> _thinkingMessages = [
    "Analyzing your uploaded PDF document...",
    "Extracting key information from the document...",
    "Processing text and identifying main topics...",
    "Detecting important sections and highlights...",
    "Evaluating document structure and content organization...",
    "Identifying primary arguments and supporting evidence...",
    "Analyzing relationships between concepts in your document...",
    "Compiling the most relevant information for your summary...",
    "Organizing key points in a logical sequence...",
    "Determining the most significant findings from your PDF...",
    "Creating a concise summary while preserving essential details...",
    "Reviewing document for critical data points to include...",
    "Optimizing summary length and comprehensiveness...",
    "Finalizing your document summary with key insights...",
    "Structuring summary for maximum clarity and readability...",
    "Almost finished with your PDF summary...",
    "Just a moment more while I refine your document summary..."
  ];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 3), // Animation cycle duration
      vsync: this,
    )..repeat(); // Repeat the animation

    _startMessageTimer();
  }

  void _startMessageTimer() {
    // Use a longer duration for a slower message change
    _messageTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      // Increased to 8 seconds for more readable speed
      if (mounted) {
        setState(() {
          _currentMessageIndex =
              (_currentMessageIndex + 1) % _thinkingMessages.length;
        });
      } else {
        timer.cancel(); // Stop the timer if disposed
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _messageTimer?.cancel(); // Use null-aware operator
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Padding(
            // Added padding for better text layout
            padding: const EdgeInsets.symmetric(
                horizontal: 34.0), // Add horizontal padding
            child: Text(
              _thinkingMessages[_currentMessageIndex],
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                color: widget.textColor ?? Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
