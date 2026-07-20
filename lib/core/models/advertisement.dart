// ignore_for_file: constant_identifier_names

import 'dart:convert';

class Advertiser {
  final int id;
  final String companyName;
  final String? companyDescription;
  final String? website;
  final String? contactEmail;
  final String? contactPhone;
  final String? logoUrl;
  final String verificationStatus;
  final DateTime createdAt;

  Advertiser({
    required this.id,
    required this.companyName,
    this.companyDescription,
    this.website,
    this.contactEmail,
    this.contactPhone,
    this.logoUrl,
    required this.verificationStatus,
    required this.createdAt,
  });

  factory Advertiser.fromJson(Map<String, dynamic> json) {
    return Advertiser(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      companyName: json['companyName']?.toString() ?? '',
      companyDescription: json['companyDescription']?.toString(),
      website: json['website']?.toString(),
      contactEmail: json['contactEmail']?.toString(),
      contactPhone: json['contactPhone']?.toString(),
      logoUrl: json['logoUrl']?.toString(),
      verificationStatus:
          json['verificationStatus']?.toString() ?? 'UNVERIFIED',
      createdAt:
          Advertisement._parseDateTime(json['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'companyName': companyName,
      'companyDescription': companyDescription,
      'website': website,
      'contactEmail': contactEmail,
      'contactPhone': contactPhone,
      'logoUrl': logoUrl,
      'verificationStatus': verificationStatus,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

enum MediaType { IMAGE, VIDEO }

enum LinkType { WEBSITE, PLAYSTORE, APPSTORE, APP_BOTH, FORM, NONE }

enum AdPlacement {
  HOME_BANNER,
  HOME_FEED,
  LISTING_DETAIL,
  SEARCH_RESULTS,
  INTERSTITIAL,
  SPLASH,
  APP_LAUNCH,
  RENTAL_FEED,
  LOCATION_FILTER,
  MARKETPLACE_FEED,
  MARKETPLACE_DETAIL,
  MARKETPLACE_SEARCH,
}

class AdFormField {
  final String id;
  final String label;
  final String type;
  final bool required;
  final String? placeholder;
  final List<String>? options;

  AdFormField({
    required this.id,
    required this.label,
    required this.type,
    required this.required,
    this.placeholder,
    this.options,
  });

  factory AdFormField.fromJson(Map<String, dynamic> json) {
    return AdFormField(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      required: json['required'] ?? false,
      placeholder: json['placeholder']?.toString(),
      options: json['options'] != null
          ? (json['options'] as List).map((e) => e.toString()).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'type': type,
      'required': required,
      'placeholder': placeholder,
      'options': options,
    };
  }
}

class AdFormSchema {
  final String? title;
  final String? submitButtonText;
  final String? successMessage;
  final List<AdFormField> fields;

  AdFormSchema({
    this.title,
    this.submitButtonText,
    this.successMessage,
    required this.fields,
  });

  factory AdFormSchema.fromJson(Map<String, dynamic> json) {
    return AdFormSchema(
      title: json['title']?.toString(),
      submitButtonText: json['submitButtonText']?.toString(),
      successMessage: json['successMessage']?.toString(),
      fields: json['fields'] is List
          ? (json['fields'] as List)
                .whereType<Map<String, dynamic>>()
                .map((f) => AdFormField.fromJson(f))
                .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'submitButtonText': submitButtonText,
      'successMessage': successMessage,
      'fields': fields.map((f) => f.toJson()).toList(),
    };
  }
}

class Advertisement {
  final int id;
  final String title;
  final String? description;
  final String? imageUrl;
  final String? videoUrl;
  final String? thumbnailUrl;
  final MediaType mediaType;
  final LinkType linkType;
  final String? targetUrl;
  final String? playStoreUrl;
  final String? appStoreUrl;
  final String? formTitle;
  final AdFormSchema? formSchema;
  final String? formSubmitButtonText;
  final String? formSuccessMessage;
  final AdPlacement placement;
  final int priority;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool active;
  final int advertiserId;
  final String advertiserName;
  final String? advertiserLogoUrl;
  final bool
  advertiserVerified; // Whether the advertiser is verified (for showing badge)
  final DateTime createdAt;
  final DateTime updatedAt;
  // New fields for enhanced ad features
  final String? locationInstructions; // Instructions for location-specific ads
  final int? skipDelaySeconds; // For app launch ads - default 5 seconds
  final bool sponsored; // Whether this is a sponsored ad

  Advertisement({
    required this.id,
    required this.title,
    this.description,
    this.imageUrl,
    this.videoUrl,
    this.thumbnailUrl,
    required this.mediaType,
    required this.linkType,
    this.targetUrl,
    this.playStoreUrl,
    this.appStoreUrl,
    this.formTitle,
    this.formSchema,
    this.formSubmitButtonText,
    this.formSuccessMessage,
    required this.placement,
    required this.priority,
    this.startDate,
    this.endDate,
    required this.active,
    required this.advertiserId,
    required this.advertiserName,
    this.advertiserLogoUrl,
    this.advertiserVerified = false,
    required this.createdAt,
    required this.updatedAt,
    this.locationInstructions,
    this.skipDelaySeconds,
    this.sponsored = false,
  });

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      if (value > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  factory Advertisement.fromJson(Map<String, dynamic> json) {
    AdFormSchema? formSchema;
    if (json['formSchema'] != null) {
      try {
        final schemaJson = json['formSchema'] is String
            ? jsonDecode(json['formSchema'])
            : json['formSchema'];
        formSchema = AdFormSchema.fromJson(schemaJson);
      } catch (e) {
        // Schema parsing failed, leave as null
      }
    }

    return Advertisement(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      videoUrl: json['videoUrl']?.toString(),
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      mediaType: MediaType.values.firstWhere(
        (e) => e.name == json['mediaType']?.toString(),
        orElse: () => MediaType.IMAGE,
      ),
      linkType: LinkType.values.firstWhere(
        (e) => e.name == json['linkType']?.toString(),
        orElse: () => LinkType.NONE,
      ),
      targetUrl: json['targetUrl']?.toString(),
      playStoreUrl: json['playStoreUrl']?.toString(),
      appStoreUrl: json['appStoreUrl']?.toString(),
      formTitle: json['formTitle']?.toString(),
      formSchema: formSchema,
      formSubmitButtonText: json['formSubmitButtonText']?.toString(),
      formSuccessMessage: json['formSuccessMessage']?.toString(),
      placement: AdPlacement.values.firstWhere(
        (e) => e.name == json['placement']?.toString(),
        orElse: () => AdPlacement.HOME_BANNER,
      ),
      priority: json['priority'] is int
          ? json['priority']
          : int.tryParse(json['priority']?.toString() ?? '0') ?? 0,
      startDate: _parseDateTime(json['startDate']),
      endDate: _parseDateTime(json['endDate']),
      active:
          json['active'] == true ||
          json['active']?.toString().toLowerCase() == 'true',
      advertiserId: json['advertiserId'] is int
          ? json['advertiserId']
          : int.tryParse(json['advertiserId']?.toString() ?? '0') ?? 0,
      advertiserName: json['advertiserName']?.toString() ?? '',
      advertiserLogoUrl: json['advertiserLogoUrl']?.toString(),
      advertiserVerified:
          json['advertiserVerified'] == true ||
          json['advertiserVerified']?.toString().toLowerCase() == 'true',
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(json['updatedAt']) ?? DateTime.now(),
      locationInstructions: json['locationInstructions']?.toString(),
      skipDelaySeconds: json['skipDelaySeconds'] is int
          ? json['skipDelaySeconds']
          : int.tryParse(json['skipDelaySeconds']?.toString() ?? ''),
      sponsored:
          json['sponsored'] == true ||
          json['sponsored']?.toString().toLowerCase() == 'true',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'mediaType': mediaType.name,
      'linkType': linkType.name,
      'targetUrl': targetUrl,
      'playStoreUrl': playStoreUrl,
      'appStoreUrl': appStoreUrl,
      'formTitle': formTitle,
      'formSchema': formSchema?.toJson(),
      'formSubmitButtonText': formSubmitButtonText,
      'formSuccessMessage': formSuccessMessage,
      'placement': placement.name,
      'priority': priority,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'active': active,
      'advertiserId': advertiserId,
      'advertiserName': advertiserName,
      'advertiserLogoUrl': advertiserLogoUrl,
      'advertiserVerified': advertiserVerified,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'locationInstructions': locationInstructions,
      'skipDelaySeconds': skipDelaySeconds,
      'sponsored': sponsored,
    };
  }

  /// Returns the display URL based on link type
  String? get displayUrl {
    switch (linkType) {
      case LinkType.WEBSITE:
        return targetUrl;
      case LinkType.PLAYSTORE:
        return playStoreUrl;
      case LinkType.APPSTORE:
        return appStoreUrl;
      default:
        return null;
    }
  }

  /// Check if ad is within valid date range
  bool get isValidDateRange {
    final now = DateTime.now();
    if (startDate != null && now.isBefore(startDate!)) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    return true;
  }

  /// Check if ad should be displayed
  bool get shouldDisplay => active && isValidDateRange;
}
