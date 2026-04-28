import 'package:flutter/material.dart';

class OnboardingItem {
  final String keyName;
  final String title;
  final String body;
  final String imagePath;
  final String imageFooterPath;
  final IconData icon;

  const OnboardingItem({
    required this.keyName,
    required this.title,
    required this.body,
    required this.imagePath,
    required this.imageFooterPath,
    required this.icon,
  });
}

const List<OnboardingItem> onboardingItems = [
  OnboardingItem(
    keyName: 'map_intro',
    title: 'みんなで共有して、\n海釣りをもっと楽しく',
    body: '釣り場の環境や釣果の投稿をシェアして、海釣りの楽しみを広げましょう。\n近くの釣り場探しや潮見表も使えます。\n※釣果は特定の釣り場ではなく、近辺エリアとして表示されます。',
    imagePath: 'assets/onboarding/fishing_normal.png',
    imageFooterPath: 'assets/onboarding/footer.png',
    icon: Icons.map,
  ),
  OnboardingItem(
    keyName: 'safe_post',
    title: '釣果は安心して\n投稿できます',
    body: '釣果は、場所が特定されにくい近辺エリアとして表示されます。\n安心して記録やシェアを楽しめます。',
    imagePath: 'assets/onboarding/fishing_post.png',
    imageFooterPath: 'assets/onboarding/footer.png',
    icon: Icons.privacy_tip_outlined,
  ),
  OnboardingItem(
    keyName: 'fishing_diary',
    title: '釣果の投稿は\n自分だけの釣り日記にも',
    body: '自分の釣果投稿は、正確な場所で見返せますので、自分だけの記録として残せます。',
    imagePath: 'assets/onboarding/fishing_viewing.png',
    imageFooterPath: 'assets/onboarding/footer.png',
    icon: Icons.menu_book,
  ),
  OnboardingItem(
    keyName: 'favorite_notify',
    title: '釣行がもっと楽しみに',
    body: '気になる釣り場をお気に入り登録。\n近辺の釣果や変化をシェアして、\n釣行に役立てましょう。\n釣り場が見つからない時は登録もできます。',
    imagePath: 'assets/onboarding/fishing_going.png',
    imageFooterPath: 'assets/onboarding/footer.png',
    icon: Icons.favorite_border,
  ),
];
