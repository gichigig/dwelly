import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/rental.dart';

class ListingShareService {
  static String getShareUrl(Rental rental) {
    return 'https://ishinadwelly.com/listing/${rental.id}';
  }

  static String getShareText(Rental rental) {
    final location = rental.fullAddress.isNotEmpty
        ? rental.fullAddress
        : (rental.city.isNotEmpty ? rental.city : 'Kenya');
    return '${rental.title} - ${rental.formattedPrice}\nLocation: $location\n\nCheck out this listing on IshinaDwelly:\n${getShareUrl(rental)}';
  }

  static Future<void> shareViaSystem(Rental rental) async {
    final text = getShareText(rental);
    await Share.share(text, subject: rental.title);
  }

  static Future<void> shareViaWhatsApp(
    BuildContext context,
    Rental rental,
  ) async {
    final text = getShareText(rental);
    final encodedText = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/?text=$encodedText');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp is not installed')),
        );
      }
    }
  }

  static Future<void> shareViaTelegram(
    BuildContext context,
    Rental rental,
  ) async {
    final url = Uri.encodeComponent(getShareUrl(rental));
    final text = Uri.encodeComponent(
      '${rental.title} - ${rental.formattedPrice}',
    );
    final uri = Uri.parse('https://t.me/share/url?url=$url&text=$text');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Telegram is not installed')),
        );
      }
    }
  }

  static Future<void> shareViaFacebook(
    BuildContext context,
    Rental rental,
  ) async {
    final url = Uri.encodeComponent(getShareUrl(rental));
    final uri = Uri.parse('https://www.facebook.com/sharer/sharer.php?u=$url');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Facebook')),
        );
      }
    }
  }

  static Future<void> shareViaTwitter(
    BuildContext context,
    Rental rental,
  ) async {
    final text = Uri.encodeComponent(
      '${rental.title} - ${rental.formattedPrice} on IshinaDwelly\n${getShareUrl(rental)}',
    );
    final uri = Uri.parse('https://twitter.com/intent/tweet?text=$text');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open X / Twitter')),
        );
      }
    }
  }

  static Future<void> shareViaSms(BuildContext context, Rental rental) async {
    final text = getShareText(rental);
    final encodedText = Uri.encodeComponent(text);
    final uri = Uri.parse('sms:?body=$encodedText');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch SMS app')),
        );
      }
    }
  }

  static Future<void> copyShareLink(BuildContext context, Rental rental) async {
    final text = getShareText(rental);
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listing link & details copied to clipboard!'),
        ),
      );
    }
  }
}
