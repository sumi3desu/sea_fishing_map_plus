import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_item.dart';

class OnboardingScreen extends StatefulWidget {
  static const onboardingSeenKey = 'onboarding_seen';

  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  bool get _isLastPage => _currentIndex == onboardingItems.length - 1;

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen.onboardingSeenKey, true);
    widget.onFinished();
  }

  void _goNext() {
    if (_isLastPage) {
      _finish();
      return;
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _skip() {
    _finish();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _skip, child: const Text('スキップ')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: onboardingItems.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final item = onboardingItems[index];
                  return _OnboardingPage(item: item);
                },
              ),
            ),
            Image.asset(
              onboardingItems[_currentIndex].imageFooterPath,
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: List.generate(
                        onboardingItems.length,
                        (index) =>
                            _PageIndicator(isActive: index == _currentIndex),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _goNext,
                    child: Text(_isLastPage ? 'はじめる' : '次へ'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final OnboardingItem item;

  const _OnboardingPage({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(item.imagePath, height: 225, fit: BoxFit.contain),
          // const SizedBox(height: 20),
          // Icon(item.icon, size: 120),
          const SizedBox(height: 40),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            item.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              height: 1.8,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final bool isActive;

  const _PageIndicator({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 8),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? Colors.blue : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
