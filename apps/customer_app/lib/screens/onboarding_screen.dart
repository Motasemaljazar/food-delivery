import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_state.dart';
import 'auth_screen.dart';

class OnboardingScreen extends StatefulWidget {
  static const route = '/onboarding';
  const OnboardingScreen({super.key, required this.prefs, required this.state});

  final SharedPreferences prefs;
  final AppState state;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pc = PageController();
  int index = 0;

  static const Color _red = Color(0xFFC41E3A);
  static const Color _yellow = Color(0xFFF9A825);
  static const Color _yellowLight = Color(0xFFFFC107);

  Widget _buildIconBox(BuildContext context, IconData icon) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFEBEE), // red tint
            Color(0xFFFFF8E1), // yellow tint
          ],
        ),
        borderRadius: BorderRadius.circular(80),
        border: Border.all(color: _yellowLight.withOpacity(0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: _red.withOpacity(0.15),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: _yellow.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: 72, color: _red),
    );
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await widget.prefs.setBool('seenOnboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AuthScreen.route);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slides = widget.state.onboardingSlides;
    final pages = slides.isNotEmpty
        ? slides.take(3).toList()
        : const [
            {
              'title': 'اطلب بسهولة',
              'subtitle': 'اختر الأصناف وأرسل الطلب خلال ثوانٍ',
              'imageUrl': null,
            },
            {
              'title': 'عروض يومية',
              'subtitle': 'خصومات وتوصيل مجاني حسب العروض المتاحة',
              'imageUrl': null,
            },
            {
              'title': 'توصيل سريع',
              'subtitle': 'نوصلك طلبك بأسرع وقت وبشكل آمن',
              'imageUrl': null,
            },
          ];

    IconData _iconFor(int i) {
      switch (i) {
        case 0:
          return Icons.restaurant_menu_rounded;
        case 1:
          return Icons.local_offer_rounded;
        default:
          return Icons.delivery_dining_rounded;
      }
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Color(0xFFFFFBF0),
              Color(0xFFFFF8E1),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // شريط علوي أحمر-أصفر
              Container(
                height: 6,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [_red, _yellow],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      widget.state.restaurantName.trim().isEmpty ? 'توب شيف' : widget.state.restaurantName.trim(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _red,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: _red,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      child: Text(
                        'تخطي',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pc,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => index = i),
                  itemBuilder: (context, i) {
                    final p = (pages[i] is Map) ? (pages[i] as Map) : const {};
                    final title = (p['title'] ?? '').toString();
                    final subtitle = (p['subtitle'] ?? '').toString();
                    final imageUrl = p['imageUrl']?.toString();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (imageUrl != null && imageUrl.trim().isNotEmpty)
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: _red.withOpacity(0.12),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.network(
                                  imageUrl,
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, _, __) =>
                                      _buildIconBox(context, _iconFor(i)),
                                  loadingBuilder: (c, child, prog) => prog == null
                                      ? child
                                      : SizedBox(
                                          height: 200,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: _red,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            )
                          else
                            _buildIconBox(context, _iconFor(i)),
                          const SizedBox(height: 36),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: const Color(0xFF616161),
                                height: 1.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // مؤشرات الصفحات
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(pages.length, (i) {
                    final active = i == index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: active ? 32 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: active
                            ? const LinearGradient(
                                colors: [_red, _yellow],
                              )
                            : null,
                        color: active ? null : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    );
                  }),
                ),
              ),
              // زر التالي / ابدأ الآن
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: () async {
                      if (index < pages.length - 1) {
                        await _pc.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        await _finish();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: _red.withOpacity(0.4),
                    ),
                    child: Text(
                      index < pages.length - 1 ? 'التالي' : 'ابدأ الآن',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
