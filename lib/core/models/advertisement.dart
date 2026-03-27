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
      id: json['id'],
      companyName: json['companyName'],
      companyDescription: json['companyDescription'],
      website: json['website'],
      contactEmail: json['contactEmail'],
      contactPhone: json['contactPhone'],
      logoUrl: json['logoUrl'],
      verificationStatus: json['verificationStatus'] ?? 'UNVERIFIED',
      createdAt: DateTime.parse(json['createdAt']),
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
  MARKETPLACE_SEARCH
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
      id: json['id'],
      label: json['label'],
      type: json['type'],
      required: json['required'] ?? false,
      placeholder: json['placeholder'],
      options: json['options'] != null 
          ? List<String>.from(json['options']) 
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
      title: json['title'],
      submitButtonText: json['submitButtonText'],
      successMessage: json['successMessage'],
      fields: (json['fields'] as List)
          .map((f) => AdFormField.fromJson(f))
          .toList(),
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
  final bool advertiserVerified; // Whether the advertiser is verified (for showing badge)
  final DateTime createdAt;
  final DateTime updatedAt;
  // New fields for enhanced ad features
  final String? locationInstructions; // Instructions for location-specific ads
  final int? skipDelaySeconds;        // For app launch ads - default 5 seconds
  final bool sponsored;               // Whether this is a sponsored ad

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
      id: json['id'],
      title: json['title'],
      description: json['description'],
      imageUrl: json['imageUrl'],
      videoUrl: json['videoUrl'],
      thumbnailUrl: json['thumbnailUrl'],
      mediaType: MediaType.values.firstWhere(
        (e) => e.name == json['mediaType'],
        orElse: () => MediaType.IMAGE,
      ),
      linkType: LinkType.values.firstWhere(
        (e) => e.name == json['linkType'],
        orElse: () => LinkType.NONE,
      ),
      targetUrl: json['targetUrl'],
      playStoreUrl: json['playStoreUrl'],
      appStoreUrl: json['appStoreUrl'],
      formTitle: json['formTitle'],
      formSchema: formSchema,
      formSubmitButtonText: json['formSubmitButtonText'],
      formSuccessMessage: json['formSuccessMessage'],
      placement: AdPlacement.values.firstWhere(
        (e) => e.name == json['placement'],
        orElse: () => AdPlacement.HOME_BANNER,
      ),
      priority: json['priority'] ?? 0,
      startDate: json['startDate'] != null ? DateTime.parse(json['startDate']) : null,
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      active: json['active'] ?? false,
      advertiserId: json['advertiserId'] ?? 0,
      advertiserName: json['advertiserName'] ?? '',
      advertiserLogoUrl: json['advertiserLogoUrl'],
      advertiserVerified: json['advertiserVerified'] ?? false,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : DateTime.now(),
      locationInstructions: json['locationInstructions'],
      skipDelaySeconds: json['skipDelaySeconds'],
      sponsored: json['sponsored'] ?? false,
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
