import 'package:academyhub_mobile/model/early_payment_offer_model.dart';
import 'package:academyhub_mobile/services/early_payment_offer_service.dart';
import 'package:academyhub_mobile/widgets/early_payment_offer_popup.dart';
import 'dart:async';
import 'dart:convert';

import 'package:academyhub_mobile/model/public_enrollment_offer_model.dart';
import 'package:academyhub_mobile/model/public_registration_class_model.dart';
import 'package:academyhub_mobile/services/public_registration_service.dart';
import 'package:academyhub_mobile/util/parauapebas_neighborhoods.dart';
import 'package:academyhub_mobile/widgets/report_card_operation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bool _registrationVisualMockEnabled =
    bool.fromEnvironment('PUBLIC_REGISTRATION_VISUAL_MOCK');

class _RegistrationFlowColors {
  final bool isDark;

  const _RegistrationFlowColors({required this.isDark});

  static _RegistrationFlowColors of(BuildContext context) {
    return _RegistrationFlowColors(
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
  }

  Color get brand => const Color(0xFF00A859);
  Color get brandStrong => const Color(0xFF047857);
  Color get background =>
      isDark ? const Color(0xFF0B1220) : const Color(0xFFF6F8FA);
  Color get surface => isDark ? const Color(0xFF111827) : Colors.white;
  Color get surfaceAlt =>
      isDark ? const Color(0xFF172033) : const Color(0xFFF8FAFC);
  Color get elevated => isDark ? const Color(0xFF182235) : Colors.white;
  Color get selectedSurface =>
      isDark ? const Color(0xFF0E2A23) : const Color(0xFFE8F8EF);
  Color get disabledSurface =>
      isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
  Color get border =>
      isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get borderStrong =>
      isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
  Color get textPrimary =>
      isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
  Color get textSecondary =>
      isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
  Color get textMuted =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get iconSurface =>
      isDark ? const Color(0xFF0F2D24) : const Color(0xFFE8F8EF);
  Color get infoSurface =>
      isDark ? const Color(0xFF13213A) : const Color(0xFFEFF6FF);
  Color get infoText =>
      isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1E40AF);
  Color get dangerSurface =>
      isDark ? const Color(0xFF3A1518) : const Color(0xFFFEE2E2);
  Color get dangerText =>
      isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
  Color get footer => isDark ? const Color(0xFF0F172A) : Colors.white;
  Color get progressTrack =>
      isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get disabledButton =>
      isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
  Color get disabledButtonText =>
      isDark ? const Color(0xFFCBD5E1) : Colors.white;
}

ThemeData _registrationFlowTheme(_RegistrationFlowColors colors) {
  final brightness = colors.isDark ? Brightness.dark : Brightness.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.brand,
      brightness: brightness,
    ).copyWith(
      primary: colors.brand,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      outline: colors.border,
    ),
    scaffoldBackgroundColor: colors.background,
  );

  return base.copyWith(
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.textPrimary,
        disabledForegroundColor: colors.textMuted,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.brand
            : colors.surface,
      ),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: BorderSide(color: colors.borderStrong),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: colors.surface,
      selectedColor: colors.selectedSurface,
      disabledColor: colors.disabledSurface,
      side: BorderSide(color: colors.border),
      labelStyle: GoogleFonts.inter(
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor:
          colors.isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
      contentTextStyle: GoogleFonts.inter(
        color: colors.isDark ? const Color(0xFF0F172A) : Colors.white,
        fontWeight: FontWeight.w600,
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class PublicRegistrationScreen extends StatefulWidget {
  final String schoolId;
  final bool onlyMinors;

  const PublicRegistrationScreen({
    super.key,
    required this.schoolId,
    this.onlyMinors = false,
  });

  @override
  State<PublicRegistrationScreen> createState() =>
      _PublicRegistrationScreenState();
}

class _PublicRegistrationScreenState extends State<PublicRegistrationScreen> {
  static const int _draftVersion = 2;
  static const int _welcomeStep = 0;
  static const int _classStep = 1;
  static const int _offerStep = 2;
  static const int _studentStep = 3;
  static const int _motherStep = 4;
  static const int _fatherStep = 5;
  static const int _responsibleStep = 6;
  static const int _addressStep = 7;
  static const int _healthStep = 8;
  static const int _reviewStep = 9;
  static const int _successStep = 10;
  static const Duration _draftTtl = Duration(days: 7);
  static const Duration _draftSaveDebounce = Duration(milliseconds: 700);

  final PublicRegistrationService _service = PublicRegistrationService();
  final EarlyPaymentOfferService _earlyPaymentService =
      EarlyPaymentOfferService();
  EarlyPaymentOffer? _earlyOffer;
  bool _earlyOfferAccepted = false;
  bool _earlyOfferToastVisible = false;
  bool _earlyOfferRegistered = false;
  bool _earlyOfferRegistering = false;
  String? _submittedRequestId;

  static const List<String> _allergyOptions = [
    'Poeira/ácaros',
    'Mofo',
    'Pólen',
    'Picada de insetos',
    'Leite',
    'Ovo',
    'Amendoim',
    'Castanhas',
    'Frutos do mar',
    'Peixe',
    'Glúten/trigo',
    'Corantes ou conservantes',
    'Medicamentos',
    'Látex',
    'Pelo de animais',
    'Outra',
  ];

  static const List<String> _disabilityOptions = [
    'Deficiência visual',
    'Deficiência auditiva',
    'Deficiência física',
    'Deficiência intelectual',
    'Deficiência múltipla',
    'Baixa visão',
    'Surdez',
    'Mobilidade reduzida',
    'Outra',
  ];

  static const List<String> _neurodevelopmentalOptions = [
    'Transtorno do Espectro Autista (TEA)',
    'TDAH',
    'Dislexia',
    'Discalculia',
    'Disgrafia',
    'Transtorno do Desenvolvimento da Linguagem',
    'Altas habilidades/superdotação',
    'Atraso no desenvolvimento',
    'Em avaliação',
    'Outra',
  ];

  static const List<String> _foodRestrictionOptions = [
    'Intolerância à lactose',
    'Restrição a glúten',
    'Diabetes',
    'Alimentação vegetariana',
    'Alimentação vegana',
    'Restrição por orientação médica',
    'Outra',
  ];

  final _studentFormKey = GlobalKey<FormState>();
  final _motherFormKey = GlobalKey<FormState>();
  final _fatherFormKey = GlobalKey<FormState>();
  final _responsibleFormKey = GlobalKey<FormState>();
  final _addressFormKey = GlobalKey<FormState>();
  final _healthFormKey = GlobalKey<FormState>();

  final _studentNameController = TextEditingController();
  final _studentBirthController = TextEditingController();
  final _studentCpfController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _motherBirthController = TextEditingController();
  final _motherCpfController = TextEditingController();
  final _motherRgController = TextEditingController();
  final _motherPhoneController = TextEditingController();
  final _motherEmailController = TextEditingController();
  final _motherProfessionController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _fatherBirthController = TextEditingController();
  final _fatherCpfController = TextEditingController();
  final _fatherRgController = TextEditingController();
  final _fatherPhoneController = TextEditingController();
  final _fatherEmailController = TextEditingController();
  final _fatherProfessionController = TextEditingController();

  final _guardianNameController = TextEditingController();
  final _guardianBirthController = TextEditingController();
  final _guardianCpfController = TextEditingController();
  final _guardianRgController = TextEditingController();
  final _guardianPhoneController = TextEditingController();
  final _guardianEmailController = TextEditingController();
  final _guardianProfessionController = TextEditingController();

  final _cepController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _blockController = TextEditingController();
  final _lotController = TextEditingController();
  final _complementController = TextEditingController();

  final _healthConditionDetailsController = TextEditingController();
  final _medicationNameController = TextEditingController();
  final _medicationGuidanceController = TextEditingController();
  final _allergyDetailsController = TextEditingController();
  final _accessibilityNeedsController = TextEditingController();
  final _neurodevelopmentalDetailsController = TextEditingController();
  final _foodRestrictionDetailsController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _emergencyRelationshipController = TextEditingController();
  final _healthGeneralNotesController = TextEditingController();

  final _dateMask = MaskTextInputFormatter(
    mask: '##/##/####',
    filter: {'#': RegExp(r'[0-9]')},
  );
  final _cpfMask = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {'#': RegExp(r'[0-9]')},
  );
  final _phoneMask = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {'#': RegExp(r'[0-9]')},
  );
  final _cepMask = MaskTextInputFormatter(
    mask: '#####-###',
    filter: {'#': RegExp(r'[0-9]')},
  );

  int _currentStep = _welcomeStep;
  bool _isDarkMode = false;
  bool _showInitialSplash = true;
  bool _isLoadingClasses = true;
  bool _isLoadingOffers = false;
  bool _isSubmitting = false;
  String? _classesError;
  String? _offersError;
  String? _offersLoadedForClassId;
  String? _selectedNeighborhood;
  String? _selectedEducationLevel;
  String _studentGender = 'Outro';
  String _relationship = 'Mãe';
  String _primaryResponsibleType = 'mother';
  String _otherRelationship = 'Responsável Legal';
  bool _fatherNotInformed = false;
  bool _hasHealthCondition = false;
  bool _usesContinuousMedication = false;
  bool _hasAllergies = false;
  bool _hasDisability = false;
  bool _hasNeurodevelopmentalCondition = false;
  bool _wearsGlasses = false;
  bool _usesGlassesDaily = false;
  bool _needsFrontSeat = false;
  bool _hasFoodRestriction = false;
  final Set<String> _selectedAllergies = {};
  final Set<String> _selectedDisabilities = {};
  final Set<String> _selectedNeurodevelopmentalConditions = {};
  final Set<String> _selectedFoodRestrictions = {};
  PublicRegistrationSchoolContext? _schoolContext;
  List<PublicRegistrationClassModel> _classes = [];
  PublicRegistrationClassModel? _selectedClass;
  List<PublicEnrollmentOfferModel> _availableOffers = [];
  PublicEnrollmentOfferModel? _selectedEnrollmentOffer;
  Timer? _draftSaveTimer;
  bool _draftReady = false;
  bool _isRestoringDraft = false;
  bool _draftRestoreAttempted = false;

  @override
  void initState() {
    super.initState();
    _addDraftListeners();
    if (_registrationVisualMockEnabled) {
      _seedVisualMockFormData();
    }
    _loadInitialData();
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _removeDraftListeners();
    _studentNameController.dispose();
    _studentBirthController.dispose();
    _studentCpfController.dispose();
    _motherNameController.dispose();
    _motherBirthController.dispose();
    _motherCpfController.dispose();
    _motherRgController.dispose();
    _motherPhoneController.dispose();
    _motherEmailController.dispose();
    _motherProfessionController.dispose();
    _fatherNameController.dispose();
    _fatherBirthController.dispose();
    _fatherCpfController.dispose();
    _fatherRgController.dispose();
    _fatherPhoneController.dispose();
    _fatherEmailController.dispose();
    _fatherProfessionController.dispose();
    _guardianNameController.dispose();
    _guardianBirthController.dispose();
    _guardianCpfController.dispose();
    _guardianRgController.dispose();
    _guardianPhoneController.dispose();
    _guardianEmailController.dispose();
    _guardianProfessionController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _blockController.dispose();
    _lotController.dispose();
    _complementController.dispose();
    _healthConditionDetailsController.dispose();
    _medicationNameController.dispose();
    _medicationGuidanceController.dispose();
    _allergyDetailsController.dispose();
    _accessibilityNeedsController.dispose();
    _neurodevelopmentalDetailsController.dispose();
    _foodRestrictionDetailsController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyRelationshipController.dispose();
    _healthGeneralNotesController.dispose();
    super.dispose();
  }

  String get _draftStorageKey =>
      'academyhub_public_registration_draft_${widget.schoolId}';

  Map<String, TextEditingController> get _draftTextControllers => {
        'studentName': _studentNameController,
        'studentBirth': _studentBirthController,
        'studentCpf': _studentCpfController,
        'motherName': _motherNameController,
        'motherBirth': _motherBirthController,
        'motherCpf': _motherCpfController,
        'motherRg': _motherRgController,
        'motherPhone': _motherPhoneController,
        'motherEmail': _motherEmailController,
        'motherProfession': _motherProfessionController,
        'fatherName': _fatherNameController,
        'fatherBirth': _fatherBirthController,
        'fatherCpf': _fatherCpfController,
        'fatherRg': _fatherRgController,
        'fatherPhone': _fatherPhoneController,
        'fatherEmail': _fatherEmailController,
        'fatherProfession': _fatherProfessionController,
        'guardianName': _guardianNameController,
        'guardianBirth': _guardianBirthController,
        'guardianCpf': _guardianCpfController,
        'guardianRg': _guardianRgController,
        'guardianPhone': _guardianPhoneController,
        'guardianEmail': _guardianEmailController,
        'guardianProfession': _guardianProfessionController,
        'cep': _cepController,
        'street': _streetController,
        'number': _numberController,
        'block': _blockController,
        'lot': _lotController,
        'complement': _complementController,
        'healthConditionDetails': _healthConditionDetailsController,
        'medicationName': _medicationNameController,
        'medicationGuidance': _medicationGuidanceController,
        'allergyDetails': _allergyDetailsController,
        'accessibilityNeeds': _accessibilityNeedsController,
        'neurodevelopmentalDetails': _neurodevelopmentalDetailsController,
        'foodRestrictionDetails': _foodRestrictionDetailsController,
        'emergencyName': _emergencyNameController,
        'emergencyPhone': _emergencyPhoneController,
        'emergencyRelationship': _emergencyRelationshipController,
        'healthGeneralNotes': _healthGeneralNotesController,
      };

  void _addDraftListeners() {
    for (final controller in _draftTextControllers.values) {
      controller.addListener(_scheduleDraftSave);
    }
  }

  void _removeDraftListeners() {
    for (final controller in _draftTextControllers.values) {
      controller.removeListener(_scheduleDraftSave);
    }
  }

  void _seedVisualMockFormData() {
    _studentNameController.text = 'Ana Clara Silva';
    _studentBirthController.text = '01/01/2018';
    _studentCpfController.text = '529.982.247-25';
    _motherNameController.text = 'Mariana Souza Silva';
    _motherBirthController.text = '10/03/1990';
    _motherCpfController.text = '529.982.247-25';
    _motherRgController.text = '1234567';
    _motherPhoneController.text = '(94) 99999-9999';
    _motherEmailController.text = 'mariana@example.com';
    _motherProfessionController.text = 'Analista';
    _cepController.text = '68515-000';
    _streetController.text = 'Rua das Acacias';
    _numberController.text = '123';
    _selectedNeighborhood = 'Cidade Nova';
    _emergencyNameController.text = 'Mariana Souza Silva';
    _emergencyPhoneController.text = '(94) 99999-9999';
    _emergencyRelationshipController.text = 'Mae';
  }

  void _scheduleDraftSave() {
    if (!_draftReady || _isRestoringDraft || !mounted) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(_draftSaveDebounce, _saveDraft);
  }

  void _setDraftState(VoidCallback update) {
    setState(update);
    _scheduleDraftSave();
  }

  Future<void> _saveDraft() async {
    if (!_draftReady || _isRestoringDraft || !mounted) return;

    final draft = {
      'version': _draftVersion,
      'schoolId': widget.schoolId,
      'currentStep': _currentStep,
      'updatedAt': DateTime.now().toIso8601String(),
      'data': _buildDraftData(),
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftStorageKey, json.encode(draft));
    } catch (_) {
      // O rascunho é uma conveniência local; falhas não devem bloquear a ficha.
    }
  }

  Future<void> _clearDraft() async {
    _draftSaveTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftStorageKey);
    } catch (_) {
      // Ignora falha de limpeza local para não interferir no envio concluído.
    }
  }

  Map<String, dynamic> _buildDraftData() {
    final data = <String, dynamic>{
      for (final entry in _draftTextControllers.entries)
        entry.key: entry.value.text,
      'selectedNeighborhood': _selectedNeighborhood,
      'selectedEducationLevel': _selectedEducationLevel,
      'selectedClassId': _selectedClass?.id,
      'selectedEnrollmentOfferId': _selectedEnrollmentOffer?.id,
      'studentGender': _studentGender,
      'relationship': _relationship,
      'primaryResponsibleType': _primaryResponsibleType,
      'otherRelationship': _otherRelationship,
      'fatherNotInformed': _fatherNotInformed,
      'hasHealthCondition': _hasHealthCondition,
      'usesContinuousMedication': _usesContinuousMedication,
      'hasAllergies': _hasAllergies,
      'hasDisability': _hasDisability,
      'hasNeurodevelopmentalCondition': _hasNeurodevelopmentalCondition,
      'wearsGlasses': _wearsGlasses,
      'usesGlassesDaily': _usesGlassesDaily,
      'needsFrontSeat': _needsFrontSeat,
      'hasFoodRestriction': _hasFoodRestriction,
      'selectedAllergies': _selectedAllergies.toList(),
      'selectedDisabilities': _selectedDisabilities.toList(),
      'selectedNeurodevelopmentalConditions':
          _selectedNeurodevelopmentalConditions.toList(),
      'selectedFoodRestrictions': _selectedFoodRestrictions.toList(),
    };

    return data;
  }

  Future<void> _restoreDraftIfNeeded() async {
    if (_registrationVisualMockEnabled) {
      _draftReady = true;
      return;
    }

    if (_draftRestoreAttempted) return;
    _draftRestoreAttempted = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final rawDraft = prefs.getString(_draftStorageKey);
      if (rawDraft == null || rawDraft.trim().isEmpty) {
        _draftReady = true;
        return;
      }

      final decoded = json.decode(rawDraft);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != _draftVersion ||
          decoded['schoolId']?.toString() != widget.schoolId) {
        await prefs.remove(_draftStorageKey);
        _draftReady = true;
        return;
      }

      final updatedAt =
          DateTime.tryParse(decoded['updatedAt']?.toString() ?? '');
      if (updatedAt == null ||
          DateTime.now().difference(updatedAt) > _draftTtl) {
        await prefs.remove(_draftStorageKey);
        _draftReady = true;
        return;
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        await prefs.remove(_draftStorageKey);
        _draftReady = true;
        return;
      }

      await _applyDraft(decoded, data);
    } catch (_) {
      _draftReady = true;
    }
  }

  Future<void> _applyDraft(
    Map<String, dynamic> draft,
    Map<String, dynamic> data,
  ) async {
    _isRestoringDraft = true;
    try {
      final selectedClassId = _readDraftString(data, 'selectedClassId');
      final selectedOfferId =
          _readDraftString(data, 'selectedEnrollmentOfferId');

      for (final entry in _draftTextControllers.entries) {
        if (data.containsKey(entry.key)) {
          entry.value.text = data[entry.key]?.toString() ?? '';
        }
      }

      final selectedClass = _findAvailableClassById(selectedClassId);

      final restoredStep = _normalizedDraftStep(
        _readDraftInt(draft, 'currentStep'),
        selectedClass: selectedClass,
        selectedEducationLevel:
            _readDraftString(data, 'selectedEducationLevel'),
      );

      if (!mounted) return;
      setState(() {
        _selectedNeighborhood = _readDraftString(data, 'selectedNeighborhood');
        _selectedEducationLevel =
            _readDraftString(data, 'selectedEducationLevel');
        _selectedClass = selectedClass;
        _selectedEnrollmentOffer = null;
        _studentGender =
            _readDraftString(data, 'studentGender') ?? _studentGender;
        _relationship = _readDraftString(data, 'relationship') ?? _relationship;
        _fatherNotInformed =
            _readDraftBool(data, 'fatherNotInformed') ?? _fatherNotInformed;
        _primaryResponsibleType =
            _readDraftString(data, 'primaryResponsibleType') ??
                _primaryResponsibleType;
        if (_primaryResponsibleType == 'father' && _fatherNotInformed) {
          _primaryResponsibleType = 'mother';
        }
        _otherRelationship =
            _readDraftString(data, 'otherRelationship') ?? _otherRelationship;
        _hasHealthCondition =
            _readDraftBool(data, 'hasHealthCondition') ?? _hasHealthCondition;
        _usesContinuousMedication =
            _readDraftBool(data, 'usesContinuousMedication') ??
                _usesContinuousMedication;
        _hasAllergies = _readDraftBool(data, 'hasAllergies') ?? _hasAllergies;
        _hasDisability =
            _readDraftBool(data, 'hasDisability') ?? _hasDisability;
        _hasNeurodevelopmentalCondition =
            _readDraftBool(data, 'hasNeurodevelopmentalCondition') ??
                _hasNeurodevelopmentalCondition;
        _wearsGlasses = _readDraftBool(data, 'wearsGlasses') ?? _wearsGlasses;
        _usesGlassesDaily =
            _readDraftBool(data, 'usesGlassesDaily') ?? _usesGlassesDaily;
        _needsFrontSeat =
            _readDraftBool(data, 'needsFrontSeat') ?? _needsFrontSeat;
        _hasFoodRestriction =
            _readDraftBool(data, 'hasFoodRestriction') ?? _hasFoodRestriction;
        _selectedAllergies
          ..clear()
          ..addAll(_readDraftStringList(data, 'selectedAllergies'));
        _selectedDisabilities
          ..clear()
          ..addAll(_readDraftStringList(data, 'selectedDisabilities'));
        _selectedNeurodevelopmentalConditions
          ..clear()
          ..addAll(
            _readDraftStringList(data, 'selectedNeurodevelopmentalConditions'),
          );
        _selectedFoodRestrictions
          ..clear()
          ..addAll(_readDraftStringList(data, 'selectedFoodRestrictions'));
        _currentStep = restoredStep;
      });

      if (_selectedClass != null && selectedOfferId != null) {
        await _fetchOffersForSelectedClass();
        if (mounted) {
          setState(() {
            _selectedEnrollmentOffer = _findOfferById(selectedOfferId);
          });
        }
      }

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showMessage(
              'Rascunho recuperado. Você pode continuar de onde parou.',
            );
          }
        });
      }
    } finally {
      _isRestoringDraft = false;
      _draftReady = true;
    }
  }

  int _normalizedDraftStep(
    int? value, {
    required PublicRegistrationClassModel? selectedClass,
    required String? selectedEducationLevel,
  }) {
    var step = value ?? 0;
    if (step < 0) step = 0;
    if (step >= _successStep) step = _reviewStep;
    const validSteps = {
      _welcomeStep,
      _classStep,
      _offerStep,
      _studentStep,
      _motherStep,
      _fatherStep,
      _responsibleStep,
      _addressStep,
      _healthStep,
      _reviewStep,
    };
    if (!validSteps.contains(step)) return _classStep;
    if (selectedEducationLevel == null && step > _classStep) {
      return _classStep;
    }
    if (selectedClass == null && step > _classStep) {
      return _classStep;
    }
    return step;
  }

  PublicRegistrationClassModel? _findAvailableClassById(String? id) {
    if (id == null) return null;
    for (final classItem in _classes) {
      if (classItem.id == id && classItem.isAvailable) return classItem;
    }
    return null;
  }

  PublicEnrollmentOfferModel? _findOfferById(String? id) {
    if (id == null) return null;
    for (final offer in _availableOffers) {
      if (offer.id == id) return offer;
    }
    return null;
  }

  String? _readDraftString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  bool? _readDraftBool(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return null;
  }

  int? _readDraftInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  List<String> _readDraftStringList(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! List) return const [];
    return value
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
  }

  Future<void> _loadInitialData() async {
    final shouldKeepSplash = _showInitialSplash;
    final splashGuard = Future.wait<void>([
      Future<void>.delayed(const Duration(milliseconds: 850)),
      Future<void>(() async {
        try {
          await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 2));
        } catch (_) {
          // A fonte não deve travar a abertura do formulário.
        }
      }),
    ]);

    setState(() {
      _isLoadingClasses = true;
      _classesError = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _service.fetchPublicContext(widget.schoolId),
        _service.fetchPublicClasses(widget.schoolId),
      ]);
      if (!mounted) return;

      final schoolContext = results[0] as PublicRegistrationSchoolContext;
      final classes = results[1] as List<PublicRegistrationClassModel>;
      final availableLevels = _availableEducationLevels(classes);
      final currentLevelStillExists = availableLevels.contains(
        _selectedEducationLevel,
      );

      await _precacheSchoolLogo(schoolContext);
      if (shouldKeepSplash) await splashGuard;
      if (!mounted) return;

      setState(() {
        _schoolContext = schoolContext;
        _classes = classes;
        _selectedEducationLevel = currentLevelStillExists
            ? _selectedEducationLevel
            : (availableLevels.length == 1 ? availableLevels.first : null);
        _selectedClass = classes.any((item) => item.id == _selectedClass?.id)
            ? _selectedClass
            : null;
      });
    } catch (error) {
      if (shouldKeepSplash) await splashGuard;
      if (!mounted) return;
      setState(() => _classesError = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingClasses = false;
          _showInitialSplash = false;
        });
        await _restoreDraftIfNeeded();
        _loadEarlyPaymentOffer();
      }
    }
  }

  /// Loads an advance-payment discount offer, if the school has one running.
  /// Failures are silent: the offer never gets in the way of the enrollment.
  Future<void> _loadEarlyPaymentOffer() async {
    try {
      final offers = await _earlyPaymentService.publicOffers(widget.schoolId);
      if (!mounted || offers.isEmpty) return;
      final offer = offers.first;
      setState(() => _earlyOffer = offer);
      if (!await EarlyPaymentOfferMemory.shouldAutoShow(offer.id)) return;
      // Let the family settle on the form before the card slides in.
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      if (mounted && _currentStep != _successStep) {
        setState(() => _earlyOfferToastVisible = true);
      }
    } catch (_) {}
  }

  void _acceptEarlyOffer() {
    setState(() => _earlyOfferAccepted = true);
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _earlyOfferToastVisible = false);
    });
    if (_currentStep == _successStep) _registerEarlyOfferAdhesion();
  }

  void _dismissEarlyOffer() {
    final offer = _earlyOffer;
    setState(() => _earlyOfferToastVisible = false);
    if (offer != null && !_earlyOfferAccepted) {
      EarlyPaymentOfferMemory.dismiss(offer.id);
    }
  }

  Future<void> _registerEarlyOfferAdhesion() async {
    final offer = _earlyOffer;
    if (offer == null || _earlyOfferRegistered || _earlyOfferRegistering) {
      return;
    }
    setState(() => _earlyOfferRegistering = true);
    final tutor = _buildTutorData(const {});
    try {
      await _earlyPaymentService.publicAdhesion(widget.schoolId, offer.id, {
        if (_submittedRequestId != null)
          'registrationRequestId': _submittedRequestId,
        'studentName': _studentNameController.text.trim(),
        'guardianName': '${tutor['fullName'] ?? ''}',
        'guardianPhone': '${tutor['phoneNumber'] ?? ''}',
        'guardianEmail': '${tutor['email'] ?? ''}',
        'targetLevel': _selectedClass?.educationLevel ?? '',
        'targetGrade': _selectedClass?.grade ?? '',
        'targetShift': _selectedClass?.shift ?? '',
      });
      if (mounted) {
        setState(() {
          _earlyOfferRegistered = true;
          _earlyOfferAccepted = true;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$error'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _earlyOfferRegistering = false);
    }
  }

  Future<void> _precacheSchoolLogo(
    PublicRegistrationSchoolContext schoolContext,
  ) async {
    final logoUrl = schoolContext.logoUrl;
    if (logoUrl == null || logoUrl.trim().isEmpty || !mounted) return;

    try {
      await precacheImage(NetworkImage(logoUrl), context)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // A primeira tela usa placeholder se a logo falhar ou demorar.
    }
  }

  void _goBack() {
    if (_isSubmitting) return;
    final previousStep = _previousStepFor(_currentStep);
    if (previousStep != null) {
      setState(() => _currentStep = previousStep);
      _scheduleDraftSave();
    }
  }

  int? _previousStepFor(int step) {
    switch (step) {
      case _classStep:
        return _welcomeStep;
      case _offerStep:
        return _classStep;
      case _studentStep:
        return _shouldShowOfferStep ? _offerStep : _classStep;
      case _motherStep:
        return _studentStep;
      case _fatherStep:
        return _motherStep;
      case _responsibleStep:
        return _fatherStep;
      case _addressStep:
        return _responsibleStep;
      case _healthStep:
        return _addressStep;
      case _reviewStep:
        return _healthStep;
      default:
        return null;
    }
  }

  Future<void> _handlePrimaryAction() async {
    FocusScope.of(context).unfocus();

    switch (_currentStep) {
      case _welcomeStep:
        if (_isLoadingClasses || _classesError != null) return;
        setState(() => _currentStep = _classStep);
        _scheduleDraftSave();
        return;
      case _studentStep:
        if (_studentFormKey.currentState?.validate() != true) return;
        setState(() => _currentStep = _motherStep);
        _scheduleDraftSave();
        return;
      case _motherStep:
        if (_motherFormKey.currentState?.validate() != true) return;
        setState(() => _currentStep = _fatherStep);
        _scheduleDraftSave();
        return;
      case _fatherStep:
        if (_fatherFormKey.currentState?.validate() != true) return;
        setState(() => _currentStep = _responsibleStep);
        _scheduleDraftSave();
        return;
      case _responsibleStep:
        if (_responsibleFormKey.currentState?.validate() != true) return;
        if (!_validatePrimaryResponsible()) return;
        setState(() => _currentStep = _addressStep);
        _scheduleDraftSave();
        return;
      case _addressStep:
        if (_addressFormKey.currentState?.validate() != true) return;
        if (_selectedNeighborhood == null) {
          _showMessage('Escolha o bairro do aluno para continuar.');
          return;
        }
        if (!_hasAddressLocator) {
          _showMessage('Informe o número ou preencha quadra e lote.');
          return;
        }
        setState(() => _currentStep = _healthStep);
        _scheduleDraftSave();
        return;
      case _healthStep:
        if (_healthFormKey.currentState?.validate() != true) return;
        if (!_validateHealthStep()) return;
        setState(() => _currentStep = _reviewStep);
        _scheduleDraftSave();
        return;
      case _classStep:
        if (_selectedClass == null || !_selectedClass!.isAvailable) {
          _showMessage('Escolha uma turma disponível para continuar.');
          return;
        }
        await _prepareRegimeStep();
        return;
      case _offerStep:
        if (_isLoadingOffers) return;
        setState(() => _currentStep = _studentStep);
        _scheduleDraftSave();
        return;
      case _reviewStep:
        await _submitRegistration();
        return;
    }
  }

  Future<void> _prepareRegimeStep() async {
    final selectedClass = _selectedClass;
    if (selectedClass == null) return;

    if (_offersLoadedForClassId != selectedClass.id && !_isLoadingOffers) {
      await _fetchOffersForSelectedClass();
    }
    if (!mounted) return;

    setState(() {
      _currentStep = _shouldShowOfferStep ? _offerStep : _studentStep;
    });
    _scheduleDraftSave();
  }

  Future<void> _fetchOffersForSelectedClass() async {
    final selectedClass = _selectedClass;
    if (selectedClass == null) return;

    setState(() {
      _isLoadingOffers = true;
      _offersError = null;
      _availableOffers = [];
      _selectedEnrollmentOffer = null;
    });

    try {
      final offers = await _service.fetchPublicEnrollmentOffers(
        schoolId: widget.schoolId,
        classId: selectedClass.id,
      );
      if (!mounted || _selectedClass?.id != selectedClass.id) return;

      setState(() {
        _availableOffers = offers;
        _offersLoadedForClassId = selectedClass.id;
        if (_currentStep == _offerStep && offers.isEmpty) {
          _currentStep = _studentStep;
        }
      });
    } catch (error) {
      if (!mounted || _selectedClass?.id != selectedClass.id) return;

      setState(() {
        _offersError = error.toString().replaceFirst('Exception: ', '');
        _offersLoadedForClassId = selectedClass.id;
      });
    } finally {
      if (mounted && _selectedClass?.id == selectedClass.id) {
        setState(() => _isLoadingOffers = false);
      }
    }
  }

  Future<void> _submitRegistration() async {
    if (_selectedClass == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    final success = await showReportCardOperationDialog(
      context: context,
      operation: () async {
        _submittedRequestId =
            await _service.submitRegistrationRequest(_buildPayload());
      },
      loadingTitle: 'Enviando solicitação',
      loadingMessage: 'Estamos enviando os dados para a escola.',
      loadingDetail: 'Não feche esta tela enquanto o envio termina.',
      successTitle: 'Dados enviados com sucesso.',
      successMessage:
          'A escola irá revisar as informações e confirmar os próximos passos.',
      errorTitle: 'Não foi possível enviar a solicitação.',
      errorFallbackMessage: 'Confira os dados informados e tente novamente.',
    );

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      if (success == true) _currentStep = _successStep;
    });
    if (success == true) {
      await _clearDraft();
      if (_earlyOfferAccepted) await _registerEarlyOfferAdhesion();
    }
  }

  Map<String, dynamic> _buildPayload() {
    final address = {
      'street': _streetController.text.trim(),
      'number': _numberController.text.trim(),
      'block': _blockController.text.trim(),
      'lot': _lotController.text.trim(),
      'complement': _complementController.text.trim(),
      'neighborhood': _selectedNeighborhood,
      'city': 'Parauapebas',
      'state': 'PA',
      'cep': _cepController.text.trim(),
      'zipCode': _cepController.text.trim(),
    };
    final tutorData = _buildTutorData(address);

    final selectedOffer = _selectedEnrollmentOffer;
    final payload = <String, dynamic>{
      'school_id': widget.schoolId,
      'registrationType': 'MINOR_STUDENT',
      'origin': 'mobile_public_enrollment',
      'onlyMinors': widget.onlyMinors,
      'selectedClassId': _selectedClass!.id,
      'requestedRegime': selectedOffer?.type ?? 'regular',
      'studentData': {
        'fullName': _studentNameController.text.trim(),
        'birthDate': _toIsoDate(_studentBirthController.text),
        'cpf': _studentCpfController.text.trim(),
        'motherName': _motherNameController.text.trim(),
        'fatherName': _normalizedFatherName,
        'parents': {
          'mother': _buildMotherData(address),
          'father': _buildFatherData(address),
        },
        'primaryResponsibleType': _primaryResponsibleType,
        'intendedGrade': _selectedClass!.grade ?? _selectedClass!.name,
        'gender': _studentGender,
        'race': 'Prefiro não dizer',
        'nationality': 'Brasileira',
        'address': address,
        'healthInfo': _buildHealthInfo(),
        'authorizedPickups': [],
      },
      'tutorData': tutorData,
    };

    if (selectedOffer != null) {
      payload['selectedEnrollmentOfferId'] = selectedOffer.id;
    }

    return payload;
  }

  Map<String, dynamic> _buildMotherData(Map<String, dynamic> address) {
    return {
      'fullName': _motherNameController.text.trim(),
      'birthDate': _toIsoDate(_motherBirthController.text),
      'cpf': _motherCpfController.text.trim(),
      'rg': _motherRgController.text.trim(),
      'phoneNumber': _motherPhoneController.text.trim(),
      'email': _motherEmailController.text.trim().toLowerCase(),
      'profession': _motherProfessionController.text.trim(),
      'relationship': 'Mãe',
      'isPrimaryResponsible': _primaryResponsibleType == 'mother',
      'notInRegistry': false,
      'address': address,
    };
  }

  Map<String, dynamic> _buildFatherData(Map<String, dynamic> address) {
    return {
      'fullName': _normalizedFatherName,
      'birthDate':
          _fatherNotInformed ? null : _toIsoDate(_fatherBirthController.text),
      'cpf': _fatherNotInformed ? '' : _fatherCpfController.text.trim(),
      'rg': _fatherNotInformed ? '' : _fatherRgController.text.trim(),
      'phoneNumber':
          _fatherNotInformed ? '' : _fatherPhoneController.text.trim(),
      'email': _fatherNotInformed
          ? ''
          : _fatherEmailController.text.trim().toLowerCase(),
      'profession':
          _fatherNotInformed ? '' : _fatherProfessionController.text.trim(),
      'relationship': 'Pai',
      'isPrimaryResponsible': _primaryResponsibleType == 'father',
      'notInRegistry': _fatherNotInformed,
      'address': address,
    };
  }

  Map<String, dynamic> _buildTutorData(Map<String, dynamic> address) {
    if (_primaryResponsibleType == 'mother') {
      return {
        ..._buildMotherData(address),
        'relationship': 'Mãe',
        'gender': 'Feminino',
        'nationality': 'Brasileira',
      };
    }

    if (_primaryResponsibleType == 'father') {
      return {
        ..._buildFatherData(address),
        'relationship': 'Pai',
        'gender': 'Masculino',
        'nationality': 'Brasileira',
      };
    }

    return {
      'fullName': _guardianNameController.text.trim(),
      'birthDate': _toIsoDate(_guardianBirthController.text),
      'cpf': _guardianCpfController.text.trim(),
      'rg': _guardianRgController.text.trim(),
      'phoneNumber': _guardianPhoneController.text.trim(),
      'email': _guardianEmailController.text.trim().toLowerCase(),
      'profession': _guardianProfessionController.text.trim(),
      'relationship': _apiRelationshipLabel(_otherRelationship),
      'gender': 'Outro',
      'nationality': 'Brasileira',
      'address': address,
    };
  }

  Map<String, dynamic> _buildHealthInfo() {
    final medicationDetails = _joinValues([
      _medicationNameController.text,
      _medicationGuidanceController.text,
    ]);
    final allergyDetails = _joinValues([
      _selectedAllergies.join(', '),
      _allergyDetailsController.text,
    ]);
    final disabilityDetails = _joinValues([
      _selectedDisabilities.join(', '),
      _accessibilityNeedsController.text,
    ]);
    final glassesDetails = _joinValues([
      if (_wearsGlasses) 'Usa óculos ou lente de contato',
      if (_usesGlassesDaily) 'Usa diariamente',
      if (_needsFrontSeat) 'Precisa sentar mais perto do quadro',
    ]);
    final foodDetails = _joinValues([
      _selectedFoodRestrictions.join(', '),
      _foodRestrictionDetailsController.text,
    ]);

    return {
      'hasHealthCondition': _hasHealthCondition,
      'healthConditionDetails': _healthConditionDetailsController.text.trim(),
      'hasHealthProblem': _hasHealthCondition,
      'healthProblemDetails': _healthConditionDetailsController.text.trim(),
      'usesContinuousMedication': _usesContinuousMedication,
      'continuousMedicationName': _medicationNameController.text.trim(),
      'continuousMedicationGuidance': _medicationGuidanceController.text.trim(),
      'takesMedication': _usesContinuousMedication,
      'medicationDetails': medicationDetails,
      'hasAllergies': _hasAllergies,
      'allergies': _selectedAllergies.toList(),
      'hasAllergy': _hasAllergies,
      'allergyDetails': allergyDetails,
      'hasMedicationAllergy': _selectedAllergies.contains('Medicamentos'),
      'medicationAllergyDetails':
          _selectedAllergies.contains('Medicamentos') ? allergyDetails : '',
      'hasDisability': _hasDisability,
      'disabilities': _selectedDisabilities.toList(),
      'accessibilityNeeds': _accessibilityNeedsController.text.trim(),
      'disabilityDetails': disabilityDetails,
      'hasNeurodevelopmentalCondition': _hasNeurodevelopmentalCondition,
      'neurodevelopmentalConditions':
          _selectedNeurodevelopmentalConditions.toList(),
      'neurodevelopmentalDetails':
          _neurodevelopmentalDetailsController.text.trim(),
      'wearsGlasses': _wearsGlasses,
      'usesGlassesDaily': _usesGlassesDaily,
      'needsFrontSeat': _needsFrontSeat,
      'hasVisionProblem': _wearsGlasses,
      'visionProblemDetails': glassesDetails,
      'hasFoodRestriction': _hasFoodRestriction,
      'foodRestrictions': _selectedFoodRestrictions.toList(),
      'foodRestrictionDetails': _foodRestrictionDetailsController.text.trim(),
      'foodObservations': foodDetails,
      'emergencyContact': {
        'name': _emergencyNameController.text.trim(),
        'phoneNumber': _emergencyPhoneController.text.trim(),
        'relationship': _emergencyRelationshipController.text.trim(),
      },
      'feverMedication': '',
      'generalNotes': _healthGeneralNotesController.text.trim(),
    };
  }

  String _joinValues(Iterable<String> values) {
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' | ');
  }

  String _apiRelationshipLabel(String value) {
    if (value == 'Avó/Avô') return 'Avó/Avô';
    if (value == 'Tio/Tia') return 'Tio/Tia';
    if (value == 'Pai') return 'Pai';
    if (value == 'Mãe') return 'Mãe';
    return 'Outro';
  }

  String? _toIsoDate(String value) {
    final date = _parseDate(value);
    return date?.toIso8601String();
  }

  DateTime? _parseDate(String value) {
    try {
      return DateFormat('dd/MM/yyyy').parseStrict(value.trim());
    } catch (_) {
      return null;
    }
  }

  bool _isMinor(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age < 18;
  }

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

  bool _isValidCpf(String value) {
    final digits = _digitsOnly(value);
    if (digits.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

    int calculateDigit(int length) {
      var sum = 0;
      for (var index = 0; index < length; index++) {
        sum += int.parse(digits[index]) * ((length + 1) - index);
      }
      final remainder = (sum * 10) % 11;
      return remainder == 10 ? 0 : remainder;
    }

    return calculateDigit(9) == int.parse(digits[9]) &&
        calculateDigit(10) == int.parse(digits[10]);
  }

  String? _validateFullName(String? value) {
    final parts = (value ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.length > 1)
        .toList();
    if (parts.length < 2) return 'Informe nome e sobrenome.';
    return null;
  }

  String? _validateOptionalFullName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    return _validateFullName(text);
  }

  String? _validateBirthDate(String? value, {bool mustBeMinor = false}) {
    final date = _parseDate(value ?? '');
    if (date == null) return 'Informe uma data válida.';
    if (date.isAfter(DateTime.now())) return 'A data não pode ser futura.';
    if (mustBeMinor && !_isMinor(date)) {
      return 'Este link é para solicitação de matrícula de menores.';
    }
    return null;
  }

  String? _validateCpf(String? value, {bool required = true}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty && !required) return null;
    if (text.isEmpty) return 'Informe o CPF.';
    if (!_isValidCpf(text)) return 'Digite um CPF válido.';
    return null;
  }

  String? _validatePhone(String? value) {
    final digits = _digitsOnly(value ?? '');
    if (digits.length != 10 && digits.length != 11) {
      return 'Informe um telefone válido com DDD.';
    }
    return null;
  }

  String? _validateOptionalPhone(String? value) {
    final digits = _digitsOnly(value ?? '');
    if (digits.isEmpty) return null;
    if (digits.length != 10 && digits.length != 11) {
      return 'Informe um telefone válido com DDD.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
    if (normalized.isEmpty) return 'Informe o e-mail.';
    if (!regex.hasMatch(normalized)) return 'Digite um e-mail válido.';
    return null;
  }

  String? _validateOptionalEmail(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
    if (!regex.hasMatch(normalized)) return 'Digite um e-mail válido.';
    return null;
  }

  String? _validateOptionalBirthDate(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    return _validateBirthDate(text);
  }

  String? _validateCep(String? value) {
    if (_digitsOnly(value ?? '').length != 8) return 'Informe um CEP válido.';
    return null;
  }

  String? _validateRequired(String? value, String message) {
    if ((value ?? '').trim().isEmpty) return message;
    return null;
  }

  String? _validateAddressLocator(String? value) {
    if (_hasAddressLocator) return null;
    return 'Informe o número ou quadra e lote.';
  }

  String? _validateBlock(String? value) {
    if (_numberController.text.trim().isNotEmpty) return null;
    if (_blockController.text.trim().isEmpty &&
        _lotController.text.trim().isNotEmpty) {
      return 'Informe a quadra.';
    }
    return null;
  }

  String? _validateLot(String? value) {
    if (_numberController.text.trim().isNotEmpty) return null;
    if (_lotController.text.trim().isEmpty &&
        _blockController.text.trim().isNotEmpty) {
      return 'Informe o lote.';
    }
    return null;
  }

  String get _normalizedFatherName {
    if (_fatherNotInformed) return 'Não informado';
    return _fatherNameController.text.trim();
  }

  bool get _hasAddressLocator {
    final number = _numberController.text.trim();
    final block = _blockController.text.trim();
    final lot = _lotController.text.trim();
    return number.isNotEmpty || (block.isNotEmpty && lot.isNotEmpty);
  }

  bool _validatePrimaryResponsible() {
    if (_primaryResponsibleType == 'father' && _fatherNotInformed) {
      _showMessage('Informe os dados do pai ou escolha outro responsável.');
      return false;
    }

    final requiredError = _primaryResponsibleMissingMessage;
    if (requiredError != null) {
      _showMessage(requiredError);
      return false;
    }

    return true;
  }

  String? get _primaryResponsibleMissingMessage {
    final data = _primaryResponsibleFields;

    if (_validateFullName(data['name']) != null) {
      return 'Informe o nome completo do responsável principal.';
    }
    if (_validateBirthDate(data['birthDate']) != null) {
      return 'Informe a data de nascimento do responsável principal.';
    }
    if (_validateCpf(data['cpf']) != null) {
      return 'Informe um CPF válido para o responsável principal.';
    }
    if (_validatePhone(data['phone']) != null) {
      return 'Informe um telefone válido com DDD para o responsável principal.';
    }
    if (_validateEmail(data['email']) != null) {
      return 'Informe um e-mail válido para o responsável principal.';
    }

    return null;
  }

  Map<String, String> get _primaryResponsibleFields {
    if (_primaryResponsibleType == 'mother') {
      return {
        'name': _motherNameController.text,
        'birthDate': _motherBirthController.text,
        'cpf': _motherCpfController.text,
        'phone': _motherPhoneController.text,
        'email': _motherEmailController.text,
      };
    }

    if (_primaryResponsibleType == 'father') {
      return {
        'name': _fatherNameController.text,
        'birthDate': _fatherBirthController.text,
        'cpf': _fatherCpfController.text,
        'phone': _fatherPhoneController.text,
        'email': _fatherEmailController.text,
      };
    }

    return {
      'name': _guardianNameController.text,
      'birthDate': _guardianBirthController.text,
      'cpf': _guardianCpfController.text,
      'phone': _guardianPhoneController.text,
      'email': _guardianEmailController.text,
    };
  }

  bool _validateHealthStep() {
    if (_hasHealthCondition &&
        _healthConditionDetailsController.text.trim().isEmpty) {
      _showMessage('Descreva a condição de saúde informada.');
      return false;
    }
    if (_usesContinuousMedication &&
        _medicationNameController.text.trim().isEmpty) {
      _showMessage('Informe o medicamento de uso contínuo.');
      return false;
    }
    if (_hasAllergies &&
        _selectedAllergies.isEmpty &&
        _allergyDetailsController.text.trim().isEmpty) {
      _showMessage('Selecione ou descreva a alergia.');
      return false;
    }
    if (_hasDisability &&
        _selectedDisabilities.isEmpty &&
        _accessibilityNeedsController.text.trim().isEmpty) {
      _showMessage('Selecione ou descreva a necessidade de acessibilidade.');
      return false;
    }
    if (_hasNeurodevelopmentalCondition &&
        _selectedNeurodevelopmentalConditions.isEmpty &&
        _neurodevelopmentalDetailsController.text.trim().isEmpty) {
      _showMessage(
          'Selecione ou descreva a orientação de neurodesenvolvimento.');
      return false;
    }
    if (_hasFoodRestriction &&
        _selectedFoodRestrictions.isEmpty &&
        _foodRestrictionDetailsController.text.trim().isEmpty) {
      _showMessage('Selecione ou descreva a restrição alimentar.');
      return false;
    }
    return true;
  }

  String get _primaryResponsibleLabel {
    switch (_primaryResponsibleType) {
      case 'mother':
        return 'Mãe';
      case 'father':
        return 'Pai';
      default:
        return 'Outro responsável';
    }
  }

  String get _primaryResponsibleName {
    if (_primaryResponsibleType == 'mother') {
      return _motherNameController.text.trim();
    }
    if (_primaryResponsibleType == 'father') {
      return _normalizedFatherName;
    }
    return _guardianNameController.text.trim();
  }

  String get _primaryResponsiblePhone {
    if (_primaryResponsibleType == 'mother') {
      return _motherPhoneController.text.trim();
    }
    if (_primaryResponsibleType == 'father') {
      return _fatherPhoneController.text.trim();
    }
    return _guardianPhoneController.text.trim();
  }

  String get _primaryResponsibleEmail {
    if (_primaryResponsibleType == 'mother') {
      return _motherEmailController.text.trim().toLowerCase();
    }
    if (_primaryResponsibleType == 'father') {
      return _fatherEmailController.text.trim().toLowerCase();
    }
    return _guardianEmailController.text.trim().toLowerCase();
  }

  TextEditingController get _emailControllerForPrimary {
    if (_primaryResponsibleType == 'mother') return _motherEmailController;
    if (_primaryResponsibleType == 'father') return _fatherEmailController;
    return _guardianEmailController;
  }

  Map<String, String> get _healthReviewItems {
    return {
      'Condição de saúde': _hasHealthCondition
          ? _healthConditionDetailsController.text.trim()
          : 'Não informado',
      'Medicamento': _usesContinuousMedication
          ? _joinValues([
              _medicationNameController.text,
              _medicationGuidanceController.text,
            ])
          : 'Não usa',
      'Alergias': _hasAllergies
          ? _joinValues([
              _selectedAllergies.join(', '),
              _allergyDetailsController.text,
            ])
          : 'Não informado',
      'Acessibilidade': _hasDisability
          ? _joinValues([
              _selectedDisabilities.join(', '),
              _accessibilityNeedsController.text,
            ])
          : 'Não informado',
      'Neurodesenvolvimento': _hasNeurodevelopmentalCondition
          ? _joinValues([
              _selectedNeurodevelopmentalConditions.join(', '),
              _neurodevelopmentalDetailsController.text,
            ])
          : 'Não informado',
      'Óculos': _wearsGlasses
          ? _joinValues([
              'Sim',
              if (_usesGlassesDaily) 'uso diário',
              if (_needsFrontSeat) 'sentar perto do quadro',
            ])
          : 'Não usa',
      'Alimentação': _hasFoodRestriction
          ? _joinValues([
              _selectedFoodRestrictions.join(', '),
              _foodRestrictionDetailsController.text,
            ])
          : 'Sem restrição informada',
      'Emergência': _emergencyNameController.text.trim().isEmpty
          ? 'Não informado'
          : _joinValues([
              _emergencyNameController.text,
              _emergencyPhoneController.text,
              _emergencyRelationshipController.text,
            ]),
    };
  }

  List<String> get _educationLevels => _availableEducationLevels(_classes);

  List<String> _availableEducationLevels(
    List<PublicRegistrationClassModel> classes,
  ) {
    final levels = <String>{};
    for (final item in classes) {
      final level = (item.educationLevel ?? '').trim();
      if (level.isNotEmpty) levels.add(level);
    }
    const preferredOrder = [
      'Educação Infantil',
      'Ensino Fundamental I',
      'Ensino Fundamental II',
      'Ensino Médio',
    ];
    return levels.toList()
      ..sort((a, b) {
        final aIndex = preferredOrder.indexOf(a);
        final bIndex = preferredOrder.indexOf(b);
        if (aIndex != -1 && bIndex != -1) return aIndex.compareTo(bIndex);
        if (aIndex != -1) return -1;
        if (bIndex != -1) return 1;
        return a.compareTo(b);
      });
  }

  List<PublicRegistrationClassModel> get _visibleClasses {
    if (_selectedEducationLevel == null) return const [];
    return (_classes
        .where((item) => item.educationLevel == _selectedEducationLevel)
        .where((item) => item.id.trim().isNotEmpty)
        .toList()
      ..sort((a, b) {
        final gradeCompare = (a.grade ?? '').compareTo(b.grade ?? '');
        if (gradeCompare != 0) return gradeCompare;
        final nameCompare = a.name.compareTo(b.name);
        if (nameCompare != 0) return nameCompare;
        return (a.shift ?? '').compareTo(b.shift ?? '');
      }));
  }

  bool get _shouldShowOfferStep =>
      _availableOffers.isNotEmpty || _offersError != null;

  List<int> get _orderedDataSteps => [
        _classStep,
        if (_shouldShowOfferStep) _offerStep,
        _studentStep,
        _motherStep,
        _fatherStep,
        _responsibleStep,
        _addressStep,
        _healthStep,
        _reviewStep,
      ];

  int get _visibleStepCount => _orderedDataSteps.length;

  int get _visibleStepNumber {
    final index = _orderedDataSteps.indexOf(_currentStep);
    return index == -1 ? 0 : index + 1;
  }

  Map<String, String> get _regimeReviewItems {
    final selectedClass = _selectedClass;
    final selectedOffer = _selectedEnrollmentOffer;
    if (selectedOffer == null) {
      return {
        'Regime escolhido': 'Meio período',
        if (selectedClass != null) 'Turma de referência': selectedClass.name,
        if (selectedClass != null)
          'Mensalidade da turma': _formatMonthlyFee(selectedClass.monthlyFee),
      };
    }

    return {
      'Regime escolhido': selectedOffer.displayName,
      'Horário': _offerScheduleLabel(selectedOffer),
      'Mensalidade': _offerFeeLabel(selectedOffer),
      if (selectedClass != null) 'Turma de referência': selectedClass.name,
      if (selectedOffer.permanenceClassMode != 'none')
        'Contraturno':
            'A escola irá revisar as informações e organizar os próximos passos.',
    };
  }

  void _clearSelectedOffer() {
    _availableOffers = [];
    _selectedEnrollmentOffer = null;
    _offersError = null;
    _offersLoadedForClassId = null;
    _isLoadingOffers = false;
  }

  void _selectEducationLevel(String level) {
    setState(() {
      _selectedEducationLevel = level;
      _selectedClass = null;
      _clearSelectedOffer();
    });
    _scheduleDraftSave();
  }

  Future<void> _selectClass(PublicRegistrationClassModel classItem) async {
    if (!classItem.isAvailable) return;

    setState(() {
      _selectedClass = classItem;
      _clearSelectedOffer();
    });
    _scheduleDraftSave();

    await _fetchOffersForSelectedClass();
  }

  void _handleRelationshipChanged(String? value) {
    if (value == null) return;

    final shouldSuggestName = _guardianNameController.text.trim().isEmpty;
    setState(() {
      _relationship = value;
      if (shouldSuggestName && value == 'Mãe') {
        _guardianNameController.text = _motherNameController.text.trim();
      } else if (shouldSuggestName && value == 'Pai' && !_fatherNotInformed) {
        _guardianNameController.text = _fatherNameController.text.trim();
      }
    });
    _scheduleDraftSave();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.replaceFirst('Exception: ', '')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool get _canUsePrimaryButton {
    if (_isSubmitting) return false;
    if (_currentStep == _welcomeStep) {
      return !_isLoadingClasses && _classesError == null;
    }
    if (_currentStep == _classStep) {
      return _selectedClass?.isAvailable == true && !_isLoadingOffers;
    }
    if (_currentStep == _offerStep) return !_isLoadingOffers;
    return _currentStep < _successStep;
  }

  String get _primaryButtonLabel {
    if (_currentStep == _welcomeStep) return 'Começar';
    if (_currentStep == _reviewStep) return 'Enviar solicitação';
    return 'Continuar';
  }

  bool get _shouldShowEmailSuggestions {
    final text = _emailControllerForPrimary.text.trim().toLowerCase();
    if (text.isEmpty) return true;
    return _validateEmail(text) != null;
  }

  _RegistrationFlowColors get _flowColors =>
      _RegistrationFlowColors(isDark: _isDarkMode);

  @override
  Widget build(BuildContext context) {
    final isSuccess = _currentStep == _successStep;
    final flowColors = _RegistrationFlowColors(isDark: _isDarkMode);

    return Theme(
      data: _registrationFlowTheme(flowColors),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: _showInitialSplash
            ? _buildInitialSplash()
            : Scaffold(
                key: const ValueKey('registration-form'),
                backgroundColor: flowColors.background,
                body: SafeArea(
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          if (!isSuccess) _buildHeader(),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _buildStepContent(),
                            ),
                          ),
                          if (!isSuccess) _buildBottomBar(),
                        ],
                      ),
                      if (_earlyOffer != null &&
                          _earlyOfferToastVisible &&
                          !isSuccess)
                        Positioned(
                          left: 12.w,
                          right: 12.w,
                          bottom: 92.h,
                          child: Center(
                            child: EarlyPaymentOfferToast(
                              offer: _earlyOffer!,
                              accepted: _earlyOfferAccepted,
                              onAccept: _acceptEarlyOffer,
                              onDismiss: _dismissEarlyOffer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildInitialSplash() {
    return Scaffold(
      key: const ValueKey('initial-splash'),
      backgroundColor: Colors.white,
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.96, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 420),
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 112.w,
                height: 112.w,
                child: SvgPicture.asset(
                  'lib/assets/logo_chapeu_academy.svg',
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF111827),
                    BlendMode.srcIn,
                  ),
                ),
              ),
              SizedBox(height: 22.h),
              Text(
                'Carregando solicitação...',
                style: GoogleFonts.inter(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final colors = _flowColors;
    final hasProgress = _currentStep != _welcomeStep;
    final progress = hasProgress ? _visibleStepNumber / _visibleStepCount : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 48.w,
                height: 48.w,
                child: IconButton(
                  tooltip: 'Voltar',
                  onPressed: _currentStep == _welcomeStep ? null : _goBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
              Expanded(
                child: Text(
                  'Solicitação de matrícula',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              SizedBox(
                width: 48.w,
                height: 48.w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.selectedSurface,
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: colors.border),
                  ),
                  child: IconButton(
                    tooltip: colors.isDark
                        ? 'Ativar modo claro'
                        : 'Ativar modo escuro',
                    onPressed: () {
                      setState(() => _isDarkMode = !_isDarkMode);
                    },
                    icon: Icon(
                      colors.isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      color: colors.isDark
                          ? const Color(0xFFFDE68A)
                          : colors.brandStrong,
                      size: 22.sp,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_earlyOffer != null && !_earlyOfferToastVisible) ...[
            SizedBox(height: 4.h),
            EarlyPaymentOfferPill(
              offer: _earlyOffer!,
              accepted: _earlyOfferAccepted,
              onTap: () => setState(() => _earlyOfferToastVisible = true),
            ),
          ],
          SizedBox(height: 6.h),
          if (hasProgress) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6.h,
                value: progress,
                backgroundColor: colors.progressTrack,
                valueColor: AlwaysStoppedAnimation(colors.brand),
              ),
            ),
            SizedBox(height: 8.h),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Etapa $_visibleStepNumber de $_visibleStepCount',
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case _welcomeStep:
        return _buildWelcomeStep();
      case _classStep:
        return _buildClassStep();
      case _offerStep:
        return _shouldShowOfferStep ? _buildOfferStep() : _buildStudentStep();
      case _studentStep:
        return _buildStudentStep();
      case _motherStep:
        return _buildMotherStep();
      case _fatherStep:
        return _buildFatherStep();
      case _responsibleStep:
        return _buildResponsibleStep();
      case _addressStep:
        return _buildAddressStep();
      case _healthStep:
        return _buildHealthStep();
      case _reviewStep:
        return _buildReviewStep();
      case _successStep:
        return _buildSuccessStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWelcomeStep() {
    return _StepContainer(
      key: const ValueKey('welcome'),
      children: [
        const _StepIntro(
          title: 'Vamos iniciar a solicitação de matrícula.',
          subtitle:
              'Você vai preencher os dados em etapas rápidas. A escola revisará tudo antes de confirmar.',
          icon: Icons.school_rounded,
        ),
        SizedBox(height: 20.h),
        if (_schoolContext != null) _buildSchoolBrandCard(_schoolContext!),
        SizedBox(height: 18.h),
        if (_isLoadingClasses)
          _InfoBox(
            icon: Icons.sync_rounded,
            title: 'Carregando dados da escola',
            message: 'Estamos preparando as opções de turma para você.',
            trailing: SizedBox(
              width: 22.w,
              height: 22.w,
              child: const CircularProgressIndicator(strokeWidth: 2.4),
            ),
          )
        else if (_classesError != null)
          _InfoBox(
            icon: Icons.wifi_off_rounded,
            title: 'Não conseguimos carregar as turmas',
            message: _classesError!,
            actionLabel: 'Tentar novamente',
            onAction: _loadInitialData,
          )
        else
          const _InfoBox(
            icon: Icons.check_circle_rounded,
            title: 'Tudo pronto para começar',
            message:
                'Na etapa de turma, você verá apenas informações públicas e seguras.',
          ),
      ],
    );
  }

  Widget _buildSchoolBrandCard(PublicRegistrationSchoolContext school) {
    final colors = _flowColors;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: Container(
              width: 54.w,
              height: 54.w,
              color: colors.iconSurface,
              child: school.logoUrl == null
                  ? _SchoolLogoPlaceholder(initials: school.initials)
                  : Image.network(
                      school.logoUrl!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return _SchoolLogoPlaceholder(
                            initials: school.initials);
                      },
                      errorBuilder: (_, __, ___) =>
                          _SchoolLogoPlaceholder(initials: school.initials),
                    ),
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Você está solicitando matrícula para:',
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: colors.textMuted,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  school.name,
                  style: GoogleFonts.inter(
                    fontSize: 16.sp,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentStep() {
    return _StepContainer(
      key: const ValueKey('student'),
      children: [
        const _StepIntro(
          title: 'Vamos começar pelos dados do aluno.',
          subtitle: 'Informe os dados principais para identificar o estudante.',
          icon: Icons.person_rounded,
        ),
        SizedBox(height: 22.h),
        Form(
          key: _studentFormKey,
          child: Column(
            children: [
              _buildTextField(
                label: 'Nome completo do aluno',
                controller: _studentNameController,
                icon: Icons.badge_outlined,
                textCapitalization: TextCapitalization.words,
                validator: _validateFullName,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Data de nascimento',
                controller: _studentBirthController,
                icon: Icons.calendar_today_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: [_dateMask],
                validator: (value) => _validateBirthDate(
                  value,
                  mustBeMinor: widget.onlyMinors,
                ),
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'CPF do aluno, se tiver',
                controller: _studentCpfController,
                icon: Icons.credit_card_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: [_cpfMask],
                validator: (value) => _validateCpf(value, required: false),
              ),
              SizedBox(height: 14.h),
              _buildDropdownField(
                label: 'Gênero',
                value: _studentGender,
                items: const ['Feminino', 'Masculino', 'Outro'],
                onChanged: (value) =>
                    _setDraftState(() => _studentGender = value!),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMotherStep() {
    return _StepContainer(
      key: const ValueKey('mother'),
      children: [
        const _StepIntro(
          title: 'Agora, os dados da mãe.',
          subtitle:
              'Essas informações ajudam nos registros, documentos e contato escolar.',
          icon: Icons.person_2_rounded,
        ),
        SizedBox(height: 22.h),
        Form(
          key: _motherFormKey,
          child: Column(
            children: [
              _buildTextField(
                label: 'Nome completo da mãe',
                controller: _motherNameController,
                icon: Icons.badge_outlined,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                validator: _validateFullName,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Data de nascimento',
                controller: _motherBirthController,
                icon: Icons.event_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: [_dateMask],
                onChanged: (_) => setState(() {}),
                validator: _validateOptionalBirthDate,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'CPF da mãe',
                controller: _motherCpfController,
                icon: Icons.credit_card_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: [_cpfMask],
                onChanged: (_) => setState(() {}),
                validator: (value) => _validateCpf(value, required: false),
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'RG, se houver',
                controller: _motherRgController,
                icon: Icons.assignment_ind_outlined,
                textCapitalization: TextCapitalization.characters,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Telefone ou WhatsApp',
                controller: _motherPhoneController,
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneMask],
                onChanged: (_) => setState(() {}),
                validator: _validateOptionalPhone,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'E-mail',
                controller: _motherEmailController,
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                onChanged: (_) => setState(() {}),
                validator: _validateOptionalEmail,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Profissão/Ocupação',
                controller: _motherProfessionController,
                icon: Icons.work_outline_rounded,
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFatherStep() {
    final colors = _flowColors;

    return _StepContainer(
      key: const ValueKey('father'),
      children: [
        const _StepIntro(
          title: 'Agora, os dados do pai.',
          subtitle:
              'Se não constar no registro, marque a opção abaixo e siga em frente.',
          icon: Icons.person_3_rounded,
        ),
        SizedBox(height: 22.h),
        CheckboxListTile(
          value: _fatherNotInformed,
          onChanged: (value) {
            _setDraftState(() {
              _fatherNotInformed = value ?? false;
              if (_fatherNotInformed) {
                _fatherNameController.clear();
                _fatherBirthController.clear();
                _fatherCpfController.clear();
                _fatherRgController.clear();
                _fatherPhoneController.clear();
                _fatherEmailController.clear();
                _fatherProfessionController.clear();
                if (_primaryResponsibleType == 'father') {
                  _primaryResponsibleType = 'mother';
                }
              }
            });
          },
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: colors.brand,
          title: Text(
            'Não consta no registro',
            style: GoogleFonts.inter(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
        ),
        SizedBox(height: 10.h),
        Form(
          key: _fatherFormKey,
          child: Column(
            children: [
              _buildTextField(
                label: 'Nome completo do pai',
                controller: _fatherNameController,
                icon: Icons.badge_outlined,
                textCapitalization: TextCapitalization.words,
                enabled: !_fatherNotInformed,
                onChanged: (_) => setState(() {}),
                validator:
                    _fatherNotInformed ? null : _validateOptionalFullName,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Data de nascimento',
                controller: _fatherBirthController,
                icon: Icons.event_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: [_dateMask],
                enabled: !_fatherNotInformed,
                onChanged: (_) => setState(() {}),
                validator:
                    _fatherNotInformed ? null : _validateOptionalBirthDate,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'CPF do pai',
                controller: _fatherCpfController,
                icon: Icons.credit_card_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: [_cpfMask],
                enabled: !_fatherNotInformed,
                onChanged: (_) => setState(() {}),
                validator: _fatherNotInformed
                    ? null
                    : (value) => _validateCpf(value, required: false),
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'RG, se houver',
                controller: _fatherRgController,
                icon: Icons.assignment_ind_outlined,
                textCapitalization: TextCapitalization.characters,
                enabled: !_fatherNotInformed,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Telefone ou WhatsApp',
                controller: _fatherPhoneController,
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneMask],
                enabled: !_fatherNotInformed,
                onChanged: (_) => setState(() {}),
                validator: _fatherNotInformed ? null : _validateOptionalPhone,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'E-mail',
                controller: _fatherEmailController,
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textCapitalization: TextCapitalization.none,
                enabled: !_fatherNotInformed,
                onChanged: (_) => setState(() {}),
                validator: _fatherNotInformed ? null : _validateOptionalEmail,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Profissão/Ocupação',
                controller: _fatherProfessionController,
                icon: Icons.work_outline_rounded,
                textCapitalization: TextCapitalization.words,
                enabled: !_fatherNotInformed,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildFiliationStep() {
    final colors = _flowColors;

    return _StepContainer(
      key: const ValueKey('filiation'),
      children: [
        const _StepIntro(
          title: 'Informe a filiação do aluno.',
          subtitle:
              'Esses dados são usados em documentos e registros escolares.',
          icon: Icons.family_restroom_rounded,
        ),
        SizedBox(height: 22.h),
        Form(
          key: _motherFormKey,
          child: Column(
            children: [
              _buildTextField(
                label: 'Nome completo da mãe',
                controller: _motherNameController,
                icon: Icons.person_2_outlined,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                validator: _validateFullName,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Nome completo do pai',
                controller: _fatherNameController,
                icon: Icons.person_3_outlined,
                textCapitalization: TextCapitalization.words,
                enabled: !_fatherNotInformed,
                onChanged: (_) => setState(() {}),
                validator:
                    _fatherNotInformed ? null : _validateOptionalFullName,
              ),
              SizedBox(height: 8.h),
              CheckboxListTile(
                value: _fatherNotInformed,
                onChanged: (value) {
                  setState(() {
                    _fatherNotInformed = value ?? false;
                    if (_fatherNotInformed) _fatherNameController.clear();
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: colors.brand,
                title: Text(
                  'Não consta no registro',
                  style: GoogleFonts.inter(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResponsibleStep() {
    return _StepContainer(
      key: const ValueKey('responsible'),
      children: [
        const _StepIntro(
          title: 'Quem será o responsável principal?',
          subtitle:
              'Escolha a pessoa que a escola deve usar como contato principal da solicitação.',
          icon: Icons.supervisor_account_rounded,
        ),
        SizedBox(height: 22.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            _buildResponsibleChoice('mother', 'Mãe'),
            _buildResponsibleChoice('father', 'Pai',
                enabled: !_fatherNotInformed),
            _buildResponsibleChoice('other', 'Outro responsável'),
          ],
        ),
        SizedBox(height: 18.h),
        _InfoBox(
          icon: Icons.contact_phone_outlined,
          title: 'Contato principal',
          message:
              'Selecionado: $_primaryResponsibleLabel. O responsável principal precisa ter nome, nascimento, CPF, telefone e e-mail válidos.',
        ),
        if (_primaryResponsibleType != 'other') ...[
          SizedBox(height: 16.h),
          Form(
            key: _responsibleFormKey,
            child: Column(
              children: [
                _buildTextField(
                  label: 'Data de nascimento',
                  controller: _primaryResponsibleType == 'mother'
                      ? _motherBirthController
                      : _fatherBirthController,
                  icon: Icons.event_rounded,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_dateMask],
                  onChanged: (_) => setState(() {}),
                  validator: _validateBirthDate,
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  label: 'CPF do responsável',
                  controller: _primaryResponsibleType == 'mother'
                      ? _motherCpfController
                      : _fatherCpfController,
                  icon: Icons.credit_card_rounded,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_cpfMask],
                  onChanged: (_) => setState(() {}),
                  validator: _validateCpf,
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  label: 'Telefone ou WhatsApp',
                  controller: _primaryResponsibleType == 'mother'
                      ? _motherPhoneController
                      : _fatherPhoneController,
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_phoneMask],
                  onChanged: (_) => setState(() {}),
                  validator: _validatePhone,
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  label: 'E-mail',
                  controller: _emailControllerForPrimary,
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  onChanged: (_) => setState(() {}),
                  validator: _validateEmail,
                ),
              ],
            ),
          ),
        ],
        if (_shouldShowEmailSuggestions) ...[
          SizedBox(height: 14.h),
          _buildEmailSuggestions(),
        ],
        if (_primaryResponsibleType == 'other') ...[
          SizedBox(height: 20.h),
          Form(
            key: _responsibleFormKey,
            child: Column(
              children: [
                _buildTextField(
                  label: 'Nome completo do responsável',
                  controller: _guardianNameController,
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  validator: _validateFullName,
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  label: 'Data de nascimento',
                  controller: _guardianBirthController,
                  icon: Icons.event_rounded,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_dateMask],
                  onChanged: (_) => setState(() {}),
                  validator: _validateBirthDate,
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  label: 'CPF',
                  controller: _guardianCpfController,
                  icon: Icons.credit_card_rounded,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_cpfMask],
                  onChanged: (_) => setState(() {}),
                  validator: _validateCpf,
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  label: 'RG, se houver',
                  controller: _guardianRgController,
                  icon: Icons.assignment_ind_outlined,
                  textCapitalization: TextCapitalization.characters,
                ),
                SizedBox(height: 14.h),
                _buildDropdownField(
                  label: 'Parentesco',
                  value: _otherRelationship,
                  items: const [
                    'Responsável Legal',
                    'Avó/Avô',
                    'Tio/Tia',
                    'Outro',
                  ],
                  onChanged: (value) =>
                      _setDraftState(() => _otherRelationship = value!),
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  label: 'Telefone ou WhatsApp',
                  controller: _guardianPhoneController,
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_phoneMask],
                  onChanged: (_) => setState(() {}),
                  validator: _validatePhone,
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  label: 'E-mail',
                  controller: _guardianEmailController,
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  onChanged: (_) => setState(() {}),
                  validator: _validateEmail,
                ),
                SizedBox(height: 14.h),
                _buildTextField(
                  label: 'Profissão/Ocupação',
                  controller: _guardianProfessionController,
                  icon: Icons.work_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ignore: unused_element
  Widget _buildGuardianStep() {
    return _StepContainer(
      key: const ValueKey('guardian'),
      children: [
        const _StepIntro(
          title: 'Agora, informe os dados do responsável.',
          subtitle:
              'Esses dados serão usados pela escola para contato e conferência.',
          icon: Icons.supervisor_account_rounded,
        ),
        SizedBox(height: 22.h),
        Form(
          key: _responsibleFormKey,
          child: Column(
            children: [
              _buildTextField(
                label: 'Nome completo do responsável',
                controller: _guardianNameController,
                icon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                validator: _validateFullName,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Data de nascimento do responsável',
                controller: _guardianBirthController,
                icon: Icons.event_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: [_dateMask],
                onChanged: (_) => setState(() {}),
                validator: _validateBirthDate,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'CPF do responsável',
                controller: _guardianCpfController,
                icon: Icons.credit_card_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: [_cpfMask],
                onChanged: (_) => setState(() {}),
                validator: _validateCpf,
              ),
              SizedBox(height: 14.h),
              _buildDropdownField(
                label: 'Parentesco',
                value: _relationship,
                items: const [
                  'Mãe',
                  'Pai',
                  'Responsável Legal',
                  'Avó/Avô',
                  'Outro',
                ],
                onChanged: _handleRelationshipChanged,
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Telefone ou WhatsApp',
                controller: _guardianPhoneController,
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneMask],
                onChanged: (_) => setState(() {}),
                validator: _validatePhone,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildEmailStep() {
    final colors = _flowColors;

    return _StepContainer(
      key: const ValueKey('email'),
      children: [
        const _StepIntro(
          title: 'Qual e-mail a escola pode usar para contato?',
          subtitle: 'Use um e-mail que você acessa com frequência.',
          icon: Icons.alternate_email_rounded,
        ),
        SizedBox(height: 22.h),
        Form(
          key: _responsibleFormKey,
          child: _buildTextField(
            label: 'E-mail do responsável',
            controller: _guardianEmailController,
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            onChanged: (_) => setState(() {}),
            validator: _validateEmail,
          ),
        ),
        if (_shouldShowEmailSuggestions) ...[
          SizedBox(height: 16.h),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Sugestões rápidas',
              style: GoogleFonts.inter(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: const [
              _EmailDomainChip(domain: '@gmail.com'),
              _EmailDomainChip(domain: '@hotmail.com'),
              _EmailDomainChip(domain: '@outlook.com'),
              _EmailDomainChip(domain: '@icloud.com'),
              _EmailDomainChip(domain: '@yahoo.com.br'),
            ].map((chip) {
              return ActionChip(
                label: Text(chip.domain),
                onPressed: () => _applyEmailDomain(chip.domain),
                backgroundColor: colors.surface,
                side: BorderSide(color: colors.border),
                labelStyle: GoogleFonts.inter(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildAddressStep() {
    return _StepContainer(
      key: const ValueKey('address'),
      children: [
        const _StepIntro(
          title: 'Complete o endereço do aluno.',
          subtitle: 'O bairro deve ser escolhido na lista de Parauapebas.',
          icon: Icons.location_on_rounded,
        ),
        SizedBox(height: 22.h),
        Form(
          key: _addressFormKey,
          child: Column(
            children: [
              _buildTextField(
                label: 'CEP',
                controller: _cepController,
                icon: Icons.local_post_office_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [_cepMask],
                onChanged: (_) => setState(() {}),
                validator: _validateCep,
              ),
              SizedBox(height: 14.h),
              _buildNeighborhoodField(),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Rua, avenida ou travessa',
                controller: _streetController,
                icon: Icons.route_rounded,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                validator: (value) => _validateRequired(
                  value,
                  'Informe o logradouro.',
                ),
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Número',
                controller: _numberController,
                icon: Icons.pin_rounded,
                keyboardType: TextInputType.text,
                onChanged: (_) => setState(() {}),
                validator: _validateAddressLocator,
              ),
              SizedBox(height: 14.h),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      label: 'Quadra',
                      controller: _blockController,
                      icon: Icons.grid_view_rounded,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      validator: _validateBlock,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: _buildTextField(
                      label: 'Lote',
                      controller: _lotController,
                      icon: Icons.crop_square_rounded,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      validator: _validateLot,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              _buildTextField(
                label: 'Complemento, se houver',
                controller: _complementController,
                icon: Icons.add_home_work_outlined,
                textCapitalization: TextCapitalization.sentences,
              ),
              SizedBox(height: 14.h),
              _ReadOnlyLocationPill(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHealthStep() {
    final colors = _flowColors;

    return _StepContainer(
      key: const ValueKey('health'),
      children: [
        const _StepIntro(
          title: 'Ficha de saúde do aluno.',
          subtitle:
              'Essas informações ajudam a escola a oferecer o cuidado adequado no dia a dia.',
          icon: Icons.health_and_safety_rounded,
        ),
        SizedBox(height: 22.h),
        Form(
          key: _healthFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildYesNoQuestion(
                title:
                    'A criança possui alguma condição de saúde que a escola precisa saber?',
                value: _hasHealthCondition,
                onChanged: (value) =>
                    _setDraftState(() => _hasHealthCondition = value),
              ),
              if (_hasHealthCondition) ...[
                SizedBox(height: 12.h),
                _buildTextField(
                  label: 'Descreva a condição ou orientação',
                  controller: _healthConditionDetailsController,
                  icon: Icons.notes_rounded,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) => _hasHealthCondition
                      ? _validateRequired(
                          value,
                          'Descreva a condição de saúde.',
                        )
                      : null,
                ),
              ],
              SizedBox(height: 18.h),
              _buildYesNoQuestion(
                title: 'Usa medicamento de uso contínuo?',
                value: _usesContinuousMedication,
                onChanged: (value) =>
                    _setDraftState(() => _usesContinuousMedication = value),
              ),
              if (_usesContinuousMedication) ...[
                SizedBox(height: 12.h),
                _buildTextField(
                  label: 'Nome do medicamento',
                  controller: _medicationNameController,
                  icon: Icons.medication_outlined,
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => _usesContinuousMedication
                      ? _validateRequired(value, 'Informe o medicamento.')
                      : null,
                ),
                SizedBox(height: 12.h),
                _buildTextField(
                  label: 'Horário ou orientação',
                  controller: _medicationGuidanceController,
                  icon: Icons.schedule_rounded,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
              SizedBox(height: 18.h),
              _buildYesNoQuestion(
                title: 'Possui alergia?',
                value: _hasAllergies,
                onChanged: (value) => _setDraftState(() {
                  _hasAllergies = value;
                  if (!value) _selectedAllergies.clear();
                }),
              ),
              if (_hasAllergies) ...[
                SizedBox(height: 12.h),
                _buildMultiChoiceGroup(
                  options: _allergyOptions,
                  selected: _selectedAllergies,
                ),
                SizedBox(height: 12.h),
                _buildTextField(
                  label: 'Descreva a alergia ou orientação importante',
                  controller: _allergyDetailsController,
                  icon: Icons.notes_rounded,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
              SizedBox(height: 18.h),
              _buildYesNoQuestion(
                title: 'Possui deficiência ou necessidade de acessibilidade?',
                value: _hasDisability,
                onChanged: (value) => _setDraftState(() {
                  _hasDisability = value;
                  if (!value) _selectedDisabilities.clear();
                }),
              ),
              if (_hasDisability) ...[
                SizedBox(height: 12.h),
                _buildMultiChoiceGroup(
                  options: _disabilityOptions,
                  selected: _selectedDisabilities,
                ),
                SizedBox(height: 12.h),
                _buildTextField(
                  label: 'Apoios ou adaptações importantes',
                  controller: _accessibilityNeedsController,
                  icon: Icons.accessibility_new_rounded,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
              SizedBox(height: 18.h),
              _buildYesNoQuestion(
                title:
                    'Possui diagnóstico ou acompanhamento relacionado ao neurodesenvolvimento?',
                value: _hasNeurodevelopmentalCondition,
                onChanged: (value) => _setDraftState(() {
                  _hasNeurodevelopmentalCondition = value;
                  if (!value) _selectedNeurodevelopmentalConditions.clear();
                }),
              ),
              if (_hasNeurodevelopmentalCondition) ...[
                SizedBox(height: 12.h),
                _buildMultiChoiceGroup(
                  options: _neurodevelopmentalOptions,
                  selected: _selectedNeurodevelopmentalConditions,
                ),
                SizedBox(height: 12.h),
                _buildTextField(
                  label: 'Orientações importantes para a escola',
                  controller: _neurodevelopmentalDetailsController,
                  icon: Icons.psychology_alt_outlined,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
              SizedBox(height: 18.h),
              _buildYesNoQuestion(
                title: 'Usa óculos ou lente de contato?',
                value: _wearsGlasses,
                onChanged: (value) => _setDraftState(() {
                  _wearsGlasses = value;
                  if (!value) {
                    _usesGlassesDaily = false;
                    _needsFrontSeat = false;
                  }
                }),
              ),
              if (_wearsGlasses) ...[
                SizedBox(height: 8.h),
                CheckboxListTile(
                  value: _usesGlassesDaily,
                  onChanged: (value) =>
                      _setDraftState(() => _usesGlassesDaily = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  activeColor: colors.brand,
                  title: Text(
                    'Usa diariamente',
                    style: GoogleFonts.inter(color: colors.textSecondary),
                  ),
                ),
                CheckboxListTile(
                  value: _needsFrontSeat,
                  onChanged: (value) =>
                      _setDraftState(() => _needsFrontSeat = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  activeColor: colors.brand,
                  title: Text(
                    'Precisa sentar mais perto do quadro',
                    style: GoogleFonts.inter(color: colors.textSecondary),
                  ),
                ),
              ],
              SizedBox(height: 18.h),
              _buildYesNoQuestion(
                title: 'Possui restrição alimentar?',
                value: _hasFoodRestriction,
                onChanged: (value) => _setDraftState(() {
                  _hasFoodRestriction = value;
                  if (!value) _selectedFoodRestrictions.clear();
                }),
              ),
              if (_hasFoodRestriction) ...[
                SizedBox(height: 12.h),
                _buildMultiChoiceGroup(
                  options: _foodRestrictionOptions,
                  selected: _selectedFoodRestrictions,
                ),
                SizedBox(height: 12.h),
                _buildTextField(
                  label: 'Detalhes da restrição alimentar',
                  controller: _foodRestrictionDetailsController,
                  icon: Icons.restaurant_rounded,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
              SizedBox(height: 18.h),
              const _InfoBox(
                icon: Icons.emergency_outlined,
                title: 'Contato de emergência',
                message:
                    'Pode ser o responsável principal ou outra pessoa de confiança.',
              ),
              SizedBox(height: 12.h),
              _buildTextField(
                label: 'Nome do contato',
                controller: _emergencyNameController,
                icon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
              ),
              SizedBox(height: 12.h),
              _buildTextField(
                label: 'Telefone do contato',
                controller: _emergencyPhoneController,
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                inputFormatters: [_phoneMask],
                validator: _validateOptionalPhone,
              ),
              SizedBox(height: 12.h),
              _buildTextField(
                label: 'Parentesco',
                controller: _emergencyRelationshipController,
                icon: Icons.group_outlined,
                textCapitalization: TextCapitalization.words,
              ),
              SizedBox(height: 12.h),
              _buildTextField(
                label: 'Observações gerais, se houver',
                controller: _healthGeneralNotesController,
                icon: Icons.notes_rounded,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClassStep() {
    final colors = _flowColors;
    final visibleClasses = _visibleClasses;

    return _StepContainer(
      key: const ValueKey('class'),
      children: [
        const _StepIntro(
          title: 'Escolha a turma desejada.',
          subtitle: 'Selecione uma opção disponível para esta solicitação.',
          icon: Icons.groups_rounded,
        ),
        SizedBox(height: 20.h),
        if (_isLoadingClasses)
          const Center(child: CircularProgressIndicator())
        else if (_classesError != null)
          _InfoBox(
            icon: Icons.wifi_off_rounded,
            title: 'Não foi possível carregar as turmas',
            message: _classesError!,
            actionLabel: 'Tentar novamente',
            onAction: _loadInitialData,
          )
        else if (_classes.isEmpty)
          const _InfoBox(
            icon: Icons.info_outline_rounded,
            title: 'Nenhuma turma disponível',
            message:
                'A escola ainda não liberou turmas para este formulário público.',
          )
        else if (_educationLevels.isEmpty)
          const _InfoBox(
            icon: Icons.info_outline_rounded,
            title: 'Nenhuma turma disponível',
            message:
                'A escola ainda não liberou turmas disponíveis para este formulário.',
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Qual nível de ensino você procura?',
                style: GoogleFonts.inter(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(height: 10.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: _educationLevels.map((level) {
                  final selected = level == _selectedEducationLevel;
                  return ChoiceChip(
                    label: Text(level),
                    selected: selected,
                    onSelected: (_) => _selectEducationLevel(level),
                    selectedColor: colors.selectedSurface,
                    backgroundColor: colors.surface,
                    side: BorderSide(
                      color: selected ? colors.brand : colors.border,
                    ),
                    labelStyle: GoogleFonts.inter(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w800,
                      color:
                          selected ? colors.brandStrong : colors.textSecondary,
                    ),
                  );
                }).toList(),
              ),
              SizedBox(height: 20.h),
              if (_selectedEducationLevel != null) ...[
                Text(
                  'Agora escolha a turma desejada.',
                  style: GoogleFonts.inter(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                SizedBox(height: 10.h),
                if (visibleClasses.isEmpty)
                  const _InfoBox(
                    icon: Icons.info_outline_rounded,
                    title: 'Nenhuma turma disponível',
                    message:
                        'Nenhuma turma disponível para este nível no momento.',
                  )
                else
                  ...visibleClasses.map(_buildClassCard),
                if (_isLoadingOffers) ...[
                  SizedBox(height: 8.h),
                  const _InfoBox(
                    icon: Icons.sync_rounded,
                    title: 'Carregando regimes disponíveis',
                    message:
                        'Estamos verificando se a escola liberou período integral ou outra opção para esta turma.',
                    trailing: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                ],
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildOfferStep() {
    final selectedClass = _selectedClass;

    return _StepContainer(
      key: const ValueKey('offer'),
      children: [
        const _StepIntro(
          title: 'Escolha o regime de permanência.',
          subtitle:
              'Você pode manter apenas a turma principal ou escolher uma opção adicional disponível pela escola.',
          icon: Icons.schedule_rounded,
        ),
        SizedBox(height: 20.h),
        if (selectedClass != null)
          _InfoBox(
            icon: Icons.groups_rounded,
            title: 'Turma principal',
            message:
                '${selectedClass.name} • ${selectedClass.shift ?? 'Turno a confirmar'} • ${_classScheduleLabel(selectedClass)}',
          ),
        if (selectedClass != null) SizedBox(height: 14.h),
        if (_offersError != null) ...[
          _InfoBox(
            icon: Icons.info_outline_rounded,
            title: 'Não conseguimos carregar as opções adicionais',
            message:
                'Você pode tentar novamente ou seguir com meio período. ${_offersError!}',
            actionLabel: 'Tentar novamente',
            onAction: _fetchOffersForSelectedClass,
          ),
          SizedBox(height: 14.h),
        ],
        _buildRegularRegimeCard(selectedClass),
        if (_isLoadingOffers)
          Padding(
            padding: EdgeInsets.only(top: 14.h),
            child: const Center(child: CircularProgressIndicator()),
          )
        else ...[
          SizedBox(height: 10.h),
          ..._availableOffers.map(_buildOfferRegimeCard),
        ],
      ],
    );
  }

  Widget _buildRegularRegimeCard(PublicRegistrationClassModel? selectedClass) {
    final classTitle = selectedClass == null
        ? 'Turma principal'
        : '${selectedClass.name} • ${selectedClass.shift ?? 'Turno a confirmar'}';
    final schedule = selectedClass == null
        ? 'Horário da turma'
        : _classScheduleLabel(selectedClass);
    final fee = selectedClass == null
        ? 'Mensalidade: a confirmar'
        : 'Mensalidade: ${_formatMonthlyFee(selectedClass.monthlyFee)}';

    return _buildRegimeCard(
      selected: _selectedEnrollmentOffer == null,
      title: 'Meio período',
      subtitle: classTitle,
      schedule: schedule,
      feeLabel: fee,
      description:
          'O aluno frequenta a escola no horário regular da turma escolhida.',
      onTap: () => _setDraftState(() => _selectedEnrollmentOffer = null),
    );
  }

  Widget _buildOfferRegimeCard(PublicEnrollmentOfferModel offer) {
    final isSelected = _selectedEnrollmentOffer?.id == offer.id;

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: _buildRegimeCard(
        selected: isSelected,
        title: offer.displayName,
        subtitle: _offerTypeLabel(offer),
        schedule: _offerScheduleLabel(offer),
        feeLabel: _offerFeeLabel(offer),
        description: _offerDescription(offer),
        onTap: () => _setDraftState(() => _selectedEnrollmentOffer = offer),
      ),
    );
  }

  Widget _buildRegimeCard({
    required bool selected,
    required String title,
    required String subtitle,
    required String schedule,
    required String feeLabel,
    required String description,
    required VoidCallback onTap,
  }) {
    final colors = _flowColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: selected ? colors.selectedSurface : colors.surface,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: selected ? colors.brand : colors.border,
            width: selected ? 1.8 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.brand.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? colors.brand : colors.textMuted,
              size: 24.sp,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w900,
                      color: colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 6.h,
                    children: [
                      _RegimeInfoPill(
                        icon: Icons.access_time_rounded,
                        label: schedule,
                      ),
                      _RegimeInfoPill(
                        icon: Icons.payments_outlined,
                        label: feeLabel,
                      ),
                    ],
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      height: 1.38,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewStep() {
    final selectedClass = _selectedClass;

    return _StepContainer(
      key: const ValueKey('review'),
      children: [
        const _StepIntro(
          title: 'Revise os dados antes de enviar.',
          subtitle:
              'A escola irá revisar os dados e confirmar os próximos passos.',
          icon: Icons.fact_check_rounded,
        ),
        SizedBox(height: 22.h),
        _ReviewSection(
          title: 'Escola',
          items: {
            'Nome': _schoolContext?.name ?? 'Escola',
          },
        ),
        _ReviewSection(
          title: 'Aluno',
          items: {
            'Nome': _studentNameController.text.trim(),
            'Nascimento': _studentBirthController.text.trim(),
            'CPF': _studentCpfController.text.trim().isEmpty
                ? 'Não informado'
                : _studentCpfController.text.trim(),
          },
        ),
        _ReviewSection(
          title: 'Filiação',
          items: {
            'Mãe': _motherNameController.text.trim(),
            'Pai': _normalizedFatherName,
          },
        ),
        _ReviewSection(
          title: 'Mãe',
          items: {
            'CPF': _motherCpfController.text.trim().isEmpty
                ? 'Não informado'
                : _motherCpfController.text.trim(),
            'Telefone': _motherPhoneController.text.trim().isEmpty
                ? 'Não informado'
                : _motherPhoneController.text.trim(),
            'E-mail': _motherEmailController.text.trim().isEmpty
                ? 'Não informado'
                : _motherEmailController.text.trim().toLowerCase(),
            'Profissão': _motherProfessionController.text.trim().isEmpty
                ? 'Não informado'
                : _motherProfessionController.text.trim(),
          },
        ),
        _ReviewSection(
          title: 'Pai',
          items: _fatherNotInformed
              ? {'Situação': 'Não consta no registro'}
              : {
                  'Nome': _fatherNameController.text.trim().isEmpty
                      ? 'Não informado'
                      : _fatherNameController.text.trim(),
                  'CPF': _fatherCpfController.text.trim().isEmpty
                      ? 'Não informado'
                      : _fatherCpfController.text.trim(),
                  'Telefone': _fatherPhoneController.text.trim().isEmpty
                      ? 'Não informado'
                      : _fatherPhoneController.text.trim(),
                  'E-mail': _fatherEmailController.text.trim().isEmpty
                      ? 'Não informado'
                      : _fatherEmailController.text.trim().toLowerCase(),
                  'Profissão': _fatherProfessionController.text.trim().isEmpty
                      ? 'Não informado'
                      : _fatherProfessionController.text.trim(),
                },
        ),
        _ReviewSection(
          title: 'Responsável principal',
          items: {
            'Quem é': _primaryResponsibleLabel,
            'Nome': _primaryResponsibleName,
            'Telefone': _primaryResponsiblePhone,
            'E-mail': _primaryResponsibleEmail,
          },
        ),
        _ReviewSection(
          title: 'Endereço',
          items: {
            'CEP': _cepController.text.trim(),
            'Bairro': _selectedNeighborhood ?? '',
            'Logradouro': _streetController.text.trim(),
            'Número': _numberController.text.trim().isEmpty
                ? 'Não informado'
                : _numberController.text.trim(),
            'Quadra': _blockController.text.trim().isEmpty
                ? 'Não informado'
                : _blockController.text.trim(),
            'Lote': _lotController.text.trim().isEmpty
                ? 'Não informado'
                : _lotController.text.trim(),
          },
        ),
        _ReviewSection(
          title: 'Saúde',
          items: _healthReviewItems,
        ),
        if (selectedClass != null)
          _ReviewSection(
            title: 'Turma principal',
            items: {
              'Turma': selectedClass.name,
              'Nível': selectedClass.educationLevel ?? 'Não informado',
              'Turno': selectedClass.shift ?? 'Não informado',
              'Horário': _classScheduleLabel(selectedClass),
              'Mensalidade': _formatMonthlyFee(selectedClass.monthlyFee),
            },
          ),
        if (selectedClass != null)
          _ReviewSection(
            title: 'Regime de permanência',
            items: _regimeReviewItems,
          ),
      ],
    );
  }

  Widget _buildEarlyOfferSuccessCard(EarlyPaymentOffer offer) {
    final colors = _flowColors;
    final done = _earlyOfferRegistered;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF5A524).withValues(alpha: colors.isDark ? .16 : .10),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFF5A524).withValues(alpha: .45)),
      ),
      child: Row(children: [
        Icon(done ? Icons.check_circle : Icons.card_giftcard_rounded,
            color: done ? const Color(0xFF00A859) : const Color(0xFFB86E00),
            size: 26.sp),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                done ? 'Desconto reservado!' : offer.title,
                style: GoogleFonts.inter(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(height: 3.h),
              Text(
                done
                    ? 'A escola vai entrar em contato com as instruções para pagar a mensalidade de ${offer.referenceLabel} com ${offer.discountLabel.toLowerCase()}.'
                    : '${offer.discountLabel} pagando a mensalidade de ${offer.referenceLabel} antecipada ${earlyPaymentDeadlineText(offer)}.',
                style: GoogleFonts.inter(
                  fontSize: 12.5.sp,
                  height: 1.35,
                  color: colors.textMuted,
                ),
              ),
              if (!done) ...[
                SizedBox(height: 8.h),
                FilledButton(
                  onPressed: _earlyOfferRegistering
                      ? null
                      : () {
                          _earlyOfferAccepted = true;
                          _registerEarlyOfferAdhesion();
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF5A524),
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(_earlyOfferRegistering
                      ? 'Registrando…'
                      : 'Quero aproveitar'),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildSuccessStep() {
    final colors = _flowColors;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 28.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96.w,
            height: 96.w,
            decoration: BoxDecoration(
              color: colors.selectedSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 54.sp,
              color: colors.brand,
            ),
          ),
          SizedBox(height: 28.h),
          Text(
            'Dados enviados com sucesso.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 28.sp,
              height: 1.12,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            'A escola irá revisar as informações e confirmar os próximos passos. O envio não significa aprovação automática da matrícula.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15.sp,
              height: 1.45,
              color: colors.textMuted,
            ),
          ),
          if (_earlyOffer != null) ...[
            SizedBox(height: 18.h),
            _buildEarlyOfferSuccessCard(_earlyOffer!),
          ],
          if (_selectedEnrollmentOffer != null) ...[
            SizedBox(height: 18.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                'Regime informado: ${_selectedEnrollmentOffer!.displayName}',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w800,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
          SizedBox(height: 32.h),
          SizedBox(
            width: double.infinity,
            height: 52.h,
            child: ElevatedButton(
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
              child: Text(
                'Concluir',
                style: GoogleFonts.inter(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final colors = _flowColors;

    return Container(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 18.h),
      decoration: BoxDecoration(
        color: colors.footer,
        border: Border(
          top: BorderSide(color: colors.border),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54.h,
        child: ElevatedButton(
          onPressed: _canUsePrimaryButton ? _handlePrimaryAction : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.brand,
            disabledBackgroundColor: colors.disabledButton,
            foregroundColor: Colors.white,
            disabledForegroundColor: colors.disabledButtonText,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.r),
            ),
          ),
          child: _isSubmitting
              ? SizedBox(
                  width: 22.w,
                  height: 22.w,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _primaryButtonLabel,
                  style: GoogleFonts.inter(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildResponsibleChoice(
    String value,
    String label, {
    bool enabled = true,
  }) {
    final colors = _flowColors;
    final selected = _primaryResponsibleType == value;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled
          ? (_) => _setDraftState(() => _primaryResponsibleType = value)
          : null,
      selectedColor: colors.selectedSurface,
      disabledColor: colors.disabledSurface,
      backgroundColor: colors.surface,
      side: BorderSide(
        color: selected ? colors.brand : colors.border,
      ),
      labelStyle: GoogleFonts.inter(
        fontSize: 13.sp,
        fontWeight: FontWeight.w800,
        color: enabled
            ? (selected ? colors.brandStrong : colors.textSecondary)
            : colors.textMuted,
      ),
    );
  }

  Widget _buildEmailSuggestions() {
    final colors = _flowColors;
    const domains = [
      '@gmail.com',
      '@hotmail.com',
      '@outlook.com',
      '@icloud.com',
      '@yahoo.com.br',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sugestões rápidas de e-mail',
          style: GoogleFonts.inter(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
          ),
        ),
        SizedBox(height: 10.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: domains.map((domain) {
            return ActionChip(
              label: Text(domain),
              onPressed: () => _applyEmailDomain(domain),
              backgroundColor: colors.surface,
              side: BorderSide(color: colors.border),
              labelStyle: GoogleFonts.inter(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildYesNoQuestion({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = _flowColors;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14.sp,
              height: 1.35,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _buildSegmentButton(
                  label: 'Não',
                  selected: !value,
                  onTap: () => onChanged(false),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _buildSegmentButton(
                  label: 'Sim',
                  selected: value,
                  onTap: () => onChanged(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = _flowColors;

    return InkWell(
      borderRadius: BorderRadius.circular(12.r),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 44.h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.selectedSurface : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: selected ? colors.brand : colors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14.sp,
            fontWeight: FontWeight.w800,
            color: selected ? colors.brandStrong : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMultiChoiceGroup({
    required List<String> options,
    required Set<String> selected,
  }) {
    final colors = _flowColors;

    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (value) {
            _setDraftState(() {
              if (value) {
                selected.add(option);
              } else {
                selected.remove(option);
              }
            });
          },
          selectedColor: colors.selectedSurface,
          backgroundColor: colors.surface,
          side: BorderSide(
            color: isSelected ? colors.brand : colors.border,
          ),
          labelStyle: GoogleFonts.inter(
            fontSize: 12.sp,
            fontWeight: FontWeight.w700,
            color: isSelected ? colors.brandStrong : colors.textSecondary,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
    ValueChanged<String>? onChanged,
    bool enabled = true,
  }) {
    final colors = _flowColors;

    return TextFormField(
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      style: GoogleFonts.inter(
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      decoration: _inputDecoration(label: label, icon: icon),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final colors = _flowColors;
    final dropdownTextStyle = GoogleFonts.inter(
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    );

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: colors.surface,
      iconEnabledColor: colors.brand,
      iconDisabledColor: colors.textMuted,
      style: dropdownTextStyle,
      decoration: _inputDecoration(
        label: label,
        icon: Icons.keyboard_arrow_down_rounded,
      ),
      selectedItemBuilder: (context) {
        return items.map((item) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              item,
              overflow: TextOverflow.ellipsis,
              style: dropdownTextStyle,
            ),
          );
        }).toList();
      },
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
                style: dropdownTextStyle,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildNeighborhoodField() {
    final colors = _flowColors;

    return InkWell(
      borderRadius: BorderRadius.circular(16.r),
      onTap: _openNeighborhoodPicker,
      child: InputDecorator(
        decoration: _inputDecoration(
          label: 'Bairro',
          icon: Icons.home_work_outlined,
        ),
        child: Text(
          _selectedNeighborhood ?? 'Escolha na lista',
          style: GoogleFonts.inter(
            fontSize: 15.sp,
            fontWeight: FontWeight.w600,
            color: _selectedNeighborhood == null
                ? colors.textMuted
                : colors.textPrimary,
          ),
        ),
      ),
    );
  }

  Future<void> _openNeighborhoodPicker() async {
    final colors = _flowColors;

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (context) {
        var query = '';

        return Theme(
          data: Theme.of(context).copyWith(
            brightness: colors.isDark ? Brightness.dark : Brightness.light,
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: colors.brand,
                  surface: colors.surface,
                  onSurface: colors.textPrimary,
                ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: colors.brand,
              selectionColor: colors.brand.withValues(alpha: 0.22),
              selectionHandleColor: colors.brand,
            ),
            dividerColor: colors.border,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              final filtered = parauapebasNeighborhoods.where((item) {
                return item.toLowerCase().contains(query.toLowerCase().trim());
              }).toList();

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20.w,
                    18.h,
                    20.w,
                    MediaQuery.of(context).viewInsets.bottom + 18.h,
                  ),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Escolha o bairro',
                          style: GoogleFonts.inter(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        TextField(
                          autofocus: true,
                          cursorColor: colors.brand,
                          style: GoogleFonts.inter(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                          decoration: _inputDecoration(
                            label: 'Buscar bairro',
                            icon: Icons.search_rounded,
                          ).copyWith(
                            hintStyle: GoogleFonts.inter(
                              color: colors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onChanged: (value) =>
                              setModalState(() => query = value),
                        ),
                        SizedBox(height: 12.h),
                        Expanded(
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: colors.border,
                            ),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final isSelected = item == _selectedNeighborhood;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  item,
                                  style: GoogleFonts.inter(
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: colors.brand,
                                      )
                                    : null,
                                selected: isSelected,
                                selectedTileColor: colors.selectedSurface,
                                onTap: () => Navigator.of(context).pop(item),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (selected != null) {
      setState(() => _selectedNeighborhood = selected);
      _scheduleDraftSave();
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    final colors = _flowColors;

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: colors.brand),
      filled: true,
      fillColor: colors.surface,
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.r),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.r),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.r),
        borderSide: BorderSide(color: colors.brand, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.r),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16.r),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.6),
      ),
      labelStyle: GoogleFonts.inter(
        color: colors.textMuted,
        fontWeight: FontWeight.w600,
      ),
      errorStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildClassCard(PublicRegistrationClassModel classItem) {
    final colors = _flowColors;
    final selected = classItem.id == _selectedClass?.id;
    final enabled = classItem.isAvailable;

    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: InkWell(
        onTap: enabled ? () => _selectClass(classItem) : null,
        borderRadius: BorderRadius.circular(14.r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: enabled ? colors.surface : colors.disabledSurface,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: selected ? colors.brand : colors.border,
              width: selected ? 1.8 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.brand.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 22.sp,
                      color: selected ? colors.brand : colors.textMuted,
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        classItem.name,
                        style: GoogleFonts.inter(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    _AvailabilityPill(status: classItem.availabilityLabel),
                  ],
                ),
                SizedBox(height: 5.h),
                Padding(
                  padding: EdgeInsets.only(left: 30.w),
                  child: Text(
                    '${_classLevelLabel(classItem)} • ${classItem.shift ?? 'Turno não informado'}',
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                SizedBox(height: 4.h),
                Padding(
                  padding: EdgeInsets.only(left: 30.w),
                  child: Text(
                    '${_classScheduleLabel(classItem)} • ${_formatMonthlyFee(classItem.monthlyFee)}',
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _classLevelLabel(PublicRegistrationClassModel item) {
    final parts = [
      item.educationLevel,
      if ((item.grade ?? '').trim().isNotEmpty) '${item.grade}º ano',
    ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();

    return parts.isEmpty ? 'Série não informada' : parts.join(' • ');
  }

  String _classScheduleLabel(PublicRegistrationClassModel item) {
    if ((item.startTime ?? '').isEmpty) return 'Horário a confirmar';
    if ((item.endTime ?? '').isEmpty) return 'Início às ${item.startTime}';
    return '${item.startTime} às ${item.endTime}';
  }

  String _offerTypeLabel(PublicEnrollmentOfferModel offer) {
    switch (offer.type) {
      case 'full_time':
        return 'Período integral';
      case 'extended_stay':
        return 'Permanência estendida';
      case 'complementary_activity':
        return 'Atividade complementar';
      case 'reinforcement':
        return 'Reforço';
      default:
        return 'Opção de permanência';
    }
  }

  String _offerScheduleLabel(PublicEnrollmentOfferModel offer) {
    if ((offer.startTime ?? '').isEmpty) return 'Horário a confirmar';
    if ((offer.endTime ?? '').isEmpty) return 'Início às ${offer.startTime}';
    return '${offer.startTime} às ${offer.endTime}';
  }

  String _offerFeeLabel(PublicEnrollmentOfferModel offer) {
    final fee = _formatMonthlyFee(offer.monthlyFee);
    if (offer.isTotalPricing) return 'Mensalidade: $fee';
    return 'Adicional: $fee';
  }

  String _offerDescription(PublicEnrollmentOfferModel offer) {
    final parts = <String>[];
    final description = (offer.description ?? '').trim();

    if (offer.isFullTime) {
      parts.add(
        'O aluno permanece na escola em horário ampliado, conforme a rotina organizada pela escola.',
      );
    } else if (description.isNotEmpty) {
      parts.add(description);
    } else {
      parts.add(
        'A escola irá orientar a rotina dessa opção após revisar os dados.',
      );
    }

    if (!offer.isTotalPricing) {
      final classFee = _selectedClass?.monthlyFee;
      final offerFee = offer.monthlyFee;
      if (classFee != null && offerFee != null) {
        parts.add(
          'Estimativa informativa: ${_formatMonthlyFee(classFee + offerFee)}. A escola confirma o valor final.',
        );
      } else {
        parts.add('A escola confirma o valor final na revisão.');
      }
    }

    if (offer.permanenceClassMode == 'optional') {
      parts.add(
        'A escola organizará a permanência do aluno no contraturno, quando necessário.',
      );
    } else if (offer.permanenceClassMode == 'required') {
      parts.add(
        'A organização do contraturno será feita pela escola antes da confirmação.',
      );
    }

    return parts.join(' ');
  }

  String _formatMonthlyFee(double? value) {
    if (value == null) return 'A confirmar';
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  void _applyEmailDomain(String domain) {
    final controller = _emailControllerForPrimary;
    final current = controller.text.trim().toLowerCase();
    final localPart =
        current.contains('@') ? current.split('@').first : current;
    if (localPart.isEmpty) return;

    setState(() => controller.text = '$localPart$domain');
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }
}

class _EmailDomainChip {
  final String domain;

  const _EmailDomainChip({required this.domain});
}

class _SchoolLogoPlaceholder extends StatelessWidget {
  final String initials;

  const _SchoolLogoPlaceholder({required this.initials});

  @override
  Widget build(BuildContext context) {
    final colors = _RegistrationFlowColors.of(context);

    return Center(
      child: Text(
        initials,
        style: GoogleFonts.inter(
          fontSize: 18.sp,
          fontWeight: FontWeight.w900,
          color: colors.brandStrong,
        ),
      ),
    );
  }
}

class _StepContainer extends StatelessWidget {
  final List<Widget> children;

  const _StepContainer({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 24.h),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _StepIntro extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _StepIntro({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _RegistrationFlowColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54.w,
          height: 54.w,
          decoration: BoxDecoration(
            color: colors.iconSurface,
            borderRadius: BorderRadius.circular(18.r),
          ),
          child: Icon(icon, color: colors.brand, size: 28.sp),
        ),
        SizedBox(height: 20.h),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 28.sp,
            height: 1.08,
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 15.sp,
            height: 1.45,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const _InfoBox({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _RegistrationFlowColors.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.brand, size: 26.sp),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  message,
                  style: GoogleFonts.inter(
                    fontSize: 13.sp,
                    height: 1.38,
                    color: colors.textMuted,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  SizedBox(height: 10.h),
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size(44.w, 36.h),
                      foregroundColor: colors.brand,
                    ),
                    child: Text(
                      actionLabel!,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: 10.w),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _ReadOnlyLocationPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = _RegistrationFlowColors.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: colors.infoSurface,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Text(
        'Cidade: Parauapebas • Estado: PA',
        style: GoogleFonts.inter(
          fontSize: 13.sp,
          fontWeight: FontWeight.w700,
          color: colors.infoText,
        ),
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  final String status;

  const _AvailabilityPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final colors = _RegistrationFlowColors.of(context);
    final unavailable = status == 'Indisponível';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: unavailable ? colors.dangerSurface : colors.selectedSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: GoogleFonts.inter(
          fontSize: 12.sp,
          fontWeight: FontWeight.w800,
          color: unavailable ? colors.dangerText : colors.brandStrong,
        ),
      ),
    );
  }
}

class _RegimeInfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RegimeInfoPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _RegistrationFlowColors.of(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: colors.infoSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.sp, color: colors.infoText),
          SizedBox(width: 5.w),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.sp,
              fontWeight: FontWeight.w800,
              color: colors.infoText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final String title;
  final Map<String, String> items;

  const _ReviewSection({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _RegistrationFlowColors.of(context);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15.sp,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          SizedBox(height: 10.h),
          ...items.entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92.w,
                    child: Text(
                      entry.key,
                      style: GoogleFonts.inter(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
