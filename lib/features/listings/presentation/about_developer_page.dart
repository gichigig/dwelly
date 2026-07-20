import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class AboutDeveloperPage extends StatelessWidget {
  const AboutDeveloperPage({super.key});

  Future<void> _launchUrl(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildContactTile({
    required Widget icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: icon,
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About Developer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: Image.asset(
                  'assets/images/developer.jpg',
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Bildad Mwangi',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Software Developer',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildContactTile(
                    icon: const Icon(Icons.email, color: Colors.blueAccent),
                    title: 'Email',
                    subtitle: 'ngangabildad@gmail.com\nngangabildad@icloud.com',
                    onTap: () => _launchUrl('mailto:ngangabildad@gmail.com'),
                  ),
                  const Divider(height: 1),
                  _buildContactTile(
                    icon: const FaIcon(
                      FontAwesomeIcons.github,
                      color: Colors.blueAccent,
                    ),
                    title: 'GitHub',
                    subtitle: 'gichigig',
                    onTap: () => _launchUrl('https://github.com/gichigig'),
                  ),
                  const Divider(height: 1),
                  _buildContactTile(
                    icon: const FaIcon(
                      FontAwesomeIcons.linkedin,
                      color: Colors.blueAccent,
                    ),
                    title: 'LinkedIn',
                    subtitle: 'bildad-mwangi',
                    onTap: () => _launchUrl(
                      'https://www.linkedin.com/in/bildad-mwangi/',
                    ),
                  ),
                  const Divider(height: 1),
                  _buildContactTile(
                    icon: const FaIcon(
                      FontAwesomeIcons.whatsapp,
                      color: Colors.blueAccent,
                    ),
                    title: 'WhatsApp',
                    subtitle: '+254 106 546 233',
                    onTap: () => _launchUrl('https://wa.me/254106546233'),
                  ),
                  const Divider(height: 1),
                  _buildContactTile(
                    icon: const FaIcon(
                      FontAwesomeIcons.xTwitter,
                      color: Colors.blueAccent,
                    ),
                    title: 'Twitter / X',
                    subtitle: '@billy_bill021',
                    onTap: () =>
                        _launchUrl('https://twitter.com/billy_bill021'),
                  ),
                  const Divider(height: 1),
                  _buildContactTile(
                    icon: const FaIcon(
                      FontAwesomeIcons.tiktok,
                      color: Colors.blueAccent,
                    ),
                    title: 'TikTok',
                    subtitle: '@billy_bill021',
                    onTap: () =>
                        _launchUrl('https://www.tiktok.com/@billy_bill021'),
                  ),
                  const Divider(height: 1),
                  _buildContactTile(
                    icon: const FaIcon(
                      FontAwesomeIcons.facebook,
                      color: Colors.blueAccent,
                    ),
                    title: 'Facebook',
                    subtitle: 'ngangabildad',
                    onTap: () =>
                        _launchUrl('https://www.facebook.com/ngangabildad'),
                  ),
                  const Divider(height: 1),
                  _buildContactTile(
                    icon: const FaIcon(
                      FontAwesomeIcons.instagram,
                      color: Colors.blueAccent,
                    ),
                    title: 'Instagram',
                    subtitle: '@gichigi_m.n',
                    onTap: () =>
                        _launchUrl('https://www.instagram.com/gichigi_m.n'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
