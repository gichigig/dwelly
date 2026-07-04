import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import 'package:realestate/core/services/api_service.dart';
import 'package:realestate/core/services/auth_service.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Service for scanning Kenyan IDs and interacting with the Found ID API
class IdScannerService {
  /// Scan an image and extract Kenyan ID information
  static Future<IdScanResult> scanIdFromImage(File imageFile) async {
    final textRecognizer = TextRecognizer();
    
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final recognizedText = await textRecognizer.processImage(inputImage);
      
      final text = recognizedText.text;
      final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      
      // Extract ID fields
      final idNumber = _extractIdNumber(text, lines);
      final names = _extractFullNames(text, lines);
      
      final errors = <String>[];
      
      if (idNumber == null) {
        errors.add('Could not detect ID number. Please ensure the ID number is clearly visible.');
      }
      if (names['fullName'] == null) {
        errors.add('Could not detect name. Please ensure the name is clearly visible.');
      }

      final hasAnyCoreField = idNumber != null || names['fullName'] != null;
      
      return IdScanResult(
        success: hasAnyCoreField,
        idNumber: idNumber,
        fullName: names['fullName'],
        firstName: names['firstName'],
        middleName: names['middleName'],
        lastName: names['lastName'],
        fullText: text,
        errors: errors,
      );
    } catch (e) {
      return IdScanResult(
        success: false,
        fullText: '',
        errors: ['Failed to process image: ${e.toString()}'],
      );
    } finally {
      textRecognizer.close();
    }
  }
  
  /// Extract ID number (7-8 digits)
  static String? _extractIdNumber(String text, List<String> lines) {
    // Patterns for ID number
    final patterns = [
      RegExp(r'ID\s*NUMBER\s*[:\.]?\s*(\d{7,8})', caseSensitive: false),
      RegExp(r'ID\s*NO\s*[:\.]?\s*(\d{7,8})', caseSensitive: false),
      RegExp(r'ID[:\.]?\s*(\d{7,8})', caseSensitive: false),
      RegExp(r'NUMBER\s*[:\.]?\s*(\d{7,8})', caseSensitive: false),
    ];
    
    // Helper to fix common OCR mistakes in numbers
    String fixOCRNumbers(String input) {
      return input
          .replaceAll(RegExp(r'[oO]'), '0')
          .replaceAll(RegExp(r'[lI|]'), '1')
          .replaceAll(RegExp(r'[zZ]'), '2')
          .replaceAll(RegExp(r'[sS]'), '5')
          .replaceAll(RegExp(r'[bB]'), '8');
    }
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.group(1) != null) {
        return match.group(1);
      }
    }
    
    // Look for 7-8 digit numbers on lines containing "ID"
    for (final line in lines) {
      if (line.toUpperCase().contains('ID') && !line.toUpperCase().contains('SERIAL')) {
        // Try with OCR fix
        final fixedLine = fixOCRNumbers(line);
        final numMatch = RegExp(r'\b(\d{7,8})\b').firstMatch(fixedLine);
        if (numMatch != null) {
          return numMatch.group(1);
        }
      }
    }
    
    // Look in top portion of ID
    final topLines = lines.take(8).toList();
    for (final line in topLines) {
      if (line.toUpperCase().contains('SERIAL')) continue;
      final fixedLine = fixOCRNumbers(line);
      final numMatch = RegExp(r'\b(\d{7,8})\b').firstMatch(fixedLine);
      if (numMatch != null) {
        return numMatch.group(1);
      }
    }
    
    // Fallback: find any standalone 7-8 digit number
    final fixedText = fixOCRNumbers(text);
    final allNumbers = RegExp(r'\b\d{7,8}\b').allMatches(fixedText);
    for (final match in allNumbers) {
      final num = match.group(0);
      if (num != null && (num.length == 7 || num.length == 8)) {
        return num;
      }
    }
    
    return null;
  }
  
  /// Extract full names from Kenyan ID
  /// Supports both "FULL NAMES" format and "SURNAME"/"GIVEN NAME" format
  static Map<String, String?> _extractFullNames(String text, List<String> lines) {
    const excludedWords = [
      'JAMHURI', 'YA', 'KENYA', 'REPUBLIC', 'OF', 'THE', 'AND', 'FOR',
      'SERIAL', 'NUMBER', 'ID', 'FULL', 'NAMES', 'NAME', 'DATE', 'BIRTH',
      'SEX', 'MALE', 'FEMALE', 'DISTRICT', 'PLACE', 'ISSUE', 'HOLDER',
      'SIGN', 'SIGNATURE', 'NATIONAL', 'IDENTITY', 'CARD', 'GOK',
      'SURNAME', 'SURNAMES', 'GIVEN', 'GIVENNAME', 'GIVENNAMES',
    ];
    
    String cleanName(String name) {
      return name
          .replaceAll(RegExp(r"[^A-Za-z'\s-]"), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toUpperCase();
    }
    
    bool isValidName(String name) {
      return name.length >= 2 && 
             RegExp(r"^[A-Z'\s-]+$").hasMatch(name) &&
             !excludedWords.contains(name);
    }
    
    // Try Format 2: SURNAME and GIVEN NAME labels (newer format)
    final surnameLineIndex = lines.indexWhere((line) {
      final upper = line.toUpperCase().trim();
      return upper == 'SURNAME' || upper == 'SURNAMES' ||
             (upper.startsWith('SURNAME') && upper.length < 15);
    });
    
    final givenNameLineIndex = lines.indexWhere((line) {
      final upper = line.toUpperCase().trim();
      return upper == 'GIVEN NAME' || upper == 'GIVEN NAMES' ||
             upper == 'GIVENNAME' || upper == 'GIVENNAMES' ||
             (upper.startsWith('GIVEN NAME') && upper.length < 20);
    });
    
    if (surnameLineIndex != -1 || givenNameLineIndex != -1) {
      String? surname;
      String? givenNames;
      
      if (surnameLineIndex != -1 && surnameLineIndex + 1 < lines.length) {
        final surnameCandidate = cleanName(lines[surnameLineIndex + 1]);
        if (isValidName(surnameCandidate)) {
          surname = surnameCandidate;
        }
      }
      
      if (givenNameLineIndex != -1 && givenNameLineIndex + 1 < lines.length) {
        var givenNameCandidate = lines[givenNameLineIndex + 1].trim();
        
        // Check for name continuation
        if (givenNameLineIndex + 2 < lines.length) {
          final nextLine = lines[givenNameLineIndex + 2].trim().toUpperCase();
          if (!nextLine.contains('DATE') && !nextLine.contains('BIRTH') &&
              !nextLine.contains('SEX') && !nextLine.contains('ID') &&
              !nextLine.contains('SURNAME') && !nextLine.contains('NUMBER') &&
              nextLine.isNotEmpty && nextLine.length < 30) {
            if (RegExp(r"^[A-Z'\s-]+$").hasMatch(nextLine)) {
              givenNameCandidate += ' ${lines[givenNameLineIndex + 2].trim()}';
            }
          }
        }
        
        givenNameCandidate = cleanName(givenNameCandidate);
        if (givenNameCandidate.length >= 2) {
          givenNames = givenNameCandidate;
        }
      }
      
      if (surname != null || givenNames != null) {
        final givenParts = givenNames?.split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty && !excludedWords.contains(p))
            .toList() ?? [];
        
        final allParts = [...givenParts];
        if (surname != null) {
          allParts.add(surname);
        }
        
        return {
          'fullName': allParts.isNotEmpty ? allParts.join(' ') : null,
          'firstName': givenParts.isNotEmpty ? givenParts[0] : null,
          'middleName': givenParts.length > 1 ? givenParts.sublist(1).join(' ') : null,
          'lastName': surname,
        };
      }
    }
    
    // Try Format 1: FULL NAMES label (older format)
    final namesLineIndex = lines.indexWhere((line) {
      final upper = line.toUpperCase().trim();
      return upper == 'FULL NAMES' || upper == 'FULL NAME' ||
             upper.contains('FULL NAMES') || upper.contains('FULLNAMES');
    });
    
    if (namesLineIndex != -1 && namesLineIndex + 1 < lines.length) {
      var nameCandidate = lines[namesLineIndex + 1].trim();
      
      if (namesLineIndex + 2 < lines.length) {
        final nextLine = lines[namesLineIndex + 2].trim().toUpperCase();
        if (!nextLine.contains('DATE') && !nextLine.contains('BIRTH') &&
            !nextLine.contains('SEX') && nextLine.isNotEmpty) {
          if (RegExp(r"^[A-Z'\s-]+$").hasMatch(nextLine) && nextLine.length < 30) {
            nameCandidate += ' ${lines[namesLineIndex + 2].trim()}';
          }
        }
      }
      
      nameCandidate = cleanName(nameCandidate);
      
      if (nameCandidate.length >= 3 && RegExp(r"^[A-Z'\s-]+$").hasMatch(nameCandidate)) {
        final nameParts = nameCandidate.split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty && !excludedWords.contains(p))
            .toList();
        
        if (nameParts.length >= 2) {
          return {
            'fullName': nameParts.join(' '),
            'firstName': nameParts[0],
            'middleName': nameParts.length > 2 ? nameParts.sublist(1, nameParts.length - 1).join(' ') : null,
            'lastName': nameParts[nameParts.length - 1],
          };
        }
      }
    }
    
    return {
      'fullName': null,
      'firstName': null,
      'middleName': null,
      'lastName': null,
    };
  }
  
  // ==================== API Methods ====================
  
  /// Register a found ID in the database
  static Future<RegisterFoundIdResponse> registerFoundId({
    required String idNumber,
    required String fullName,
    String? idType,
    String? schoolName,
    String? dateOfBirth,
    required String finderPhone,
    String? finderWhatsApp,
    String? foundLocation,
    String? collectionPlace,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/found-ids'),
        headers: {
          'Content-Type': 'application/json',
          'X-Mobile-Api-Key': ApiService.mobileApiKey,
        },
        body: jsonEncode({
          'idNumber': idNumber,
          'fullName': fullName,
          'idType': idType,
          'schoolName': schoolName,
          'dateOfBirth': (dateOfBirth != null && dateOfBirth.isNotEmpty)
              ? dateOfBirth
              : null,
          'finderPhone': finderPhone,
          'finderWhatsApp': finderWhatsApp,
          'foundLocation': foundLocation,
          'collectionLocation': collectionPlace,
          'collectionPlace': collectionPlace,
        }),
      );
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return RegisterFoundIdResponse(
          success: true,
          message: data['message'] ?? 'ID registered successfully!',
          id: data['id'],
        );
      } else {
        final detail = data['detail'] ?? '';
        final errorMsg = data['error'] ?? 'Failed to register ID';
        debugPrint('[FoundID] Registration error: $errorMsg ($detail) [${response.statusCode}]');
        return RegisterFoundIdResponse(
          success: false,
          message: detail.isNotEmpty ? '$errorMsg ($detail)' : errorMsg,
          errorCode: data['code'],
        );
      }
    } catch (e) {
      debugPrint('[FoundID] Network exception during registration: $e');
      return RegisterFoundIdResponse(
        success: false,
        message: 'Network error. Please check your connection.',
      );
    }
  }
  
  /// Search for a lost ID
  static Future<SearchLostIdResponse> searchLostId({
    required String fullName,
    required String idNumber,
    String? idType,
    String? schoolName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/found-ids/search'),
        headers: ApiService.getHeaders(token: AuthService.token),
        body: jsonEncode({
          'fullName': fullName,
          'idNumber': idNumber,
          'idType': idType,
          'schoolName': schoolName,
        }),
      );
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return SearchLostIdResponse(
          found: data['found'] ?? false,
          message: data['message'] ?? '',
          finderPhone: data['finderPhone'],
          finderWhatsApp: data['finderWhatsApp'],
          foundLocation: data['foundLocation'],
          collectionPlace: data['collectionPlace'] ?? data['collectionLocation'],
          foundAt: data['foundAt'] != null ? DateTime.parse(data['foundAt']) : null,
          foundIdId: data['foundId'],
        );
      } else if (response.statusCode == 429) {
        throw Exception(data['error'] ?? 'Too many search requests. Please try again later.');
      } else if (response.statusCode == 401) {
        return SearchLostIdResponse(
          found: false,
          message: 'Please login to search for lost IDs.',
        );
      } else {
        throw Exception(data['error'] ?? 'Search failed');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a found ID record
  static Future<void> deleteFoundId(int foundId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/found-ids/$foundId'),
        headers: ApiService.getHeaders(token: AuthService.token),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'Failed to delete data');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Create a lost ID alert subscription
  static Future<LostIdAlertModel?> createLostIdAlert({
    required String idNumber,
    required String fullName,
    required bool whatsappAlertsEnabled,
    String? whatsappNumber,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/found-ids/alerts'),
        headers: ApiService.getHeaders(token: AuthService.token),
        body: jsonEncode({
          'idNumber': idNumber,
          'fullName': fullName,
          'whatsappAlertsEnabled': whatsappAlertsEnabled,
          'whatsappNumber': whatsappNumber,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return LostIdAlertModel.fromJson(data);
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'Failed to create lost ID alert');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get active lost ID alerts for current user
  static Future<List<LostIdAlertModel>> getLostIdAlerts() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/found-ids/alerts'),
        headers: ApiService.getHeaders(token: AuthService.token),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => LostIdAlertModel.fromJson(json)).toList();
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'Failed to fetch lost ID alerts');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Delete a lost ID alert subscription
  static Future<void> deleteLostIdAlert(int alertId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/found-ids/alerts/$alertId'),
        headers: ApiService.getHeaders(token: AuthService.token),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        throw Exception(data['error'] ?? 'Failed to delete lost ID alert');
      }
    } catch (e) {
      rethrow;
    }
  }
}

/// Model for lost ID alerts
class LostIdAlertModel {
  final int id;
  final String idNumber;
  final String fullName;
  final bool whatsappAlertsEnabled;
  final String? whatsappNumber;
  final DateTime createdAt;

  LostIdAlertModel({
    required this.id,
    required this.idNumber,
    required this.fullName,
    required this.whatsappAlertsEnabled,
    this.whatsappNumber,
    required this.createdAt,
  });

  factory LostIdAlertModel.fromJson(Map<String, dynamic> json) {
    return LostIdAlertModel(
      id: json['id'] as int,
      idNumber: json['idNumber'] as String,
      fullName: json['fullName'] as String,
      whatsappAlertsEnabled: json['whatsappAlertsEnabled'] as bool? ?? false,
      whatsappNumber: json['whatsappNumber'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

/// Result of scanning an ID image
class IdScanResult {
  final bool success;
  final String? idNumber;
  final String? fullName;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? dateOfBirth;
  final String fullText;
  final List<String> errors;
  
  IdScanResult({
    required this.success,
    this.idNumber,
    this.fullName,
    this.firstName,
    this.middleName,
    this.lastName,
    this.dateOfBirth,
    required this.fullText,
    required this.errors,
  });
}

/// Response from registering a found ID
class RegisterFoundIdResponse {
  final bool success;
  final String message;
  final int? id;
  final String? errorCode;
  
  RegisterFoundIdResponse({
    required this.success,
    required this.message,
    this.id,
    this.errorCode,
  });
}

/// Response from searching for a lost ID
class SearchLostIdResponse {
  final bool found;
  final String message;
  final String? finderPhone;
  final String? finderWhatsApp;
  final String? foundLocation;
  final String? collectionPlace;
  final DateTime? foundAt;
  final int? foundIdId;
  
  SearchLostIdResponse({
    required this.found,
    required this.message,
    this.finderPhone,
    this.finderWhatsApp,
    this.foundLocation,
    this.collectionPlace,
    this.foundAt,
    this.foundIdId,
  });
}
